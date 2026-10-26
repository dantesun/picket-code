<#
.SYNOPSIS
  Picket Code 自动下载 + 合并 + SHA256 校验（Windows PowerShell 版）
.DESCRIPTION
  从 Gitee/GitHub Release 自动下载全部分卷段，合并还原原始包，并与
  release 描述中的【合并后校验值】比对。
.EXAMPLE
  .\download-verify.ps1
  .\download-verify.ps1 -Tag v1.143.1-p1 -Source github
  .\download-verify.ps1 -OutDir D:\Downloads
#>
param(
  [string]$Tag = "v1.143.1-p1",
  [string]$Repo = "dsun/picket-code",
  [ValidateSet("gitee","github")][string]$Source = "gitee",
  [string]$OutDir = (Get-Location).Path
)
$ErrorActionPreference = "Stop"

# 检测平台与架构（兼容 Windows PowerShell 5.1：无 $IsWindows 自动变量）
$win = $env:OS -eq "Windows_NT"
$os = if ($win) { "win32" } elseif ($IsLinux) { "linux" } elseif ($IsMacOS) { "darwin" } else { "linux" }
$mach = if ($win) { $env:PROCESSOR_ARCHITECTURE } elseif ($IsLinux -or $IsMacOS) { (uname -m) } else { "x86_64" }
$arch = if ($mach -match "ARM|aarch64") { "arm64" } else { "x64" }
$ext = if ($os -eq "win32") { "zip" } else { "tar.gz" }
$base = "picket-code-$os-$arch.$ext"

$hostName = if ($Source -eq "github") { "github.com/dantesun/picket-code" } else { "gitee.com/$Repo" }
$prefix = "https://$hostName/releases/download/$Tag"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

Write-Host "== 下载 $base (源: $Source) =="
$segments = @()
$i = 0
while ($true) {
  $segName = "{0}.{1:D2}.part" -f $base, $i
  $segPath = Join-Path $OutDir $segName
  $url = "$prefix/$segName"
  Write-Host "  段 $segName ..."
  & curl.exe -fsSL --retry 3 -o $segPath $url 2>$null
  if ($LASTEXITCODE -ne 0) {
    if ($i -eq 0) { throw "第一段下载失败: $url" }
    Remove-Item $segPath -ErrorAction SilentlyContinue
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
& curl.exe -fsSL --retry 3 -o $mergePath "$prefix/MERGE.txt" 2>$null
if ($LASTEXITCODE -ne 0) { throw "下载 MERGE.txt 失败" }
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
