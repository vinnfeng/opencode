# ═══════════════════════════════════════════════════════════
#  开渠 (OpenCode) 个人版一键安装/更新 - Windows (PowerShell)
#
#  用法：
#    # 首次安装 / 完整更新（管理员 PowerShell 推荐，raw URL 固定到 RELEASE_TAG）
#    irm https://raw.githubusercontent.com/vinnfeng/opencode/v1.3.17-kaiqu.3/scripts/setup.ps1 | iex
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
# D4 条件 2/3: CONFIG checkout 固定 commit SHA（非浮动 office-windows 分支）
$CONFIG_REF    = "de6a37e8ffcf1f73ebe0aa1fb162794d1b965e7c"
$CONFIG_DIR    = Join-Path $env:APPDATA "opencode"
$INSTALL_DIR   = Join-Path $env:LOCALAPPDATA "opencode-bin"
# D4 缺陷6修复: INSTALL_PATH 必须在 rollback 块（Copy-Item 处）使用前定义，否则 Copy-Item 到空路径 → rc=0 打印成功但目标不存在（假成功）
$INSTALL_PATH  = Join-Path $INSTALL_DIR "opencode.exe"
$KEYS_FILE     = Join-Path $CONFIG_DIR ".keys"
$TEMPLATE_FILE = Join-Path $CONFIG_DIR "opencode.template.jsonc"
$CONFIG_FILE   = Join-Path $CONFIG_DIR "opencode.jsonc"
$VERSION_STAMP          = Join-Path $CONFIG_DIR ".installed_version"
$PREVIOUS_VERSION_STAMP = Join-Path $CONFIG_DIR ".previous_version"
$BACKUP_DIR             = Join-Path $env:LOCALAPPDATA "opencode-bin\backups"
# D4 条件 5: manifest 保存来源/版本/哈希/获取时间
$MANIFEST_FILE          = Join-Path $CONFIG_DIR ".install_manifest"
# D4 条件 2/3: 脚本分发 URL 固定到 RELEASE_TAG（非浮动分支）
$SETUP_URL              = "https://raw.githubusercontent.com/vinnfeng/opencode/$RELEASE_TAG/scripts/setup.ps1"

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

# ── D4: SHA256 验证（条件 4）─────────────────────────────────
# 取 $url 的 .sha256 校验文件，对比 $file 实际哈希；不存在/不匹配 err 阻断
function Verify-Sha256 { param($url, $file)
  $sumUrl = "$url.sha256"
  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    Invoke-WebRequest -Uri $sumUrl -OutFile $tmp -UseBasicParsing
  } catch {
    Remove-Item $tmp -ErrorAction SilentlyContinue
    err "SHA256 校验文件不存在: $sumUrl（D4 条件 4：release 须附 .sha256 资产，当前 release 未附）"
  }
  $content = (Get-Content $tmp -Raw).Trim()
  Remove-Item $tmp -ErrorAction SilentlyContinue
  $expected = ""
  if ($content -match '([a-fA-F0-9]{64})') { $expected = $matches[1].ToLower() }
  if (-not $expected) { err "SHA256 校验文件格式无效: $sumUrl" }
  $actual = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
  if ($actual -ne $expected) {
    err "SHA256 校验失败: $file（预期 $($expected.Substring(0,16))…，实际 $($actual.Substring(0,16))…）"
  }
  return $actual
}

# ── D4: manifest 保存（条件 5）──────────────────────────────
function Save-Manifest { param($sourceUrl, $version, $sha256, $fetchTime)
  New-Item -ItemType Directory -Force -Path (Split-Path $MANIFEST_FILE) | Out-Null
  $content = @"
source_url=$sourceUrl
version=$version
sha256=$sha256
fetch_time=$fetchTime
"@
  Set-Content $MANIFEST_FILE $content -Encoding UTF8
}

