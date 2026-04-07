# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 个人版一键安装 — Windows (PowerShell)
#  安装我们 fork 的自定义二进制 + 个人配置（含 key）
#
#  用法（Windows PowerShell）：
#    irm https://raw.githubusercontent.com/vinnfeng/opencode/fengzhen/performance-tuning/scripts/setup.ps1 | iex
# ═══════════════════════════════════════════════════════════
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$RELEASE_TAG  = "v1.3.17-kaiqu.3"
$RELEASE_BASE = "https://github.com/vinnfeng/opencode/releases/download/$RELEASE_TAG"
$CONFIG_REPO  = "https://github.com/vinnfeng/opencode-config.git"
$CONFIG_DIR   = Join-Path $env:APPDATA "opencode"
$CACHE_DIR    = Join-Path $env:LOCALAPPDATA "opencode"
$INSTALL_DIR  = Join-Path $env:LOCALAPPDATA "opencode-bin"

function ok   { param($m) Write-Host "✅  $m" -ForegroundColor Green }
function warn { param($m) Write-Host "⚠️   $m" -ForegroundColor Yellow }
function info { param($m) Write-Host "➜   $m" -ForegroundColor Cyan }
function err  { param($m) Write-Host "❌  $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host "  开渠 OpenCode 个人版 — 一键安装 (Windows)    " -ForegroundColor White
Write-Host "  $RELEASE_TAG" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""

# ── 1. 检查依赖 ───────────────────────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { err "缺少依赖: git" }

# ── 2. 下载并安装自定义二进制 ────────────────────────────────
$ARCH = if ([System.Environment]::Is64BitOperatingSystem) {
  if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
} else { err "不支持 32 位系统" }

$BINARY_NAME = "opencode-windows-$ARCH.exe"
$DOWNLOAD_URL = "$RELEASE_BASE/$BINARY_NAME"

# 确认安装目录
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
$INSTALL_PATH = Join-Path $INSTALL_DIR "opencode.exe"

info "下载 $BINARY_NAME ($RELEASE_TAG)..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
  Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $INSTALL_PATH -UseBasicParsing
} catch {
  err "下载失败: $DOWNLOAD_URL`n$_"
}
ok "二进制已安装: $INSTALL_PATH"

# 加入 PATH（当前会话 + 用户永久）
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$INSTALL_DIR*") {
  [Environment]::SetEnvironmentVariable("PATH", "$userPath;$INSTALL_DIR", "User")
  $env:PATH = "$env:PATH;$INSTALL_DIR"
  info "已将 $INSTALL_DIR 加入用户 PATH（重开 Shell 后生效）"
}

# ── 3. 克隆或更新配置仓库 ────────────────────────────────────
if (Test-Path (Join-Path $CONFIG_DIR ".git")) {
  info "配置目录已存在，拉取最新..."
  Push-Location $CONFIG_DIR
  $branch = & git branch --show-current
  & git pull origin $branch --rebase 2>&1 | Select-Object -Last 2
  Pop-Location
  ok "配置已更新"
} else {
  if (Test-Path $CONFIG_DIR) {
    Rename-Item -Path $CONFIG_DIR -NewName "${CONFIG_DIR}.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
  }
  info "克隆个人配置..."
  & git clone $CONFIG_REPO $CONFIG_DIR
  ok "配置克隆完成"
}

# ── 4. 切换到 office-windows 分支 ────────────────────────────
Push-Location $CONFIG_DIR
& git fetch origin 2>$null
& git checkout office-windows 2>$null
if ($LASTEXITCODE -ne 0) {
  & git checkout -b office-windows --track origin/office-windows
}
ok "已切换到 office-windows 分支"
Pop-Location

# ── 5. 完成 ───────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
ok "安装完成！opencode 已是我们的自定义版本。"
Write-Host ""
Write-Host "  版本:       $RELEASE_TAG" -ForegroundColor White
Write-Host "  安装位置:   $INSTALL_PATH" -ForegroundColor White
Write-Host "  配置目录:   $CONFIG_DIR" -ForegroundColor White
Write-Host "  运行方式:   opencode （重开 PowerShell 后生效）" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""
