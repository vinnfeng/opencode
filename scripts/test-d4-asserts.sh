#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════
#  D4 assert 回归测试（四载体）
#  铸言工程复核反馈：补四载体 assert 回归测试
#
#  Part A: 行为测试 — sed 提取 setup.sh / community-setup.sh 的【真实】
#          assert_* 函数，err 桩化（不 exit），跑缺陷 2/3/5 绕过矩阵
#  Part B: 结构校验 — 全 4 文件 grep 关键模式在位（defect 1/3/4/5/6）
#
#  用法: bash test-d4-asserts.sh
#  退出码: 0=全过, 1=有失败
# ═════════════════════════════════════════════════════════════
# 注意: 不用 set -e —— err 桩 return 1 不能杀测试
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SH="$SCRIPT_DIR/setup.sh"
SETUP_PS="$SCRIPT_DIR/setup.ps1"
COMM_SH="$SCRIPT_DIR/community-setup.sh"
COMM_PS="$SCRIPT_DIR/community-setup.ps1"

FAILS=0
FAILED=""

# err 桩：真实脚本里 err 用 exit 1（fail-fast 正确）；测试需捕获而非退出
err() { FAILED="$1"; return 1; }

# ── 提取某 .sh 文件的 assert_* 函数定义（真实代码，非复制）──
extract_asserts() {
  local f="$1"
  sed -n '/^assert_trusted_source()/,/^}/p; /^assert_immutable_ref()/,/^}/p; /^assert_commit_sha()/,/^}/p' "$f"
}

load_asserts() {
  eval "$(extract_asserts "$1")"
}

run_case() {
  local fn="$1" val="$2" expect="$3"
  FAILED=""
  "$fn" "$val" 2>/dev/null || true
  local actual
  if [ -z "$FAILED" ]; then actual=pass; else actual=fail; fi
  if [ "$actual" = "$expect" ]; then
    printf '  PASS  %-26s %-46s -> %s\n' "$fn" "'$val'" "$actual"
  else
    printf '  FAIL  %-26s %-46s -> %s (expect %s) [%s]\n' "$fn" "'$val'" "$actual" "$expect" "$FAILED"
    FAILS=$((FAILS+1))
  fi
}

run_matrix() {
  local label="$1"
  echo "--- $label ---"
  # 缺陷2: trusted_source（含 dot-segment / 编码点 / 前缀穿越绕过）
  run_case assert_trusted_source "https://github.com/vinnfeng/opencode/x"      pass
  run_case assert_trusted_source "https://raw.githubusercontent.com/vinnfeng/opencode/x" pass
  run_case assert_trusted_source "https://github.com/attacker/repo"            fail
  run_case assert_trusted_source "https://github.com/vinnfeng/../attacker/repo" fail
  run_case assert_trusted_source "https://github.com/vinnfeng/x/.."            fail
  run_case assert_trusted_source "https://github.com/vinnfeng/%2e%2e/attacker" fail
  run_case assert_trusted_source "https://github.com/vinnfengfoo/evil"         fail
  run_case assert_trusted_source "http://github.com/vinnfeng/x"                fail
  # 缺陷2 三审：编码斜杠/反斜杠/双重编码/反斜杠变体绕过 dot-segment
  run_case assert_trusted_source 'https://github.com/vinnfeng/%2f../attacker'    fail
  run_case assert_trusted_source 'https://github.com/vinnfeng/x%5c..%5cattacker' fail
  run_case assert_trusted_source 'https://github.com/vinnfeng/%252e%252e/attacker' fail
  run_case assert_trusted_source 'https://github.com/vinnfeng/x\..\attacker'     fail
  # 缺陷2 四审：多级编码绕过（%25%32%65→%2e→. 等），可信 URL 不应含任何 %
  run_case assert_trusted_source 'https://github.com/vinnfeng/%25%32%65%25%32%65/attacker' fail
  run_case assert_trusted_source 'https://github.com/vinnfeng/%25252e%25252e/attacker' fail
  run_case assert_trusted_source 'https://github.com/vinnfeng/x%255c..%255cattacker' fail
  # 缺陷5: immutable_ref（白名单：40hex SHA 或 vX.Y.Z[-pre]；黑名单漏项必须拒）
  run_case assert_immutable_ref "de6a37e8ffcf1f73ebe0aa1fb162794d1b965e7c"     pass
  run_case assert_immutable_ref "v1.3.17-kaiqu.3"                              pass
  run_case assert_immutable_ref "v2.0.0"                                       pass
  run_case assert_immutable_ref ""                                             fail
  run_case assert_immutable_ref "main"                                         fail
  run_case assert_immutable_ref "release"                                      fail
  run_case assert_immutable_ref "office-windows"                               fail
  run_case assert_immutable_ref "feature/foo"                                  fail
  run_case assert_immutable_ref "latest"                                       fail
  # 缺陷5 三审：严格 semver 拒绝非法 prerelease 标签（空标识符/双点/尾空）
  run_case assert_immutable_ref "v1.2.3-rc.1"                                  pass
  run_case assert_immutable_ref "v1.2.3-alpha.1.beta.2"                        pass
  run_case assert_immutable_ref "v1.2.3-."                                     fail
  run_case assert_immutable_ref "v1.2.3-a..b"                                  fail
  run_case assert_immutable_ref "v1.2.3-"                                      fail
  run_case assert_immutable_ref "v1.2.3-a."                                    fail
  # 缺陷5 四审：严格 SemVer 拒绝前导零（major/minor/patch/prerelease）
  run_case assert_immutable_ref "v01.2.3"                                      fail
  run_case assert_immutable_ref "v1.02.3"                                      fail
  run_case assert_immutable_ref "v1.2.3-01"                                    fail
  # 缺陷3: commit_sha（严格 40hex，拒绝 tag/短sha/分支名）
  run_case assert_commit_sha "de6a37e8ffcf1f73ebe0aa1fb162794d1b965e7c"        pass
  run_case assert_commit_sha "v1.3.17-kaiqu.3"                                 fail
  run_case assert_commit_sha "de6a37e8"                                        fail
  run_case assert_commit_sha "migration"                                       fail
}

