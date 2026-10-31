# Remote-WSL 扩展实现分析（内部备忘）

研究 `ms-vscode-remote.remote-wsl` 的内部实现，目的是判断"Windows 宿主 + WSL 内执行"能不能接进我们自己的发行版，以及需要补哪些基础设施。

- 分析对象：Marketplace 上的 `remote-wsl` **v1.104.7**（`engines.vscode: ^1.104.0`，`extensionKind: ["ui"]`，68 个文件）
- 取得方式：`https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-vscode-remote/vsextensions/remote-wsl/latest/vspackage`（返回 gzip，解压后是 VSIX/zip）
- 方法：静态结构重建（REA `analyze-javascript-application`，Evidence `ev_609a0eb988695343…`：192 条目内 35 个相关文件、4 个 JS、336,456 AST 节点、349 findings、`parse_failures: 0`；同时保留 24 条 unknowns、21 条 limitations，例如别名展开上限 512、语义图 47,601 个未解析项）

> **证据边界**：以下全部来自**静态代码与随包脚本**，不包含运行时观察。版本号指的是扩展自身版本，与宿主 VS Code 版本无关。
>
> **许可证**：该扩展按微软产品条款分发（`LICENSE.txt`，仅授权在微软产品内使用）。本备忘用于互操作性研究；**不得把其代码或脚本复制进我们的发行版**，需要重写。

## 一、激活与探测

| 项 | 值 |
|---|---|
| `activationEvents` | `onResolveRemoteAuthority:wsl`、`onStartupFinished`、`onCommand:remote-wsl.newWindow*` |
| `extensionKind` | `ui`（纯客户端，服务端在发行版内运行） |
| 命令 | `remote-wsl.connect` / `connectUsingDistro` / `openFolder` / `reopenInWSL` / `reopenInWindows` / `explorer.*`（24 个） |

探测手段（`dist/node/extension.js`）：

- 发行版列表：`wsl.exe --list --verbose`、`wslconfig.exe /list`，解析后建模为 `{ name, version(1|2), default }`；
- WSL 特性是否安装：检查 `System32\lxss\LxssManager.dll`（或 `Sysnative`，进程为 32 位时）；
- 安装发行版：`wsl.exe --install -d <distro>`；
- 网络模式：发行版内 `/usr/bin/wslinfo --networking-mode`（NAT / mirrored）；
- 可执行文件选择：Win10 ≥ 16299 用 `wsl.exe`，否则回退 `bash.exe`；`WSL_UTF8=1` 让输出按 UTF-8 解析。

## 二、远端命令的统一形态

```js
function w(distro, cmd, useDefaultShell) {
  let a = [];
  if (newWsl) { a.push("-d", distro); useDefaultShell !== true && a.push("-e"); a.push("sh", "-c", cmd); }
  else if (midWsl) { a.push("sh", "-c", cmd); }
  else { a.push("-c", cmd); }
  return a;
}
// 最终：fs.exec({ cmd: "wsl.exe", args: w(...), env, cwd, options })
```

所有远端动作（探测、下载、启动 server、清理）都是这条命令的一个实例，环境变量通过 `env` 逐条传入，没有常驻连接——常驻部分见第四节的 daemon。

## 三、服务端从哪来

服务端不是随扩展分发的，而是**按 commit 从更新服务器取整包**。下面是脚本视角的两条路径，但要注意 **1.104.7 里脚本已不是主路径**：`dist/node/extension.js` 对 `wslServer.sh` / `wslCode.sh` / `wslDownload.sh` 的引用为 0，主流程改成了「在发行版里放 `bin-cli/<commit>/code-cli`，再用 `spawnCli` + exec-server 协议驱动它」，脚本只在 `dist/node/wslDaemon.js` 里还有残留引用。手工预置的做法见 `docs/manual-remote-wsl.md`。

### 3.1 传统路径（脚本，1.104.7 已非主路径）

`scripts/wslCode.sh`（`code .` 入口）、`scripts/wslServer.sh`（起 server）、`scripts/wslDownload.sh`（下载安装）。

