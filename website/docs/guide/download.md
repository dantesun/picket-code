# 下载与安装

> 当前默认版本：**v1.143.1**。发行包只发布在 GitHub Releases；Gitee 仓库只镜像源码，不承载 Release 附件。

## 平台支持

| 平台 | 架构 | 格式 | 状态 |
|---|---|---|---|
| Linux | x64 | `tar.gz` | 当前发行 |
| Windows | x64 | `zip` | 当前发行 |
| macOS | - | - | P0 验证闭环后规划 |
| ARM64 | - | - | P0 验证闭环后规划 |

## 方式一：直接从 Releases 下载

前往 [GitHub Releases](https://github.com/dantesun/picket-code/releases)，下载对应平台的压缩包：

- `picket-code-linux-x64-v1.143.1.tar.gz`
- `picket-code-win32-x64-v1.143.1.zip`

每个 Release 附带 `SHA256SUMS` 校验文件。

## 方式二：一键下载安装命令

一条命令完成全部流程：**拉取最新下载脚本 → 下载发行包（显式进度 / 失败重试 / 断点续传）→ SHA256 校验 → 解压**。

### Windows（PowerShell 单行，自动走系统代理）

::: code-group

```powershell [PowerShell]
powershell -NoProfile -ExecutionPolicy Bypass -Command '$f=(Join-Path $PWD "download-verify.ps1");$wc=New-Object System.Net.WebClient;$u1="https://raw.githubusercontent.com/dantesun/picket-code/main/build/download-verify.ps1";$u2="https://gitee.com/dsun/picket-code/raw/main/build/download-verify.ps1";try{$wc.DownloadFile($u1,$f)}catch{$wc.DownloadFile($u2,$f)};& $f -Tag v1.143.1'
```

```cmd [CMD]
powershell -NoProfile -ExecutionPolicy Bypass -File .\download-verify.bat -Tag v1.143.1
```

:::

- 脚本优先从 GitHub raw 拉取，失败改用 Gitee 镜像 raw（Gitee 只镜像源码，脚本可用、附件不在那里）。
- WebClient 自动使用系统代理 + 当前 Windows 用户凭据，企业网络可直接下载。
- 若代理要求单独账号密码：`powershell -NoProfile -ExecutionPolicy Bypass -File .\download-verify.ps1 -Tag v1.143.1 -ProxyCredential (Get-Credential)`
- 完成后程序位置：`<当前目录>\picket-code-win32-x64\Picket Code.exe`

### Linux（bash 单行）

::: code-group

```bash [GitHub]
curl -fSL "https://raw.githubusercontent.com/dantesun/picket-code/main/build/download-verify.sh" -o dv.sh && bash dv.sh v1.143.1
```

```bash [Gitee 镜像]
curl -fSL "https://gitee.com/dsun/picket-code/raw/main/build/download-verify.sh" -o dv.sh && bash dv.sh v1.143.1
```

:::

完成后程序位置：解压后目录下的 `bin/picket-code`。

### 脚本参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `Tag` | v1.143.1 | 版本号，如 `v1.143.1` |

## 校验机制

SHA256 不写死在脚本中（每次发版都会变）：脚本会自动下载该版本 Release 的 `SHA256SUMS` 并逐包比对；手工核对时同样以 `SHA256SUMS`（或 Release 说明）为准。

## 方式三：让 AI 助手自动安装

复制 [docs/ai-download-prompt.md](https://github.com/dantesun/picket-code/blob/main/docs/ai-download-prompt.md) 中的任务全文发给任意 AI 助手（豆包、Claude、Codex 等），AI 将自动完成下载、校验与安装，并报告发行包 SHA256、校验结果与安装路径。

## 常见问题

**Q：下载 GitHub 附件慢怎么办？**
脚本会自动回退到 Gitee 源码镜像拉取脚本；发行包附件本身只存在 GitHub Releases，可使用支持断点续传的下载工具，或配置代理。

**Q：如何换版本？**
修改命令 / 脚本中的版本号（`-Tag` / 第一个参数）即可，校验值自动从该版本 Release 的 `SHA256SUMS` 读取，无需手工修改。
