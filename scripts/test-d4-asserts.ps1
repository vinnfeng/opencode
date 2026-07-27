# D4 assert regression test - PowerShell carriers (setup.ps1 + community-setup.ps1)
# Zhuyan engineering review feedback: add 4-carrier assert regression tests.
#
# Uses AST to extract the REAL Assert-* functions from each .ps1 file,
# stubs err (no exit), runs the defect 2/3/5 bypass matrix.
# Exit code: 0 = all pass, 1 = failures.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File test-d4-asserts.ps1

$ErrorActionPreference = "Stop"
$script:FAILED = $null
$script:GFAIL = 0
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# err stub: real err uses exit 1 (fail-fast correct); test needs capture not exit
function err { param($m) $script:FAILED = $m }

# Returns concatenated Assert-* function source from a .ps1 file (AST-extracted).
# iex must run at SCRIPT scope (caller) so defs survive - hence return-string design.
function Get-AssertCode {
  param([string]$file)
  $errs = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errs)
  if ($errs) { Write-Host "PARSE ERR in $file" -ForegroundColor Red; $errs | ForEach-Object { Write-Host $_.Message }; exit 2 }
  $names = @('Assert-TrustedSource','Assert-ImmutableRef','Assert-CommitSha')
  $funcs = $ast.FindAll({
    param($node)
    ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and
    ($names -contains $node.Name)
  }, $true)
  if (-not $funcs -or $funcs.Count -lt 3) {
    Write-Host "EXTRACT FAIL: expected 3 Assert funcs in $file, got $(if($funcs){$funcs.Count}else{0})" -ForegroundColor Red
    exit 2
  }
  return ($funcs | ForEach-Object { $_.Extent.Text }) -join "`n`n"
}

function Expect {
  param([string]$fnName, [string]$val, [bool]$shouldPass)
  $script:FAILED = $null
  & $fnName $val
  $actualPass = [string]::IsNullOrEmpty($script:FAILED)
  if ($actualPass -eq $shouldPass) {
    Write-Host ("  PASS  {0,-26} {1,-46} pass={2}" -f $fnName, $val, $actualPass) -ForegroundColor Green
  } else {
    Write-Host ("  FAIL  {0,-26} {1,-46} pass={2} expect={3} [{4}]" -f $fnName, $val, $actualPass, $shouldPass, $script:FAILED) -ForegroundColor Red
    $script:GFAIL = $script:GFAIL + 1
  }
}

