#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 个人版一键安装/更新 - macOS & Linux
#
#  首次安装 / 完整更新（raw URL 固定到 RELEASE_TAG，符合 RAW-URL-POLICY 条件 2/3）：
#    bash <(curl -fsSL https://raw.githubusercontent.com/vinnfeng/opencode/v1.3.17-kaiqu.3/scripts/setup.sh)
#
#  带参数运行（同样用 curl 方式）：
#    bash <(curl -fsSL ...setup.sh) --keys       # 只更新所有 key
#    bash <(curl -fsSL ...setup.sh) --key mify   # 只换 Provider key
#    bash <(curl -fsSL ...setup.sh) --key bailian # 只换百炼 key
#    bash <(curl -fsSL ...setup.sh) --binary     # 只更新二进制
#    bash <(curl -fsSL ...setup.sh) --help       # 查看帮助
#
#  也可保存到本地后使用：
#    curl -fsSL https://raw.githubusercontent.com/vinnfeng/opencode/v1.3.17-kaiqu.3/scripts/setup.sh -o ~/opencode-setup.sh && chmod +x ~/opencode-setup.sh
#    ~/opencode-setup.sh --keys
# ═══════════════════════════════════════════════════════════
set -euo pipefail

RELEASE_REPO="vinnfeng/opencode"
RELEASE_TAG="v1.3.17-kaiqu.3"
RELEASE_BASE="https://github.com/$RELEASE_REPO/releases/download/$RELEASE_TAG"
CONFIG_REPO="https://github.com/vinnfeng/opencode-config.git"
# D4 条件 2/3: CONFIG checkout 固定 commit SHA（非浮动 main 分支），获取时锁定
CONFIG_REF="239172fb812ab87d79eada36f9253a39018e59bc"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencode"
KEYS_FILE="$CONFIG_DIR/.keys"
TEMPLATE_FILE="$CONFIG_DIR/opencode.template.jsonc"
CONFIG_FILE="$CONFIG_DIR/opencode.jsonc"
VERSION_STAMP="$CONFIG_DIR/.installed_version"
PREVIOUS_VERSION_STAMP="$CONFIG_DIR/.previous_version"
BACKUP_DIR="$CACHE_DIR/backups"
# D4 条件 5: manifest 保存来源/版本/哈希/获取时间
MANIFEST_FILE="$CONFIG_DIR/.install_manifest"
# D4 条件 2/3: 脚本分发 URL 固定到 RELEASE_TAG（非浮动分支）
SETUP_URL="https://raw.githubusercontent.com/vinnfeng/opencode/$RELEASE_TAG/scripts/setup.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}✅  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️   $*${RESET}"; }
err()  { echo -e "${RED}❌  $*${RESET}"; exit 1; }
info() { echo -e "${BLUE}➜   $*${RESET}"; }

# ── D4 缺陷2: 可信来源白名单校验（硬化：decode+规范化+拒 dot-segment 变体）──
# 严格前缀匹配 https://<host>/vinnfeng/（尾斜杠防 vinnfengfoo 前缀绕过）。
# 先 URL decode（%2e/%2f/%5c/%25，循环解码双重编码 %252e->%2e->.）+ 反斜杠转斜杠，
# 再拒任何 dot-segment（../ /./ 及编码/反斜杠变体）防 owner 路径穿越到 attacker 仓。
assert_trusted_source() {
  local url="$1" decoded prev
  case "$url" in
    https://github.com/vinnfeng/*|https://raw.githubusercontent.com/vinnfeng/*) : ;;
    *) err "来源不在可信白名单（D4 缺陷2）: $url（仅允许 github.com/vinnfeng/* 或 raw.githubusercontent.com/vinnfeng/*）" ;;
  esac
  decoded="$url"; prev=""
  while [ "$decoded" != "$prev" ]; do
    prev="$decoded"
    decoded="$(printf '%s' "$decoded" | sed 's/%2[eE]/./g; s/%2[fF]/\//g; s/%5[cC]/\\/g; s/%25/%/g')"
  done
  decoded="$(printf '%s' "$decoded" | tr '\\' '/')"
  if printf '%s' "$decoded" | grep -qE '/(\.\.?)(/|$)'; then
    err "来源含 dot-segment/编码/反斜杠变体（D4 缺陷2 路径穿越）: $url"
  fi
}

