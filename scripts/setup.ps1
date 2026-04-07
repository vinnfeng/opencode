# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 一键配置安装脚本 — Windows (PowerShell)
#  用法：irm <raw-url>/scripts/setup.ps1 | iex
#  或：  .\scripts\setup.ps1
# ═══════════════════════════════════════════════════════════
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$CONFIG_REPO = "https://github.com/vinnfeng/opencode-config.git"
$CONFIG_DIR  = Join-Path $env:APPDATA "opencode"
$CACHE_DIR   = Join-Path $env:LOCALAPPDATA "opencode"

function ok   { param($msg) Write-Host "✅  $msg" -ForegroundColor Green }
function warn { param($msg) Write-Host "⚠️   $msg" -ForegroundColor Yellow }
function info { param($msg) Write-Host "➜   $msg" -ForegroundColor Cyan }
function err  { param($msg) Write-Host "❌  $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host "  开渠 OpenCode — 一键配置安装 (Windows)        " -ForegroundColor White
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""

# ── 1. 检查依赖 ───────────────────────────────────────────────
foreach ($cmd in @("git", "node", "npm")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    err "缺少依赖: $cmd。请先安装后重试。"
  }
}

# ── 2. 安装 opencode（如未安装）────────────────────────────────
$ocInstalled = Get-Command opencode -ErrorAction SilentlyContinue
if ($ocInstalled) {
  $ver = & opencode --version 2>$null
  ok "opencode 已安装: $ver"
} else {
  info "安装 opencode-ai..."
  & npm install -g opencode-ai
  if ($LASTEXITCODE -ne 0) { err "opencode 安装失败，请检查 npm 权限" }
  ok "opencode 安装完成"
}

# ── 3. 克隆或更新配置仓库 ────────────────────────────────────
if (Test-Path (Join-Path $CONFIG_DIR ".git")) {
  info "配置目录已存在，拉取最新..."
  Push-Location $CONFIG_DIR
  $branch = & git branch --show-current
  & git pull origin $branch --rebase 2>&1 | Select-Object -Last 3
  Pop-Location
  ok "配置已更新 (分支: $branch)"
} else {
  if (Test-Path $CONFIG_DIR) {
    $backup = "${CONFIG_DIR}.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    warn "~\AppData\Roaming\opencode 已存在，备份到 $backup"
    Rename-Item -Path $CONFIG_DIR -NewName $backup
  }
  info "克隆配置仓库..."
  & git clone $CONFIG_REPO $CONFIG_DIR
  ok "配置仓库克隆完成"
}

# ── 4. 切换到 office-windows 分支 ────────────────────────────
Push-Location $CONFIG_DIR
$remoteBranch = "origin/office-windows"
$branchExists = & git show-ref --verify --quiet "refs/remotes/$remoteBranch" 2>$null
if ($LASTEXITCODE -eq 0) {
  info "切换到 office-windows 分支..."
  & git checkout office-windows 2>$null
  if ($LASTEXITCODE -ne 0) {
    & git checkout -b office-windows --track $remoteBranch
  }
  ok "已切换到 office-windows 分支"
}

# ── 5. 修复 plugin 路径 ───────────────────────────────────────
$pluginFile = Join-Path $CONFIG_DIR "opencode.jsonc"
$omoCachePath = Join-Path $CACHE_DIR "node_modules\oh-my-opencode"

if (Test-Path $pluginFile) {
  $content = Get-Content $pluginFile -Raw
  if (Test-Path $omoCachePath) {
    $newPath = "file://$($omoCachePath -replace '\\', '/')"
    $content = $content -replace '"file://[^"]*oh-my-opencode[^"]*"', "`"$newPath`""
    info "plugin 路径已更新 → $newPath"
  } else {
    $content = $content -replace '"file://[^"]*oh-my-opencode[^"]*"', '"oh-my-opencode@latest"'
    info "plugin 路径已重置为 npm 安装: oh-my-opencode@latest"
  }
  Set-Content $pluginFile $content -Encoding UTF8
}

Pop-Location

# ── 6. 完成 ───────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
ok "安装完成！"
Write-Host ""
Write-Host "  配置目录: $CONFIG_DIR" -ForegroundColor White
Write-Host "  运行方式: opencode" -ForegroundColor White
Write-Host ""
Write-Host "  可用 Agent（按 Tab 切换）:" -ForegroundColor White
Write-Host "    • orchestrator — 主编排（默认）" -ForegroundColor White
Write-Host "    • Sisyphus     — oh-my-opencode 全力模式" -ForegroundColor White
Write-Host "    • Prometheus   — 任务规划" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""
