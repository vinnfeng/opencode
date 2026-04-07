# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 社区版安装 — Windows (PowerShell)
#  安装官方 opencode + Mify 配置 + 优化 agent 体系
#  需要输入 Mify API Key
#
#  用法：
#    irm https://raw.githubusercontent.com/vinnfeng/opencode/fengzhen/performance-tuning/scripts/community-setup.ps1 | iex
# ═══════════════════════════════════════════════════════════
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$CONFIG_REPO = "https://github.com/vinnfeng/opencode-config.git"
$CONFIG_DIR  = Join-Path $env:APPDATA "opencode"

function ok   { param($m) Write-Host "✅  $m" -ForegroundColor Green }
function warn { param($m) Write-Host "⚠️   $m" -ForegroundColor Yellow }
function info { param($m) Write-Host "➜   $m" -ForegroundColor Cyan }
function err  { param($m) Write-Host "❌  $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host "  开渠 OpenCode 社区版 — 安装配置 (Windows)    " -ForegroundColor White
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""

# ── 1. 检查依赖 ───────────────────────────────────────────────
foreach ($cmd in @("git", "node", "npm")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { err "缺少依赖: $cmd" }
}

# ── 2. 输入 Mify API Key ──────────────────────────────────────
Write-Host "请输入你的 Mify API Key：" -ForegroundColor White
Write-Host "（从内网 Mify 平台获取，格式：sk-...）" -ForegroundColor Gray
$secureKey = Read-Host "Mify API Key" -AsSecureString
$MIFY_KEY = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
)
if (-not $MIFY_KEY -or -not $MIFY_KEY.StartsWith("sk-")) {
  err "Key 格式不对，应以 sk- 开头"
}
ok "Key 已输入"

# ── 3. 安装官方 opencode ──────────────────────────────────────
if (Get-Command opencode -ErrorAction SilentlyContinue) {
  ok "opencode 已安装"
} else {
  info "安装 opencode-ai (官方版)..."
  & npm install -g opencode-ai
  if ($LASTEXITCODE -ne 0) { err "安装失败，请检查 npm 权限" }
  ok "opencode 安装完成"
}

# ── 4. 克隆配置仓库（community 分支）────────────────────────
if (Test-Path (Join-Path $CONFIG_DIR ".git")) {
  info "配置目录已存在，更新中..."
  Push-Location $CONFIG_DIR
  & git fetch origin
  & git checkout community 2>$null
  if ($LASTEXITCODE -ne 0) {
    & git checkout -b community --track origin/community
  }
  & git pull origin community --rebase 2>&1 | Select-Object -Last 2
  Pop-Location
  ok "配置已更新"
} else {
  if (Test-Path $CONFIG_DIR) {
    Rename-Item -Path $CONFIG_DIR -NewName "${CONFIG_DIR}.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
  }
  info "克隆配置（community 分支）..."
  & git clone --branch community $CONFIG_REPO $CONFIG_DIR
  ok "配置克隆完成"
}

# ── 5. 替换 API Key 占位符 ────────────────────────────────────
$pluginFile = Join-Path $CONFIG_DIR "opencode.jsonc"
if (Test-Path $pluginFile) {
  $content = (Get-Content $pluginFile -Raw).Replace("MIFY_API_KEY", $MIFY_KEY)
  Set-Content $pluginFile $content -Encoding UTF8
  ok "API Key 已写入配置"
}

# ── 6. 完成 ───────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
ok "安装完成！"
Write-Host ""
Write-Host "  配置目录: $CONFIG_DIR" -ForegroundColor White
Write-Host "  运行方式: opencode" -ForegroundColor White
Write-Host ""
Write-Host "  包含功能：" -ForegroundColor White
Write-Host "    • orchestrator agent（主编排，自动分工）" -ForegroundColor White
Write-Host "    • Sisyphus / Prometheus（oh-my-opencode 插件）" -ForegroundColor White
Write-Host "    • Mify 全模型接入（Opus/Sonnet/GPT-5.4/Gemini）" -ForegroundColor White
Write-Host "    • 自动 compaction + context pruning" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""
