# 手工安装 Remote-WSL 与 VS Code Server

目标是**不依赖任何在线解析**把 `ms-vscode-remote.remote-wsl` 跑起来：`.vsix` 离线安装，服务端产物手工预置。适用于 Picket Code 1.143.1（上游 commit `e646868227c`）＋ Remote-WSL 1.104.7。

两条前置事实决定了流程形状：

1. 发行版上报的版本号必须是**裸 `X.Y.Z`**，否则 `.vsix` 装不上（见第一节）。
2. 1.104.7 已经不用 `scripts/wslDownload.sh` 那套脚本了，主流程是「发行版里放一个 `code-cli`，由它起 server」。扩展的两个探针**只看目录是否存在**，所以把产物预先放好，它就不下载。

## 一、前置：版本号必须是裸 `X.Y.Z`

上游 `src/vs/platform/extensions/common/extensionValidator.ts` 用这个正则解析**产品版本**：

```js
const VERSION_REGEXP = /^(\^|>=)?((\d+)|x)\.((\d+)|x)\.((\d+)|x)(\-.*)?$/;
```

它只允许 `-prerelease`，**没有 `+build` 分支**。实测三种写法的后果：

| 产品版本 | `parseVersion()` | 后果 |
|---|---|---|
| `1.143.1` | 成功 | 正常 |
| `1.143.1+p4` | 返回 null | `isValidVersion()` 恒 false → **所有带 `main` 的扩展**都报 `not compatible with Code 1.143.1+p4` |
| `1.143.1-p4` | 成功 | VS Code 侧能过，但它在 semver 里是 prerelease，画廊侧 `semver.satisfies()` 匹配 `^1.x` 会失败 |

所以 `build/build.sh` 已去掉版本戳，打包产物保持上游原值。构建后自检：

```powershell
& "D:\Downloads\picket-code-win32-x64\Picket Code.exe" --version
# 期望：1.143.1（带 +p 就说明是旧构建，装不了任何扩展）
```

影响面不止安装：`extensionsScannerService` 扫描**已安装**扩展时也走同一个校验，所以带 `+pN` 的构建里，已有扩展同样会被判为不兼容。

## 二、离线安装 Remote-WSL

`extensionKind` 是 `ui`，只能在 Windows 侧装。

```powershell
# CLI 方式
& "D:\Downloads\picket-code-win32-x64\Picket Code.exe" `
  --install-extension "D:\Downloads\ms-vscode-remote.remote-wsl-1.104.7.vsix"

# 或 GUI：扩展面板 → ··· → 从 VSIX 安装…

# 确认
& "D:\Downloads\picket-code-win32-x64\Picket Code.exe" --list-extensions --show-versions |
  Select-String remote-wsl
```

## 三、为什么服务端必须手工备

扩展里的下载器是 `EP()`：

```js
function EP(t, e, r, n, i, o = AU) {
  let { updateUrl: a, quality: u, commit: c } = r;
  if (!c || !u || !a) return { start() {}, stop() {}, async getOrDownloadBuild() { return "" } };
  return OU(c, a, u, t, e, n, i, o);
}
```

三个输入全部来自客户端 `product.json`。发行版当前是 `commit` 有值、`quality: "stable"`、但 **`updateUrl: null`**，于是直接返回空实现的下载器，拿不到 server 就起不来。这与「微软侧没有我们的 commit」无关——`commit` 是上游真实 commit，产物在微软 CDN 上都在（见第六节）。

## 四、用脚本

脚本：`build/manual-wsl-server.sh`。**在目标发行版内部执行**（不是 Windows 侧）；多发行版要各跑一遍，因为它写 `$HOME`。

```bash
# 在线：从 Windows 安装里读 commit / serverDataFolderName / quality
bash build/manual-wsl-server.sh \
  --product-json /mnt/d/Downloads/picket-code-win32-x64/resources/app/product.json

# 离线：两段归档已经在本地
bash build/manual-wsl-server.sh --commit e646868227c3e3a9e3f24277c8c7220be42c0be7 \
  --cli-tar /mnt/d/vscode_cli_linux_x64_cli.tar.gz \
  --server-tar /mnt/d/vscode-server-linux-x64.tar.gz

# 只看看会发生什么
bash build/manual-wsl-server.sh --product-json <...> --dry-run
```

| 参数 | 说明 |
|---|---|
| `--commit <sha>` | 上游 commit，40 位小写十六进制 |
| `--product-json <路径>` | 从 `resources/app/product.json` 读 commit / `serverDataFolderName` / quality |
| `--folder <名>` | 发行版内数据目录，默认 `.picket-code-server` |
| `--arch <平台>` | `linux-x64`（默认按 `uname` 推断）/ `linux-arm64` / `linux-alpine` / `alpine-arm64` |
| `--quality` | `stable`（默认）/ `insider` |
| `--cli-tar` / `--server-tar` | 离线归档，给了就不联网 |
| `--force` / `--dry-run` | 重装 / 只打印 |

脚本行为：下载时用更新服务器 302 响应头里的 `x-sha256` 做校验（不写死哈希）→ 解包 → CLI 的单个 `code` 重命名为 `code-cli` 并 `chmod +x` → server 用 `--strip-components 1` 解开 → 打印最终路径。已存在的部分默认跳过。

## 五、等价的手工命令

不依赖脚本时（在发行版里执行）：

```bash
COMMIT=e646868227c3e3a9e3f24277c8c7220be42c0be7
FOLDER=.picket-code-server
ARCH=linux-x64
BASE="https://update.code.visualstudio.com/commit:$COMMIT"

