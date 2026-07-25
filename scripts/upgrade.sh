#!/usr/bin/env bash
# opencode 升级脚本：拉取官方最新 + rebase 我们的补丁 + 构建 + 安装
# 用法：bash scripts/upgrade.sh [--dry-run] [--force]
# --dry-run : 只拉取和 rebase，不构建不安装
# --force   : 即使开渠正在运行也强制替换二进制（危险）
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$HOME/.nvm/versions/node/$(node --version 2>/dev/null)/lib/node_modules/opencode-ai/bin"
_current_branch="$(git -C "$REPO" branch --show-current 2>/dev/null || true)"
BRANCH="${OPENCODE_BRANCH:-${_current_branch:-main}}"  # 可配置(OPENCODE_BRANCH), 默认当前分支(detached HEAD 空值回退 main), 去硬编码 release/kaiqu
UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="dev"
DRY_RUN=false
FORCE=false

# ── 参数解析 ────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --force)   FORCE=true ;;
    *) echo "未知参数: $arg"; exit 1 ;;
  esac
done

cd "$REPO"

# ── 安全检查：开渠是否在运行 ────────────────────────────
check_opencode_running() {
  pgrep -x "opencode-tui\|opencode" > /dev/null 2>&1
}

echo "═══════════════════════════════════════════════"
echo " OpenCode 升级脚本"
echo "═══════════════════════════════════════════════"
echo "仓库: $REPO"
echo "分支: $BRANCH"
echo "目标: $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
echo ""

# ── Step 1: 确认当前分支 ─────────────────────────────────
CURRENT=$(git branch --show-current)
if [ "$CURRENT" != "$BRANCH" ]; then
  echo "⚠️  当前在 $CURRENT，切换到 $BRANCH ..."
  git checkout "$BRANCH"
fi

# ── Step 2: 记录我们的自定义提交 ──────────────────────────
echo "📋 我们在 upstream 之上的自定义提交："
CUSTOM_COMMITS=$(git log --oneline "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH".."$BRANCH" 2>/dev/null || echo "(none)")
echo "$CUSTOM_COMMITS"
echo ""

# ── Step 3: 拉取官方最新 ──────────────────────────────────
echo "⬇️  拉取 $UPSTREAM_REMOTE 最新..."
git fetch "$UPSTREAM_REMOTE"

BEHIND=$(git rev-list --count "$BRANCH".."$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" 2>/dev/null || echo "0")
if [ "$BEHIND" = "0" ]; then
  echo "✅ 已是最新，upstream 无新提交"
  if [ "$DRY_RUN" = "true" ]; then exit 0; fi
else
  echo "📦 上游有 $BEHIND 个新提交，开始 rebase..."
  # ── Step 4: Rebase ────────────────────────────────────
  if ! git rebase "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"; then
    echo ""
    echo "❌ Rebase 出现冲突！"
    echo ""
    echo "冲突文件："
    git diff --name-only --diff-filter=U 2>/dev/null || true
    echo ""
    echo "处理方式："
    echo "  1. 手动解决冲突文件"
    echo "  2. git add <冲突文件>"
    echo "  3. git rebase --continue"
    echo "  或：git rebase --abort 放弃本次升级"
    exit 1
  fi
  echo "✅ Rebase 成功"
fi

if [ "$DRY_RUN" = "true" ]; then
  echo ""
  echo "[dry-run] 跳过构建和安装"
  exit 0
fi

# ── Step 5: 检查开渠是否在运行 ────────────────────────────
if check_opencode_running && [ "$FORCE" = "false" ]; then
  echo ""
  echo "⚠️  开渠（opencode）正在运行，跳过二进制安装"
  echo "   构建完成后请在开渠空闲时手动执行安装："
  echo "   bash $REPO/scripts/install-binary.sh"
  echo ""
  echo "   或使用 --force 强制替换（可能导致当前会话崩溃）"
  BUILD_ONLY=true
else
  BUILD_ONLY=false
fi

# ── Step 6: 构建 ─────────────────────────────────────────
echo ""
echo "🔨 构建中... (需要 1-3 分钟)"
BUILD_PKG="$REPO/packages/opencode"

if [ ! -d "$BUILD_PKG" ]; then
  echo "❌ 找不到 packages/opencode 目录: $BUILD_PKG"
  exit 1
fi

cd "$BUILD_PKG"
bun run build 2>&1 | tail -20
# 平台动态检测（替代硬编码 darwin-arm64，适配 WSL/Linux/macOS）
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in x86_64|amd64) ARCH="x64" ;; aarch64|arm64) ARCH="arm64" ;; esac
BUILD_BINARY="$BUILD_PKG/dist/opencode-${OS}-${ARCH}/bin/opencode"

if [ ! -f "$BUILD_BINARY" ]; then
  echo "❌ 构建产物不存在: $BUILD_BINARY"
  exit 1
fi
echo "✅ 构建成功: $BUILD_BINARY"

# ── Step 7: 安装 ─────────────────────────────────────────
if [ "$BUILD_ONLY" = "true" ]; then
  echo ""
  echo "构建产物已准备好，等待手动安装："
  echo "  bash $REPO/scripts/install-binary.sh"
  exit 0
fi

cd "$REPO"
bash "$REPO/scripts/install-binary.sh"
