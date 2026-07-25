# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 个人版一键安装/更新 — Windows (PowerShell)
#
#  用法：
#    # 首次安装 / 完整更新（管理员 PowerShell 推荐）
#    irm https://raw.githubusercontent.com/vinnfeng/opencode/release/kaiqu/scripts/setup.ps1 | iex
#
#    # 只更新所有 API Key
#    .\setup.ps1 --keys
#
#    # 只更新某个 provider 的 key
#    .\setup.ps1 --key mify
#    .\setup.ps1 --key bailian
#
#    # 只更新二进制（不动 key 和配置）
#    .\setup.ps1 --binary
# ═══════════════════════════════════════════════════════════
#Requires -Version 5.1
param(
  [switch]$keys,
  [string]$key      = "",
  [switch]$binary,
  [switch]$rollback,
  [switch]$h,
  [switch]$help
)
$ErrorActionPreference = "Stop"

$RELEASE_TAG   = "v1.3.17-kaiqu.3"
$RELEASE_BASE  = "https://github.com/vinnfeng/opencode/releases/download/$RELEASE_TAG"
$CONFIG_REPO   = "https://github.com/vinnfeng/opencode-config.git"
$CONFIG_DIR    = Join-Path $env:APPDATA "opencode"
$INSTALL_DIR   = Join-Path $env:LOCALAPPDATA "opencode-bin"
$KEYS_FILE     = Join-Path $CONFIG_DIR ".keys"
$TEMPLATE_FILE = Join-Path $CONFIG_DIR "opencode.template.jsonc"
$CONFIG_FILE   = Join-Path $CONFIG_DIR "opencode.jsonc"
$VERSION_STAMP          = Join-Path $CONFIG_DIR ".installed_version"
$PREVIOUS_VERSION_STAMP = Join-Path $CONFIG_DIR ".previous_version"
$BACKUP_DIR             = Join-Path $env:LOCALAPPDATA "opencode-bin\backups"

function ok   { param($m) Write-Host "✅  $m" -ForegroundColor Green }
function warn { param($m) Write-Host "⚠️   $m" -ForegroundColor Yellow }
function info { param($m) Write-Host "➜   $m" -ForegroundColor Cyan }
function err  { param($m) Write-Host "❌  $m" -ForegroundColor Red; exit 1 }

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

# required: $true=必填, $false=可选
function Prompt-Key { param($name, $label, [bool]$required=$true, $hint="")
  $current = Read-Key $name
  Write-Host ""
  Write-Host "  $label" -ForegroundColor White
  if ($hint) { Write-Host "  $hint" -ForegroundColor Cyan }
  if ($current) {
    Write-Host "  当前值: $(Mask-Key $current)" -ForegroundColor Yellow
    Write-Host "  直接回车保留当前，输入新值则更新：" -ForegroundColor Gray
  } else {
    if ($required) {
      Write-Host "  (未设置，必填)" -ForegroundColor Yellow
    } else {
      Write-Host "  (未设置，可选 — 直接回车跳过)" -ForegroundColor Yellow
    }
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
  } elseif (-not $required) {
    warn "$label 跳过（该 provider 在配置中将不可用）"
  } else {
    err "$label 为必填项，请重新运行并输入"
  }
}

function Generate-Config {
  info "生成 opencode.jsonc..."
  if (-not (Test-Path $TEMPLATE_FILE)) { err "模板文件不存在，请先完整安装一次" }
  if (Test-Path $CONFIG_FILE) { Copy-Item $CONFIG_FILE "$CONFIG_FILE.bak" -Force }

  $mifyKey    = Read-Key "PROVIDER_API_KEY"
  $bailianKey = Read-Key "BAILIAN_API_KEY"

  if ([string]::IsNullOrEmpty($mifyKey)) {
    err "PROVIDER_API_KEY 未设置，请先运行：.\setup.ps1 --key mify"
  }

  # 用 node 做 JSON 解析，确保 bailian 移除后结构合法
  # 写临时 JS 文件避免 PS5.1 here-string 解析 bug
  $env:GEN_PROVIDER    = $mifyKey
  $env:GEN_BAILIAN = $bailianKey
  $env:GEN_TPL     = $TEMPLATE_FILE
  $env:GEN_OUT     = $CONFIG_FILE
  $tmpJs = [System.IO.Path]::GetTempFileName() + ".js"
  @(
    "var fs=require('fs'),e=process.env;"
    "var c=fs.readFileSync(e.GEN_TPL,'utf8');"
    "c=c.split('PROVIDER_API_KEY').join(e.GEN_PROVIDER);"
    "c=c.split('PLUGIN_PATH').join('oh-my-opencode@latest');"
    "var obj=JSON.parse(c);"
    "if(e.GEN_BAILIAN){obj.provider.bailian.options.apiKey=e.GEN_BAILIAN;}else{delete obj.provider.bailian;}"
    "fs.writeFileSync(e.GEN_OUT,JSON.stringify(obj,null,2));"
  ) -join "`n" | Set-Content $tmpJs -Encoding UTF8
  node $tmpJs
  Remove-Item $tmpJs -ErrorAction SilentlyContinue
  $env:GEN_PROVIDER=$null; $env:GEN_BAILIAN=$null; $env:GEN_TPL=$null; $env:GEN_OUT=$null
  ok "opencode.jsonc 已生成"
}

