# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 个人版一键安装/更新 — Windows (PowerShell)
#  安装我们 fork 的自定义二进制 + 配置（key 本地存储，不进 git）
#
#  用法：
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
$KEYS_FILE    = Join-Path $CONFIG_DIR ".keys"
$TEMPLATE_FILE= Join-Path $CONFIG_DIR "opencode.template.jsonc"
$CONFIG_FILE  = Join-Path $CONFIG_DIR "opencode.jsonc"

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

# 工具函数：写入 .keys（upsert）
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

# 工具函数：掩码显示 key
function Mask-Key { param($k)
  if ([string]::IsNullOrEmpty($k)) { return "(未设置)" }
  if ($k.Length -le 12) { return $k.Substring(0,4) + "****" }
  return $k.Substring(0,8) + "..." + $k.Substring($k.Length - 4)
}

# ── 工具函数：交互式 key 设置 ────────────────────────────────
function Prompt-Key { param($name, $label)
  $current = Read-Key $name
  Write-Host ""
  Write-Host "  $label" -ForegroundColor White
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
    err "$label 不能为空，请重新运行并输入"
  }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host "  开渠 OpenCode 个人版 — 安装/更新 (Windows)  " -ForegroundColor White
Write-Host "  $RELEASE_TAG" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""

# ── 1. 检查依赖 ───────────────────────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { err "缺少依赖: git" }

# ── 2. 克隆或更新配置仓库 ────────────────────────────────────
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

# 切换到 office-windows 分支
Push-Location $CONFIG_DIR
& git fetch origin 2>$null
& git checkout office-windows 2>$null
if ($LASTEXITCODE -ne 0) {
  & git checkout -b office-windows --track origin/office-windows
}
ok "已切换到 office-windows 分支"
Pop-Location

# ── 3. 设置 API Keys ─────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host "  API Key 配置                                  " -ForegroundColor White
Write-Host "  Key 仅保存在本机 $KEYS_FILE" -ForegroundColor Yellow
Write-Host "  不进 git，安全可靠" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White

Prompt-Key "MIFY_API_KEY"    "Mify API Key（获取地址：https://llm.mioffice.cn/apikey）"
Prompt-Key "BAILIAN_API_KEY" "百炼 API Key（阿里云 Qwen）"

# ── 4. 生成 opencode.jsonc ───────────────────────────────────
info "生成 opencode.jsonc..."
if (-not (Test-Path $TEMPLATE_FILE)) { err "模板文件不存在: $TEMPLATE_FILE" }

$MIFY_KEY    = Read-Key "MIFY_API_KEY"
$BAILIAN_KEY = Read-Key "BAILIAN_API_KEY"

$content = Get-Content $TEMPLATE_FILE -Raw -Encoding UTF8
$content = $content.Replace("MIFY_API_KEY", $MIFY_KEY)
$content = $content.Replace("BAILIAN_API_KEY", $BAILIAN_KEY)
# Windows 使用 oh-my-opencode@latest（无本地缓存路径替换需求）
$content = $content.Replace("PLUGIN_PATH", "oh-my-opencode@latest")
Set-Content $CONFIG_FILE $content -Encoding UTF8
ok "opencode.jsonc 已生成"

# ── 5. 下载并安装自定义二进制 ────────────────────────────────
$ARCH = if ([System.Environment]::Is64BitOperatingSystem) {
  if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
} else { err "不支持 32 位系统" }

$BINARY_NAME  = "opencode-windows-$ARCH.exe"
$DOWNLOAD_URL = "$RELEASE_BASE/$BINARY_NAME"

New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
$INSTALL_PATH = Join-Path $INSTALL_DIR "opencode.exe"

$VERSION_STAMP = Join-Path $CONFIG_DIR ".installed_version"
$SKIP_BINARY = $false
if (Test-Path $INSTALL_PATH) {
  $installedTag = if (Test-Path $VERSION_STAMP) { (Get-Content $VERSION_STAMP -Raw).Trim() } else { "" }
  if ($installedTag -eq $RELEASE_TAG) {
    ok "二进制已是最新版 ($RELEASE_TAG)，跳过下载"
    $SKIP_BINARY = $true
  } else {
    info "已安装: $(if ($installedTag) { $installedTag } else { '未知' })，将更新至 $RELEASE_TAG"
  }
}

if (-not $SKIP_BINARY) {
  info "下载 $BINARY_NAME ($RELEASE_TAG)..."
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  try {
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $INSTALL_PATH -UseBasicParsing
  } catch {
    err "下载失败: $DOWNLOAD_URL`n$_"
  }
  Set-Content $VERSION_STAMP $RELEASE_TAG -Encoding UTF8
  ok "二进制已安装: $INSTALL_PATH ($RELEASE_TAG)"
}

# 加入 PATH（当前会话 + 用户永久）
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$INSTALL_DIR*") {
  [Environment]::SetEnvironmentVariable("PATH", "$userPath;$INSTALL_DIR", "User")
  $env:PATH = "$env:PATH;$INSTALL_DIR"
  info "已将 $INSTALL_DIR 加入用户 PATH（重开 Shell 后生效）"
}

# ── 6. 完成 ───────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
ok "安装完成！opencode 已是我们的自定义版本。"
Write-Host ""
Write-Host "  版本:       $RELEASE_TAG" -ForegroundColor White
Write-Host "  安装位置:   $INSTALL_PATH" -ForegroundColor White
Write-Host "  配置目录:   $CONFIG_DIR" -ForegroundColor White
Write-Host "  Key 文件:   $KEYS_FILE (仅本机可见)" -ForegroundColor Yellow
Write-Host "  运行方式:   opencode （重开 PowerShell 后生效）" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""