# CLI：归档里只有一个可执行文件 code，扩展按 code-cli 命名
mkdir -p ~/$FOLDER/bin-cli/$COMMIT
curl -fsSL -o /tmp/cli.tar.gz "$BASE/cli-$ARCH/stable"
tar -xzf /tmp/cli.tar.gz -C ~/$FOLDER/bin-cli/$COMMIT
mv ~/$FOLDER/bin-cli/$COMMIT/code ~/$FOLDER/bin-cli/$COMMIT/code-cli
chmod +x ~/$FOLDER/bin-cli/$COMMIT/code-cli

# Server：归档自带顶层目录，按扩展的 --strip-components 1 解开
mkdir -p ~/$FOLDER/bin/$COMMIT
curl -fsSL -o /tmp/server.tar.gz "$BASE/server-$ARCH/stable"
tar -xzf /tmp/server.tar.gz -C ~/$FOLDER/bin/$COMMIT --strip-components 1
```

这两个路径不是猜的，来自扩展自身的探针：

```js
// extension.js: _probeInstallInWSL
let c = `$HOME/${productConfiguration.serverDataFolderName || ".vscode-remote"}/bin-cli`;
let a = `if [ -d "${c}/${commit}" ]; then printf 'install-found '; fi; ...`
// 命中后直接 spawnCli: wsl.exe -d <distro> <cliExe>，不下载
```

```js
// wslDaemon.js：server 侧
`if [ -d ~/${folder}/bin/${commit} ]; then printf 'install-found '; fi; ...`
```

CLI 可执行文件名也是从代码里取的（`eE = "code-cli"`），扩展自己下载时是用 `tee` 把归档流写进这个名字，所以手工要改名。

## 六、产物清单（commit `e646868227c`）

| 归档 | 平台名 | 大小 | sha256 |
|---|---|---|---|
| CLI | `cli-linux-x64` / `cli-linux-arm64` / `cli-alpine-arm64` | 12,921,992 B | `22da21dfa7051bf3a0f048cd7e875c4fe582ddd3e8451cd17a725d199029a9fe` |
| Server | `server-linux-x64` / `server-linux-arm64` / `server-linux-alpine` / `server-alpine-arm64` | 222,356,453 B | `5cc911f00c7fd762afa1f978485d9604ceac5984f2b5e6607d981092f894326a` |

URL 形状：`https://update.code.visualstudio.com/commit:<commit>/<平台名>/<quality>`。注意 **Alpine x64 没有 CLI 产物**（`cli-linux-alpine` 返回 404），只有 server 侧有 `server-linux-alpine`。

## 七、验证

```bash
ls -l ~/.picket-code-server/bin-cli/<commit>/code-cli     # 必须可执行
~/.picket-code-server/bin-cli/<commit>/code-cli --version # code 1.143.1 (commit <commit>)
ls ~/.picket-code-server/bin/<commit>/bin                 # server 的入口目录
```

Windows 侧打开/重载 WSL 窗口，WSL 输出面板（`remote.WSL.logLevel` 设 `trace` 更详细）应出现：

- `install-found` / `Server install found in WSL`
- **不应**出现 `Downloading VS Code Server`

## 八、已知限制

- **两套布局并存**：扩展上层走 `bin-cli/<commit>`（`spawnCli`），daemon 侧还认 `bin/<commit>`。两者都放上最稳；只放 `bin-cli` 时如果日志显示还在下载，说明走到了 daemon 路径。
- **`serverApplicationName` 不一致**：发行版是 `picket-code-server`，而微软 server 归档的 `bin/` 里是 `code-server`、`helpers`、`remote-cli`。1.104.7 的 `extension.js` 里 `serverApplicationName` 出现 0 次，CLI 路径不读它；若日志显示走到了 daemon 路径（按 `bin/<commit>/bin/<serverApplicationName>` 启动），补一个链接即可：
  ```bash
  ln -s code-server ~/.picket-code-server/bin/<commit>/bin/picket-code-server
  ```
- **CLI 自己的数据目录**：`code-cli` 默认用 `~/.vscode-server`（二进制里有 `--server-data-dir=` 可改），和 `serverDataFolderName` 不是同一个。如果它坚持自己下载 server，按同一套路径把它那份也预置好。
- **不要把 `updateUrl` 随便指向微软**：它同时是自更新入口，指向 `https://update.code.visualstudio.com` 会让应用去拉正版 VS Code 覆盖自己。真要设就同时配 `"update.mode": "none"`。
- **许可证**：Remote-WSL 按微软产品条款分发，本次只做手工预置与互操作，勿把其代码/脚本复制进发行版。

## 九、参考

- 实现分析：`docs/remote-wsl-extension-analysis.md`
- 脚本：`build/manual-wsl-server.sh`
- 版本戳问题的源头：`build/build.sh`（已移除标记步骤，注释里记了原因）
- 关键代码位置（VSIX 内）：`dist/node/extension.js` 的 `_probeInstallInWSL` / `_installCliInWSL` / `_connectToCliInWsl` / `EP` / `LU` / `T`，`dist/node/wslDaemon.js` 的探针与 `tar -xz --strip-components 1` 解包