function Run-Matrix {
  param([string]$label)
  Write-Host "--- $label ---"
  # defect 2: trusted source (dot-segment / encoding / prefix bypass)
  Expect 'Assert-TrustedSource' "https://github.com/vinnfeng/opencode/x"        $true
  Expect 'Assert-TrustedSource' "https://raw.githubusercontent.com/vinnfeng/opencode/x" $true
  Expect 'Assert-TrustedSource' "https://github.com/attacker/repo"              $false
  Expect 'Assert-TrustedSource' "https://github.com/vinnfeng/../attacker/repo"  $false
  Expect 'Assert-TrustedSource' "https://github.com/vinnfeng/x/.."              $false
  Expect 'Assert-TrustedSource' "https://github.com/vinnfeng/%2e%2e/attacker"   $false
  Expect 'Assert-TrustedSource' "https://github.com/vinnfengfoo/evil"           $false
  Expect 'Assert-TrustedSource' "http://github.com/vinnfeng/x"                  $false
  # defect 2 round3: encoded slash/backslash/double-encode/backslash bypass
  Expect 'Assert-TrustedSource' "https://github.com/vinnfeng/%2f../attacker"    $false
  Expect 'Assert-TrustedSource' "https://github.com/vinnfeng/x%5c..%5cattacker" $false
  Expect 'Assert-TrustedSource' "https://github.com/vinnfeng/%252e%252e/attacker" $false
  Expect 'Assert-TrustedSource' "https://github.com/vinnfeng/x\..\attacker"     $false
  # defect 2 round4: multi-level encoded % bypasses (reject ANY % in trusted URL)
  Expect 'Assert-TrustedSource' "https://github.com/vinnfeng/%25%32%65%25%32%65/attacker" $false
  Expect 'Assert-TrustedSource' "https://github.com/vinnfeng/%25252e%25252e/attacker" $false
  Expect 'Assert-TrustedSource' "https://github.com/vinnfeng/x%255c..%255cattacker" $false
  # defect 5: immutable ref (whitelist 40hex SHA or vX.Y.Z[-pre]; blacklist gaps must reject)
  Expect 'Assert-ImmutableRef' "de6a37e8ffcf1f73ebe0aa1fb162794d1b965e7c"       $true
  Expect 'Assert-ImmutableRef' "v1.3.17-kaiqu.3"                                $true
  Expect 'Assert-ImmutableRef' "v2.0.0"                                         $true
  Expect 'Assert-ImmutableRef' ""                                               $false
  Expect 'Assert-ImmutableRef' "main"                                           $false
  Expect 'Assert-ImmutableRef' "release"                                        $false
  Expect 'Assert-ImmutableRef' "office-windows"                                 $false
  Expect 'Assert-ImmutableRef' "feature/foo"                                    $false
  Expect 'Assert-ImmutableRef' "latest"                                         $false
  # defect 5 round3: strict semver reject illegal prerelease tags (empty/double-dot/trailing)
  Expect 'Assert-ImmutableRef' "v1.2.3-rc.1"                                    $true
  Expect 'Assert-ImmutableRef' "v1.2.3-alpha.1.beta.2"                          $true
  Expect 'Assert-ImmutableRef' "v1.2.3-."                                       $false
  Expect 'Assert-ImmutableRef' "v1.2.3-a..b"                                    $false
  Expect 'Assert-ImmutableRef' "v1.2.3-"                                        $false
  Expect 'Assert-ImmutableRef' "v1.2.3-a."                                      $false
  # defect 5 round4: strict SemVer rejects leading zeros in major/minor/patch/prerelease
  Expect 'Assert-ImmutableRef' "v01.2.3"                                        $false
  Expect 'Assert-ImmutableRef' "v1.02.3"                                        $false
  Expect 'Assert-ImmutableRef' "v1.2.3-01"                                      $false
  # defect 3: commit sha (strict 40hex; reject tag/short-sha/branch)
  Expect 'Assert-CommitSha' "de6a37e8ffcf1f73ebe0aa1fb162794d1b965e7c"          $true
  Expect 'Assert-CommitSha' "v1.3.17-kaiqu.3"                                   $false
  Expect 'Assert-CommitSha' "de6a37e8"                                          $false
  Expect 'Assert-CommitSha' "migration"                                         $false
}

Write-Host "=== Part A (PS): behavioral test (AST-extract real Assert funcs + err stub) ==="
# iex at SCRIPT scope so function defs are visible to Expect/Run-Matrix
Invoke-Expression (Get-AssertCode (Join-Path $ScriptDir "setup.ps1"))
Run-Matrix "setup.ps1"
Invoke-Expression (Get-AssertCode (Join-Path $ScriptDir "community-setup.ps1"))
Run-Matrix "community-setup.ps1"

# ═════════════════════════════════════════════════════════════
# Part B: 动态控制流测试（缺陷4 五审）—— 执行 Verify-OpencodeViaPath
# 覆盖 4 类绕过 + 1 sanity：①外部PATH ③1.18.7-evil suffix ④空prefix ⑤sibling-prefix
# ═════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== Part B (PS): 动态控制流测试（缺陷4 五审 Verify-OpencodeViaPath）==="

# Verify 成功路径调用 ok/warn/info，补 stub（Part A 的 Assert 不需要）
function ok   { param($m) }
function warn { param($m) }
function info { param($m) }

function Get-VerifyCode {
  param([string]$file)
  $errs = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errs)
  if ($errs) { Write-Host "PARSE ERR in $file" -ForegroundColor Red; $errs | ForEach-Object { Write-Host $_.Message }; exit 2 }
  $funcs = $ast.FindAll({
    param($node)
    ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and
    ($node.Name -eq 'Verify-OpencodeViaPath')
  }, $true)
  if (-not $funcs) { Write-Host "EXTRACT FAIL: Verify-OpencodeViaPath not in $file" -ForegroundColor Red; exit 2 }
  return $funcs[0].Extent.Text
}