# ── D4: 来源/版本一致性阻断（条件 7）────────────────────────
function Check-Consistency {
  if (-not (Test-Path $MANIFEST_FILE)) { return }
  $lines = Get-Content $MANIFEST_FILE
  $recordedUrl = ($lines | Where-Object { $_ -match "^source_url=" } | Select-Object -First 1) -replace "^source_url=", ""
  $recordedVersion = ($lines | Where-Object { $_ -match "^version=" } | Select-Object -First 1) -replace "^version=", ""
  $recordedSha = ($lines | Where-Object { $_ -match "^sha256=" } | Select-Object -First 1) -replace "^sha256=", ""
  if ($recordedUrl -ne $DOWNLOAD_URL -or $recordedVersion -ne $RELEASE_TAG) {
    err "来源/版本不一致（D4 条件 7 阻断）: 记录 $recordedUrl/$recordedVersion，当前 $DOWNLOAD_URL/$RELEASE_TAG"
  }
  # 缺陷4强化：manifest 必须含 sha256（缺失=被篡改/不完整，必须拒绝，不能假跳过）
  if (-not $recordedSha) { err "manifest 缺少 sha256（D4 缺陷4）：$MANIFEST_FILE（不能假跳过）" }
  # 已装二进制实际 sha 必须与 manifest 记录一致（防同 URL/version 下二进制被替换/篡改）
  if ($INSTALL_PATH -and (Test-Path $INSTALL_PATH)) {
    $actualSha = (Get-FileHash $INSTALL_PATH -Algorithm SHA256).Hash.ToLower()
    if ($actualSha -ne $recordedSha.ToLower()) {
      err "已装二进制哈希与 manifest 不符（D4 缺陷4 篡改检测）: 记录 $($recordedSha.Substring(0,16))…，实际 $($actualSha.Substring(0,16))…"
    }
  }
}

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
      Write-Host "  (未设置，可选 - 直接回车跳过)" -ForegroundColor Yellow
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
    "c=c.split('PLUGIN_PATH').join('oh-my-opencode@4.19.2');"
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
  Write-Host "    irm $SETUP_URL | iex"
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
Write-Host "  开渠 OpenCode 个人版 - 安装/更新 (Windows)  " -ForegroundColor White
Write-Host "  版本: $RELEASE_TAG" -ForegroundColor White
Write-Host "  来源: $RELEASE_BASE" -ForegroundColor White
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
  # D4 条件 10: 回滚资产必须事先存在
  if (-not (Test-Path $prevBin)) { err "回滚资产不存在: $prevBin（D4 条件 10：更新前未备份该版本）" }

  $curTag = if (Test-Path $VERSION_STAMP) { (Get-Content $VERSION_STAMP -Raw).Trim() } else { "未知" }
  info "回退: $curTag -> $prevTag"
  Copy-Item $prevBin $INSTALL_PATH -Force
  # 缺陷6: 复制后校验目标存在 + hash 与备份一致（防 rc=0 打印成功但目标不存在的假成功）
  if (-not (Test-Path $INSTALL_PATH)) { err "回滚复制失败，目标不存在: $INSTALL_PATH（D4 缺陷6）" }
  $rollbackSha = (Get-FileHash $INSTALL_PATH -Algorithm SHA256).Hash.ToLower()
  $backupSha = (Get-FileHash $prevBin -Algorithm SHA256).Hash.ToLower()
  if ($rollbackSha -ne $backupSha) { err "回滚哈希与备份不符（D4 缺陷6）: $INSTALL_PATH vs $prevBin" }
  Set-Content $VERSION_STAMP $prevTag -Encoding UTF8

  # D4: 回滚 manifest（若有备份）
  $prevManifest = Join-Path $BACKUP_DIR "manifest-$prevTag"
  if (Test-Path $prevManifest) {
    Copy-Item $prevManifest $MANIFEST_FILE -Force
    ok "manifest 已回滚到 $prevTag"
  }

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

# ── D4 缺陷2/5: 安装入口白名单 + 不可变 ref 校验（任何下载/克隆前）──
Assert-TrustedSource $SETUP_URL
Assert-TrustedSource $RELEASE_BASE
Assert-TrustedSource $CONFIG_REPO
Assert-ImmutableRef $RELEASE_TAG
Assert-CommitSha $CONFIG_REF

# ── full 模式：克隆/更新配置 + 设置 key ──────────────────────
if ($MODE -eq "full") {
  if (Test-Path (Join-Path $CONFIG_DIR ".git")) {
    info "拉取配置（固定到 $CONFIG_REF）..."
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
    info "克隆个人配置（固定到 $CONFIG_REF）..."
    & git clone $CONFIG_REPO $CONFIG_DIR
    Push-Location $CONFIG_DIR
    & git fetch origin 2>&1 | Select-Object -Last 2
    & git checkout $CONFIG_REF 2>$null
    if ($LASTEXITCODE -ne 0) { Pop-Location; err "CONFIG_REF 固定版本不存在: $CONFIG_REF（D4 条件 2/3）" }
    Pop-Location
    ok "配置克隆完成（固定版本）"
  }

  Write-Host ""
  Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
  Write-Host "  API Key 配置                                  " -ForegroundColor White
  Write-Host "  Key 仅存于本机 $KEYS_FILE" -ForegroundColor Yellow
  Write-Host "═══════════════════════════════════════════════" -ForegroundColor White

  Prompt-Key "PROVIDER_API_KEY"    "Provider API Key（必填 - 全平台模型入口）" $true  "向管理员获取 API Key"
  Prompt-Key "BAILIAN_API_KEY" "百炼 API Key（可选 - 阿里云 Qwen）"   $false

  Generate-Config
}

