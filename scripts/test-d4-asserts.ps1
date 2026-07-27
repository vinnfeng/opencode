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

Write-Host ""
if ($script:GFAIL -eq 0) {
  Write-Host "=== ALL PASS (D4 PS carriers assert regression) ===" -ForegroundColor Cyan
  exit 0
} else {
  Write-Host ("=== {0} FAILED ===" -f $script:GFAIL) -ForegroundColor Red
  exit 1
}