```sh
# scripts/wslDownload.sh
PLATFORM=x64|arm64   # uname -m
[ -f /etc/alpine-release ] && INSTALL="server-linux-alpine" || INSTALL="server-linux-$PLATFORM"
local_url="https://update.code.visualstudio.com/commit:$COMMIT/$INSTALL/$QUALITY"

# 安装位置与校验
VSCODE_REMOTE_BIN="$HOME/$DATAFOLDER/bin"       # 默认 $HOME/.vscode-remote/bin
[ -d "$VSCODE_REMOTE_BIN/$COMMIT" ] || 下载解包
tar -xf "$SERVER_TAR_FILE" -C "$TMP_EXTRACT_FOLDER" --strip-components 1
mv "$TMP_EXTRACT_FOLDER" "$VSCODE_REMOTE_BIN/$COMMIT"    # 重试 5 次（WSL 文件系统抖动）
"$VSCODE_REMOTE_BIN/$COMMIT/bin/helpers/check-requirements.sh"   # 退出码 99 = OS 不兼容
```

`wslCode.sh` 的关键不是下载，而是**把 Windows 侧 exe 交给 WSL 里的 CLI**：

```sh
VSCODE_CLIENT_COMMAND="$WIN_CODE_CMD"        # Windows 上 picket-code.exe 的 wsl 路径
VSCODE_CLIENT_COMMAND_CWD="$(dirname "$0")"
VSCODE_CLI_AUTHORITY="wsl+$WSL_DISTRO_NAME"   # 无 WSL_DISTRO_NAME 时为 wsl+default
VSCODE_CLI_REMOTE_ENV="$STORED_ENV"           # env --null 存下的发行版环境
WSLENV="VSCODE_CLI_REMOTE_ENV/w:$WSLENV"
"$VSCODE_REMOTE_BIN/$COMMIT/bin/remote-cli/$APP_NAME" "$@"
```

`wslServer.sh` 起服务前会先 source `~/$DATAFOLDER/server-env-setup`（若存在），相当于"登录环境注入点"。

### 3.2 Scriptless 路径（默认关闭）

设置 `remote.WSL.experimental.scriptLessStartup`（默认 `false`）切到新实现：

- **Windows 侧下载**：`https` 直连拿 tarball，落盘 `%USERPROFILE%\vscode-remote-wsl\vscode-server-<commit>-<platform>.tar.gz`，校验 checksum 与长度（错误文案 `Download checksum does not match.` / `Download length does not match.`），旧的下载目录会被清理；后台预下载由 `remote.WSL.downloadInBackground` 控制，状态存在全局 `wsl.latestDownloadedCommit` / `wsl.downloadInProgress` / `wsl.lastUpdateCheck` / `wsl.usageTime.<platform>`；
- **发行版侧 daemon**：`dist/node/wslDaemon.js`（Node 进程，经 `wsl.exe` 启动），与扩展通过命名管道通信：

```
\\.\pipe\vscode-wsl-<sha256(commit + quality + distro + Windows 用户名)>
请求/通知：downloadRequest、makeDefault、portResolvedNotification、fatalErrorOccuredNotification
环境：VSCODE_WSL_PIPE_NAME、VSCODE_WSL_EXT_HOST_PID、VSCODE_WSL_EXT_LOCATION
```

## 四、连上之后：端口 + token + exec server

- server 在发行版内监听本地 TCP 端口，扩展用 `probe(port, connectionToken, 2s)` 探活；`revalidate()` 发现不通就重新 `resolveAuthority`（日志：`Server on port N is no longer reachable, resolving again.`），重试间隔由 `remote.WSL.serverProbeRetryTimeout`（默认 60 s）控制；
- 客户端与 server 之间走 exec/proxy 协议：

```js
new ExecServer(stream).serve({
  socket_id, extensions, quality: product.quality,
  commit_id: product.commit, archive_path,
  connection_token, compress
})
```

  另有 `vscode-server-proxy-<sha256>-daemon` 的 bearer 通道，方法名 `calltunnel`。

## 五、决定可用性的那三行代码

下载 URL 的构造与短路：

```js
function LU(updateUrl, commit, platform, quality) {
  return `${updateUrl}/commit:${commit}/server-${platform}/${quality || "insider"}`;
}
const PLATFORMS = ["linux-x64", "linux-alpine", "linux-arm64", "alpine-arm64"];

function EP(..., { updateUrl, quality, commit }, ...) {
  if (!commit || !quality || !updateUrl) {
    return { start() {}, stop() {}, onPlatformUsed() {}, async getOrDownloadBuild() { return ""; } };
  }
  return OU(commit, updateUrl, quality, ...);
}
```

三个输入全部取自**客户端自己的 `product.json`**。装好的 1.143.1 里实际是：

```
commit    = e646868227c3e3a9e3f24277c8c7220be42c0be7   （上游真实 commit）
updateUrl = null
quality   = "stable"
```

因此：**这个扩展在我们的发行版上不会尝试任何下载**，`EP()` 直接返回空实现的下载器，解析阶段就失败。