echo "=== Part A: 行为测试（真实提取 assert 函数 + err 桩）==="
load_asserts "$SETUP_SH";  run_matrix "setup.sh"
load_asserts "$COMM_SH";   run_matrix "community-setup.sh"

echo ""
echo "=== Part B: 结构校验（四载体 defect 1/3/4/5/6 关键模式在位）==="
struct_check() {
  local label="$1" file="$2" pattern="$3" expect="$4"  # expect=present|absent
  local n actual
  n=$(grep -cE "$pattern" "$file" 2>/dev/null || true)
  n=${n:-0}
  if [ "${n:-0}" -gt 0 ]; then actual=present; else actual=absent; fi
  if [ "$actual" = "$expect" ]; then
    printf '  PASS  %-34s %-10s %s\n' "$label" "$actual" "$(basename "$file")"
  else
    printf '  FAIL  %-34s %-10s (expect %s) %s\n' "$label" "$actual" "$expect" "$(basename "$file")"
    FAILS=$((FAILS+1))
  fi
}
# 固定串版（避免 ERE 对 \. \? 转义歧义）
struct_check_f() {
  local label="$1" file="$2" needle="$3" expect="$4"
  local n actual
  n=$(grep -Fc -- "$needle" "$file" 2>/dev/null || true)
  n=${n:-0}
  if [ "${n:-0}" -gt 0 ]; then actual=present; else actual=absent; fi
  if [ "$actual" = "$expect" ]; then
    printf '  PASS  %-34s %-10s %s\n' "$label" "$actual" "$(basename "$file")"
  else
    printf '  FAIL  %-34s %-10s (expect %s) %s\n' "$label" "$actual" "$expect" "$(basename "$file")"
    FAILS=$((FAILS+1))
  fi
}

# 缺陷2: dot-segment 拒绝模式存在（固定串 '(\.\.?)' 在 bash/ps 正则里都出现）
for f in "$SETUP_SH" "$SETUP_PS" "$COMM_SH" "$COMM_PS"; do
  struct_check_f "defect2 dot-segment reject" "$f" '(\.\.?)' present
done
# 缺陷3: commit SHA 校验函数存在
for f in "$SETUP_SH" "$SETUP_PS" "$COMM_SH" "$COMM_PS"; do
  struct_check "defect3 commit-sha assert" "$f" 'assert_commit_sha|Assert-CommitSha' present
done
# 缺陷5: 不可变 ref 白名单 40hex 模式存在
for f in "$SETUP_SH" "$SETUP_PS" "$COMM_SH" "$COMM_PS"; do
  struct_check "defect5 whitelist 40hex" "$f" '\{40\}' present