# ── D4 缺陷5: 不可变 ref 校验（白名单：仅 40hex SHA 或 vX.Y.Z[-pre] tag）──
# 黑名单易漏（release/office-windows/feature/foo 不在表内会被放行），改白名单严格允许。
assert_immutable_ref() {
  local ref="${1:-}"
  [ -n "$ref" ] || err "拒绝空 ref（D4 缺陷5）"
  printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$' && return 0
  printf '%s' "$ref" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' && return 0
  err "拒绝浮动/非法 ref（D4 缺陷5）: '$ref'（仅允许 40位hex SHA 或 vX.Y.Z[-pre] tag；禁 main/master/dev/release/office-windows/latest/HEAD 等）"
}

# ── D4 缺陷3: CONFIG_REF 必须 40位hex commit SHA（防误填分支名/tag）──
assert_commit_sha() {
  local ref="${1:-}"
  printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$' \
    || err "CONFIG_REF 必须 40位hex commit SHA（D4 缺陷3）: '$ref'（不得用分支名/tag）"
}

# ── D4: SHA256 验证（条件 4）─────────────────────────────────
# 取 $url 的 .sha256 校验文件，对比 $file 实际哈希；不存在/不匹配 err 阻断
verify_sha256() {
  local url="$1" file="$2" sum_url sum_tmp expected actual
  sum_url="${url}.sha256"
  sum_tmp="$(mktemp)"
  if ! curl -fsSL "$sum_url" -o "$sum_tmp" 2>/dev/null || [ ! -s "$sum_tmp" ]; then
    rm -f "$sum_tmp"
    err "SHA256 校验文件不存在: $sum_url（D4 条件 4：release 须附 .sha256 资产，当前 release 未附）"
  fi
  expected="$(grep -oE '^[a-f0-9]{64}' "$sum_tmp" | head -1)"
  rm -f "$sum_tmp"
  [ -n "$expected" ] || err "SHA256 校验文件格式无效: $sum_url"
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  if [ "$actual" != "$expected" ]; then
    err "SHA256 校验失败: $file（预期 ${expected:0:16}…，实际 ${actual:0:16}…）"
  fi
  printf '%s' "$actual"
}

# ── D4: manifest 保存（条件 5）──────────────────────────────
save_manifest() {
  local source_url="$1" version="$2" sha256="$3" fetch_time="$4"
  mkdir -p "$(dirname "$MANIFEST_FILE")"
  {
    echo "source_url=$source_url"
    echo "version=$version"
    echo "sha256=$sha256"
    echo "fetch_time=$fetch_time"
  } > "$MANIFEST_FILE"
  chmod 600 "$MANIFEST_FILE"
}

# ── D4: 来源/版本一致性阻断（条件 7）────────────────────────
check_consistency() {
  [ -f "$MANIFEST_FILE" ] || return 0
  local recorded_url recorded_version recorded_sha actual_sha
  recorded_url="$(grep -E '^source_url=' "$MANIFEST_FILE" | cut -d= -f2-)"
  recorded_version="$(grep -E '^version=' "$MANIFEST_FILE" | cut -d= -f2-)"
  recorded_sha="$(grep -E '^sha256=' "$MANIFEST_FILE" | cut -d= -f2-)"
  if [ "$recorded_url" != "$DOWNLOAD_URL" ] || [ "$recorded_version" != "$RELEASE_TAG" ]; then
    err "来源/版本不一致（D4 条件 7 阻断）: 记录 $recorded_url/$recorded_version，当前 $DOWNLOAD_URL/$RELEASE_TAG"
  fi
  # 缺陷4强化：manifest 必须含 sha256（缺失=被篡改/不完整，必须拒绝，不能假跳过）
  [ -n "$recorded_sha" ] || err "manifest 缺少 sha256（D4 缺陷4）：$MANIFEST_FILE（不能假跳过）"
  # 已装二进制实际 sha 必须与 manifest 记录一致（防同 URL/version 下二进制被替换/篡改）
  if [ -n "${INSTALL_PATH:-}" ] && [ -f "$INSTALL_PATH" ]; then
    actual_sha="$(sha256sum "$INSTALL_PATH" | cut -d' ' -f1)"
    [ "$actual_sha" = "$recorded_sha" ] \
      || err "已装二进制哈希与 manifest 不符（D4 缺陷4 篡改检测）: 记录 ${recorded_sha:0:16}…，实际 ${actual_sha:0:16}…"
  fi
}

