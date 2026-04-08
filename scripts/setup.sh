#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 个人版一键安装/更新 — macOS & Linux
#
#  用法：
#    # 首次安装 / 完整更新
#    bash <(curl -fsSL https://raw.githubusercontent.com/vinnfeng/opencode/fengzhen/performance-tuning/scripts/setup.sh)
#
#    # 只更新所有 API Key
#    ./setup.sh --keys
#
#    # 只更新某个 provider 的 key
#    ./setup.sh --key mify
#    ./setup.sh --key bailian
#
#    # 只更新二进制（不动 key 和配置）
#    ./setup.sh --binary
# ═══════════════════════════════════════════════════════════
set -euo pipefail

RELEASE_REPO="vinnfeng/opencode"
RELEASE_TAG="v1.3.17-kaiqu.3"
RELEASE_BASE="https://github.com/$RELEASE_REPO/releases/download/$RELEASE_TAG"
CONFIG_REPO="https://github.com/vinnfeng/opencode-config.git"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencode"
KEYS_FILE="$CONFIG_DIR/.keys"
TEMPLATE_FILE="$CONFIG_DIR/opencode.template.jsonc"
CONFIG_FILE="$CONFIG_DIR/opencode.jsonc"
VERSION_STAMP="$CONFIG_DIR/.installed_version"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}✅  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️   $*${RESET}"; }
err()  { echo -e "${RED}❌  $*${RESET}"; exit 1; }
info() { echo -e "${BLUE}➜   $*${RESET}"; }

# ── 参数解析 ─────────────────────────────────────────────────
MODE="full"       # full | keys | key | binary
TARGET_KEY=""     # 指定单个 key 时的 provider 名（mify / bailian）

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keys|-k)   MODE="keys" ;;
    --key)       MODE="key"; TARGET_KEY="${2:-}"; shift ;;
    --binary|-b) MODE="binary" ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
  shift
done

if [ "$MODE" = "key" ] && [ -z "$TARGET_KEY" ]; then
  err "--key 需要指定 provider 名，例如：--key mify 或 --key bailian"
fi

# ── 工具函数 ─────────────────────────────────────────────────
read_key() {
  local name="$1"
  [ -f "$KEYS_FILE" ] && grep -E "^${name}=" "$KEYS_FILE" 2>/dev/null | cut -d= -f2- | tr -d '\n' || true
}

write_key() {
  local name="$1" value="$2"
  mkdir -p "$(dirname "$KEYS_FILE")"
  if [ -f "$KEYS_FILE" ] && grep -qE "^${name}=" "$KEYS_FILE"; then
    WKEY_NAME="$name" WKEY_VALUE="$value" WKEY_FILE="$KEYS_FILE" \
    node -e "
      const fs=require('fs');
      const f=process.env.WKEY_FILE, n=process.env.WKEY_NAME, v=process.env.WKEY_VALUE;
      fs.writeFileSync(f, fs.readFileSync(f,'utf8').replace(new RegExp('^'+n+'=.*$','m'), n+'='+v));
    "
  else
    printf '%s=%s\n' "$name" "$value" >> "$KEYS_FILE"
  fi
  chmod 600 "$KEYS_FILE"
}

mask_key() {
  local k="$1"
  [ -z "$k" ] && echo "(未设置)" && return
  [ "${#k}" -le 12 ] && echo "${k:0:4}****" && return
  echo "${k:0:8}...${k: -4}"
}

# required=1 表示必填，required=0 表示可选（直接回车跳过）
prompt_key() {
  local name="$1" label="$2" required="${3:-1}" current hint="${4:-}"
  current="$(read_key "$name")"
  echo -e ""
  echo -e "${BOLD}${label}${RESET}"
  [ -n "$hint" ] && echo -e "  ${BLUE}${hint}${RESET}"
  if [ -n "$current" ]; then
    echo -e "  当前值: ${YELLOW}$(mask_key "$current")${RESET}"
    echo -e "  直接回车保留当前，输入新值则更新："
  else
    if [ "$required" -eq 0 ]; then
      echo -e "  ${YELLOW}(未设置，可选 — 直接回车跳过)${RESET}"
    else
      echo -e "  ${YELLOW}(未设置，必填)${RESET}"
    fi
  fi
  read -rsp "  输入: " input
  echo ""
  if [ -n "$input" ]; then
    write_key "$name" "$input"
    ok "${label} 已更新"
  elif [ -n "$current" ]; then
    ok "${label} 保留不变"
  elif [ "$required" -eq 0 ]; then
    warn "${label} 跳过（该 provider 在配置中将不可用）"
  else
    err "${label} 为必填项，请重新运行并输入"
  fi
}

