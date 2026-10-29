<#
.SYNOPSIS
  Picket Code 下载 + SHA256 校验（Windows PowerShell 版）
.DESCRIPTION
  从 GitHub Release 下载当前平台的发行包，并与同一 Release 的 SHA256SUMS 比对。
  支持：显式进度（百分比）、失败重试 5 次、断点续传。
  代理策略：WebRequest 自动使用系统代理 + 当前 Windows 用户凭据（解决企业代理 407）；
  curl 作为直连环境的兜底（-C - 续传）。
.EXAMPLE
  .\download-verify.ps1
  .\download-verify.ps1 -Tag v1.143.1-p2
  .\download-verify.ps1 -Tag v1.143.1-p2 -OutDir D:\Downloads
  .\download-verify.ps1 -ProxyCredential (Get-Credential)
.NOTES
  不带 -Tag 时自动使用 GitHub 上最新的 release；产物名为
  picket-code-<tag>-<os>-<arch>.<ext>，校验和文件为 picket-code-<tag>-SHA256SUMS。
  本文件必须保存为 UTF-8 with BOM：Windows PowerShell 5.1 对无 BOM 的脚本按系统 ANSI
  代码页解析，中文字符会破坏字符串字面量并直接报语法错误。
#>
param(
  [string]$Tag = "",
  [string]$Repo = "dantesun/picket-code",
  [string]$OutDir = (Get-Location).Path,
  [pscredential]$ProxyCredential
)
$ErrorActionPreference = "Stop"

# 检测平台与架构（兼容 Windows PowerShell 5.1）
$win = $env:OS -eq "Windows_NT"
$os = if ($win) { "win32" } elseif ($IsLinux) { "linux" } elseif ($IsMacOS) { "darwin" } else { "linux" }
$mach = if ($win) { $env:PROCESSOR_ARCHITECTURE } elseif ($IsLinux -or $IsMacOS) { (uname -m) } else { "x86_64" }
$arch = if ($mach -match "ARM|aarch64") { "arm64" } else { "x64" }
$ext = if ($os -eq "win32") { "zip" } else { "tar.gz" }

# 不带 -Tag 时取最新 release；仓库 API 不可达时要求显式传入。
if (-not $Tag) {
  try {
    $Tag = (Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "picket-code-downloader" }).tag_name
  } catch {
    throw "无法确定最新版本，请显式传入 -Tag，例如: .\download-verify.ps1 -Tag v1.143.1-p2"
  }
}
if (-not $Tag) { throw "无法确定最新版本，请显式传入 -Tag" }

$base = "picket-code-$Tag-$os-$arch.$ext"
$sums = "picket-code-$Tag-SHA256SUMS"

$prefix = "https://github.com/$Repo/releases/download/$Tag"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# 代理凭据：显式传入优先，否则用当前 Windows 用户（DefaultCredentials）
$proxyCred = if ($ProxyCredential) { $ProxyCredential.GetNetworkCredential() } else { [System.Net.CredentialCache]::DefaultCredentials }

