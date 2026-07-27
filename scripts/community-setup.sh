#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 社区版安装/更新 - macOS & Linux
#  安装官方 opencode + Provider 配置 + 优化 agent 体系
#  Key 本地存储，不进 git，支持更新时保留上次配置
#
#  用法（raw URL 固定到 RELEASE_TAG，符合 RAW-URL-POLICY 条件 2/3）：
#    bash <(curl -fsSL https://raw.githubusercontent.com/vinnfeng/opencode/v1.3.17-kaiqu.3/scripts/community-setup.sh)
# ═══════════════════════════════════════════════════════════
set -euo pipefail

RELEASE_TAG="v1.3.17-kaiqu.3"
CONFIG_REPO="https://github.com/vinnfeng/opencode-config.git"
# D4 条件 2/3: CONFIG checkout 固定 commit SHA（非浮动 community 分支）
CONFIG_REF="3b91bce58bb4d99b4b33c58d52a73e90721e1e75"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
KEYS_FILE="$CONFIG_DIR/.keys"
TEMPLATE_FILE="$CONFIG_DIR/opencode.template.jsonc"
CONFIG_FILE="$CONFIG_DIR/opencode.jsonc"
# D4 条件 2/3: 脚本分发 URL 固定到 RELEASE_TAG（非浮动分支）
COMMUNITY_URL="https://raw.githubusercontent.com/vinnfeng/opencode/$RELEASE_TAG/scripts/community-setup.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}✅  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️   $*${RESET}"; }
err()  { echo -e "${RED}❌  $*${RESET}"; exit 1; }
info() { echo -e "${BLUE}➜   $*${RESET}"; }

# ── D4 缺陷2: 可信来源白名单校验（硬化：decode+规范化+拒 dot-segment 变体）──
assert_trusted_source() {
  local url="$1"
  case "$url" in
    https://github.com/vinnfeng/*|https://raw.githubusercontent.com/vinnfeng/*) : ;;
    *) err "来源不在可信白名单（D4 缺陷2）: $url（仅允许 github.com/vinnfeng/* 或 raw.githubusercontent.com/vinnfeng/*）" ;;
  esac
  # 四审加固：可信 URL 本不需编码，拒绝任何 % 编码和反斜杠（最小修复）
  case "$url" in
    *%*) err "可信 URL 含 % 编码（D4 缺陷2 四审）: $url" ;;
  esac
  case "$url" in
    *\\*) err "可信 URL 含反斜杠（D4 缺陷2 四审）: $url" ;;
  esac
  # 明文 dot-segment 检查（防御深度）
  if printf '%s' "$url" | grep -qE '/(\.\.?)(/|$)'; then
    err "来源含 dot-segment（D4 缺陷2）: $url"
  fi
}
# ── D4 缺陷5: 不可变 ref 校验（白名单：仅 40hex SHA 或 vX.Y.Z[-pre] tag）──
assert_immutable_ref() {
  local ref="${1:-}"
  [ -n "$ref" ] || err "拒绝空 ref（D4 缺陷5）"
  printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$' && return 0
  printf '%s' "$ref" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$' && return 0
  err "拒绝浮动/非法 ref（D4 缺陷5）: '$ref'（仅允许 40位hex SHA 或 vX.Y.Z[-pre] tag；禁 main/master/dev/release/office-windows/latest/HEAD 等）"
}
# ── D4 缺陷3: CONFIG_REF 必须 40位hex commit SHA（防误填分支名/tag）──
assert_commit_sha() {
  local ref="${1:-}"
  printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$' \
    || err "CONFIG_REF 必须 40位hex commit SHA（D4 缺陷3）: '$ref'（不得用分支名/tag）"
}

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
    echo -e "  当前值: ${YELLOW}$(mask_key "$current")}${RESET}"
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
echo -e "${BOLD}  开渠 OpenCode 社区版 - 安装/更新              ${RESET}"
echo -e "${BOLD}  版本: $RELEASE_TAG                            ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""

# ── 1. 检查依赖 ───────────────────────────────────────────────
for cmd in git curl node npm; do
  command -v "$cmd" &>/dev/null || err "缺少依赖: $cmd"
done

# ── D4 缺陷2/3/5: 白名单 + 不可变 ref + CONFIG_REF SHA 校验 ──
assert_trusted_source "$COMMUNITY_URL"
assert_trusted_source "$CONFIG_REPO"
assert_immutable_ref "$RELEASE_TAG"
assert_commit_sha "$CONFIG_REF"

