#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 一键配置安装脚本 — macOS & Linux
#  用法：curl -fsSL <raw-url>/scripts/setup.sh | bash
#  或：  bash scripts/setup.sh
# ═══════════════════════════════════════════════════════════
set -euo pipefail

CONFIG_REPO="https://github.com/vinnfeng/opencode-config.git"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencode"

# ── 颜色 ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}✅  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️   $*${RESET}"; }
err()  { echo -e "${RED}❌  $*${RESET}"; exit 1; }
info() { echo -e "${BLUE}➜   $*${RESET}"; }

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  开渠 OpenCode — 一键配置安装                  ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""

# ── 1. 检测平台 ───────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"
info "平台: $OS / $ARCH"

# ── 2. 检查依赖 ───────────────────────────────────────────────
for cmd in git node npm; do
  if ! command -v "$cmd" &>/dev/null; then
    err "缺少依赖: $cmd。请先安装后重试。"
  fi
done

# ── 3. 安装 opencode（如未安装）────────────────────────────────
if command -v opencode &>/dev/null; then
  CURRENT_VER=$(opencode --version 2>/dev/null || echo "unknown")
  ok "opencode 已安装: $CURRENT_VER"
else
  info "安装 opencode-ai..."
  npm install -g opencode-ai || err "opencode 安装失败，请检查 npm 权限"
  ok "opencode 安装完成: $(opencode --version 2>/dev/null || echo 'ok')"
fi

# ── 4. 克隆或更新配置仓库 ────────────────────────────────────
if [ -d "$CONFIG_DIR/.git" ]; then
  info "配置目录已存在，拉取最新..."
  cd "$CONFIG_DIR"
  CURRENT_BRANCH=$(git branch --show-current)
  git pull origin "$CURRENT_BRANCH" --rebase 2>&1 | tail -3
  ok "配置已更新 (分支: $CURRENT_BRANCH)"
else
  if [ -d "$CONFIG_DIR" ] && [ "$(ls -A "$CONFIG_DIR" 2>/dev/null)" ]; then
    warn "~/.config/opencode 已存在且非空，备份到 ~/.config/opencode.bak..."
    mv "$CONFIG_DIR" "${CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
  fi
  info "克隆配置仓库..."
  git clone "$CONFIG_REPO" "$CONFIG_DIR"
  ok "配置仓库克隆完成"
fi

cd "$CONFIG_DIR"

# ── 5. 选择分支 ───────────────────────────────────────────────
if [ "$OS" = "Linux" ]; then
  TARGET_BRANCH="main"
elif [ "$OS" = "Darwin" ]; then
  TARGET_BRANCH="main"
else
  TARGET_BRANCH="main"
fi

if git show-ref --verify --quiet "refs/remotes/origin/$TARGET_BRANCH"; then
  git checkout "$TARGET_BRANCH" 2>/dev/null || true
fi

# ── 6. 修复 plugin 路径（适配本机缓存路径）────────────────────
PLUGIN_FILE="$CONFIG_DIR/opencode.jsonc"
OMO_CACHE_PATH="$CACHE_DIR/node_modules/oh-my-opencode"

if [ -f "$PLUGIN_FILE" ]; then
  if [ -d "$OMO_CACHE_PATH" ]; then
    # 缓存目录存在，使用 file:// 路径（绕过代理问题）
    NEW_PLUGIN="file://$OMO_CACHE_PATH"
    # 用 node 替换（避免 sed 的跨平台差异）
    node -e "
      const fs = require('fs');
      const path = '$PLUGIN_FILE';
      let content = fs.readFileSync(path, 'utf8');
      content = content.replace(
        /\"file:\/\/[^\"]*oh-my-opencode[^\"]*\"/,
        '\"$NEW_PLUGIN\"'
      );
      fs.writeFileSync(path, content);
    " && info "plugin 路径已更新 → file://$OMO_CACHE_PATH"
  else
    # 缓存不存在，切回 npm 安装方式
    node -e "
      const fs = require('fs');
      const path = '$PLUGIN_FILE';
      let content = fs.readFileSync(path, 'utf8');
      content = content.replace(
        /\"file:\/\/[^\"]*oh-my-opencode[^\"]*\"/,
        '\"oh-my-opencode@latest\"'
      );
      fs.writeFileSync(path, content);
    " && info "plugin 路径已重置为 npm 安装: oh-my-opencode@latest"
  fi
fi

# ── 7. 安装配置依赖（如有 package.json）────────────────────────
if [ -f "$CONFIG_DIR/package.json" ]; then
  info "安装配置依赖..."
  cd "$CONFIG_DIR"
  if command -v bun &>/dev/null; then
    bun install --silent 2>/dev/null || npm install --silent
  else
    npm install --silent
  fi
fi

# ── 8. 完成 ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
ok "安装完成！"
echo ""
echo -e "  配置目录: ${BOLD}$CONFIG_DIR${RESET}"
echo -e "  运行方式: ${BOLD}opencode${RESET}"
echo ""
echo -e "  可用 Agent（按 Tab 切换）:"
echo -e "    • orchestrator — 主编排（默认）"
echo -e "    • Sisyphus     — oh-my-opencode 全力模式"
echo -e "    • Prometheus   — 任务规划"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""
