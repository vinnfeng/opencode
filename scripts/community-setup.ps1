# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 社区版安装/更新 - Windows (PowerShell)
#  安装官方 opencode + Provider 配置 + 优化 agent 体系
#  Key 本地存储，不进 git，支持更新时保留上次配置
#
#  用法（raw URL 固定到 RELEASE_TAG，符合 RAW-URL-POLICY 条件 2/3）：
#    irm https://raw.githubusercontent.com/vinnfeng/opencode/v1.3.17-kaiqu.3/scripts/community-setup.ps1 | iex
# ═══════════════════════════════════════════════════════════
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$RELEASE_TAG   = "v1.3.17-kaiqu.3"
$CONFIG_REPO   = "https://github.com/vinnfeng/opencode-config.git"
# D4 条件 2/3: CONFIG checkout 固定 commit SHA（非浮动 community 分支）
$CONFIG_REF    = "3b91bce58bb4d99b4b33c58d52a73e90721e1e75"
$CONFIG_DIR    = Join-Path $env:APPDATA "opencode"
$KEYS_FILE     = Join-Path $CONFIG_DIR ".keys"
$TEMPLATE_FILE = Join-Path $CONFIG_DIR "opencode.template.jsonc"
$CONFIG_FILE   = Join-Path $CONFIG_DIR "opencode.jsonc"
# D4 条件 2/3: 脚本分发 URL 固定到 RELEASE_TAG（非浮动分支）
$COMMUNITY_URL = "https://raw.githubusercontent.com/vinnfeng/opencode/$RELEASE_TAG/scripts/community-setup.ps1"

function ok   { param($m) Write-Host "✅  $m" -ForegroundColor Green }
function warn { param($m) Write-Host "⚠️   $m" -ForegroundColor Yellow }
function info { param($m) Write-Host "➜   $m" -ForegroundColor Cyan }
function err  { param($m) Write-Host "❌  $m" -ForegroundColor Red; exit 1 }