# 下载单文件：WebRequest（系统代理 + 凭据 + 续传 + 百分比进度）优先；curl 直连兜底
function Download-Resume {
  param([string]$Url, [string]$Path)
  for ($try = 1; $try -le 5; $try++) {
    # 1) WebRequest：企业代理环境主路径
    try {
      $req = [System.Net.HttpWebRequest]::Create($Url)
      $req.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
      $req.Proxy.Credentials = $proxyCred
      $req.UserAgent = "picket-code-downloader"
      $len = if (Test-Path $Path) { (Get-Item $Path).Length } else { 0 }
      $mode = "Create"
      if ($len -gt 0) { try { $req.AddRange([long]$len); $mode = "Append" } catch { $len = 0 } }
      $resp = $req.GetResponse()
      if ($resp.StatusCode -ne [System.Net.HttpStatusCode]::PartialContent -and $len -gt 0) {
        $len = 0; $mode = "Create"   # 服务器忽略 Range（返回 200）：从头覆盖
      }
      $total = if ($resp.ContentLength -gt 0) { $resp.ContentLength } else { 0 }
      $totalMB = [math]::Round(($total + $len) / 1MB, 1)
      $fs = if ($mode -eq "Append") { [System.IO.File]::Open($Path, [System.IO.FileMode]::Append) } else { [System.IO.File]::Create($Path) }
      $stream = $resp.GetResponseStream()
      $buf = New-Object byte[] 262144
      $done = $len
      while (($read = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
        $fs.Write($buf, 0, $read)
        $done += $read
        $doneMB = [math]::Round($done / 1MB, 1)
        if ($total -gt 0) {
          $pct = [math]::Round($done * 100 / ($total + $len), 1)
          [Console]::Write("`r  进度: $doneMB / $totalMB MB ($pct%)   ")
        } else {
          [Console]::Write("`r  已下载: $doneMB MB   ")
        }
      }
      [Console]::WriteLine("")
      $fs.Close(); $stream.Close(); $resp.Close()
      return $true
    } catch {
      Write-Host "  WebRequest 失败: $($_.Exception.Message)"
    }
    # 2) curl：直连（无代理环境）兜底，-C - 续传 + 进度条
    $existing = if (Test-Path $Path) { (Get-Item $Path).Length } else { 0 }
    if ($existing -gt 0) { Write-Host "  已有 $([math]::Round($existing/1MB,1)) MB，断点续传..." }
    & curl.exe -fL -C - --retry 3 --retry-delay 2 --progress-bar -o $Path $Url
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($try -lt 5) { Write-Host "  第 $try 次失败，2 秒后重试..."; Start-Sleep -Seconds 2 }
  }
  return $false
}

# 下载小文件（SHA256SUMS）：curl 优先，失败改用走系统代理的 WebClient
function Get-RemoteFile {
  param([string]$Url, [string]$Path)
  # PS 5.1 会把原生命令的 stderr（含 curl 进度条）在 $ErrorActionPreference='Stop' 下
  # 变成 NativeCommandError，因此这里改用 -s 静音并把偏好降级为本函数局部。
  $ErrorActionPreference = "Continue"
  & curl.exe -fsSL --retry 3 -o $Path $Url
  if ($LASTEXITCODE -eq 0) { return $true }
  try {
    $wc = New-Object System.Net.WebClient
    $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $wc.Proxy.Credentials = $proxyCred
    $wc.DownloadFile($Url, $Path)
    return $true
  } catch {
    return $false
  }
}

$target = Join-Path $OutDir $base
Write-Host "== 下载 $base (Tag: $Tag) =="
if (-not (Download-Resume -Url "$prefix/$base" -Path $target)) { throw "下载失败: $prefix/$base" }

Write-Host "== 校验 SHA256 =="
$hash = (Get-FileHash -Algorithm SHA256 $target).Hash.ToLower()
$sumsPath = Join-Path $OutDir $sums
$expected = $null
if (Get-RemoteFile -Url "$prefix/$sums" -Path $sumsPath) {
  foreach ($line in Get-Content $sumsPath -Encoding UTF8) {
    if ($line -match "^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$" -and $Matches[2] -eq $base) { $expected = $Matches[1].ToLower() }
  }
}

if (-not $expected) {
  Write-Host "警告: SHA256SUMS 中没有 $base，请与该 Release 的说明手工比对" -ForegroundColor Yellow
  Write-Host "SHA256: $hash"
  Write-Host "完成。解压 $target 后即可使用。"
  exit 0
}

if ($hash -eq $expected) {
  Write-Host "校验通过: $base" -ForegroundColor Green
  Write-Host "SHA256: $hash"
  Write-Host "完成。解压 $target 后即可使用。"
} else {
  Write-Host "校验失败!" -ForegroundColor Red
  Write-Host "实际: $hash"
  Write-Host "预期: $expected"
  exit 1
}
