# Picket Code 一键下载安装命令

一条命令完成全部流程：**拉取最新下载脚本 → 下载分卷段（显式进度/失败重试/断点续传）→ 合并 → SHA256 校验 → 解压**。

> 当前默认版本：**v1.143.1-p2**。
> 脚本自带：显式进度（curl 进度条 / 百分比）、失败自动重试 5 次、断点续传（服务器支持 Range 时）。
> Gitee release 附件不支持 Range，脚本会自动探测并降级为全量下载（不会报错中断）。

---

## Windows（PowerShell 单行，自动走系统代理）

在目标目录（如 `D:\Downloads`）直接粘贴运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command '$f=(Join-Path $PWD "download-verify.ps1");$wc=New-Object System.Net.WebClient;$u1="https://raw.githubusercontent.com/dantesun/picket-code/main/build/download-verify.ps1";$u2="https://gitee.com/dsun/picket-code/raw/main/build/download-verify.ps1";try{$wc.DownloadFile($u1,$f)}catch{$wc.DownloadFile($u2,$f)};& $f -Tag v1.143.1-p2'
```

- 脚本优先从 GitHub raw 拉取（避免 Gitee CDN 缓存旧版），失败自动改用 Gitee raw。
- WebClient 自动使用系统代理 + 当前 Windows 用户凭据，企业网络可直接下载（已解决 407 代理认证）。
- 若代理要求单独账号密码：`powershell -NoProfile -ExecutionPolicy Bypass -File .\download-verify.ps1 -Tag v1.143.1-p2 -ProxyCredential (Get-Credential)`
- 完成后程序位置：`<当前目录>\picket-code-win32-x64\Picket Code.exe`

**已下载过脚本、只想重新运行**：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\download-verify.ps1 -Tag v1.143.1-p2
```

---

## Linux / macOS（bash 单行）

```bash
curl -fSL "https://raw.githubusercontent.com/dantesun/picket-code/main/build/download-verify.sh" -o dv.sh && bash dv.sh v1.143.1-p2
```

国内访问 GitHub 慢时改用 Gitee 源拉脚本：

```bash
curl -fSL "https://gitee.com/dsun/picket-code/raw/main/build/download-verify.sh" -o dv.sh && bash dv.sh v1.143.1-p2
```

完成后程序位置：解压后目录下的 `bin/picket-code`。

---

## 脚本参数

| 参数 | 默认 | 说明 |
|------|------|------|
| Tag | v1.143.1-p2 | 版本号，如 `v1.143.1-p3` |
| Source | gitee | `gitee` 或 `github`（GitHub 源支持断点续传） |

示例：`bash dv.sh v1.143.1-p2 github`

---

## 换版本

1. 修改命令/脚本中的版本号（`-Tag` / 第一个参数）
2. 校验值自动从该版本 Release 的 MERGE.txt 读取，无需手工改

## 校验值参考（v1.143.1-p2）

| 平台 | 合并后 SHA256 |
|------|---------------|
| win32 zip | 52c959632597f15125b2c96e99b4a45b0b03d227b1a8f5cd609580fba7c4bac0 |
| linux tar.gz | b4a4d7a564fba131d6da6025e74b3fdbf6410114cb480763960075bed9bde5c6 |