# ── 帮助信息 ──────────────────────────────────────────────────
if ($h -or $help) {
  Write-Host "用法：" -ForegroundColor White
  Write-Host "  首次安装 / 完整更新" -ForegroundColor Cyan
  Write-Host "    irm https://raw.githubusercontent.com/vinnfeng/opencode/release/kaiqu/scripts/setup.ps1 | iex"
  Write-Host ""
  Write-Host "  只更新所有 API Key" -ForegroundColor Cyan
  Write-Host "    .\setup.ps1 --keys"
  Write-Host ""
  Write-Host "  只更新某个 provider 的 key" -ForegroundColor Cyan
  Write-Host "    .\setup.ps1 --key mify"
  Write-Host "    .\setup.ps1 --key bailian"
  Write-Host ""
  Write-Host "  只更新二进制（不动 key 和配置）" -ForegroundColor Cyan
  Write-Host "    .\setup.ps1 --binary"
  Write-Host ""
  Write-Host "  回退到上一个版本" -ForegroundColor Cyan
  Write-Host "    .\setup.ps1 --rollback"
  Write-Host ""
  Write-Host "  可用 provider：mify（必填）、bailian（可选）" -ForegroundColor Gray
  exit 0
}

# ── 模式判断 ──────────────────────────────────────────────────
$MODE = "full"
if ($binary)   { $MODE = "binary" }
elseif ($rollback) { $MODE = "rollback" }
elseif ($keys) { $MODE = "keys" }
elseif ($key)  { $MODE = "key" }

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host "  开渠 OpenCode 个人版 — 安装/更新 (Windows)  " -ForegroundColor White
Write-Host "  版本: $RELEASE_TAG" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""

# ── only-keys 模式 ────────────────────────────────────────────
if ($MODE -eq "keys") {
  Write-Host "  模式：更新所有 API Key" -ForegroundColor White
  Prompt-Key "PROVIDER_API_KEY"    "Provider API Key（必填）"  $true  "向管理员获取 API Key"
  Prompt-Key "BAILIAN_API_KEY" "百炼 API Key（可选）"  $false "阿里云百炼平台 Qwen 系列模型"
  Generate-Config
  ok "Key 更新完成，配置已重新生成"
  exit 0
}

# ── only-key 模式 ─────────────────────────────────────────────
if ($MODE -eq "key") {
  Write-Host "  模式：更新 $key API Key" -ForegroundColor White
  switch ($key.ToLower()) {
    "mify"    { Prompt-Key "PROVIDER_API_KEY"    "Provider API Key（必填）"  $true  "向管理员获取 API Key" }
    "bailian" { Prompt-Key "BAILIAN_API_KEY" "百炼 API Key（可选）"  $false "阿里云百炼平台 Qwen 系列模型" }
    default   { err "不支持的 provider: $key，可用值：mify / bailian" }
  }
  Generate-Config
  ok "Key 更新完成，配置已重新生成"
  exit 0
}

# ── rollback 模式 ─────────────────────────────────────────────
if ($MODE -eq "rollback") {
  Write-Host "  模式：回退" -ForegroundColor White
  $prevTag = if (Test-Path $PREVIOUS_VERSION_STAMP) { (Get-Content $PREVIOUS_VERSION_STAMP -Raw).Trim() } else { "" }
  if ([string]::IsNullOrEmpty($prevTag)) { err "没有可用的回退版本（从未更新过，或备份已清除）" }

  $prevBin = Join-Path $BACKUP_DIR "opencode-$prevTag.exe"
  if (-not (Test-Path $prevBin)) { err "备份二进制不存在: $prevBin" }

  $curTag = if (Test-Path $VERSION_STAMP) { (Get-Content $VERSION_STAMP -Raw).Trim() } else { "未知" }
  info "回退: $curTag → $prevTag"
  Copy-Item $prevBin $INSTALL_PATH -Force
  Set-Content $VERSION_STAMP $prevTag -Encoding UTF8

  if (Test-Path "$CONFIG_FILE.bak") {
    Copy-Item "$CONFIG_FILE.bak" $CONFIG_FILE -Force
    ok "opencode.jsonc 已还原"
  } else {
    warn "opencode.jsonc 备份不存在，配置未还原"
  }

  ok "已回退到 $prevTag`: $INSTALL_PATH"
  exit 0
}

# ── 检查依赖 ──────────────────────────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { err "缺少依赖: git（请先安装 Git for Windows）" }

