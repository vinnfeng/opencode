# OpenCode Fork 分支管理规范

**维护人：曜构（Claude Code）**  
**建立时间：2026-04-05**  
**最后更新：2026-04-08**  
**完整版本说明：[RELEASE.md](./RELEASE.md)**

---

## 分支结构

| 分支 | 用途 | 操作规则 |
|------|------|---------|
| `upstream-sync` | 跟踪官方 `anomalyco/opencode` dev | 只用于拉取官方更新，**不在此开发** |
| `fengzhen/performance-tuning` | 当前生产分支，含我们的优化补丁 | 在此开发、发版、部署 |
| `fengzhen/cultivation` | 研究/实验分支 | 随时可用，不影响生产 |

---

## Remote 说明

| Remote | URL | 用途 |
|--------|-----|------|
| `origin` | `https://github.com/vinnfeng/opencode.git` | 我们自己的 fork |
| `upstream` | `https://github.com/anomalyco/opencode.git` | 官方上游 |

---

## 升级流程（脚本化）

```bash
# 一键升级：fetch + rebase + 构建（若开渠在运行，构建后等待手动安装）
bash scripts/upgrade.sh

# 仅验证同步是否干净（不构建不安装）
bash scripts/upgrade.sh --dry-run

# 开渠空闲后安装已构建的新版本
bash scripts/install-binary.sh

# push 更新
git push origin fengzhen/performance-tuning --force-with-lease
```

**冲突处理**：遇到 rebase 冲突时脚本会列出文件并退出，手动 `git add + git rebase --continue`，再运行 `install-binary.sh`。

**注意**：upgrade.sh 检测到 opencode 进程在运行时会跳过二进制安装，只构建。安装前确认开渠已退出。

---

## 当前优化内容（performance-tuning）

**提交**：`6908d6a63` — `perf: aggressive compaction and tighter tool output limits`

| 文件 | 参数 | 原值 | 优化值 |
|------|------|------|-------|
| `compaction.ts` | PRUNE_MINIMUM | 20K | 10K |
| `compaction.ts` | PRUNE_PROTECT | 40K | 20K |
| `overflow.ts` | COMPACTION_BUFFER | 20K | 30K |
| `truncate.ts` | MAX_LINES | 2000 | 1000 |
| `truncate.ts` | MAX_BYTES | 50KB | 25KB |

效果：compaction 提前 ~20% 触发，压缩力度翻倍，每次工具调用 token 消耗减半。

---

## 能力路线图

| 项 | 内容 | 状态 | 位置 |
|----|------|------|------|
| Perf patch | aggressive compaction + tighter truncation | ✅ 已实现 | `6908d6a63` |
| P3 context-pruner | LLM 动态摘要旧对话（>60% 触发） | ✅ 已启用 | `oh-my-opencode.json` experimental |
| P2 Best-of-N | 高风险任务多模型验证 | ✅ 已写入协议 | `agents/orchestrator.md` |
| P4 评测框架 | 175+ 项目 OpenCode runner | ✅ 已实现 | `scripts/eval-runner.ts` + `eval-cases/` |

---

## 评测框架（P4）使用方式

```bash
# 运行所有用例（并发 2）
bun scripts/eval-runner.ts

# 只跑 smoke 快速验证
bun scripts/eval-runner.ts --filter smoke

# 只跑性能补丁回归
bun scripts/eval-runner.ts --filter perf

# 指定单个用例
bun scripts/eval-runner.ts --case smoke_read_file

# dry-run（列出用例不执行）
bun scripts/eval-runner.ts --dry-run
```

报告输出至 `.artifacts/eval/eval-<timestamp>.md`，同目录有 `.json` 原始数据。

新增用例：在 `scripts/eval-cases/` 下添加 `.json` 文件，每个文件为单个 case 对象或 case 数组。

---

## 备份文件说明

| 文件 | 内容 |
|------|------|
| `.opencode` | 当前生产版本（我们的优化构建）|
| `.opencode.bak.20260403` | 上一个生产版本备份 |
| `.opencode.official.bak` | 原始官方二进制 |