generate_config() {
  info "生成 opencode.jsonc..."
  [ -f "$TEMPLATE_FILE" ] || err "模板文件不存在: $TEMPLATE_FILE，请先完整安装一次"

  local mify_key bailian_key plugin_val
  mify_key="$(read_key MIFY_API_KEY)"
  bailian_key="$(read_key BAILIAN_API_KEY)"

  [ -z "$mify_key" ] && err "MIFY_API_KEY 未设置，请先运行：./setup.sh --key mify"

  local omo_path="$CACHE_DIR/node_modules/oh-my-opencode"
  if [ -d "$omo_path" ]; then
    plugin_val="file://$omo_path"
  else
    plugin_val="oh-my-opencode@latest"
    warn "oh-my-opencode 本地缓存未找到，使用在线版（需要网络）"
  fi

  GEN_MIFY="$mify_key" GEN_BAILIAN="$bailian_key" GEN_PLUGIN="$plugin_val" \
  GEN_TPL="$TEMPLATE_FILE" GEN_OUT="$CONFIG_FILE" \
  node -e "
    const fs=require('fs'), e=process.env;
    let c=fs.readFileSync(e.GEN_TPL,'utf8');
    c=c.replaceAll('MIFY_API_KEY', e.GEN_MIFY);
    c=c.replaceAll('BAILIAN_API_KEY', e.GEN_BAILIAN || 'BAILIAN_API_KEY_NOT_SET');
    c=c.replaceAll('PLUGIN_PATH', e.GEN_PLUGIN);
    // 若 bailian key 未设置，移除整个 bailian provider 块
    if (!e.GEN_BAILIAN) {
      c=c.replace(/,\s*\n\s*\"bailian\":\s*\{[^}]*(?:\{[^}]*\}[^}]*)*\}/s, '');
    }
    fs.writeFileSync(e.GEN_OUT, c);
  "
  ok "opencode.jsonc 已生成"
}

# ── 主流程 ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  开渠 OpenCode 个人版 — 安装/更新              ${RESET}"
echo -e "${BOLD}  版本: $RELEASE_TAG                           ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""

# ── only-keys 模式 ────────────────────────────────────────────
if [ "$MODE" = "keys" ]; then
  echo -e "${BOLD}  模式：更新所有 API Key${RESET}"
  echo ""
  prompt_key "MIFY_API_KEY"    "Mify API Key（必填）" 1 "获取地址：https://llm.mioffice.cn/apikey"
  prompt_key "BAILIAN_API_KEY" "百炼 API Key（可选）" 0 "阿里云百炼平台 Qwen 系列模型"
  generate_config
  ok "Key 更新完成，配置已重新生成"
  exit 0
fi

# ── only-key 模式 ─────────────────────────────────────────────
if [ "$MODE" = "key" ]; then
  case "$TARGET_KEY" in
    mify|MIFY)
      echo -e "${BOLD}  模式：更新 Mify API Key${RESET}"
      echo ""
      prompt_key "MIFY_API_KEY" "Mify API Key（必填）" 1 "获取地址：https://llm.mioffice.cn/apikey"
      ;;
    bailian|BAILIAN)
      echo -e "${BOLD}  模式：更新百炼 API Key${RESET}"
      echo ""
      prompt_key "BAILIAN_API_KEY" "百炼 API Key（可选）" 0 "阿里云百炼平台 Qwen 系列模型"
      ;;
    *) err "不支持的 provider: $TARGET_KEY，可用值：mify / bailian" ;;
  esac
  generate_config
  ok "Key 更新完成，配置已重新生成"
  exit 0
fi

# ── only-binary 模式 ──────────────────────────────────────────
if [ "$MODE" = "binary" ]; then
  echo -e "${BOLD}  模式：只更新二进制${RESET}"
  echo ""
fi

# ── 以下为 full / binary 模式共用 ─────────────────────────────

# 1. 平台检测
OS="$(uname -s)"; ARCH="$(uname -m)"
info "平台: $OS / $ARCH"
case "$OS-$ARCH" in
  Darwin-arm64)  BINARY_NAME="opencode-darwin-arm64" ;;
  Darwin-x86_64) BINARY_NAME="opencode-darwin-x64" ;;
  Linux-x86_64)  BINARY_NAME="opencode-linux-x64" ;;
  Linux-aarch64) BINARY_NAME="opencode-linux-arm64" ;;
  *) err "不支持的平台: $OS-$ARCH" ;;
