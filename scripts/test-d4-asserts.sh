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
# 缺陷2 三审: decode+normalize 循环在位（4 载体）
for f in "$SETUP_SH" "$SETUP_PS" "$COMM_SH" "$COMM_PS"; do
  struct_check_f "defect2 decode loop" "$f" '%2[eE]' present
done
# 缺陷4 三审: manifest 缺 sha256 必须拒绝（不能假跳过）
struct_check_f "defect4 reject missing-sha (sh)" "$SETUP_SH" 'manifest 缺少 sha256' present
struct_check_f "defect4 reject missing-sha (ps)" "$SETUP_PS" 'manifest 缺少 sha256' present
# 缺陷4 三审: 二进制缺失不假跳过（warn 在位）
struct_check_f "defect4 binary-missing warn (sh)" "$SETUP_SH" '但二进制缺失' present
struct_check_f "defect4 binary-missing warn (ps)" "$SETUP_PS" '但二进制缺失' present
# 缺陷5 三审: 严格 semver 正则（拒空标识符/双点）
for f in "$SETUP_SH" "$SETUP_PS" "$COMM_SH" "$COMM_PS"; do
  struct_check_f "defect5 strict semver" "$f" '-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*' present
done
# 缺陷5 三审: community 已存在旧版卸载重装
struct_check_f "defect5 community reinstall (sh)" "$COMM_SH" '卸载重装' present
struct_check_f "defect5 community reinstall (ps)" "$COMM_PS" '卸载重装' present

echo ""
if [ "$FAILS" -eq 0 ]; then
  echo "=== ALL PASS (D4 四载体 assert 回归) ==="
  exit 0
else
  echo "=== $FAILS FAILED ===" >&2
  exit 1
fi
