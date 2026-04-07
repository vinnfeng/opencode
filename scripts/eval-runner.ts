#!/usr/bin/env bun
/**
 * 开渠评测框架 (P4)
 * 对 opencode 进行系统性能力验证，支持批量测试用例跨项目运行
 *
 * 用法:
 *   bun scripts/eval-runner.ts                        # 运行所有用例
 *   bun scripts/eval-runner.ts --filter smoke         # 按 tag 过滤
 *   bun scripts/eval-runner.ts --case read_file       # 运行单个用例
 *   bun scripts/eval-runner.ts --concurrency 3        # 并发数（默认 2）
 *   bun scripts/eval-runner.ts --model claude-sonnet  # 覆盖模型
 *   bun scripts/eval-runner.ts --dry-run              # 只打印用例，不执行
 *   bun scripts/eval-runner.ts --report path/out.md   # 指定报告输出路径
 *
 * 测试用例放在 scripts/eval-cases/*.json
 */

import { spawnSync, spawn } from "child_process"
import { existsSync, readFileSync, writeFileSync, readdirSync, mkdirSync } from "fs"
import { join, resolve, dirname } from "path"
import { EOL } from "os"

// ── 类型定义 ─────────────────────────────────────────────────────────────────

type Assertion =
  | { type: "no_error" }
  | { type: "output_contains"; pattern: string; flags?: string }
  | { type: "output_not_contains"; pattern: string; flags?: string }
  | { type: "file_exists"; path: string }
  | { type: "file_contains"; path: string; pattern: string; flags?: string }
  | { type: "exit_code"; code: number }
  | { type: "tool_used"; tool: string }

type EvalCase = {
  id: string
  description: string
  tags?: string[]
  prompt: string
  dir: string          // 测试项目目录（绝对路径或相对于 eval-cases/ 的路径）
  model?: string
  agent?: string
  timeout?: number     // 秒，默认 120
  setup?: string[]     // 执行前 bash 命令列表
  teardown?: string[]  // 执行后 bash 命令列表
  assertions: Assertion[]
}

type RunEvent = {
  type: string
  timestamp: number
  sessionID: string
  [key: string]: unknown
}

type CaseResult = {
  case: EvalCase
  passed: boolean
  durationMs: number
  outputText: string
  toolsUsed: string[]
  events: RunEvent[]
  assertionResults: { assertion: Assertion; passed: boolean; reason?: string }[]
  error?: string
}

// ── CLI 参数解析 ──────────────────────────────────────────────────────────────

const args = process.argv.slice(2)
function flag(name: string, defaultVal: string | number | boolean): string | number | boolean {
  const i = args.indexOf(`--${name}`)
  if (i === -1) return defaultVal
  if (typeof defaultVal === "boolean") return true
  return args[i + 1] ?? defaultVal
}

const FILTER_TAG    = flag("filter", "") as string
const FILTER_CASE   = flag("case", "") as string
const CONCURRENCY   = Number(flag("concurrency", 2))
const MODEL_OVERRIDE = flag("model", "") as string
const DRY_RUN       = flag("dry-run", false) as boolean
const REPORT_PATH   = flag("report", "") as string

const SCRIPT_DIR = dirname(import.meta.path)
const CASES_DIR  = join(SCRIPT_DIR, "eval-cases")
const ARTIFACTS_DIR = join(SCRIPT_DIR, "..", ".artifacts", "eval")

// ── 用例加载 ──────────────────────────────────────────────────────────────────

function loadCases(): EvalCase[] {
  if (!existsSync(CASES_DIR)) {
    console.error(`❌ eval-cases 目录不存在: ${CASES_DIR}`)
    console.error(`   请创建 ${CASES_DIR}/*.json 测试用例文件`)
    process.exit(1)
  }

  const files = readdirSync(CASES_DIR).filter(f => f.endsWith(".json"))
  if (files.length === 0) {
    console.error(`❌ ${CASES_DIR} 中没有 .json 测试用例`)
    process.exit(1)
  }

  const cases: EvalCase[] = []
  for (const file of files) {
    const raw = JSON.parse(readFileSync(join(CASES_DIR, file), "utf-8"))
    const list: EvalCase[] = Array.isArray(raw) ? raw : [raw]
    for (const c of list) {
      // 相对路径转绝对路径
      if (!c.dir.startsWith("/")) {
        c.dir = resolve(CASES_DIR, c.dir)
      }
      cases.push(c)
    }
  }
  return cases
}

// ── 断言评估 ──────────────────────────────────────────────────────────────────

