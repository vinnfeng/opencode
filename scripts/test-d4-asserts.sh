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

rm -rf "$MOCK_ROOT"

echo ""
if [ "$FAILS" -eq 0 ]; then
  echo "=== ALL PASS (D4 四载体 assert 回归) ==="
  exit 0
else
  echo "=== $FAILS FAILED ===" >&2
  exit 1
fi