done
# 缺陷5: 活的 @latest 安装/插件用法必须不存在（注释/warn 里提到 @latest 不算）
for f in "$SETUP_SH" "$SETUP_PS" "$COMM_SH" "$COMM_PS"; do
  struct_check "defect5 no live @latest" "$f" 'opencode-ai@latest|oh-my-opencode@latest' absent
done
# 缺陷5: plugin 锁版（主线 setup）
struct_check "defect5 plugin locked (sh)" "$SETUP_SH" 'oh-my-opencode@4\.19\.2' present
struct_check "defect5 plugin locked (ps)" "$SETUP_PS" 'oh-my-opencode@4\.19\.2' present
# 缺陷4 (主线): manifest sha 比对存在
struct_check "defect4 sha compare (sh)" "$SETUP_SH" 'sha256sum' present
struct_check "defect4 sha compare (ps)" "$SETUP_PS" 'Get-FileHash' present
# 缺陷4 (社区): npm 版本锁 + registry 固定
struct_check "defect4 npm version lock (sh)" "$COMM_SH" 'opencode-ai@1\.18\.7' present
struct_check "defect4 npm version lock (ps)" "$COMM_PS" 'opencode-ai@1\.18\.7' present
struct_check "defect4 npm registry pin (sh)" "$COMM_SH" 'registry\.npmjs\.org' present
struct_check "defect4 npm registry pin (ps)" "$COMM_PS" 'registry\.npmjs\.org' present
# 缺陷6: rollback 复制后 Test-Path + hash 双校验（setup.ps1）
struct_check "defect6 rollback target verify (ps)" "$SETUP_PS" '回滚复制失败' present
struct_check "defect6 rollback hash verify (ps)"   "$SETUP_PS" '回滚哈希与备份不符' present
# 缺陷2 四审: 拒绝任何 % 编码（4 载体）
for f in "$SETUP_SH" "$SETUP_PS" "$COMM_SH" "$COMM_PS"; do
  struct_check_f "defect2 reject % (round4)" "$f" '% 编码' present
done
# 缺陷4 三审: manifest 缺 sha256 必须拒绝（不能假跳过）
struct_check_f "defect4 reject missing-sha (sh)" "$SETUP_SH" 'manifest 缺少 sha256' present
struct_check_f "defect4 reject missing-sha (ps)" "$SETUP_PS" 'manifest 缺少 sha256' present
# 缺陷4 三审: 二进制缺失不假跳过（warn 在位）
struct_check_f "defect4 binary-missing warn (sh)" "$SETUP_SH" '但二进制缺失' present
struct_check_f "defect4 binary-missing warn (ps)" "$SETUP_PS" '但二进制缺失' present
# 缺陷5 四审: strict SemVer 无 leading-zero 标记 (0|[1-9][0-9]*)
for f in "$SETUP_SH" "$SETUP_PS" "$COMM_SH" "$COMM_PS"; do
  struct_check_f "defect5 strict semver (round4)" "$f" '(0|[1-9][0-9]*)' present
done
# 缺陷5 三审: community 已存在旧版卸载重装
struct_check_f "defect5 community reinstall (sh)" "$COMM_SH" '卸载重装' present
struct_check_f "defect5 community reinstall (ps)" "$COMM_PS" '卸载重装' present

# ═════════════════════════════════════════════════════════════
# Part C: 动态控制流测试（缺陷4 五审）—— 执行 verify_opencode_via_path，不靠结构 grep
# 覆盖五审 4 类绕过 + 1 sanity：①外部PATH ③1.18.7-evil suffix ④空prefix ⑤sibling-prefix
# ═════════════════════════════════════════════════════════════
echo ""
echo "=== Part C: 动态控制流测试（缺陷4 五审 community verify_opencode_via_path）==="

# 提取 verify_opencode_via_path 函数定义（真实代码，非复制）
extract_verify_fn() {
  sed -n '/^verify_opencode_via_path()/,/^}/p' "$1"
}