# ── 参数解析 ─────────────────────────────────────────────────
MODE="full"       # full | keys | key | binary | rollback
TARGET_KEY=""     # 指定单个 key 时的 provider 名（mify / bailian）

show_help() {
  local U="$SETUP_URL"
  echo -e "${BOLD}用法：${RESET}"
  echo -e "  ${BLUE}首次安装 / 完整更新${RESET}"
  echo -e "    bash <(curl -fsSL $U)"
  echo ""
  echo -e "  ${BLUE}只更新所有 API Key${RESET}"
  echo -e "    bash <(curl -fsSL $U) --keys"
  echo ""
  echo -e "  ${BLUE}只更新某个 provider 的 key${RESET}"
  echo -e "    bash <(curl -fsSL $U) --key mify"
  echo -e "    bash <(curl -fsSL $U) --key bailian"
  echo ""
  echo -e "  ${BLUE}只更新二进制（不动 key 和配置）${RESET}"
  echo -e "    bash <(curl -fsSL $U) --binary"
  echo ""
  echo -e "  ${BLUE}回退到上一个版本${RESET}"
  echo -e "    bash <(curl -fsSL $U) --rollback"
  echo ""
  echo -e "  ${BLUE}可用 provider：${RESET}mify（必填）、bailian（可选）"
  echo ""
  echo -e "  ${BLUE}保存到本地后可直接执行：${RESET}"
  echo -e "    curl -fsSL $U -o ~/opencode-setup.sh && chmod +x ~/opencode-setup.sh"
  echo -e "    ~/opencode-setup.sh --keys"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)   show_help ;;
    --keys|-k)   MODE="keys" ;;
    --key)       MODE="key"; TARGET_KEY="${2:-}"; shift ;;
    --binary|-b) MODE="binary" ;;
    --rollback|-r) MODE="rollback" ;;
    *) echo -e "${RED}❌  未知参数: $1${RESET}"; echo "运行 --help 查看用法"; exit 1 ;;
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
      echo -e "  ${YELLOW}(未设置，可选 - 直接回车跳过)${RESET}"
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
  [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

  local provider_key bailian_key plugin_val
  provider_key="$(read_key PROVIDER_API_KEY)"
  bailian_key="$(read_key BAILIAN_API_KEY)"

  [ -z "$provider_key" ] && err "PROVIDER_API_KEY 未设置，请运行：bash <(curl -fsSL $SETUP_URL) --key mify"

  local omo_path="$CACHE_DIR/node_modules/oh-my-opencode"
  if [ -d "$omo_path" ]; then
    plugin_val="file://$omo_path"
  else
    plugin_val="oh-my-opencode@4.19.2"
    warn "oh-my-opencode 本地缓存未找到，使用在线固定版本 4.19.2（D4 缺陷5：禁 @latest 浮动）"
  fi

  GEN_PROVIDER="$provider_key" GEN_BAILIAN="$bailian_key" GEN_PLUGIN="$plugin_val" \
  GEN_TPL="$TEMPLATE_FILE" GEN_OUT="$CONFIG_FILE" \
  node -e "
    const fs=require('fs'), e=process.env;
    let c=fs.readFileSync(e.GEN_TPL,'utf8');
    c=c.replaceAll('PROVIDER_API_KEY', e.GEN_PROVIDER);
    c=c.replaceAll('PLUGIN_PATH', e.GEN_PLUGIN);
    // 用 JSON 解析确保 bailian 移除后结构合法
    const obj=JSON.parse(c);
    if (e.GEN_BAILIAN) {
      obj.provider.bailian.options.apiKey=e.GEN_BAILIAN;
    } else {
      delete obj.provider.bailian;
    }
    fs.writeFileSync(e.GEN_OUT, JSON.stringify(obj, null, 2));
  "
  ok "opencode.jsonc 已生成"
}

