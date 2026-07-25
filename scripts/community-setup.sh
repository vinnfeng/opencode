#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 社区版安装/更新 — macOS & Linux
#  安装官方 opencode + Provider 配置 + 优化 agent 体系
#  Key 本地存储，不进 git，支持更新时保留上次配置
#
#  用法：
#    ./community-setup.sh  (在 vinnfeng/opencode 克隆目录的 scripts/ 下运行)
# ═══════════════════════════════════════════════════════════
set -euo pipefail

CONFIG_REPO="https://github.com/vinnfeng/opencode-config.git"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
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

# 工具函数：掩码显示 key
mask_key() {
  local k="$1"
  if [ -z "$k" ]; then echo "(未设置)"; return; fi
  local len=${#k}
  if [ "$len" -le 12 ]; then echo "${k:0:4}****"; return; fi
  echo "${k:0:8}...${k: -4}"
}

# ── 工具函数：交互式 key 设置 ────────────────────────────────
prompt_key() {
  local name="$1" label="$2" current hint="${3:-}"
  current="$(read_key "$name")"
  echo -e ""
  echo -e "${BOLD}${label}${RESET}"
  [ -n "$hint" ] && echo -e "  ${BLUE}${hint}${RESET}"
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
    err "${label} 为必填项，请重新运行并输入"
  fi
}

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  开渠 OpenCode 社区版 — 安装/更新              ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""

# ── 1. 检查依赖 ───────────────────────────────────────────────
for cmd in git curl node npm; do
  command -v "$cmd" &>/dev/null || err "缺少依赖: $cmd"
done

# ── 2. 安装官方 opencode ──────────────────────────────────────
if command -v opencode &>/dev/null; then
  ok "opencode 已安装: $(opencode --version 2>/dev/null || echo 'ok')"
else
  info "安装 opencode-ai (官方版)..."
  npm install -g opencode-ai || err "安装失败，请检查 npm 权限"
  ok "opencode 安装完成"
fi

# ── 3. 克隆配置仓库（community 分支）────────────────────────
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

cd "$CONFIG_DIR"

# ── 4. 设置 API Key ──────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  API Key 配置                                  ${RESET}"
echo -e "  Key 仅保存在本机 ${YELLOW}$KEYS_FILE${RESET}，不进 git"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"

prompt_key "PROVIDER_API_KEY" "Provider API Key（必填）" "向管理员获取 API Key"

# ── 5. 生成 opencode.jsonc ───────────────────────────────────
info "生成 opencode.jsonc..."
[ -f "$TEMPLATE_FILE" ] || err "模板文件不存在: $TEMPLATE_FILE"

PROVIDER_KEY="$(read_key PROVIDER_API_KEY)"

GEN_PROVIDER="$PROVIDER_KEY" GEN_TPL="$TEMPLATE_FILE" GEN_OUT="$CONFIG_FILE" \
node -e "
  const fs=require('fs'), e=process.env;
  let c=fs.readFileSync(e.GEN_TPL,'utf8');
  c=c.replaceAll('PROVIDER_API_KEY', e.GEN_PROVIDER);
  fs.writeFileSync(e.GEN_OUT, c);
"
ok "opencode.jsonc 已生成"

# ── 6. 完成 ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
ok "安装完成！"
echo ""
echo -e "  配置目录: ${BOLD}$CONFIG_DIR${RESET}"
echo -e "  Key 文件: ${BOLD}$KEYS_FILE${RESET} (仅本机可见)"
echo -e "  运行:     ${BOLD}opencode${RESET}"
echo ""
echo -e "  包含功能："
echo -e "    • orchestrator agent（主编排，自动分工）"
echo -e "    • Sisyphus / Prometheus（oh-my-opencode 插件）"
echo -e "    • Provider 全模型接入（Opus/Sonnet/GPT-5.4/Gemini）"
echo -e "    • 自动 compaction + context pruning"
COMMUNITY_URL="https://raw.githubusercontent.com/vinnfeng/opencode/release/kaiqu/scripts/community-setup.sh"
echo -e "  更新时重新运行，Key 自动从上次记录填入："
echo -e "    ${BLUE}bash <(curl -fsSL $COMMUNITY_URL)${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""
