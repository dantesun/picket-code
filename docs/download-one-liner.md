# Picket Code 一键下载安装命令

一条命令完成全部流程：**拉取最新下载脚本 → 下载发行包（显式进度/失败重试/断点续传）→ SHA256 校验 → 解压**。

> 当前默认版本：**v1.143.1-p1**。
> 发行包只发布在 GitHub Releases；Gitee 仓库只镜像源码（含本脚本），不承载 Release 附件。
> 脚本自带：显式进度（curl 进度条 / 百分比）、失败自动重试 5 次、断点续传（服务器支持 Range 时）。

---

## Windows（PowerShell 单行，自动走系统代理）

在目标目录（如 `D:\Downloads`）直接粘贴运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command '$f=(Join-Path $PWD "download-verify.ps1");$wc=New-Object System.Net.WebClient;$u1="https://raw.githubusercontent.com/dantesun/picket-code/main/build/download-verify.ps1";$u2="https://gitee.com/dsun/picket-code/raw/main/build/download-verify.ps1";try{$wc.DownloadFile($u1,$f)}catch{$wc.DownloadFile($u2,$f)};& $f -Tag v1.143.1-p1'
```

- 脚本优先从 GitHub raw 拉取，失败改用 Gitee 镜像 raw（Gitee 只镜像源码，脚本可用、附件不在那里）。
- WebClient 自动使用系统代理 + 当前 Windows 用户凭据，企业网络可直接下载（已解决 407 代理认证）。
- 若代理要求单独账号密码：`powershell -NoProfile -ExecutionPolicy Bypass -File .\download-verify.ps1 -Tag v1.143.1-p1 -ProxyCredential (Get-Credential)`
- 完成后程序位置：`<当前目录>\picket-code-win32-x64\Picket Code.exe`

**已下载过脚本、只想重新运行**：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\download-verify.ps1 -Tag v1.143.1-p1
```

---

## Linux / macOS（bash 单行）

```bash
curl -fSL "https://raw.githubusercontent.com/dantesun/picket-code/main/build/download-verify.sh" -o dv.sh && bash dv.sh v1.143.1-p1
```

访问 GitHub 慢时从 Gitee 镜像拉脚本（只镜像源码）：

```bash
curl -fSL "https://gitee.com/dsun/picket-code/raw/main/build/download-verify.sh" -o dv.sh && bash dv.sh v1.143.1-p1
```

完成后程序位置：解压后目录下的 `bin/picket-code`。

---

## 脚本参数

| 参数 | 默认 | 说明 |
|------|------|------|
| Tag | v1.143.1-p1 | 版本号，如 `v1.143.1-p1` |

示例：`bash dv.sh v1.143.1-p1`

---

## 换版本

1. 修改命令/脚本中的版本号（`-Tag` / 第一个参数）
2. 校验值自动从该版本 Release 的 `SHA256SUMS` 读取，无需手工改

## 校验值

SHA256 不写死在本文件（每次发版都会变，写死只会过期）：
脚本会下载该版本 Release 的 `SHA256SUMS` 并自动比对；手工核对时同样以 `SHA256SUMS`
（或 Release 说明）为准。