# ── 主流程 ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  开渠 OpenCode 个人版 - 安装/更新              ${RESET}"
echo -e "${BOLD}  版本: $RELEASE_TAG                           ${RESET}"
echo -e "${BOLD}  来源: $RELEASE_BASE                          ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""

# ── 依赖检查（所有模式共用）──────────────────────────────────
for cmd in node git curl; do
  command -v "$cmd" &>/dev/null || err "缺少依赖: $cmd（请先安装）"
done
command -v sha256sum &>/dev/null || err "缺少依赖: sha256sum（D4 条件 4 校验所需）"

# ── D4 缺陷2/5: 安装入口白名单 + 不可变 ref 校验（执行任何下载前）──
assert_trusted_source "$SETUP_URL"
assert_trusted_source "$RELEASE_BASE"
assert_trusted_source "$CONFIG_REPO"
assert_immutable_ref "$RELEASE_TAG"
assert_commit_sha "$CONFIG_REF"

# ── only-keys 模式 ────────────────────────────────────────────
if [ "$MODE" = "keys" ]; then
  echo -e "${BOLD}  模式：更新所有 API Key${RESET}"
  echo ""
  prompt_key "PROVIDER_API_KEY"    "Provider API Key（必填）" 1 "向管理员获取 API Key"
  prompt_key "BAILIAN_API_KEY" "百炼 API Key（可选）" 0 "阿里云百炼平台 Qwen 系列模型"
  generate_config
  ok "Key 更新完成，配置已重新生成"
  exit 0
fi

# ── only-key 模式 ─────────────────────────────────────────────
if [ "$MODE" = "key" ]; then
  case "$TARGET_KEY" in
    mify|MIFY)
      echo -e "${BOLD}  模式：更新 Provider API Key${RESET}"
      echo ""
      prompt_key "PROVIDER_API_KEY" "Provider API Key（必填）" 1 "向管理员获取 API Key"
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

# ── rollback 模式 ─────────────────────────────────────────────
if [ "$MODE" = "rollback" ]; then
  echo -e "${BOLD}  模式：回退${RESET}"
  echo ""
  PREV_TAG="$(cat "$PREVIOUS_VERSION_STAMP" 2>/dev/null | tr -d '[:space:]' || true)"
  [ -z "$PREV_TAG" ] && err "没有可用的回退版本（从未更新过，或备份已清除）"

  PREV_BIN="$BACKUP_DIR/opencode-${PREV_TAG}"
  # D4 条件 10: 回滚资产必须事先存在
  [ -f "$PREV_BIN" ] || err "回滚资产不存在: $PREV_BIN（D4 条件 10：更新前未备份该版本）"

  INSTALL_PATH="$(command -v opencode 2>/dev/null || echo "/usr/local/bin/opencode")"
  info "回退: $(cat "$VERSION_STAMP" 2>/dev/null || echo "未知") -> $PREV_TAG"

  if [ -w "$(dirname "$INSTALL_PATH")" ]; then cp "$PREV_BIN" "$INSTALL_PATH"
  else sudo cp "$PREV_BIN" "$INSTALL_PATH"; fi
  # 缺陷6: 回滚复制后校验目标存在 + hash 与备份一致（防 PS 那种"rc=0 打印成功但目标不存在"假成功）
  [ -f "$INSTALL_PATH" ] || err "回滚复制失败，目标不存在: $INSTALL_PATH（D4 缺陷6）"
  if command -v sha256sum &>/dev/null; then
    ROLLBACK_SHA="$(sha256sum "$INSTALL_PATH" | cut -d' ' -f1)"
    BACKUP_SHA="$(sha256sum "$PREV_BIN" | cut -d' ' -f1)"
    [ "$ROLLBACK_SHA" = "$BACKUP_SHA" ] \
      || err "回滚哈希与备份不符（D4 缺陷6）: $INSTALL_PATH vs $PREV_BIN"
  fi
  echo "$PREV_TAG" > "$VERSION_STAMP"

  # D4: 回滚 manifest（若有备份）
  if [ -f "$BACKUP_DIR/manifest-${PREV_TAG}" ]; then
    cp "$BACKUP_DIR/manifest-${PREV_TAG}" "$MANIFEST_FILE"
    ok "manifest 已回滚到 $PREV_TAG"
  fi

  if [ -f "${CONFIG_FILE}.bak" ]; then
    cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
    ok "opencode.jsonc 已还原"
  else
    warn "opencode.jsonc 备份不存在，配置未还原"
  fi

  ok "已回退到 $PREV_TAG: $INSTALL_PATH"
  exit 0
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

