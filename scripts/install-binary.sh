#!/usr/bin/env bash
# 安装已构建的 opencode 二进制到系统（不构建，只替换）
# 用法：bash scripts/install-binary.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$HOME/.nvm/versions/node/$(node --version 2>/dev/null)/lib/node_modules/opencode-ai/bin"
# 平台动态检测（替代硬编码 darwin-arm64，适配 WSL/Linux/macOS）
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in x86_64|amd64) ARCH="x64" ;; aarch64|arm64) ARCH="arm64" ;; esac
BUILD_BINARY="$REPO/packages/opencode/dist/opencode-${OS}-${ARCH}/bin/opencode"
DATE=$(date +%Y%m%d)

if [ ! -f "$BUILD_BINARY" ]; then
  echo "❌ 构建产物不存在，请先运行 upgrade.sh"
  exit 1
fi

if pgrep -x "opencode-tui\|opencode" > /dev/null 2>&1; then
  echo "⚠️  opencode 进程仍在运行，强制替换可能导致崩溃"
  read -p "确认继续？(y/N) " confirm
  [ "$confirm" = "y" ] || exit 0
fi

# 备份当前版本
if [ -f "$INSTALL/.opencode" ]; then
  cp "$INSTALL/.opencode" "$INSTALL/.opencode.bak.$DATE"
  echo "📦 已备份当前版本 → .opencode.bak.$DATE"
fi

# 替换
cp "$BUILD_BINARY" "$INSTALL/.opencode"
chmod +x "$INSTALL/.opencode"

echo "✅ 已安装新版本"
opencode --version 2>/dev/null || echo "(版本号查询失败，但二进制已替换)"
