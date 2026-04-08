#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 个人版一键安装/更新 — macOS & Linux
#  安装我们 fork 的自定义二进制 + 配置（key 本地存储，不进 git）
#
#  用法：
#    bash <(curl -fsSL https://raw.githubusercontent.com/vinnfeng/opencode/fengzhen/performance-tuning/scripts/setup.sh)
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

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}✅  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️   $*${RESET}"; }
err()  { echo -e "${RED}❌  $*${RESET}"; exit 1; }
info() { echo -e "${BLUE}➜   $*${RESET}"; }

# ── 工具函数：从 .keys 读取 key ──────────────────────────────
read_key() {
  local name="$1"
  if [ -f "$KEYS_FILE" ]; then
    grep -E "^${name}=" "$KEYS_FILE" 2>/dev/null | cut -d= -f2- | tr -d '\n' || true
  fi
}

# 工具函数：写入 .keys（upsert）
write_key() {
  local name="$1" value="$2"
  mkdir -p "$(dirname "$KEYS_FILE")"
  if [ -f "$KEYS_FILE" ] && grep -qE "^${name}=" "$KEYS_FILE"; then
    # 通过环境变量传值，避免 shell 注入
    WKEY_NAME="$name" WKEY_VALUE="$value" WKEY_FILE="$KEYS_FILE" \
    node -e "
      const fs=require('fs');
      const f=process.env.WKEY_FILE, n=process.env.WKEY_NAME, v=process.env.WKEY_VALUE;
      const re=new RegExp('^' + n + '=.*$', 'm');
      fs.writeFileSync(f, fs.readFileSync(f,'utf8').replace(re, n + '=' + v));
    "
  else
    printf '%s=%s\n' "$name" "$value" >> "$KEYS_FILE"
  fi
  chmod 600 "$KEYS_FILE"
}

# 工具函数：掩码显示 key（sk-xxxx...xxxx）
mask_key() {
  local k="$1"
  if [ -z "$k" ]; then echo "(未设置)"; return; fi
  local len=${#k}
  if [ "$len" -le 12 ]; then echo "${k:0:4}****"; return; fi
  echo "${k:0:8}...${k: -4}"
}

# ── 工具函数：交互式 key 设置 ────────────────────────────────
prompt_key() {
  local name="$1" label="$2" current
  current="$(read_key "$name")"
  echo -e ""
  echo -e "${BOLD}${label}${RESET}"
  if [ -n "$current" ]; then
    echo -e "  当前值: ${YELLOW}$(mask_key "$current")${RESET}"
    echo -e "  直接回车保留当前，输入新值则更新："
  else
    echo -e "  ${YELLOW}(未设置，请输入)${RESET}"
  fi
  read -rsp "  输入: " input
  echo ""
  if [ -n "$input" ]; then
    write_key "$name" "$input"
    ok "${label} 已更新"
  elif [ -n "$current" ]; then
    ok "${label} 保留不变"
  else
    err "${label} 不能为空，请重新运行并输入"
  fi
}

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  开渠 OpenCode 个人版 — 安装/更新              ${RESET}"
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

# ── 3. 克隆或更新配置仓库 ────────────────────────────────────
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

# 切换到 main 分支
cd "$CONFIG_DIR"
git checkout main 2>/dev/null || true

# ── 4. 设置 API Keys ─────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  API Key 配置                                  ${RESET}"
echo -e "  Key 仅保存在本机 ${YELLOW}$KEYS_FILE${RESET}，不进 git"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"

prompt_key "MIFY_API_KEY"    "Mify API Key（获取地址：https://llm.mioffice.cn/apikey）"
prompt_key "BAILIAN_API_KEY" "百炼 API Key（阿里云 Qwen）"

# ── 5. 生成 opencode.jsonc ───────────────────────────────────
info "生成 opencode.jsonc..."
[ -f "$TEMPLATE_FILE" ] || err "模板文件不存在: $TEMPLATE_FILE"

MIFY_KEY="$(read_key MIFY_API_KEY)"
BAILIAN_KEY="$(read_key BAILIAN_API_KEY)"

# 找 oh-my-opencode 缓存路径
OMO_PATH="$CACHE_DIR/node_modules/oh-my-opencode"
if [ -d "$OMO_PATH" ]; then
  PLUGIN_VAL="file://$OMO_PATH"
else
  PLUGIN_VAL="oh-my-opencode@latest"
  warn "oh-my-opencode 缓存未找到，将使用在线版（需要网络）"
fi

GEN_MIFY="$MIFY_KEY" GEN_BAILIAN="$BAILIAN_KEY" GEN_PLUGIN="$PLUGIN_VAL" \
GEN_TPL="$TEMPLATE_FILE" GEN_OUT="$CONFIG_FILE" \
node -e "
  const fs=require('fs'), e=process.env;
  let c=fs.readFileSync(e.GEN_TPL,'utf8');
  c=c.replaceAll('MIFY_API_KEY', e.GEN_MIFY);
  c=c.replaceAll('BAILIAN_API_KEY', e.GEN_BAILIAN);
  c=c.replaceAll('PLUGIN_PATH', e.GEN_PLUGIN);
  fs.writeFileSync(e.GEN_OUT, c);
"
ok "opencode.jsonc 已生成"

# ── 6. 下载并安装我们的自定义二进制 ──────────────────────────
DOWNLOAD_URL="$RELEASE_BASE/$BINARY_NAME"
VERSION_STAMP="$CONFIG_DIR/.installed_version"

if command -v opencode &>/dev/null; then
  INSTALL_PATH="$(command -v opencode)"
  INSTALLED_TAG="$(cat "$VERSION_STAMP" 2>/dev/null | tr -d '[:space:]' || true)"
  if [ "$INSTALLED_TAG" = "$RELEASE_TAG" ]; then
    ok "二进制已是最新版 ($RELEASE_TAG)，跳过下载"
    SKIP_BINARY=1
  else
    info "已安装: ${INSTALLED_TAG:-未知}，将更新至 $RELEASE_TAG"
    SKIP_BINARY=0
  fi
else
  INSTALL_PATH="/usr/local/bin/opencode"
  info "将安装到: $INSTALL_PATH"
  SKIP_BINARY=0
fi

if [ "$SKIP_BINARY" -eq 0 ]; then
  info "下载 $BINARY_NAME ($RELEASE_TAG)..."
  TMP_BIN="$(mktemp)"
  curl -fsSL --progress-bar "$DOWNLOAD_URL" -o "$TMP_BIN" || err "下载失败: $DOWNLOAD_URL"
  chmod +x "$TMP_BIN"
  if [ -w "$(dirname "$INSTALL_PATH")" ]; then
    mv "$TMP_BIN" "$INSTALL_PATH"
  else
    sudo mv "$TMP_BIN" "$INSTALL_PATH"
  fi
  echo "$RELEASE_TAG" > "$VERSION_STAMP"
  ok "二进制已安装: $INSTALL_PATH ($RELEASE_TAG)"
fi

# ── 7. 完成 ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
ok "安装完成！opencode 已是我们的自定义版本。"
echo ""
echo -e "  版本:     ${BOLD}$RELEASE_TAG${RESET}"
echo -e "  配置目录: ${BOLD}$CONFIG_DIR${RESET}"
echo -e "  Key 文件: ${BOLD}$KEYS_FILE${RESET} (仅本机可见)"
echo -e "  运行:     ${BOLD}opencode${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""