早先这里有两处判断需要更正：

- `commit` 并不是 null，它就是上游 1.143.1 的 commit。微软 CDN 上这个 commit 的 `server-linux-x64`（222 MB）与 `cli-linux-x64`（13 MB）**都存在**，实测可下载，所以「填了也只会 404」不成立。
- 因此第六节 ②「自建 reh server」不是必需项，可以改为把 `updateUrl` 指向微软更新服务器、再按 `docs/manual-remote-wsl.md` 预置产物。代价是 `updateUrl` 同时是自更新入口，指过去必须配 `"update.mode": "none"`，否则应用会去拉一份正版 VS Code 覆盖自己。

另记一条与本节无关、但同样卡住侧载的事实：发行版早先把产品版本打成 `1.143.1+p4`，而上游 `extensionValidator.ts` 的版本正则不接受 `+build`（`/^(\^|>=)?((\d+)|x)\.((\d+)|x)\.((\d+)|x)(\-.*)?$/`），导致**任何**带 `main` 的扩展（含侧载 `.vsix`）都被判为不兼容。该版本戳已从 `build/build.sh` 移除。

（"侧载官方 VSIX 在 Codium 类产品上跑不起来"要分两层：**装不上**一般另有原因，例如本发行版早先的 `+p4` 版本戳（见上）；**装了起不来**才是这里说的服务端获取，不是签名或许可证。）

## 六、要接进我们的发行版，缺三块（都是开源部分）

| # | 缺口 | 说明 |
|---|---|---|
| ① | **reh server 产物** | 上游 `build/gulpfile.reh.ts` 的 `vscode-reh-linux-x64`；与现有 Linux 桌面包同源，加一条构建线 |
| ② | **托管下载路径** | `<updateUrl>/commit:<our-commit>/server-linux-x64/stable`，tar.gz 需能 `--strip-components 1` 解开；现成的 R2 + `download.noware.cn` 可用 |
| ③ | **客户端解析器** | `wsl.exe` 探测、管道/daemon、端口与 token、进程生命周期。参考 `jeanp413/open-remote-wsl`（v0.0.5，2025-04 后未更新）；自写则可控性更好 |

`product.json` 里的 `commit` 与 `updateUrl` 本身也是自更新、web server、tunnels 的前提，所以 ①② 属于"自有发行版应有的基础设施"，不是为 WSL 单独加的。

## 七、顺带得到的两个答案

1. **9p 上文件监听的官方开关**：扩展贡献了 `remote.WSL.fileWatcher.polling`（默认 `false`）与 `pollingInterval`（默认 5000）。Windows 侧直接打开 `\\wsl.localhost\...` 时 watcher 全面失效（见 `guide` 里的说明），这两个设置在远程模式下由扩展自动接管，不适用于本地打开 UNC 路径的场景。
2. **环境注入点**：`~/.vscode-remote/server-env-setup`（被 `wslServer.sh` source）与 `remote.WSL.useShellEnvironment`（默认 `true`）共同决定远端 server 看到的环境变量；我们的补丁若要在远端生效，应把配置放在 `product.json` 与 `.vscode-remote` 这两层，而不是依赖发行版 profile。

## 八、复现步骤

```bash
mkdir -p /tmp/rea-wsl && cd /tmp/rea-wsl
curl -sSL -A "VSCode" -o remote-wsl.vsix \
  'https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-vscode-remote/vsextensions/remote-wsl/latest/vspackage'
gunzip -c remote-wsl.vsix > remote-wsl.zip && unzip -qo remote-wsl.zip -d ext

npx -y rea-agents@6.8.0 analyze-javascript-application /tmp/rea-wsl/ext/extension \
  --detail summary --evidence_output /tmp/rea-wsl/evidence --format json
```

重点文件：`ext/extension/package.json`（贡献点与设置）、`dist/node/extension.js`（解析器、URL 构造、ExecServer）、`dist/node/wslDaemon.js`（管道 daemon）、`scripts/wsl{Code,Server,Download}.sh`（传统路径全流程）。

## 九、手工安装与预置

`.vsix` 离线安装、以及把 CLI + Server 预置进发行版以绕开下载的完整流程，见 `docs/manual-remote-wsl.md`（脚本：`build/manual-wsl-server.sh`）。

该文档第九节记了许可边界：这两步在**个人开发机上自用**属于超出微软许可授权范围但无分发的灰色地带；**随发行版分发或提供镜像下载是明确禁止的**。要产品化，只能换成 MIT 的客户端实现 + 自建 reh server（即第六节的 ①②③）。