# 用 mock 环境运行 verify，返回退出码（0=通过，1=被拒）
# 参数：$1=npm_prefix值  $2=opencode绝对路径  $3=opencode版本输出
run_verify_mock() {
  local npm_prefix="$1" oc_abspath="$2" oc_ver="$3"
  local mockdir oc_dir verify_fn
  mockdir="$(mktemp -d)"
  oc_dir="$(dirname "$oc_abspath")"
  mkdir -p "$oc_dir" "$mockdir"
  # mock npm（仅响应 config get prefix）
  cat > "$mockdir/npm" <<EOF
#!/usr/bin/env bash
if [ "\$*" = "config get prefix" ]; then printf '%s' "$npm_prefix"; fi
EOF
  chmod +x "$mockdir/npm"
  # mock opencode（仅响应 --version）
  cat > "$oc_abspath" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then printf '%s\n' "$oc_ver"; fi
EOF
  chmod +x "$oc_abspath"
  verify_fn="$(extract_verify_fn "$COMM_SH")"
  # 子 shell 注入 mock PATH + stub（ok/warn/info no-op，err exit 1），跑真实 verify 函数
  PATH="$mockdir:$oc_dir:$PATH" bash -c '
    ok(){ :; }; warn(){ :; }; info(){ :; }; err(){ exit 1; }
    '"$verify_fn"'
    verify_opencode_via_path
  ' >/dev/null 2>&1
  local rc=$?
  rm -rf "$mockdir" "$oc_abspath"
  rmdir "$oc_dir" 2>/dev/null || true
  return $rc
}

expect_verify_reject() {
  local label="$1" npm_prefix="$2" oc_abspath="$3" oc_ver="$4"
  if run_verify_mock "$npm_prefix" "$oc_abspath" "$oc_ver"; then
    printf '  FAIL  %-46s -> pass (expect reject)\n' "$label"
    FAILS=$((FAILS+1))
  else
    printf '  PASS  %-46s -> reject\n' "$label"
  fi
}
expect_verify_pass() {
  local label="$1" npm_prefix="$2" oc_abspath="$3" oc_ver="$4"
  if run_verify_mock "$npm_prefix" "$oc_abspath" "$oc_ver"; then
    printf '  PASS  %-46s -> pass\n' "$label"
  else
    printf '  FAIL  %-46s -> reject (expect pass)\n' "$label"
    FAILS=$((FAILS+1))
  fi
}

# ── 七审：端到端控制流（提取整个安装块，含 existing-version if 分支 + verify 调用位置）──
# 铸言六审：Part C 只调 verify 函数，未覆盖 if 分支后 verify 是否真被调用（调用位置回归）
extract_install_block() {
  sed -n '/^OPENCODE_NPM_PKG=/,/^verify_opencode_via_path$/p' "$1"
}

# 用 mock 环境跑整个安装块（OPENCODE_NPM_PKG 赋值 → existing-version if/else → verify 调用）
# 返回退出码（0=通过，1=被拒）
run_install_block_e2e() {
  local npm_prefix="$1" oc_abspath="$2" oc_ver="$3"
  local mockdir oc_dir verify_fn install_block
  mockdir="$(mktemp -d)"
  oc_dir="$(dirname "$oc_abspath")"
  mkdir -p "$oc_dir" "$mockdir"
  # mock npm：config get prefix 返回受控值；install/uninstall/list no-op rc=0
  cat > "$mockdir/npm" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "config get prefix") printf '%s' "$npm_prefix" ;;
  install*|uninstall*|list*) exit 0 ;;
esac
EOF
  chmod +x "$mockdir/npm"
  # mock opencode：仅响应 --version
  cat > "$oc_abspath" <<EOF
#!/usr/bin/env bash
[ "\$1" = "--version" ] && printf '%s\n' "$oc_ver"
EOF
  chmod +x "$oc_abspath"
  verify_fn="$(extract_verify_fn "$COMM_SH")"
  install_block="$(extract_install_block "$COMM_SH")"
  # 子 shell 注入 mock PATH + stub（ok/warn/info no-op，err exit 1），跑 verify 函数 + 整个安装块
  PATH="$mockdir:$oc_dir:$PATH" bash -c '
    set +e
    ok(){ :; }; warn(){ :; }; info(){ :; }; err(){ exit 1; }
    '"$verify_fn"'
    '"$install_block"'
  ' >/dev/null 2>&1
  local rc=$?
  rm -rf "$mockdir" "$oc_abspath"
  rmdir "$oc_dir" 2>/dev/null || true
  return $rc
}