function Run-VerifyCase {
  param([string]$Label, [bool]$ShouldReject, [string]$NpmPrefix, [string]$OcAbsPath, [string]$OcVer)
  # 创建 opencode.cmd（Application 类型，可被 Get-Command 找到并执行）
  $ocDir = Split-Path $OcAbsPath -Parent
  New-Item -ItemType Directory -Force -Path $ocDir | Out-Null
  $cmdContent = "@echo off`r`necho $OcVer`r`n"
  [System.IO.File]::WriteAllText($OcAbsPath, $cmdContent)
  # mock npm（global 函数优先于 PATH 上 npm.cmd），返回受控 prefix
  $global:_MockNpmPrefix = $NpmPrefix
  Remove-Item Function:npm -Force -ErrorAction SilentlyContinue
  function global:npm { if (("$args" -replace '\s+',' ') -match 'config\s+get\s+prefix') { return $global:_MockNpmPrefix } }
  $savedPath = $env:PATH
  $env:PATH = "$ocDir;$env:PATH"
  $script:FAILED = $null
  & Verify-OpencodeViaPath 2>$null
  $env:PATH = $savedPath
  Remove-Item Function:npm -Force -ErrorAction SilentlyContinue
  Remove-Item $OcAbsPath -ErrorAction SilentlyContinue
  $actuallyRejected = -not [string]::IsNullOrEmpty($script:FAILED)
  if ($actuallyRejected -eq $ShouldReject) {
    Write-Host ("  PASS  {0,-46} reject={1}" -f $Label, $actuallyRejected) -ForegroundColor Green
  } else {
    Write-Host ("  FAIL  {0,-46} reject={1} expect={2} [{3}]" -f $Label, $actuallyRejected, $ShouldReject, $script:FAILED) -ForegroundColor Red
    $script:GFAIL = $script:GFAIL + 1
  }
}

# ── 七审：端到端控制流（提取整个安装块，含 existing-version if 分支 + verify 调用位置）──
# 铸言六审：Part B 只调 verify 函数，未覆盖 if 分支后 verify 是否真被调用（调用位置回归）
function Get-InstallBlock {
  param([string]$file)
  $errs = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errs)
  if ($errs) { Write-Host "PARSE ERR in $file" -ForegroundColor Red; $errs | ForEach-Object { Write-Host $_.Message }; exit 2 }
  $stmts = $ast.EndBlock.Statements
  $startStmt = $null; $endStmt = $null
  foreach ($s in $stmts) {
    if ($s.Extent.Text -match '^\$OPENCODE_NPM_PKG') { $startStmt = $s }
    if ($s.Extent.Text -match '^Verify-OpencodeViaPath') { $endStmt = $s; break }
  }
  if (-not $startStmt -or -not $endStmt) { Write-Host "EXTRACT FAIL: install block not found in $file" -ForegroundColor Red; exit 2 }
  $allText = [System.IO.File]::ReadAllText($file)
  return $allText.Substring($startStmt.Extent.StartOffset, $endStmt.Extent.EndOffset - $startStmt.Extent.StartOffset)
}

function Run-InstallE2E {
  param([string]$Label, [bool]$ShouldReject, [string]$NpmPrefix, [string]$OcAbsPath, [string]$OcVer)
  $ocDir = Split-Path $OcAbsPath -Parent
  New-Item -ItemType Directory -Force -Path $ocDir | Out-Null
  $cmdContent = "@echo off`r`necho $OcVer`r`n"
  [System.IO.File]::WriteAllText($OcAbsPath, $cmdContent)
  $global:_MockNpmPrefix = $NpmPrefix
  Remove-Item Function:npm -Force -ErrorAction SilentlyContinue
  function global:npm {
    $a = ("$args" -replace '\s+',' ')
    if ($a -match 'config\s+get\s+prefix') { return $global:_MockNpmPrefix }
    if ($a -match 'install|uninstall|list') { return $null }
  }
  $savedPath = $env:PATH
  $env:PATH = "$ocDir;$env:PATH"
  $script:FAILED = $null
  $installBlock = Get-InstallBlock (Join-Path $ScriptDir "community-setup.ps1")
  Invoke-Expression $installBlock
  $env:PATH = $savedPath
  Remove-Item Function:npm -Force -ErrorAction SilentlyContinue
  Remove-Item $OcAbsPath -ErrorAction SilentlyContinue
  $actuallyRejected = -not [string]::IsNullOrEmpty($script:FAILED)
  if ($actuallyRejected -eq $ShouldReject) {
    Write-Host ("  PASS  {0,-46} reject={1}" -f $Label, $actuallyRejected) -ForegroundColor Green
  } else {
    Write-Host ("  FAIL  {0,-46} reject={1} expect={2} [{3}]" -f $Label, $actuallyRejected, $ShouldReject, $script:FAILED) -ForegroundColor Red
    $script:GFAIL = $script:GFAIL + 1
  }
}