# ── 2. 安装官方 opencode ──────────────────────────────────────
# D4 缺陷4/5：社区版走 npm 渠道，必须锁版本 + 固定官方 registry + 装后校验实际版本
# （铸言复核：原 npm install -g opencode-ai 隐式 @latest，无完整性校验，N/A 标注不合理）
OPENCODE_NPM_PKG="opencode-ai@1.18.7"
NPM_REGISTRY="https://registry.npmjs.org"
if command -v opencode &>/dev/null; then
  EXISTING_VER="$(opencode --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
else
  EXISTING_VER=""
fi
# 缺陷5：已存在 opencode 必须校验版本，旧版绕过 1.18.7 锁定 -> 卸载重装+校验
if [ "$EXISTING_VER" = "1.18.7" ]; then
  ok "opencode 已是锁定版本: $EXISTING_VER"
else
  if [ -n "$EXISTING_VER" ]; then
    warn "opencode 已存在 ($EXISTING_VER) 非 1.18.7，卸载重装（D4 缺陷5：旧版绕过锁定）"
    npm uninstall -g opencode-ai --registry="$NPM_REGISTRY" 2>/dev/null || true
  else
    info "未检测到 opencode，安装 $OPENCODE_NPM_PKG (官方版，固定 registry)..."
  fi
  npm install -g "$OPENCODE_NPM_PKG" --registry="$NPM_REGISTRY" \
    || err "安装失败，请检查 npm 权限/registry"
  # 缺陷5：装后校验实际版本，防止 registry 返回其他版本/被替换
  INSTALLED_VER="$(npm list -g opencode-ai --depth=0 2>/dev/null | grep -oE 'opencode-ai@[0-9.]+' | head -1 | cut -d@ -f2 || true)"
  [ -n "$INSTALLED_VER" ] || err "opencode-ai 安装后无法确认版本（D4 缺陷5）"
  if [ "$INSTALLED_VER" != "1.18.7" ]; then
    err "opencode-ai 实际版本 ($INSTALLED_VER) 与锁定 (1.18.7) 不符（D4 缺陷5）"
  fi
  ok "opencode 安装完成 ($INSTALLED_VER)"
fi

# ── 3. 克隆配置仓库（D4 条件 2/3: 固定 CONFIG_REF commit SHA）──
if [ -d "$CONFIG_DIR/.git" ]; then
  info "配置目录已存在，更新中（固定到 $CONFIG_REF）..."
  cd "$CONFIG_DIR"
  git fetch origin 2>&1 | tail -2
  git checkout "$CONFIG_REF" 2>/dev/null || err "CONFIG_REF 固定版本不存在: $CONFIG_REF（D4 条件 2/3）"
  ok "配置已更新到固定版本"
else
  [ -d "$CONFIG_DIR" ] && mv "$CONFIG_DIR" "${CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
  info "克隆配置（固定到 $CONFIG_REF）..."
  git clone "$CONFIG_REPO" "$CONFIG_DIR"
  cd "$CONFIG_DIR"
  git fetch origin 2>&1 | tail -2
  git checkout "$CONFIG_REF" 2>/dev/null || err "CONFIG_REF 固定版本不存在: $CONFIG_REF（D4 条件 2/3）"
  ok "配置克隆完成（固定版本）"
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

# ── 6. 完成（D4 条件 6: 显示真实来源与固定版本）──────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
ok "安装完成！"
echo ""
echo -e "  来源:     ${BOLD}$COMMUNITY_URL${RESET}"
echo -e "  版本:     ${BOLD}$RELEASE_TAG${RESET}"
echo -e "  配置目录: ${BOLD}$CONFIG_DIR${RESET}"
echo -e "  Key 文件: ${BOLD}$KEYS_FILE${RESET} (仅本机可见)"
echo -e "  运行:     ${BOLD}opencode${RESET}"
echo ""
echo -e "  包含功能："
echo -e "    • orchestrator agent（主编排，自动分工）"
echo -e "    • Sisyphus / Prometheus（oh-my-opencode 插件）"
echo -e "    • Provider 全模型接入（Opus/Sonnet/GPT-5.4/Gemini）"
echo -e "    • 自动 compaction + context pruning"
echo -e "  更新时重新运行，Key 自动从上次记录填入："
echo -e "    ${BLUE}bash <(curl -fsSL $COMMUNITY_URL)${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""