function evalAssertion(
  a: Assertion,
  { outputText, toolsUsed, events, exitCode }: {
    outputText: string
    toolsUsed: string[]
    events: RunEvent[]
    exitCode: number
  }
): { passed: boolean; reason?: string } {
  switch (a.type) {
    case "no_error": {
      const hasError = events.some(e => e.type === "error")
      return hasError
        ? { passed: false, reason: "session 产生了 error 事件" }
        : { passed: true }
    }
    case "output_contains": {
      const re = new RegExp(a.pattern, a.flags ?? "i")
      return re.test(outputText)
        ? { passed: true }
        : { passed: false, reason: `输出不包含 /${a.pattern}/` }
    }
    case "output_not_contains": {
      const re = new RegExp(a.pattern, a.flags ?? "i")
      return !re.test(outputText)
        ? { passed: true }
        : { passed: false, reason: `输出意外包含 /${a.pattern}/` }
    }
    case "file_exists":
      return existsSync(a.path)
        ? { passed: true }
        : { passed: false, reason: `文件不存在: ${a.path}` }
    case "file_contains": {
      if (!existsSync(a.path)) return { passed: false, reason: `文件不存在: ${a.path}` }
      const content = readFileSync(a.path, "utf-8")
      const re = new RegExp(a.pattern, a.flags ?? "i")
      return re.test(content)
        ? { passed: true }
        : { passed: false, reason: `${a.path} 不包含 /${a.pattern}/` }
    }
    case "exit_code":
      return exitCode === a.code
        ? { passed: true }
        : { passed: false, reason: `exit code ${exitCode} ≠ ${a.code}` }
    case "tool_used":
      return toolsUsed.includes(a.tool)
        ? { passed: true }
        : { passed: false, reason: `工具 "${a.tool}" 未被调用` }
  }
}

// ── 单用例执行 ────────────────────────────────────────────────────────────────

async function runCase(ec: EvalCase, modelOverride?: string): Promise<CaseResult> {
  const start = Date.now()
  const timeout = (ec.timeout ?? 120) * 1000

  // setup
  if (ec.setup) {
    for (const cmd of ec.setup) {
      spawnSync(cmd, { shell: true, cwd: ec.dir })
    }
  }

  const opencodeBin = process.execPath === process.argv[0]
    ? "opencode"
    : join(SCRIPT_DIR, "..", "packages/opencode/bin/opencode")

  const cmdArgs = ["run", "--format", "json", "--dangerously-skip-permissions", ec.prompt]
  if (modelOverride || ec.model) cmdArgs.push("--model", (modelOverride || ec.model)!)
  if (ec.agent) cmdArgs.push("--agent", ec.agent)

  const events: RunEvent[] = []
  const textParts: string[] = []
  const toolsUsed: string[] = []
  let buffer = ""
  let exitCode = 0
  let errorMsg: string | undefined

  await new Promise<void>((resolve, reject) => {
    const proc = spawn("opencode", cmdArgs, {
      cwd: ec.dir,
      env: { ...process.env },
      timeout,
    })

    proc.stdout.on("data", (chunk: Buffer) => {
      buffer += chunk.toString()
      const lines = buffer.split(EOL)
      buffer = lines.pop() ?? ""
      for (const line of lines) {
        if (!line.trim()) continue
        try {
          const ev: RunEvent = JSON.parse(line)
          events.push(ev)
          if (ev.type === "text") {
            const part = ev.part as { text?: string }
            if (part?.text) textParts.push(part.text)
          }
          if (ev.type === "tool_use") {
            const part = ev.part as { tool?: string }
            if (part?.tool) toolsUsed.push(part.tool)
          }
        } catch { /* non-JSON line, ignore */ }
      }
    })

    proc.stderr.on("data", (chunk: Buffer) => {
      const msg = chunk.toString()
      if (msg.trim()) errorMsg = (errorMsg ?? "") + msg
    })

    proc.on("close", (code) => {
      exitCode = code ?? 0
      resolve()
    })

    proc.on("error", (err) => {
      errorMsg = err.message
      reject(err)
    })
  }).catch(err => {
    errorMsg = String(err)
    exitCode = 1
  })

  // teardown
  if (ec.teardown) {
    for (const cmd of ec.teardown) {
      spawnSync(cmd, { shell: true, cwd: ec.dir })
    }
  }

  const outputText = textParts.join("\n")
  const assertionResults = ec.assertions.map(a => ({
    assertion: a,
    ...evalAssertion(a, { outputText, toolsUsed, events, exitCode }),
  }))

  const passed = assertionResults.every(r => r.passed) && exitCode !== 1

  return {
    case: ec,
    passed,
    durationMs: Date.now() - start,
    outputText,
    toolsUsed,
    events,
    assertionResults,
    error: errorMsg,
  }
}

// ── 并发执行器 ────────────────────────────────────────────────────────────────