expect_e2e_reject() {
  local label="$1" npm_prefix="$2" oc_abspath="$3" oc_ver="$4"
  if run_install_block_e2e "$npm_prefix" "$oc_abspath" "$oc_ver"; then
    printf '  FAIL  %-46s -> pass (expect reject)\n' "$label"
    FAILS=$((FAILS+1))
  else
    printf '  PASS  %-46s -> reject\n' "$label"
  fi
}
expect_e2e_pass() {
  local label="$1" npm_prefix="$2" oc_abspath="$3" oc_ver="$4"
  if run_install_block_e2e "$npm_prefix" "$oc_abspath" "$oc_ver"; then
    printf '  PASS  %-46s -> pass\n' "$label"
  else
    printf '  FAIL  %-46s -> reject (expect pass)\n' "$label"
    FAILS=$((FAILS+1))
  fi
}

# 构造临时 npm prefix 根（真实可写目录）
MOCK_ROOT="$(mktemp -d)"
NPM_PREFIX_GOOD="$MOCK_ROOT/npm"
mkdir -p "$NPM_PREFIX_GOOD/bin"

# 用例1 ①: 同版本但位于外部 PATH（不在 npm prefix 下）→ 拒
expect_verify_reject "defect4 ① external PATH same-ver" \
  "$NPM_PREFIX_GOOD" "$MOCK_ROOT/external/bin/opencode" "1.18.7"
# 用例2 ③: 同位置但版本带 suffix（1.18.7-evil）→ 拒
expect_verify_reject "defect4 ③ version suffix 1.18.7-evil" \
  "$NPM_PREFIX_GOOD" "$NPM_PREFIX_GOOD/bin/opencode" "1.18.7-evil"
# 用例3 ④: npm prefix 为空（通配退化）→ 拒
expect_verify_reject "defect4 ④ empty npm prefix" \
  "" "$NPM_PREFIX_GOOD/bin/opencode" "1.18.7"
# 用例4 ⑤: sibling-prefix（prefix-evil 兄弟路径）→ 拒
expect_verify_reject "defect4 ⑤ sibling prefix-evil" \
  "$NPM_PREFIX_GOOD" "$MOCK_ROOT/npm-evil/bin/opencode" "1.18.7"
# sanity: 正常位置 + 正确版本 → 通过（防误拒）
expect_verify_pass "defect4 sanity normal install" \
  "$NPM_PREFIX_GOOD" "$NPM_PREFIX_GOOD/bin/opencode" "1.18.7"

# 七审修复：六审清洗 bug 覆盖缺口——空格/Tab 后缀 reject（round-5 只测连字符后缀）
# 六审 bash:89 原 sed s/[[:space:]].*$// 把 "1.18.7 evil" 清洗成 "1.18.7" 放行（假阴性）
expect_verify_reject "defect4 ③a space suffix '1.18.7 evil'" \
  "$NPM_PREFIX_GOOD" "$NPM_PREFIX_GOOD/bin/opencode" "1.18.7 evil"
expect_verify_reject "defect4 ③b 'opencode 1.18.7 evil'" \
  "$NPM_PREFIX_GOOD" "$NPM_PREFIX_GOOD/bin/opencode" "opencode 1.18.7 evil"
expect_verify_reject "defect4 ③c tab suffix '1.18.7<TAB>evil'" \
  "$NPM_PREFIX_GOOD" "$NPM_PREFIX_GOOD/bin/opencode" "$(printf '1.18.7\tevil')"

# 七审：端到端控制流——existing-version then 分支仍调 verify 抓 evil（防调用位置回归）
# 模拟 opencode 自报 "1.18.7 evil"（宽松 EXISTING_VER 取 1.18.7 进 then 跳过 install），
# verify 仍应抓出 evil 后缀拒绝；若 verify 调用被误删（回归），then 分支直接 ok rc=0 → 用例 fail
expect_e2e_reject "defect4 e2e then-branch verify (1.18.7 evil)" \
  "$NPM_PREFIX_GOOD" "$NPM_PREFIX_GOOD/bin/opencode" "1.18.7 evil"
expect_e2e_pass "defect4 e2e then-branch sanity (1.18.7)" \
  "$NPM_PREFIX_GOOD" "$NPM_PREFIX_GOOD/bin/opencode" "1.18.7"

rm -rf "$MOCK_ROOT"