esac

# 2. 检查依赖
for cmd in git curl; do
  command -v "$cmd" &>/dev/null || err "缺少依赖: $cmd（请先安装）"
done

if [ "$MODE" = "full" ]; then
  # 3. 克隆或更新配置仓库
  if [ -d "$CONFIG_DIR/.git" ]; then
    info "拉取最新配置..."
    cd "$CONFIG_DIR"
    git pull origin "$(git branch --show-current)" --rebase 2>&1 | tail -2
    ok "配置已更新"
  else
    [ -d "$CONFIG_DIR" ] && mv "$CONFIG_DIR" "${CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    info "克隆个人配置..."
    git clone "$CONFIG_REPO" "$CONFIG_DIR"
    ok "配置克隆完成"
  fi
  cd "$CONFIG_DIR"
  git checkout main 2>/dev/null || true

  # 4. API Keys
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  API Key 配置                                  ${RESET}"
  echo -e "  Key 仅存于本机 ${YELLOW}$KEYS_FILE${RESET}，不进 git"
  echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"

  prompt_key "MIFY_API_KEY"    "Mify API Key（必填 — 全平台模型入口）" 1 "获取地址：https://llm.mioffice.cn/apikey"
  prompt_key "BAILIAN_API_KEY" "百炼 API Key（可选 — 阿里云 Qwen）"   0

  # 5. 生成配置
  generate_config
fi

# 6. 下载并安装二进制
DOWNLOAD_URL="$RELEASE_BASE/$BINARY_NAME"

if command -v opencode &>/dev/null; then
  INSTALL_PATH="$(command -v opencode)"
  INSTALLED_TAG="$(cat "$VERSION_STAMP" 2>/dev/null | tr -d '[:space:]' || true)"
  if [ "$INSTALLED_TAG" = "$RELEASE_TAG" ] && [ "$MODE" != "binary" ]; then
    ok "二进制已是最新版 ($RELEASE_TAG)，跳过下载"
  elif [ "$INSTALLED_TAG" = "$RELEASE_TAG" ] && [ "$MODE" = "binary" ]; then
    ok "已是最新版 ($RELEASE_TAG)，无需更新"
    exit 0
  else
    info "已安装: ${INSTALLED_TAG:-未知} → 更新至 $RELEASE_TAG"
    TMP_BIN="$(mktemp)"
    curl -fsSL --progress-bar "$DOWNLOAD_URL" -o "$TMP_BIN" || err "下载失败: $DOWNLOAD_URL"
    chmod +x "$TMP_BIN"
    if [ -w "$(dirname "$INSTALL_PATH")" ]; then mv "$TMP_BIN" "$INSTALL_PATH"
    else sudo mv "$TMP_BIN" "$INSTALL_PATH"; fi
    echo "$RELEASE_TAG" > "$VERSION_STAMP"
    ok "二进制已更新: $INSTALL_PATH ($RELEASE_TAG)"
  fi
else
  INSTALL_PATH="/usr/local/bin/opencode"
  info "首次安装，下载 $BINARY_NAME..."
  TMP_BIN="$(mktemp)"
  curl -fsSL --progress-bar "$DOWNLOAD_URL" -o "$TMP_BIN" || err "下载失败: $DOWNLOAD_URL"
  chmod +x "$TMP_BIN"
  if [ -w "$(dirname "$INSTALL_PATH")" ]; then mv "$TMP_BIN" "$INSTALL_PATH"
  else sudo mv "$TMP_BIN" "$INSTALL_PATH"; fi
  echo "$RELEASE_TAG" > "$VERSION_STAMP"
  ok "二进制已安装: $INSTALL_PATH ($RELEASE_TAG)"
fi

# 7. 完成
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
ok "完成！"
echo ""
echo -e "  版本:     ${BOLD}$RELEASE_TAG${RESET}"
echo -e "  配置:     ${BOLD}$CONFIG_DIR${RESET}"
echo -e "  Key 文件: ${BOLD}$KEYS_FILE${RESET} (仅本机可见)"
echo -e "  运行:     ${BOLD}opencode${RESET}"
echo ""
echo -e "  后续常用命令："
echo -e "    更新所有 key:      ${BLUE}./setup.sh --keys${RESET}"
echo -e "    只换 Mify key:     ${BLUE}./setup.sh --key mify${RESET}"
echo -e "    只换百炼 key:      ${BLUE}./setup.sh --key bailian${RESET}"
echo -e "    只更新二进制:      ${BLUE}./setup.sh --binary${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""
