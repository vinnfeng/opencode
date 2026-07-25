# OpenCode Fork 分支管理规范（公司迁移基线）

**维护人：承渊-运维（Claude Code）**
**建立时间：2026-07-25**
**基线：`ad052574`（上游干净同步点）**

---

## 分支结构

| 分支 | 用途 | 操作规则 |
|------|------|---------|
| `main` | 公司主线，跟踪上游 + 已验证的公司改动 | 只接受 PR merge，**不直接 push** |
| `migration/company-opencode-validated-*` | 验证迁移线，从干净基线重写公司需要的改动 | 独立 commit + 测试 + PR review |
| `upstream-sync` | 跟踪官方 `anomalyco/opencode` dev | 只用于拉取官方更新，**不在此开发** |

> 不再使用 `fengzhen/performance-tuning` 作为生产分支。该分支冻结为证据库（见 `证据-opencode-fengzhen-performance-tuning冻结-20260725.md`），不作运行基线，不追加修改。

---

## Remote 说明

| Remote | URL | 用途 |
|--------|-----|------|
| `origin` | `https://github.com/vinnfeng/opencode.git` | 公司自己的 fork（vinnfeng） |
| `upstream` | `https://github.com/anomalyco/opencode.git` | 官方上游 |

---

## 迁移流程

```bash
# 1. 从干净基线建迁移分支
git switch -c migration/company-opencode-validated-YYYYMMDD ad052574

# 2. 逐项重写公司需要的改动（独立 commit + 测试，禁整批 cherry-pick 旧分支）
#    每项 commit 可独立 revert

# 3. push 到 origin（只推 vinnfeng fork，不推官方）
git push origin migration/company-opencode-validated-YYYYMMDD

# 4. 建 PR -> main，待 review，不自动 merge
```

**铁律**：
- 不直接 push `main`
- 不整批 cherry-pick `fengzhen/performance-tuning` 的 20 提交
- 每项改动独立 commit + 测试 + 可 revert
- 推送只推 `origin`（vinnfeng fork），禁推官方 `anomalyco`（贡献上游走 fork PR，非 push 例外）
- WSL 访问 `/mnt/c` 大仓库用 Windows 原生 git（`powershell.exe` 调 `git.exe`），避免 9p FS 超时

---

## 旧优化补丁处理

`fengzhen/performance-tuning` 的 `6908d6a63`（aggressive compaction + tighter truncation）等 perf 补丁**不自动继承**。新基线需逐项评估是否仍有效、是否与上游冲突，按 D 类（重新设计）或 A 类（最小重实现）单独迁移，不默认保留。

---

## 备份文件说明

| 文件 | 内容 |
|------|------|
| `.opencode` | 当前运行版本 |
| `.opencode.bak.*` | 历史版本备份 |

> 备份文件不进 git，仅本地保留。

---

## 评测框架

`scripts/eval-runner.ts` + `scripts/eval-cases/` 提供能力验证：

```bash
bun scripts/eval-runner.ts --filter smoke
```

报告输出至 `.artifacts/eval/`。

> 评测框架的路径配置已去硬编码（见对应 commit），使用相对路径或环境变量，不绑定特定机器。

---

*承渊-运维 · 2026-07-25 · S3 Wave D3 重编（基于公司迁移基线 ad052574，替代旧 fengzhen/performance-tuning 分支策略）*