if [ "$MODE" = "full" ]; then
  # 3. 克隆或更新配置仓库（D4 条件 2/3: 固定 CONFIG_REF commit SHA）
  if [ -d "$CONFIG_DIR/.git" ]; then
    info "拉取配置（固定到 $CONFIG_REF）..."
    cd "$CONFIG_DIR"
    git fetch origin 2>&1 | tail -2
    git checkout "$CONFIG_REF" 2>/dev/null || err "CONFIG_REF 固定版本不存在: $CONFIG_REF（D4 条件 2/3）"
    ok "配置已更新到固定版本"
  else
    [ -d "$CONFIG_DIR" ] && mv "$CONFIG_DIR" "${CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    info "克隆个人配置（固定到 $CONFIG_REF）..."
    git clone "$CONFIG_REPO" "$CONFIG_DIR"
    cd "$CONFIG_DIR"
    git fetch origin 2>&1 | tail -2
    git checkout "$CONFIG_REF" 2>/dev/null || err "CONFIG_REF 固定版本不存在: $CONFIG_REF（D4 条件 2/3）"
    ok "配置克隆完成（固定版本）"
  fi

  # 4. API Keys
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  API Key 配置                                  ${RESET}"
  echo -e "  Key 仅存于本机 ${YELLOW}$KEYS_FILE${RESET}，不进 git"
  echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"

  prompt_key "PROVIDER_API_KEY"    "Provider API Key（必填 - 全平台模型入口）" 1 "向管理员获取 API Key"
  prompt_key "BAILIAN_API_KEY" "百炼 API Key（可选 - 阿里云 Qwen）"   0

  # 5. 生成配置
  generate_config
fi

# 6. 下载并安装二进制
DOWNLOAD_URL="$RELEASE_BASE/$BINARY_NAME"

# INSTALL_PATH 提前确定（供 check_consistency 比对已装二进制实际 sha，缺陷4强化）
if command -v opencode &>/dev/null; then
  INSTALL_PATH="$(command -v opencode)"
else
  INSTALL_PATH="/usr/local/bin/opencode"
fi

# D4 条件 7 + 缺陷4: 下载前一致性阻断 + 已装二进制 sha 篡改检测
check_consistency

