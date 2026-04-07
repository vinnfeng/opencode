# 开渠（KaiQu）— 增强版 OpenCode

**基于**: OpenCode v1.3.17 官方最新  
**分支**: `fengzhen/performance-tuning`  
**构建**: `0.0.0-fengzhen/performance-tuning-202604071837`  
**维护**: 太初合道界 · 曜构

---

## 这是什么

开渠是在 [OpenCode](https://github.com/anomalyco/opencode) 官方最新版本之上，融合 CodeBuff 最强实践，定向增强的私有构建。

官方给了底座，CodeBuff 给了方法论，我们做了融合 + 调参。

---

## 相比官方 v1.3.17，增强了什么

### 🔥 性能层（已编译进二进制）

| 参数 | 官方默认 | 开渠优化 | 效果 |
|------|---------|---------|------|
| `PRUNE_MINIMUM` | 20K tokens | **10K** | compaction 提前触发 |
| `PRUNE_PROTECT` | 40K tokens | **20K** | 保护窗口缩小 50% |
| `COMPACTION_BUFFER` | 20K tokens | **30K** | 触发更激进 |
| `MAX_LINES` | 2000 行 | **1000 行** | 单次工具输出减半 |
| `MAX_BYTES` | 50KB | **25KB** | token 消耗减半 |

**总效果**：context 使用更高效，长任务不掉速，每次工具调用 token 消耗 -50%。

### 🧠 智能层（Agent 系统，可热更新）

相比官方只有一个 primary agent，开渠配备了完整的多 Agent 体系：

| Agent | 模型 | 职责 | 来源 |
|-------|------|------|------|
| **orchestrator** | Sonnet 4.6 | 主编排，任务分析，并行调度 | 融合 CodeBuff base2 |
| **thinker** | Opus 4.6 | 纯推理，无工具，深度思考 | 移植自 CodeBuff thinker |
| **coder** | GPT-5.4 | 代码实现，先思后写，改完验证 | 融合 CodeBuff editor |
| **reviewer** | Sonnet 4.6 | 简洁犀利的代码审查 | 移植自 CodeBuff reviewer |
| **architect** | GPT-5.4 | 技术方案设计 | 自研 |
| **researcher** | Gemini Flash | 技术调研，API 验证 | 自研 |
| **basher** | Haiku 4.5 | Shell 专家，安全执行命令 | 移植自 CodeBuff basher |

**关键机制**：
- **并行调度**：orchestrator 强制并行 spawn 多个 agent，速度 vs 官方提升显著
- **Best-of-N**（P2）：高风险任务多模型交叉验证，择优合并
- **动态上下文剪枝**（P3）：LLM 主动摘要旧对话，长任务不爆 context

### ⚙️ 模型策略层（oh-my-opencode）

官方只有单一模型配置。开渠实现了分级模型路由：

```
ultrabrain → Opus 4.6     （最复杂任务）
deep       → Sonnet 4.6   （标准任务，默认）
quick      → Haiku 4.5    （简单/快速）
visual     → Gemini Pro    （视觉工程）
writing    → Sonnet 4.6   （文档/写作）
```

Fallback 链自动降级，主力挂了备选顶上，不中断。

---

## 相比 CodeBuff，优势在哪

| 维度 | CodeBuff | 开渠 |
|------|---------|------|
| 底座 | 独立产品 | OpenCode v1.3.17（更新更快）|
| 上下文管理 | context-pruner | 编译层参数优化 + P3 pruner 双重保障 |
| Agent 体系 | 完整（含 thinker/editor/reviewer）| 完整移植 + 本地模型路由 |
| 模型路由 | 内置 | 可配置多供应商（Mify/百炼）|
| 离线能力 | 依赖 Codebuff 服务 | 完全本地，无服务依赖 |
| 可定制性 | 有限 | 全部源码可改，分支可维护 |

---

## 升级方式

```bash
# 拉取官方最新 + rebase 我们的补丁 + 构建 + 安装
bash scripts/upgrade.sh

# 仅验证（不构建不安装）
bash scripts/upgrade.sh --dry-run
```

每次 `upgrade.sh` 运行后，我们的性能补丁会自动 rebase 到最新官方版本之上。**永远是官方最新 + 我们的增强**，不会落后。

---

## 版本历史

### v1.3.17+kaiqu.3 (2026-04-08)

- ✅ 基于官方 v1.3.17（含 #21350 #21355 修复）
- ✅ 性能补丁：`perf: aggressive compaction and tighter tool output limits`（编译进二进制）
- ✅ Agent 体系完整：orchestrator / thinker / coder / reviewer / architect / researcher / basher（7个）
- ✅ 模型路由：per-agent 精确模型指定，Opus/Sonnet/Haiku/GPT-5.4/Gemini 按职责分配
- ✅ P2 Best-of-N 编排协议（写入 orchestrator 提示词）
- ✅ 原生 compaction 启用：`auto: true, prune: true`
- ✅ 自动化升级脚本（`upgrade.sh` + `install-binary.sh`）
- ✅ oh-my-opencode 插件已重新启用（修复 `[Reconciler] Unknown component type: spinner` crash，在 `app.tsx` 首行注册 opentui-spinner 副作用）
- ✅ oh-my-opencode 插件实际加载验证通过（v3.14.0，via file:// 绕过代理安装问题，compaction/context-pruner/tool-truncator 全部激活）

---

*"官方给了底座，CodeBuff 给了灵魂，我们把两者焊在一起。"*
