# Picket Code 一键下载安装命令

单条命令完成全部流程：**下载分卷段 → 合并 → SHA256 校验 → 解压**。无需下载脚本文件，直接复制运行。

> 当前默认版本：**v1.143.1-p2**。换版本时按文末【换版本】修改 `T` 与校验值 `e`。
> Windows 命令外层用**单引号**包裹，避免在 PowerShell 窗口粘贴时被当前会话做变量插值。

---

## Windows（PowerShell / cmd 通用单行）

直接粘贴运行，在**当前目录**完成下载、合并、校验、解压：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command '$t="v1.143.1-p2";$b="picket-code-win32-x64.zip";$u="https://gitee.com/dsun/picket-code/releases/download/"+$t;$alt="https://github.com/dantesun/picket-code/releases/download/"+$t;$n=0;$wc=New-Object System.Net.WebClient;while($true){$s="{0:D2}"-f $n;$f=$b+"."+$s+".part";$ok=$false;try{$wc.DownloadFile(($u+"/"+$f),(Join-Path $PWD $f));$ok=$true}catch{try{$wc.DownloadFile(($alt+"/"+$f),(Join-Path $PWD $f));$ok=$true}catch{}};if(-not $ok){if($n -eq 0){throw "download failed"};break};$n++};if($n -eq 0){throw "no segments"};$segs=Get-ChildItem ($b+".*.part")|Sort-Object Name;$o=(Join-Path $PWD $b);[IO.File]::WriteAllBytes($o,[IO.File]::ReadAllBytes($segs[0].FullName));if($segs.Count -gt 1){$segs[1..($segs.Count-1)]|%{[IO.File]::AppendAllBytes($o,[IO.File]::ReadAllBytes($_.FullName))}};$h=(Get-FileHash -Algorithm SHA256 $o).Hash.ToLower();$e="52c959632597f15125b2c96e99b4a45b0b03d227b1a8f5cd609580fba7c4bac0";if($h -ne $e){Write-Host ("SHA256 MISMATCH: "+$h);exit 1};Write-Host ("OK: "+$o);Expand-Archive -Force -Path $o -DestinationPath $PWD;Write-Host ("Extracted to: "+$PWD)'
```

完成后程序位置：`<当前目录>\picket-code-win32-x64\Picket Code.exe`

---

## Linux / macOS（bash 单行）

```bash
T=v1.143.1-p2; B=picket-code-linux-x64.tar.gz; U=https://gitee.com/dsun/picket-code/releases/download/$T; n=0; while :; do s=$(printf "%02d" $n); f=$B.$s.part; if ! curl -fsSL --retry 3 -o "$f" "$U/$f" 2>/dev/null; then [ $n -eq 0 ] && { echo "download failed"; exit 1; }; rm -f "$f"; break; fi; n=$((n+1)); done; cat $B.??.part > $B; h=$(sha256sum $B|cut -d" " -f1); e=b4a4d7a564fba131d6da6025e74b3fdbf6410114cb480763960075bed9bde5c6; [ "$h" != "$e" ] && { echo "SHA256 MISMATCH: $h"; exit 1; }; echo "OK: $B"; mkdir -p picket-code && tar -xzf $B -C picket-code && echo "Extracted: picket-code/picket-code-linux-x64/bin/picket-code"
```

完成后程序位置：`picket-code/picket-code-linux-x64/bin/picket-code`

---

## 换版本

1. 修改版本号（Windows：`$t=` 后；Linux：`T=` 后）
2. 修改校验值 `e` 为新版本的合并后 SHA256（见该版本 Release 描述【合并后校验值】）
3. 平台与架构不变则文件名变量（`$b` / `B`）不用改

## 校验值参考（v1.143.1-p2）

| 平台 | 合并后 SHA256 |
|------|---------------|
| win32 zip | 52c959632597f15125b2c96e99b4a45b0b03d227b1a8f5cd609580fba7c4bac0 |
| linux tar.gz | b4a4d7a564fba131d6da6025e74b3fdbf6410114cb480763960075bed9bde5c6 |