# ── full 模式：克隆/更新配置 + 设置 key ──────────────────────
if ($MODE -eq "full") {
  if (Test-Path (Join-Path $CONFIG_DIR ".git")) {
    info "拉取最新配置..."
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

  Push-Location $CONFIG_DIR
  & git fetch origin 2>$null
  & git checkout office-windows 2>$null
  if ($LASTEXITCODE -ne 0) { & git checkout -b office-windows --track origin/office-windows }
  ok "已切换到 office-windows 分支"
  Pop-Location

  Write-Host ""
  Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
  Write-Host "  API Key 配置                                  " -ForegroundColor White
  Write-Host "  Key 仅存于本机 $KEYS_FILE" -ForegroundColor Yellow
  Write-Host "═══════════════════════════════════════════════" -ForegroundColor White

  Prompt-Key "PROVIDER_API_KEY"    "Provider API Key（必填 — 全平台模型入口）" $true  "向管理员获取 API Key"
  Prompt-Key "BAILIAN_API_KEY" "百炼 API Key（可选 — 阿里云 Qwen）"   $false

  Generate-Config
}

# ── 下载/更新二进制 ───────────────────────────────────────────
$ARCH = if ([System.Environment]::Is64BitOperatingSystem) {
  if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
} else { err "不支持 32 位系统" }

$BINARY_NAME  = "opencode-windows-$ARCH.exe"
$DOWNLOAD_URL = "$RELEASE_BASE/$BINARY_NAME"
$INSTALL_PATH = Join-Path $INSTALL_DIR "opencode.exe"

New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null

$installedTag = if (Test-Path $VERSION_STAMP) { (Get-Content $VERSION_STAMP -Raw).Trim() } else { "" }

if ($installedTag -eq $RELEASE_TAG -and $MODE -ne "binary") {
  ok "二进制已是最新版 ($RELEASE_TAG)，跳过下载"
} elseif ($installedTag -eq $RELEASE_TAG -and $MODE -eq "binary") {
  ok "已是最新版 ($RELEASE_TAG)，无需更新"
  exit 0
} else {
  if ($installedTag) {
    info "已安装: $installedTag → 更新至 $RELEASE_TAG"
    # 更新前备份旧二进制，用于回退
    New-Item -ItemType Directory -Force -Path $BACKUP_DIR | Out-Null
    $backupPath = Join-Path $BACKUP_DIR "opencode-$installedTag.exe"
    if (Test-Path $INSTALL_PATH) {
      Copy-Item $INSTALL_PATH $backupPath -Force
      Set-Content $PREVIOUS_VERSION_STAMP $installedTag -Encoding UTF8
      info "旧版本已备份: $backupPath"
    }
  } else { info "首次安装，下载 $BINARY_NAME..." }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  try {
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $INSTALL_PATH -UseBasicParsing
  } catch {
    err "下载失败: $DOWNLOAD_URL`n$_"
  }
  Set-Content $VERSION_STAMP $RELEASE_TAG -Encoding UTF8
  ok "二进制已安装: $INSTALL_PATH ($RELEASE_TAG)"
}

# 加入 PATH
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$INSTALL_DIR*") {
  [Environment]::SetEnvironmentVariable("PATH", "$userPath;$INSTALL_DIR", "User")
  $env:PATH = "$env:PATH;$INSTALL_DIR"
  info "已将 $INSTALL_DIR 加入用户 PATH（重开 Shell 后生效）"
}

# ── 完成 ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
ok "完成！"
Write-Host ""
Write-Host "  版本:     $RELEASE_TAG" -ForegroundColor White
Write-Host "  配置:     $CONFIG_DIR" -ForegroundColor White
Write-Host "  Key 文件: $KEYS_FILE (仅本机可见)" -ForegroundColor Yellow
Write-Host "  运行:     opencode （重开 PowerShell 后生效）" -ForegroundColor White
Write-Host ""
$SETUP_URL = "https://raw.githubusercontent.com/vinnfeng/opencode/release/kaiqu/scripts/setup.ps1"
Write-Host "  后续常用命令（直接粘贴运行）：" -ForegroundColor White
Write-Host "    更新所有 key:    irm $SETUP_URL | iex  # 或 .\setup.ps1 --keys（本地）" -ForegroundColor Cyan
Write-Host "    只换 Provider key:   & ([scriptblock]::Create((irm $SETUP_URL))) --key mify" -ForegroundColor Cyan
Write-Host "    只换百炼 key:    & ([scriptblock]::Create((irm $SETUP_URL))) --key bailian" -ForegroundColor Cyan
Write-Host "    只更新二进制:    & ([scriptblock]::Create((irm $SETUP_URL))) --binary" -ForegroundColor Cyan
Write-Host "    回退上一版本:    & ([scriptblock]::Create((irm $SETUP_URL))) --rollback" -ForegroundColor Cyan
Write-Host ""
Write-Host "  💡 或保存到本地，后续直接 .\opencode-setup.ps1 --keys：" -ForegroundColor White
Write-Host "    Invoke-WebRequest -Uri $SETUP_URL -OutFile `"`$env:USERPROFILE\opencode-setup.ps1`"" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""