if command -v opencode &>/dev/null; then
  INSTALL_PATH="$(command -v opencode)"
  INSTALLED_TAG="$(cat "$VERSION_STAMP" 2>/dev/null | tr -d '[:space:]' || true)"
  # 缺陷4：skip 必须二进制实际存在，否则版本戳记录最新但二进制缺失会假跳过
  if [ "$INSTALLED_TAG" = "$RELEASE_TAG" ] && [ "$MODE" != "binary" ] && [ -f "$INSTALL_PATH" ]; then
    ok "二进制已是最新版 ($RELEASE_TAG)，跳过下载"
  elif [ "$INSTALLED_TAG" = "$RELEASE_TAG" ] && [ "$MODE" = "binary" ] && [ -f "$INSTALL_PATH" ]; then
    ok "已是最新版 ($RELEASE_TAG)，无需更新"
    exit 0
  else
    if [ -n "$INSTALLED_TAG" ] && [ ! -f "$INSTALL_PATH" ]; then
      warn "版本戳记录 $INSTALLED_TAG 但二进制缺失，重新下载（D4 缺陷4：不能按版本戳假跳过）"
    else
      info "已安装: ${INSTALLED_TAG:-未知} -> 更新至 $RELEASE_TAG"
    fi
    # 更新前备份旧二进制（仅当二进制存在），用于回退（D4 条件 10）
    if [ -n "$INSTALLED_TAG" ] && [ -f "$INSTALL_PATH" ]; then
      mkdir -p "$BACKUP_DIR"
      cp "$INSTALL_PATH" "$BACKUP_DIR/opencode-${INSTALLED_TAG}"
      echo "$INSTALLED_TAG" > "$PREVIOUS_VERSION_STAMP"
      [ -f "$MANIFEST_FILE" ] && cp "$MANIFEST_FILE" "$BACKUP_DIR/manifest-${INSTALLED_TAG}"
      info "旧版本已备份: $BACKUP_DIR/opencode-${INSTALLED_TAG}"
    fi
    TMP_BIN="$(mktemp)"
    curl -fsSL --progress-bar "$DOWNLOAD_URL" -o "$TMP_BIN" || err "下载失败: $DOWNLOAD_URL"
    chmod +x "$TMP_BIN"
    # D4 条件 4/5: SHA256 验证 + manifest 保存
    ACTUAL_SHA256="$(verify_sha256 "$DOWNLOAD_URL" "$TMP_BIN")"
    FETCH_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")"
    save_manifest "$DOWNLOAD_URL" "$RELEASE_TAG" "$ACTUAL_SHA256" "$FETCH_TIME"
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
  # D4 条件 4/5: SHA256 验证 + manifest 保存
  ACTUAL_SHA256="$(verify_sha256 "$DOWNLOAD_URL" "$TMP_BIN")"
  FETCH_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")"
  save_manifest "$DOWNLOAD_URL" "$RELEASE_TAG" "$ACTUAL_SHA256" "$FETCH_TIME"
  if [ -w "$(dirname "$INSTALL_PATH")" ]; then mv "$TMP_BIN" "$INSTALL_PATH"
  else sudo mv "$TMP_BIN" "$INSTALL_PATH"; fi
  echo "$RELEASE_TAG" > "$VERSION_STAMP"
  ok "二进制已安装: $INSTALL_PATH ($RELEASE_TAG)"
fi

# 7. 完成（D4 条件 6: 显示真实来源与固定版本 + SHA256）
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
ok "完成！"
echo ""
echo -e "  来源:     ${BOLD}$DOWNLOAD_URL${RESET}"
echo -e "  版本:     ${BOLD}$RELEASE_TAG${RESET}"
[ -n "${ACTUAL_SHA256:-}" ] && echo -e "  SHA256:   ${BOLD}${ACTUAL_SHA256:0:16}…${RESET}"
echo -e "  配置:     ${BOLD}$CONFIG_DIR${RESET}"
echo -e "  Key 文件: ${BOLD}$KEYS_FILE${RESET} (仅本机可见)"
echo -e "  运行:     ${BOLD}opencode${RESET}"
echo ""
echo -e "  后续常用命令（直接粘贴运行）："
echo -e "    更新所有 key:    ${BLUE}bash <(curl -fsSL $SETUP_URL) --keys${RESET}"
echo -e "    只换 Provider key:   ${BLUE}bash <(curl -fsSL $SETUP_URL) --key mify${RESET}"
echo -e "    只换百炼 key:    ${BLUE}bash <(curl -fsSL $SETUP_URL) --key bailian${RESET}"
echo -e "    只更新二进制:    ${BLUE}bash <(curl -fsSL $SETUP_URL) --binary${RESET}"
echo -e "    回退上一版本:    ${BLUE}bash <(curl -fsSL $SETUP_URL) --rollback${RESET}"
echo -e ""
echo -e "  💡 或保存到本地，后续直接 ~/opencode-setup.sh --keys："
echo -e "    ${BLUE}curl -fsSL $SETUP_URL -o ~/opencode-setup.sh && chmod +x ~/opencode-setup.sh${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""
