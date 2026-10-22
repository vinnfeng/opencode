import { expect, test } from "bun:test"
import { Effect } from "effect"
import { execFileSync } from "node:child_process"
import path from "node:path"
import { cliIt, isolatedEnv } from "../../lib/cli-process"
import { testProviderConfig } from "../../lib/test-provider"

// Opt-in: run only against the explicitly supplied candidate, never whichever
// binary happens to be installed. The server, home, session and tmux socket
// are synthetic. Run this test in a clean environment: the shared CLI fixture
// inherits parent environment variables when it launches its subprocess.
const binary = process.env.OPENCODE_SYNTHETIC_TEST_BINARY || ""
const tmux = process.env.OPENCODE_SYNTHETIC_TEST_TMUX || "tmux"

if (!binary) {
  test.skip("compiled TUI restores an isolated synthetic session", () => {})
} else {
  cliIt.live("compiled TUI restores an isolated synthetic session", ({ home, llm, opencode }) =>
    Effect.gen(function* () {
      yield* llm.text("synthetic-answer-for-resume")
      const created = yield* opencode.run("synthetic prompt", { format: "json", env: { OPENCODE_DB: "opencode.db" } })
      opencode.expectExit(created, 0)
      const session = opencode.parseJsonEvents(created.stdout).find((item) => typeof item.sessionID === "string")?.sessionID
      expect(typeof session).toBe("string")
      const base = testProviderConfig(llm.url)
      const config = {
        ...base,
        provider: { ...base.provider, test: {
          ...base.provider.test,
          models: { ...base.provider.test.models, "alternate-model": {
            ...base.provider.test.models["test-model"],
            id: "alternate-model", name: "Alternate Model", variants: { focused: { temperature: 0.1 } },
          } },
        } },
      }
      const env = {
        PATH: process.env.PATH || "/usr/bin:/bin",
        TMPDIR: process.env.TMPDIR || "/tmp",
        LANG: "en_US.UTF-8",
        ...isolatedEnv(home, JSON.stringify(config)),
        OPENCODE_DB: "opencode.db",
        TERM: "xterm-256color",
      }
      const capture = async (label: string, expected: string[], args: string[]) => {
        const socket = path.join(home, `private-tmux-${label}.sock`)
        const run = (...args: string[]) => execFileSync(tmux, ["-f", "/dev/null", "-S", socket, ...args], {
          env, encoding: "utf8",
        })
        try {
          run("new-session", "-d", "-s", "test", "-x", "120", "-y", "40", "-c", home, binary, "--session", String(session), ...args)
          let result = ""
          for (let i = 0; i < 80; i++) {
            await Bun.sleep(250)
            result = run("capture-pane", "-p", "-t", "test")
            if (expected.every((value) => result.includes(value))) break
          }
          return result
        } finally {
          try { run("kill-server") } catch {}
        }
      }
      const screen = yield* Effect.promise(() => capture("resume", ["synthetic-answer-for-resume", "Test Model"], []))
      expect(screen).toContain("synthetic-answer-for-resume")
      expect(screen).toContain("Test Model")
      const forced = yield* Effect.promise(() => capture("forced", ["synthetic-answer-for-resume", "Alternate Model", "focused"], [
        "--model", "test/alternate-model", "--variant", "focused",
      ]))
      expect(forced).toContain("synthetic-answer-for-resume")
      expect(forced).toContain("Alternate Model")
      expect(forced).toContain("focused")
    }),
    90_000,
  )
}
