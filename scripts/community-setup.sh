#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 社区版安装 — macOS & Linux
#  安装官方 opencode + 小米内部 Mify 模型配置 + 优化 agent 体系
#  需要输入 Mify API Key
#
#  用法：
#    bash <(curl -fsSL https://raw.githubusercontent.com/vinnfeng/opencode/fengzhen/performance-tuning/scripts/community-setup.sh)
# ═══════════════════════════════════════════════════════════
set -euo pipefail

CONFIG_REPO="https://github.com/vinnfeng/opencode-config.git"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}✅  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️   $*${RESET}"; }
err()  { echo -e "${RED}❌  $*${RESET}"; exit 1; }
info() { echo -e "${BLUE}➜   $*${RESET}"; }

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  开渠 OpenCode 社区版 — 安装配置              ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""

# ── 1. 检查依赖 ───────────────────────────────────────────────
for cmd in git curl node npm; do
  command -v "$cmd" &>/dev/null || err "缺少依赖: $cmd"
done

# ── 2. 输入 Mify API Key ──────────────────────────────────────
echo -e "${BOLD}请输入你的 Mify API Key：${RESET}"
echo -e "（从内网 Mify 平台获取，格式：sk-...）"
read -rsp "Mify API Key: " MIFY_KEY
echo ""
if [[ -z "$MIFY_KEY" || "$MIFY_KEY" != sk-* ]]; then
  err "Key 格式不对，应以 sk- 开头"
fi
ok "Key 已输入"

# ── 3. 安装官方 opencode ──────────────────────────────────────
if command -v opencode &>/dev/null; then
  ok "opencode 已安装: $(opencode --version 2>/dev/null || echo 'ok')"
else
  info "安装 opencode-ai (官方版)..."
  npm install -g opencode-ai || err "安装失败，请检查 npm 权限"
  ok "opencode 安装完成"
fi

# ── 4. 克隆配置仓库（community 分支）────────────────────────
if [ -d "$CONFIG_DIR/.git" ]; then
  info "配置目录已存在，更新中..."
  cd "$CONFIG_DIR"
  git fetch origin
  git checkout community 2>/dev/null || git checkout -b community --track origin/community
  git pull origin community --rebase 2>&1 | tail -2
  ok "配置已更新"
else
  [ -d "$CONFIG_DIR" ] && mv "$CONFIG_DIR" "${CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
  info "克隆配置（community 分支）..."
  git clone --branch community "$CONFIG_REPO" "$CONFIG_DIR"
  ok "配置克隆完成"
fi

# ── 5. 将 MIFY_API_KEY 占位符替换为真实 key ──────────────────
PLUGIN_FILE="$CONFIG_DIR/opencode.jsonc"
if [ -f "$PLUGIN_FILE" ]; then
  # 用 node 做替换，避免 sed 跨平台差异
  node -e "
    const fs=require('fs'), p='$PLUGIN_FILE';
    fs.writeFileSync(p, fs.readFileSync(p,'utf8').replaceAll('MIFY_API_KEY','$MIFY_KEY'));
  "
  ok "API Key 已写入配置"
fi

# ── 6. 完成 ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
ok "安装完成！"
echo ""
echo -e "  配置目录: ${BOLD}$CONFIG_DIR${RESET}"
echo -e "  运行:     ${BOLD}opencode${RESET}"
echo ""
echo -e "  包含功能："
echo -e "    • orchestrator agent（主编排，自动分工）"
echo -e "    • Sisyphus / Prometheus（oh-my-opencode 插件）"
echo -e "    • Mify 全模型接入（Opus/Sonnet/Haiku/GPT-5.4/Gemini）"
echo -e "    • 自动 compaction + context pruning"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""
