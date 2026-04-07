#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 个人版一键安装 — macOS & Linux
#  安装我们 fork 的自定义二进制 + 个人配置（含 key）
#
#  用法（macOS/Linux）：
#    bash <(curl -fsSL https://raw.githubusercontent.com/vinnfeng/opencode/fengzhen/performance-tuning/scripts/setup.sh)
# ═══════════════════════════════════════════════════════════
set -euo pipefail

RELEASE_REPO="vinnfeng/opencode"
RELEASE_TAG="v1.3.17-kaiqu.3"
RELEASE_BASE="https://github.com/$RELEASE_REPO/releases/download/$RELEASE_TAG"
CONFIG_REPO="https://github.com/vinnfeng/opencode-config.git"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencode"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}✅  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️   $*${RESET}"; }
err()  { echo -e "${RED}❌  $*${RESET}"; exit 1; }
info() { echo -e "${BLUE}➜   $*${RESET}"; }

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  开渠 OpenCode 个人版 — 一键安装              ${RESET}"
echo -e "${BOLD}  $RELEASE_TAG                                 ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""

# ── 1. 平台检测 ───────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"
info "平台: $OS / $ARCH"

case "$OS-$ARCH" in
  Darwin-arm64)  BINARY_NAME="opencode-darwin-arm64" ;;
  Darwin-x86_64) BINARY_NAME="opencode-darwin-x64" ;;
  Linux-x86_64)  BINARY_NAME="opencode-linux-x64" ;;
  Linux-aarch64) BINARY_NAME="opencode-linux-arm64" ;;
  *) err "不支持的平台: $OS-$ARCH" ;;
esac

# ── 2. 检查依赖 ───────────────────────────────────────────────
for cmd in git curl; do
  command -v "$cmd" &>/dev/null || err "缺少依赖: $cmd"
done

# ── 3. 下载并安装我们的自定义二进制 ──────────────────────────
DOWNLOAD_URL="$RELEASE_BASE/$BINARY_NAME"

# 找到 opencode 的安装位置
if command -v opencode &>/dev/null; then
  INSTALL_PATH="$(command -v opencode)"
  info "找到已安装的 opencode: $INSTALL_PATH"
else
  # 默认安装到 /usr/local/bin
  INSTALL_PATH="/usr/local/bin/opencode"
  info "将安装到: $INSTALL_PATH"
fi

info "下载 $BINARY_NAME ($RELEASE_TAG)..."
TMP_BIN="$(mktemp)"
curl -fsSL --progress-bar "$DOWNLOAD_URL" -o "$TMP_BIN" || err "下载失败: $DOWNLOAD_URL"
chmod +x "$TMP_BIN"

# 替换二进制（需要写权限）
if [ -w "$(dirname "$INSTALL_PATH")" ]; then
  mv "$TMP_BIN" "$INSTALL_PATH"
else
  sudo mv "$TMP_BIN" "$INSTALL_PATH"
fi
ok "二进制已安装: $INSTALL_PATH ($(opencode --version 2>/dev/null || echo $RELEASE_TAG))"

# ── 4. 克隆或更新配置仓库 ────────────────────────────────────
if [ -d "$CONFIG_DIR/.git" ]; then
  info "配置目录已存在，拉取最新..."
  cd "$CONFIG_DIR"
  git pull origin "$(git branch --show-current)" --rebase 2>&1 | tail -2
  ok "配置已更新"
else
  [ -d "$CONFIG_DIR" ] && mv "$CONFIG_DIR" "${CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
  info "克隆个人配置..."
  git clone "$CONFIG_REPO" "$CONFIG_DIR"
  ok "配置克隆完成"
fi

# ── 5. 选分支（macOS 用 main，Linux 用 main）────────────────
cd "$CONFIG_DIR"
git checkout main 2>/dev/null || true

# ── 6. 修复 plugin 路径（适配本机缓存）────────────────────────
PLUGIN_FILE="$CONFIG_DIR/opencode.jsonc"
OMO_CACHE_PATH="$CACHE_DIR/node_modules/oh-my-opencode"
if [ -f "$PLUGIN_FILE" ] && [ -d "$OMO_CACHE_PATH" ]; then
  node -e "
    const fs=require('fs'), p='$PLUGIN_FILE';
    fs.writeFileSync(p, fs.readFileSync(p,'utf8').replace(
      /\"file:\/\/[^\"]*oh-my-opencode[^\"]*\"/,
      '\"file://$OMO_CACHE_PATH\"'
    ));
  " && info "plugin 路径已同步 → file://$OMO_CACHE_PATH"
fi

# ── 7. 完成 ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
ok "安装完成！opencode 已是我们的自定义版本。"
echo ""
echo -e "  版本:     ${BOLD}$RELEASE_TAG${RESET}"
echo -e "  配置目录: ${BOLD}$CONFIG_DIR${RESET}"
echo -e "  运行:     ${BOLD}opencode${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""