async function runAll(cases: EvalCase[], concurrency: number): Promise<CaseResult[]> {
  const results: CaseResult[] = []
  const queue = [...cases]
  let running = 0
  let done = 0

  await new Promise<void>((resolve) => {
    function next() {
      while (running < concurrency && queue.length > 0) {
        const ec = queue.shift()!
        running++
        process.stdout.write(`  ▶ [${done + running}/${cases.length}] ${ec.id} ...\r`)
        runCase(ec, MODEL_OVERRIDE || undefined).then(result => {
          results.push(result)
          running--
          done++
          const icon = result.passed ? "✅" : "❌"
          const ms = result.durationMs
          console.log(`  ${icon} ${ec.id.padEnd(40)} ${(ms / 1000).toFixed(1)}s`)
          if (!result.passed) {
            for (const ar of result.assertionResults.filter(r => !r.passed)) {
              console.log(`       └ ${ar.reason}`)
            }
          }
          next()
          if (done === cases.length) resolve()
        })
      }
    }
    next()
  })

  return results
}

// ── 报告生成 ──────────────────────────────────────────────────────────────────

function formatReport(results: CaseResult[]): string {
  const total = results.length
  const passed = results.filter(r => r.passed).length
  const failed = total - passed
  const totalMs = results.reduce((s, r) => s + r.durationMs, 0)
  const date = new Date().toISOString().slice(0, 16).replace("T", " ")

  const lines: string[] = [
    `# 开渠评测报告`,
    ``,
    `**时间**: ${date}  **用例**: ${total}  **通过**: ${passed}  **失败**: ${failed}  **总耗时**: ${(totalMs / 1000).toFixed(1)}s`,
    ``,
    `## 汇总`,
    ``,
    `| 用例 | 描述 | 结果 | 耗时 |`,
    `|------|------|------|------|`,
  ]

  for (const r of results) {
    const icon = r.passed ? "✅" : "❌"
    lines.push(`| \`${r.case.id}\` | ${r.case.description} | ${icon} | ${(r.durationMs / 1000).toFixed(1)}s |`)
  }

  const failures = results.filter(r => !r.passed)
  if (failures.length > 0) {
    lines.push(``, `## 失败详情`, ``)
    for (const r of failures) {
      lines.push(`### ❌ \`${r.case.id}\``, ``)
      lines.push(`**提示词**: \`${r.case.prompt.slice(0, 100)}${r.case.prompt.length > 100 ? "…" : ""}\``, ``)
      for (const ar of r.assertionResults.filter(a => !a.passed)) {
        lines.push(`- 断言失败 [\`${ar.assertion.type}\`]: ${ar.reason}`)
      }
      if (r.error) lines.push(`- 错误: \`${r.error}\``)
      if (r.outputText) {
        lines.push(``, `<details><summary>输出（前 500 字）</summary>`, ``, `\`\`\``, r.outputText.slice(0, 500), `\`\`\``, `</details>`)
      }
      lines.push(``)
    }
  }

  return lines.join("\n")
}

// ── 主流程 ────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`═══════════════════════════════════════════════`)
  console.log(` 开渠评测框架 (P4)`)
  console.log(`═══════════════════════════════════════════════`)

  let cases = loadCases()

  if (FILTER_TAG) {
    cases = cases.filter(c => c.tags?.includes(FILTER_TAG))
    console.log(`过滤 tag="${FILTER_TAG}": ${cases.length} 个用例`)
  }
  if (FILTER_CASE) {
    cases = cases.filter(c => c.id === FILTER_CASE)
    console.log(`过滤 case="${FILTER_CASE}": ${cases.length} 个用例`)
  }

  if (cases.length === 0) {
    console.log("没有匹配的测试用例")
    process.exit(0)
  }

  console.log(`用例数: ${cases.length}  并发: ${CONCURRENCY}  模型: ${MODEL_OVERRIDE || "(用例自定义)"}`)
  console.log(``)

  if (DRY_RUN) {
    console.log("【dry-run】以下用例将被执行：")
    for (const c of cases) {
      console.log(`  - ${c.id}: ${c.description}`)
    }
    process.exit(0)
  }

  const results = await runAll(cases, CONCURRENCY)

  const passed = results.filter(r => r.passed).length
  const total = results.length

  console.log(``)
  console.log(`═══════════════════════════════════════════════`)
  console.log(` 结果: ${passed}/${total} 通过`)
  console.log(`═══════════════════════════════════════════════`)

  // 生成报告
  const report = formatReport(results)
  const reportDir = ARTIFACTS_DIR
  mkdirSync(reportDir, { recursive: true })
  const reportFile = REPORT_PATH || join(reportDir, `eval-${Date.now()}.md`)
  writeFileSync(reportFile, report, "utf-8")

  // JSON 原始数据
  const jsonFile = reportFile.replace(/\.md$/, ".json")
  writeFileSync(jsonFile, JSON.stringify(results.map(r => ({
    id: r.case.id,
    passed: r.passed,
    durationMs: r.durationMs,
    toolsUsed: r.toolsUsed,
    assertionResults: r.assertionResults,
    error: r.error,
  })), null, 2), "utf-8")

  console.log(``)
  console.log(`报告: ${reportFile}`)
  console.log(`数据: ${jsonFile}`)

  process.exit(passed === total ? 0 : 1)
}

main().catch(err => {
  console.error(err)
  process.exit(1)
})