# ═════════════════════════════════════════════════════════════
# Part D: verify-release.sh 门禁防伪造动态测试（九修阻断1）
# 铸言八审 HIGH: 旧版 verify-release.sh 只累计 checked==4 + basename(path) 取 URL，
# mock 放 4 条相同 setup.sh 仍 rc=0 宣称 4/4 PASS。新版 allowlist + 严格解析 + 去重 + 缺失。
# source verify-release.sh（main 因 BASH_SOURCE guard 不执行）→ 覆盖 fetch_and_hash 为无网 stub
# → 喂构造 manifest，验证五类阻断（duplicate/missing/unknown/extra-field/hash-mismatch）+ sanity。
# ═════════════════════════════════════════════════════════════
echo ""
echo "=== Part D: verify-release.sh 门禁防伪造（九修阻断1 五类动态）==="

# shellcheck disable=SC1091
source "$SCRIPT_DIR/verify-release.sh"
FIXED_HASH="$(printf 'a%.0s' {1..64})"     # stub fetch 固定返回
MISMATCH_HASH="$(printf 'b%.0s' {1..64})"  # hash-mismatch 用例声明值
fetch_and_hash() { printf '%s' "$FIXED_HASH"; }

run_vrf_case() {
  local label="$1" manifest="$2" expect="$3" reason="${4:-}"
  local out rc actual ok
  out="$(printf '%s\n' "$manifest" | process_manifest "http://test.invalid/base" "$ALLOWED_PATHS" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then actual=pass; else actual=fail; fi
  ok=1
  [ "$actual" = "$expect" ] || ok=0
  if [ -n "$reason" ]; then
    printf '%s' "$out" | grep -qF "$reason" || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    printf '  PASS  %-46s -> %s\n' "$label" "$actual"
  else
    printf '  FAIL  %-46s -> %s (expect %s%s) out=%s\n' "$label" "$actual" "$expect" "${reason:+, want: $reason}" "$out"
    FAILS=$((FAILS+1))
  fi
}

# 用例1 duplicate: setup.sh 出现两次 → 拒（铸言攻击向量：4×相同路径）
run_vrf_case "blocker1 duplicate setup.sh" \
  "$FIXED_HASH  scripts/setup.sh
$FIXED_HASH  scripts/setup.sh
$FIXED_HASH  scripts/setup.ps1
$FIXED_HASH  scripts/community-setup.sh
$FIXED_HASH  scripts/community-setup.ps1" \
  fail "重复路径"

# 用例2 missing: 只含 3 条 → 拒
run_vrf_case "blocker1 missing community-setup.ps1" \
  "$FIXED_HASH  scripts/setup.sh
$FIXED_HASH  scripts/setup.ps1
$FIXED_HASH  scripts/community-setup.sh" \
  fail "缺失路径"

# 用例3 unknown: scripts/evil.sh 不在 allowlist → 拒
run_vrf_case "blocker1 unknown path scripts/evil.sh" \
  "$FIXED_HASH  scripts/setup.sh
$FIXED_HASH  scripts/setup.ps1
$FIXED_HASH  scripts/community-setup.sh
$FIXED_HASH  scripts/evil.sh" \
  fail "未知路径"

# 用例4 extra-field: setup.sh 行尾多 EXTRA → 行非法 → 拒
run_vrf_case "blocker1 extra field after path" \
  "$FIXED_HASH  scripts/setup.sh  EXTRA
$FIXED_HASH  scripts/setup.ps1
$FIXED_HASH  scripts/community-setup.sh
$FIXED_HASH  scripts/community-setup.ps1" \
  fail "非法 manifest 行"

# 用例5 hash-mismatch: setup.sh 声明 MISMATCH_HASH 但 fetch 返回 FIXED_HASH → 拒
run_vrf_case "blocker1 hash mismatch (setup.sh)" \
  "$MISMATCH_HASH  scripts/setup.sh
$FIXED_HASH  scripts/setup.ps1
$FIXED_HASH  scripts/community-setup.sh
$FIXED_HASH  scripts/community-setup.ps1" \
  fail "expected"

# sanity pass: 四路径各一次 + hash 全匹配 → 通过（防误拒）
run_vrf_case "blocker1 sanity all-four correct" \
  "$FIXED_HASH  scripts/setup.sh
$FIXED_HASH  scripts/setup.ps1
$FIXED_HASH  scripts/community-setup.sh
$FIXED_HASH  scripts/community-setup.ps1" \
  pass ""

unset -f fetch_and_hash 2>/dev/null || true

echo ""
if [ "$FAILS" -eq 0 ]; then
  echo "=== ALL PASS (D4 四载体 assert 回归) ==="
  exit 0
else
  echo "=== $FAILS FAILED ===" >&2
  exit 1
fi
