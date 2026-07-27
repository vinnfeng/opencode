#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
# verify-release.sh — D4 #39 release 入口门禁验证
#
# 拉远程 release.sha256（随 tag 不可变，作信任根）+ 四脚本 raw URL，
# 逐条对比 SHA256，任一不一致或不通立即阻断（exit 1）。
# 符合 RAW-URL-POLICY 条件 4（下载后验证 SHA256）/ 条件 7（来源·哈希·版本不一致阻断）。
#
# 用法（本地或自举均可）：
#   bash scripts/verify-release.sh
#   bash <(curl -fsSL https://raw.githubusercontent.com/vinnfeng/opencode/v1.3.17-kaiqu.4-d4-20260727/scripts/verify-release.sh)
# ═══════════════════════════════════════════════════════════
set -euo pipefail

RELEASE_TAG="v1.3.17-kaiqu.4-d4-20260727"
RELEASE_REPO="vinnfeng/opencode"
RAW_BASE="https://raw.githubusercontent.com/${RELEASE_REPO}/${RELEASE_TAG}/scripts"
MANIFEST_URL="${RAW_BASE}/release.sha256"

# 跨平台 SHA256（Linux: sha256sum；macOS: shasum -a 256）
sha_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  else echo "FATAL: 无 sha256sum / shasum" >&2; return 2; fi
}

echo "D4 #39 release 入口门禁验证"
echo "tag:      $RELEASE_TAG"
echo "repo:     $RELEASE_REPO"
echo "manifest: $MANIFEST_URL"
echo "------------------------------------------------------------"

# 1. 拉远程 release.sha256（不可变锚点）
if ! remote="$(curl -fsSL "$MANIFEST_URL")"; then
  echo "FAIL: 无法拉取 release.sha256（tag 未推送 / 网络异常 / 仓私有）: $MANIFEST_URL" >&2
  exit 1
fi

# 2. 逐条对比（仅解析 hash 行：64hex + 两空格 + path）
fail=0; checked=0
while IFS= read -r expected path _rest; do
  case "$expected" in
    ''|'#'*) continue ;;            # 空行 / 注释行跳过
    *[!0-9a-f]*) echo "WARN: 非法 hash 行跳过: $expected $path" >&2; continue ;;
  esac
  [ ${#expected} -eq 64 ] || { echo "WARN: hash 非 64 位跳过: $expected" >&2; continue; }
  url="${RAW_BASE}/$(basename "$path")"
  if ! actual="$(curl -fsSL "$url" | sha_cmd)"; then
    echo "FAIL  拉取失败  $url" >&2; fail=1; continue
  fi
  checked=$((checked + 1))
  if [ "$actual" = "$expected" ]; then
    printf 'OK    %-32s %s\n' "$(basename "$path")" "$actual"
  else
    printf 'FAIL  %-32s\n      expected %s\n      actual   %s\n' "$(basename "$path")" "$expected" "$actual" >&2
    fail=1
  fi
done <<< "$remote"

echo "------------------------------------------------------------"
echo "checked: $checked / 4"
if [ "$fail" -eq 0 ] && [ "$checked" -eq 4 ]; then
  echo "RESULT: PASS — 四 raw URL 全 200 + 内容 hash 对应 release.sha256（门禁闭合）"
  exit 0
else
  echo "RESULT: FAIL — 来源/哈希/版本不一致或拉取失败，已阻断（RAW-URL-POLICY 条件 7）" >&2
  exit 1
fi