# ── 下载/更新二进制 ───────────────────────────────────────────
$ARCH = if ([System.Environment]::Is64BitOperatingSystem) {
  if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
} else { err "不支持 32 位系统" }

$BINARY_NAME  = "opencode-windows-$ARCH.exe"
$DOWNLOAD_URL = "$RELEASE_BASE/$BINARY_NAME"

New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null

# D4 条件7 + 缺陷4: 一致性阻断 + 已装二进制 sha 篡改检测（须在 skip 判断前，否则 skip 路径绕过校验）
Check-Consistency

$installedTag = if (Test-Path $VERSION_STAMP) { (Get-Content $VERSION_STAMP -Raw).Trim() } else { "" }

# 缺陷4：skip 必须二进制实际存在，否则版本戳记录最新但二进制缺失会假跳过
if ($installedTag -eq $RELEASE_TAG -and $MODE -ne "binary" -and (Test-Path $INSTALL_PATH)) {
  ok "二进制已是最新版 ($RELEASE_TAG)，跳过下载"
} elseif ($installedTag -eq $RELEASE_TAG -and $MODE -eq "binary" -and (Test-Path $INSTALL_PATH)) {
  ok "已是最新版 ($RELEASE_TAG)，无需更新"
  exit 0
} else {
  if ($installedTag) {
    if (-not (Test-Path $INSTALL_PATH)) {
      warn "版本戳记录 $installedTag 但二进制缺失，重新下载（D4 缺陷4：不能按版本戳假跳过）"
    } else {
      info "已安装: $installedTag -> 更新至 $RELEASE_TAG"
    }
    # 更新前备份旧二进制，用于回退（D4 条件 10）
    New-Item -ItemType Directory -Force -Path $BACKUP_DIR | Out-Null
    $backupPath = Join-Path $BACKUP_DIR "opencode-$installedTag.exe"
    if (Test-Path $INSTALL_PATH) {
      Copy-Item $INSTALL_PATH $backupPath -Force
      Set-Content $PREVIOUS_VERSION_STAMP $installedTag -Encoding UTF8
      # D4: manifest 备份
      if (Test-Path $MANIFEST_FILE) {
        Copy-Item $MANIFEST_FILE (Join-Path $BACKUP_DIR "manifest-$installedTag") -Force
      }
      info "旧版本已备份: $backupPath"
    }
  } else { info "首次安装，下载 $BINARY_NAME..." }
  # D4 条件 4/5: 下载到临时文件 -> SHA256 验证 -> manifest 保存 -> 移到正式路径
  $tmpBin = [System.IO.Path]::GetTempFileName() + ".exe"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  try {
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $tmpBin -UseBasicParsing
  } catch {
    Remove-Item $tmpBin -ErrorAction SilentlyContinue
    err "下载失败: $DOWNLOAD_URL`n$_"
  }
  $actualSha256 = Verify-Sha256 $DOWNLOAD_URL $tmpBin
  $fetchTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  Save-Manifest $DOWNLOAD_URL $RELEASE_TAG $actualSha256 $fetchTime
  Move-Item $tmpBin $INSTALL_PATH -Force
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

# ── 完成（D4 条件 6: 显示真实来源与固定版本 + SHA256）─────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
ok "完成！"
Write-Host ""
Write-Host "  来源:     $DOWNLOAD_URL" -ForegroundColor White
Write-Host "  版本:     $RELEASE_TAG" -ForegroundColor White
if ($actualSha256) { Write-Host "  SHA256:   $($actualSha256.Substring(0,16))…" -ForegroundColor White }
Write-Host "  配置:     $CONFIG_DIR" -ForegroundColor White
Write-Host "  Key 文件: $KEYS_FILE (仅本机可见)" -ForegroundColor Yellow
Write-Host "  运行:     opencode （重开 PowerShell 后生效）" -ForegroundColor White
Write-Host ""
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
