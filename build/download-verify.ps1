<#
.SYNOPSIS
  Picket Code 自动下载 + 合并 + SHA256 校验（Windows PowerShell 版）
.DESCRIPTION
  从 Gitee/GitHub Release 自动下载全部分卷段，合并还原原始包，并与
  release 描述中的【合并后校验值】比对。
  支持：显式进度（百分比）、失败重试 5 次、断点续传。
  代理策略：WebRequest 自动使用系统代理 + 当前 Windows 用户凭据（解决企业代理 407）；
  curl 作为直连环境的兜底（-C - 续传）。
.EXAMPLE
  .\download-verify.ps1
  .\download-verify.ps1 -Tag v1.143.1-p5 -Source github
  .\download-verify.ps1 -Tag v1.143.1-p5 -OutDir D:\Downloads
  .\download-verify.ps1 -ProxyCredential (Get-Credential)
#>
param(
  [string]$Tag = "v1.143.1-p5",
  [string]$Repo = "dsun/picket-code",
  [ValidateSet("gitee","github")][string]$Source = "gitee",
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
$base = "picket-code-$os-$arch.$ext"

$hostName = if ($Source -eq "github") { "github.com/dantesun/picket-code" } else { "gitee.com/$Repo" }
$prefix = "https://$hostName/releases/download/$Tag"
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

Write-Host "== 下载 $base (源: $Source, Tag: $Tag) =="
$segments = @()
$i = 0
while ($true) {
  $segName = "{0}.{1:D2}.part" -f $base, $i
  $segPath = Join-Path $OutDir $segName
  $url = "$prefix/$segName"
  Write-Host "  段 $segName ..."
  $ok = Download-Resume -Url $url -Path $segPath
  if (-not $ok) {
    if ($i -eq 0) { throw "第一段下载失败: $url" }
    break
  }
  $segments += $segPath
  $i++
}
if ($segments.Count -eq 0) { throw "未下载到任何分卷段" }

Write-Host "== 合并 $($segments.Count) 段 =="
$merged = Join-Path $OutDir $base
[System.IO.File]::WriteAllBytes($merged, [System.IO.File]::ReadAllBytes($segments[0]))
foreach ($p in $segments[1..($segments.Count - 1)]) {
  [System.IO.File]::AppendAllBytes($merged, [System.IO.File]::ReadAllBytes($p))
}

Write-Host "== 校验 SHA256 =="
$hash = (Get-FileHash -Algorithm SHA256 $merged).Hash.ToLower()
$mergePath = Join-Path $OutDir "MERGE.txt"
& curl.exe -fSL --retry 3 -o $mergePath "$prefix/MERGE.txt" 2>$null
if ($LASTEXITCODE -ne 0) {
  try {
    $wc = New-Object System.Net.WebClient
    $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $wc.Proxy.Credentials = $proxyCred
    $wc.DownloadFile("$prefix/MERGE.txt", $mergePath)
  } catch { throw "下载 MERGE.txt 失败: $($_.Exception.Message)" }
}
$expected = $null
foreach ($line in Get-Content $mergePath -Encoding UTF8) {
  if ($line -match ("合并后校验值.*" + [regex]::Escape($base) + " = ([0-9a-f]+)")) { $expected = $Matches[1] }
}
if (-not $expected) { throw "MERGE.txt 中未找到 $base 的合并后校验值" }

if ($hash -eq $expected) {
  Write-Host "校验通过: $base" -ForegroundColor Green
  Write-Host "SHA256: $hash"
  Write-Host "完成。解压 $merged 后即可使用。"
} else {
  Write-Host "校验失败!" -ForegroundColor Red
  Write-Host "实际: $hash"
  Write-Host "预期: $expected"
  exit 1
}
