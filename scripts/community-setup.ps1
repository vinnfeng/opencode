# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 社区版安装/更新 — Windows (PowerShell)
#  安装官方 opencode + Provider 配置 + 优化 agent 体系
#  Key 本地存储，不进 git，支持更新时保留上次配置
#
#  用法：
#    .\community-setup.ps1  (在 vinnfeng/opencode 克隆目录的 scripts\ 下运行)
# ═══════════════════════════════════════════════════════════
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$CONFIG_REPO   = "https://github.com/vinnfeng/opencode-config.git"
$CONFIG_DIR    = Join-Path $env:APPDATA "opencode"
$KEYS_FILE     = Join-Path $CONFIG_DIR ".keys"
$TEMPLATE_FILE = Join-Path $CONFIG_DIR "opencode.template.jsonc"
$CONFIG_FILE   = Join-Path $CONFIG_DIR "opencode.jsonc"

function ok   { param($m) Write-Host "✅  $m" -ForegroundColor Green }
function warn { param($m) Write-Host "⚠️   $m" -ForegroundColor Yellow }
function info { param($m) Write-Host "➜   $m" -ForegroundColor Cyan }
function err  { param($m) Write-Host "❌  $m" -ForegroundColor Red; exit 1 }

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
Write-Host "  开渠 OpenCode 社区版 — 安装/更新 (Windows)  " -ForegroundColor White
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""

# ── 1. 检查依赖 ───────────────────────────────────────────────
foreach ($cmd in @("git", "node", "npm")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { err "缺少依赖: $cmd" }
}

# ── 2. 安装官方 opencode ──────────────────────────────────────
if (Get-Command opencode -ErrorAction SilentlyContinue) {
  ok "opencode 已安装"
} else {
  info "安装 opencode-ai (官方版)..."
  & npm install -g opencode-ai
  if ($LASTEXITCODE -ne 0) { err "安装失败，请检查 npm 权限" }
  ok "opencode 安装完成"
}

# ── 3. 克隆配置仓库（community 分支）────────────────────────
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

# ── 6. 完成 ───────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
ok "安装完成！"
Write-Host ""
Write-Host "  配置目录: $CONFIG_DIR" -ForegroundColor White
Write-Host "  Key 文件: $KEYS_FILE (仅本机可见)" -ForegroundColor Yellow
Write-Host "  运行方式: opencode" -ForegroundColor White
Write-Host ""
Write-Host "  包含功能：" -ForegroundColor White
Write-Host "    • orchestrator agent（主编排，自动分工）" -ForegroundColor White
Write-Host "    • Sisyphus / Prometheus（oh-my-opencode 插件）" -ForegroundColor White
Write-Host "    • Provider 全模型接入（Opus/Sonnet/GPT-5.4/Gemini）" -ForegroundColor White
Write-Host "    • 自动 compaction + context pruning" -ForegroundColor White
$COMMUNITY_URL = "https://raw.githubusercontent.com/vinnfeng/opencode/release/kaiqu/scripts/community-setup.ps1"
Write-Host "  更新时重新运行，Key 自动从上次记录填入：" -ForegroundColor Gray
Write-Host "    irm $COMMUNITY_URL | iex" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""