# iex Verify-OpencodeViaPath 到 SCRIPT scope（复用 err stub + ok stub）
Invoke-Expression (Get-VerifyCode (Join-Path $ScriptDir "community-setup.ps1"))

$MockRoot = Join-Path $env:TEMP ("d4mock_" + (Get-Date -Format "yyyyMMddHHmmssfff"))
$NpmPrefixGood = Join-Path $MockRoot "npm"

Run-VerifyCase "defect4 (1) external PATH same-ver"    $true  $NpmPrefixGood (Join-Path $MockRoot "external\bin\opencode.cmd") "1.18.7"
Run-VerifyCase "defect4 (3) version suffix 1.18.7-evil" $true  $NpmPrefixGood (Join-Path $NpmPrefixGood "bin\opencode.cmd") "1.18.7-evil"
Run-VerifyCase "defect4 (4) empty npm prefix"          $true  ""             (Join-Path $NpmPrefixGood "bin\opencode.cmd") "1.18.7"
Run-VerifyCase "defect4 (5) sibling prefix-evil"       $true  $NpmPrefixGood (Join-Path $MockRoot "npm-evil\bin\opencode.cmd") "1.18.7"
Run-VerifyCase "defect4 sanity normal install"          $false $NpmPrefixGood (Join-Path $NpmPrefixGood "bin\opencode.cmd") "1.18.7"

# 七审修复：六审 bash 清洗 bug 覆盖缺口——空格/Tab 后缀 reject
# PS 用 .Trim()+-replace 无 bash 清洗 bug（Trim 只去首尾空白），补覆盖证明空白后缀被拒
Run-VerifyCase "defect4 (3a) space suffix 1.18.7 evil"  $true  $NpmPrefixGood (Join-Path $NpmPrefixGood "bin\opencode.cmd") "1.18.7 evil"
Run-VerifyCase "defect4 (3b) opencode 1.18.7 evil"      $true  $NpmPrefixGood (Join-Path $NpmPrefixGood "bin\opencode.cmd") "opencode 1.18.7 evil"
# Tab 后缀：cmd echo 会把参数间 tab 折叠为空格，最终仍验证含空白后缀被拒
Run-VerifyCase "defect4 (3c) tab suffix 1.18.7 evil"    $true  $NpmPrefixGood (Join-Path $NpmPrefixGood "bin\opencode.cmd") "1.18.7`tevil"

# 七审：端到端控制流——existing-version then 分支仍调 verify 抓 evil（防调用位置回归）
# PS 用 Trim 无清洗 bug，端到端验证 then 分支后 Verify-OpencodeViaPath 真被调用
Run-InstallE2E "defect4 e2e then-branch (1.18.7 evil)"   $true  $NpmPrefixGood (Join-Path $NpmPrefixGood "bin\opencode.cmd") "1.18.7 evil"
Run-InstallE2E "defect4 e2e then-branch sanity (1.18.7)" $false $NpmPrefixGood (Join-Path $NpmPrefixGood "bin\opencode.cmd") "1.18.7"

Remove-Item -Recurse -Force $MockRoot -ErrorAction SilentlyContinue

Write-Host ""
if ($script:GFAIL -eq 0) {
  Write-Host "=== ALL PASS (D4 PS carriers assert regression) ===" -ForegroundColor Cyan
  exit 0
} else {
  Write-Host ("=== {0} FAILED ===" -f $script:GFAIL) -ForegroundColor Red
  exit 1
}
