#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
# verify-release.sh — D4 #39 release 入口门禁验证（九修阻断1: 防伪造加固）
#
# 拉远程 release.sha256（随 tag 不可变，作信任根）+ 四脚本 raw URL，
# 逐条对比 SHA256。任一不一致/不通/伪造立即阻断（exit 1）。
#
# 九修阻断1（铸言 HIGH）加固——旧版 verify-release.sh:41-62 只累计 checked==4
# 且用 basename(path) 取 URL，mock 放 4 条相同 setup.sh 仍 rc=0 宣称 4/4 PASS：
#   - 固定 allowlist 四路径，精确串匹配（禁 basename 映射）
#   - 严格行格式：<64hex> 两空格 <单路径>；未知/重复/缺失/额外字段全 FAIL（非 WARN 跳过）
#   - 四路径各出现且仅出现一次（count==1 per path，非仅 checked==4）
#
# 符合 RAW-URL-POLICY 条件 4（下载后验证 SHA256）/ 条件 7（来源·哈希·版本不一致阻断）。
#
# 用法（本地或自举均可）：
#   bash scripts/verify-release.sh
#   bash <(curl -fsSL https://raw.githubusercontent.com/vinnfeng/opencode/v1.3.17-kaiqu.5-d4-20260727/scripts/verify-release.sh)
#
# 测试（test-d4-asserts.sh Part D）：source 本文件后覆盖 fetch_and_hash 为无网 stub，
# 喂构造 manifest 验证五类伪造阻断。生产执行（bash 进程）不受外部函数覆盖影响。
# ═══════════════════════════════════════════════════════════
# 注意：仅 set -uo pipefail（nounset + pipefail），不开 errexit——
# process_manifest 用显式 fail 累计 + return，避免 errexit 在函数末尾 `[ -eq 0 ]` 误杀。
set -uo pipefail

RELEASE_TAG="v1.3.17-kaiqu.5-d4-20260727"
RELEASE_REPO="vinnfeng/opencode"
# 九修阻断1: base 不含 /scripts 后缀——manifest 路径自带 scripts/ 前缀，精确拼接出 raw URL（禁 basename）
RELEASE_BASE="https://raw.githubusercontent.com/${RELEASE_REPO}/${RELEASE_TAG}"
MANIFEST_URL="${RELEASE_BASE}/scripts/release.sha256"

# 固定 allowlist：仅这四条路径合法（精确串匹配，拒任何其它路径/dot-segment/变体）
ALLOWED_PATHS="scripts/setup.sh scripts/setup.ps1 scripts/community-setup.sh scripts/community-setup.ps1"

# 跨平台 SHA256（Linux: sha256sum；macOS: shasum -a 256）——读 stdin
sha_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  else echo "FATAL: 无 sha256sum / shasum" >&2; return 2; fi
}

# 默认 fetcher：curl 拉 URL 内容并算 SHA256。测试 source 本文件后可覆盖为无网 stub
# （生产 bash 进程执行时为全新进程，外部无法注入覆盖——门禁不受影响）。
fetch_and_hash() {
  curl -fsSL "$1" | sha_cmd
}

# ── 九修阻断1: 严格解析单行 manifest ──
# 合法行：<64hex><两空格><单路径>，路径非空且不含空白（拒额外字段）。
# 成功置全局 _EXP _PATH 并 return 0；失败 return 1（调用方报具体类别）。
parse_manifest_line() {
  local line="$1" hash_part sep
  _EXP=""; _PATH=""
  hash_part="${line:0:64}"
  [ "${#hash_part}" -eq 64 ] || return 1
  case "$hash_part" in *[!0-9a-f]*) return 1 ;; esac
  sep="${line:64:2}"
  [ "$sep" = "  " ] || return 1
  _PATH="${line:66}"
  [ -n "$_PATH" ] || return 1
  case "$_PATH" in *[[:space:]]*) return 1 ;; esac
  _EXP="$hash_part"
  return 0
}

# ── 九修阻断1: 处理整份 manifest（从 stdin 读，base/allowed 作参数）──
# 逐行严格解析 + allowlist 精确匹配 + 去重 + 精确路径取 URL + hash 对比。
# 末尾补缺失检查。任一类别失败返回非零。所有 FAIL 原因打 stderr。
process_manifest() {
  local base="$1" allowed="$2" line url actual p
  local fail=0 seen=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    if ! parse_manifest_line "$line"; then
      printf 'FAIL  非法 manifest 行（需 <64hex> 两空格 <单路径>，无额外字段）: %s\n' "$line" >&2
      fail=1; continue
    fi
    # allowlist 精确匹配（拒未知路径 / dot-segment / 兄弟路径）
    case " $allowed " in *" $_PATH "*) ;; *)
      printf 'FAIL  未知路径（不在四脚本白名单）: %s\n' "$_PATH" >&2
      fail=1; continue ;;
    esac
    # 去重（拒重复路径——铸言攻击向量：4×相同 setup.sh）
    case " $seen " in *" $_PATH "*)
      printf 'FAIL  重复路径: %s\n' "$_PATH" >&2
      fail=1; continue ;;
    esac
    seen="$seen $_PATH"
    # 精确路径取 URL（禁 basename 映射——旧版以此被伪造）
    url="${base}/${_PATH}"
    if ! actual="$(fetch_and_hash "$url")"; then
      printf 'FAIL  拉取失败  %s\n' "$url" >&2
      fail=1; continue
    fi
    if [ "$actual" != "$_EXP" ]; then
      printf 'FAIL  %-40s\n      expected %s\n      actual   %s\n' "$_PATH" "$_EXP" "$actual" >&2
      fail=1; continue
    fi
    printf 'OK    %-40s %s\n' "$_PATH" "$actual"
  done
  # 缺失检查：四路径各须出现且仅出现一次
  for p in $allowed; do
    case " $seen " in *" $p "*) ;;
      *) printf 'FAIL  缺失路径（manifest 未含）: %s\n' "$p" >&2; fail=1 ;;
    esac
  done
  [ "$fail" -eq 0 ]
}

# ── 主入口（被执行时运行；被 source 时不运行——便于 test 注入 fetch_and_hash）──
main() {
  local remote rc
  echo "D4 #39 release 入口门禁验证（九修阻断1 防伪造加固）"
  echo "tag:      $RELEASE_TAG"
  echo "repo:     $RELEASE_REPO"
  echo "manifest: $MANIFEST_URL"
  echo "------------------------------------------------------------"

  # 1. 拉远程 release.sha256（不可变锚点）
  if ! remote="$(curl -fsSL "$MANIFEST_URL")"; then
    echo "FAIL: 无法拉取 release.sha256（tag 未推送 / 网络异常 / 仓私有）: $MANIFEST_URL" >&2
    exit 1
  fi

  # 2. 严格逐条对比（allowlist + 去重 + 缺失 + 精确路径 hash）
  if printf '%s\n' "$remote" | process_manifest "$RELEASE_BASE" "$ALLOWED_PATHS"; then
    rc=0
  else
    rc=$?
  fi
  echo "------------------------------------------------------------"
  if [ "$rc" -eq 0 ]; then
    echo "RESULT: PASS — 四脚本各出现一次 + 内容 hash 对应 release.sha256（门禁闭合，防伪造）"
    exit 0
  else
    echo "RESULT: FAIL — manifest 非法 / 来源·哈希·版本不一致，已阻断（RAW-URL-POLICY 条件 7）" >&2
    exit 1
  fi
}

# 被 source（测试）时不跑 main；被执行时跑。
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  main
fi