# ── D4 缺陷2: 可信来源白名单校验（硬化：decode+规范化+拒 dot-segment 变体）──
function Assert-TrustedSource { param($url)
  if (-not ($url -like "https://github.com/vinnfeng/*" -or $url -like "https://raw.githubusercontent.com/vinnfeng/*")) {
    err "来源不在可信白名单（D4 缺陷2）: $url（仅允许 github.com/vinnfeng/* 或 raw.githubusercontent.com/vinnfeng/*）"
  }
  # 四审加固：可信 URL 本不需编码，拒绝任何 % 编码和反斜杠（最小修复）
  if ($url.Contains('%')) { err "可信 URL 含 % 编码（D4 缺陷2 四审）: $url" }
  if ($url.Contains('\')) { err "可信 URL 含反斜杠（D4 缺陷2 四审）: $url" }
  # 明文 dot-segment 检查（防御深度）
  if ($url -match '/(\.\.?)(/|$)') {
    err "来源含 dot-segment（D4 缺陷2）: $url"
  }
}
# ── D4 缺陷5: 不可变 ref 校验（白名单：仅 40hex SHA 或 vX.Y.Z[-pre] tag）──
function Assert-ImmutableRef { param($ref)
  if ([string]::IsNullOrEmpty($ref)) { err "拒绝空 ref（D4 缺陷5）" }
  if ($ref -cmatch '^[0-9a-f]{40}$') { return }
  if ($ref -cmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?$') { return }
  err "拒绝浮动/非法 ref（D4 缺陷5）: '$ref'（仅允许 40位hex SHA 或 vX.Y.Z[-pre] tag；禁 main/master/dev/release/office-windows/latest/HEAD 等）"
}
# ── D4 缺陷3: CONFIG_REF 必须 40位hex commit SHA（防误填分支名/tag）──
function Assert-CommitSha { param($ref)
  if ($ref -cmatch '^[0-9a-f]{40}$') { return }
  err "CONFIG_REF 必须 40位hex commit SHA（D4 缺陷3）: '$ref'（不得用分支名/tag）"
}

# ── 工具函数：从 .keys 读取 key ──────────────────────────────
function Read-Key { param($name)
  if (Test-Path $KEYS_FILE) {
    $line = Get-Content $KEYS_FILE | Where-Object { $_ -match "^${name}=" } | Select-Object -First 1
    if ($line) { return $line.Substring($name.Length + 1) }
  }
  return ""
}

function Write-Key { param($name, $value)
  New-Item -ItemType Directory -Force -Path (Split-Path $KEYS_FILE) | Out-Null
  if (Test-Path $KEYS_FILE) {
    $content = Get-Content $KEYS_FILE -Raw
    if ($content -match "(?m)^${name}=") {
      $content = $content -replace "(?m)^${name}=.*$", "${name}=${value}"
      Set-Content $KEYS_FILE $content -Encoding UTF8 -NoNewline
    } else {
      Add-Content $KEYS_FILE "${name}=${value}" -Encoding UTF8
    }
  } else {
    Set-Content $KEYS_FILE "${name}=${value}" -Encoding UTF8
  }
}

function Mask-Key { param($k)
  if ([string]::IsNullOrEmpty($k)) { return "(未设置)" }
  if ($k.Length -le 12) { return $k.Substring(0,4) + "****" }
  return $k.Substring(0,8) + "..." + $k.Substring($k.Length - 4)
}

function Prompt-Key { param($name, $label, $hint="")
  $current = Read-Key $name
  Write-Host ""
  Write-Host "  $label" -ForegroundColor White
  if ($hint) { Write-Host "  $hint" -ForegroundColor Cyan }
  if ($current) {
    Write-Host "  当前值: $(Mask-Key $current)" -ForegroundColor Yellow
    Write-Host "  直接回车保留当前，输入新值则更新：" -ForegroundColor Gray
  } else {
    Write-Host "  (未设置，请输入)" -ForegroundColor Yellow
  }
  $secureInput = Read-Host "  输入" -AsSecureString
  $input = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
  )
  if ($input) {
    Write-Key $name $input
    ok "$label 已更新"
  } elseif ($current) {
    ok "$label 保留不变"
  } else {
    err "$label 为必填项，请重新运行并输入"
  }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host "  开渠 OpenCode 社区版 - 安装/更新 (Windows)  " -ForegroundColor White
Write-Host "  版本: $RELEASE_TAG" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""

# ── 1. 检查依赖 ───────────────────────────────────────────────
foreach ($cmd in @("git", "node", "npm")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { err "缺少依赖: $cmd" }
}

# ── D4 缺陷2/3/5: 白名单 + 不可变 ref + CONFIG_REF SHA 校验 ──
Assert-TrustedSource $COMMUNITY_URL
Assert-TrustedSource $CONFIG_REPO
Assert-ImmutableRef $RELEASE_TAG
Assert-CommitSha $CONFIG_REF

# ── 2. 安装官方 opencode ──────────────────────────────────────
# D4 缺陷4/5：社区版走 npm 渠道，必须锁版本 + 固定官方 registry + 装后校验实际版本
# （铸言复核：原 npm install -g opencode-ai 隐式 @latest，无完整性校验，N/A 标注不合理）
$OPENCODE_NPM_PKG = "opencode-ai@1.18.7"
$NPM_REGISTRY     = "https://registry.npmjs.org"
$existingVer = ""
if (Get-Command opencode -ErrorAction SilentlyContinue) {
  $verOut = & opencode --version 2>$null
  if ($verOut -match '([0-9]+\.[0-9]+\.[0-9]+)') { $existingVer = $Matches[1] }
}
# 缺陷5：已存在 opencode 必须校验版本，旧版绕过 1.18.7 锁定 -> 卸载重装+校验
if ($existingVer -eq "1.18.7") {
  ok "opencode 已是锁定版本: $existingVer"
} else {
  if ($existingVer) {
    warn "opencode 已存在 ($existingVer) 非 1.18.7，卸载重装（D4 缺陷5：旧版绕过锁定）"
    & npm uninstall -g opencode-ai --registry=$NPM_REGISTRY 2>$null | Out-Null
  } else {
    info "未检测到 opencode，安装 $OPENCODE_NPM_PKG (官方版，固定 registry)..."
  }
  & npm install -g $OPENCODE_NPM_PKG --registry=$NPM_REGISTRY
  if ($LASTEXITCODE -ne 0) { err "安装失败，请检查 npm 权限/registry" }
  # 缺陷4 四审加固：装后通过 PATH 实际命令校验（不信任 npm metadata，防 PATH 残留旧版）
  $installedCmd = Get-Command opencode -ErrorAction SilentlyContinue
  if (-not $installedCmd) { err "opencode-ai 安装后未在 PATH 找到二进制（D4 缺陷4 四审）" }
  $npmPrefix = & npm config get prefix 2>$null
  if ($installedCmd.Path -notlike "$npmPrefix*") {
    err "opencode 二进制路径异常（D4 缺陷4 四审）: $($installedCmd.Path)（期望在 npm prefix $npmPrefix 下）"
  }
  $verOut = & $installedCmd.Path --version 2>$null
  if ($verOut -match '([0-9]+\.[0-9]+\.[0-9]+)') { $installedVer = $Matches[1] } else { $installedVer = "" }
  if (-not $installedVer) { err "opencode-ai PATH 命令无法返回版本（D4 缺陷4 四审）" }
  if ($installedVer -ne "1.18.7") { err "opencode-ai PATH 命令实际版本 ($installedVer) 与锁定 (1.18.7) 不符（D4 缺陷4 四审：PATH 残留旧版/异常）" }
  ok "opencode PATH 校验通过：版本 $installedVer，位于 $($installedCmd.Path)"
}

# ── 3. 克隆配置仓库（D4 条件 2/3: 固定 CONFIG_REF commit SHA）──
if (Test-Path (Join-Path $CONFIG_DIR ".git")) {
  info "配置目录已存在，更新中（固定到 $CONFIG_REF）..."
  Push-Location $CONFIG_DIR
  & git fetch origin 2>&1 | Select-Object -Last 2
  & git checkout $CONFIG_REF 2>$null
  if ($LASTEXITCODE -ne 0) { Pop-Location; err "CONFIG_REF 固定版本不存在: $CONFIG_REF（D4 条件 2/3）" }
  Pop-Location
  ok "配置已更新到固定版本"
} else {
  if (Test-Path $CONFIG_DIR) {
    Rename-Item -Path $CONFIG_DIR -NewName "${CONFIG_DIR}.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
  }
  info "克隆配置（固定到 $CONFIG_REF）..."
  & git clone $CONFIG_REPO $CONFIG_DIR
  Push-Location $CONFIG_DIR
  & git fetch origin 2>&1 | Select-Object -Last 2
  & git checkout $CONFIG_REF 2>$null
  if ($LASTEXITCODE -ne 0) { Pop-Location; err "CONFIG_REF 固定版本不存在: $CONFIG_REF（D4 条件 2/3）" }
  Pop-Location
  ok "配置克隆完成（固定版本）"
}

# ── 4. 设置 API Key ──────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host "  API Key 配置                                  " -ForegroundColor White
Write-Host "  Key 仅保存在本机 $KEYS_FILE" -ForegroundColor Yellow
Write-Host "  不进 git，安全可靠" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White

Prompt-Key "PROVIDER_API_KEY" "Provider API Key（必填）" "向管理员获取 API Key"

# ── 5. 生成 opencode.jsonc ───────────────────────────────────
info "生成 opencode.jsonc..."
if (-not (Test-Path $TEMPLATE_FILE)) { err "模板文件不存在: $TEMPLATE_FILE" }

$PROVIDER_KEY = Read-Key "PROVIDER_API_KEY"

$content = Get-Content $TEMPLATE_FILE -Raw -Encoding UTF8
$content = $content.Replace("PROVIDER_API_KEY", $PROVIDER_KEY)
Set-Content $CONFIG_FILE $content -Encoding UTF8
ok "opencode.jsonc 已生成"

# ── 6. 完成（D4 条件 6: 显示真实来源与固定版本）──────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
ok "安装完成！"
Write-Host ""
Write-Host "  来源:     $COMMUNITY_URL" -ForegroundColor White
Write-Host "  版本:     $RELEASE_TAG" -ForegroundColor White
Write-Host "  配置目录: $CONFIG_DIR" -ForegroundColor White
Write-Host "  Key 文件: $KEYS_FILE (仅本机可见)" -ForegroundColor Yellow
Write-Host "  运行方式: opencode" -ForegroundColor White
Write-Host ""
Write-Host "  包含功能：" -ForegroundColor White
Write-Host "    • orchestrator agent（主编排，自动分工）" -ForegroundColor White
Write-Host "    • Sisyphus / Prometheus（oh-my-opencode 插件）" -ForegroundColor White
Write-Host "    • Provider 全模型接入（Opus/Sonnet/GPT-5.4/Gemini）" -ForegroundColor White
Write-Host "    • 自动 compaction + context pruning" -ForegroundColor White
Write-Host "  更新时重新运行，Key 自动从上次记录填入：" -ForegroundColor Gray
Write-Host "    irm $COMMUNITY_URL | iex" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""
