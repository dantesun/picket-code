# 发行与版本

> 推送 `v*` 标签（或手动 `workflow_dispatch`）触发 GitHub Actions 发行工作流，四段发行流水线自动产出双平台发行包，末尾的 `r2-sync` 任务再把资产镜像到 Cloudflare R2（保留最近 3 个版本）。

## 发行流水线

```
versions ──► compile(linux) ──┐
             compile(win32) ──┼──► package(linux) ──┐
                              │    package(win32) ──┼──► release ──► r2-sync
                              └─────────────────────┘
```

| 阶段 | 职责 |
|---|---|
| **versions** | 从标签解析上游 VS Code tag（去掉 `-pN` 后缀）与 Node 版本（从上游 `.nvmrc` 读取） |
| **compile** | linux / win32 矩阵：钉版 tag 处克隆 `microsoft/vscode` → 裁剪内置扩展 → 应用补丁 → `npm ci` → 上游 min 构建，产出 `vscode.tar.gz` |
| **package** | 按平台解包、重命名为 `picket-code-*`、归档并生成 `SHA256SUMS`；同时跑三项门禁（见下） |
| **release** | 将产物发布到 GitHub Release，并把镜像地址写在 Release 说明顶部 |
| **r2-sync** | `rclone copy` 当前 Release 资产到 Cloudflare R2 桶 `picket-releases`，再跑 `prune-r2.sh` 只保留最近 3 个版本 |

## CI 门禁

`package` 阶段失败即中止发行，三项断言与动态检查：

- `node build/check-asar.mjs` 解析产出的 `node_modules.asar`，条目偏移重叠 / 数据区不匹配即失败；
- 账号残留断言：`product.json` 不得含 `defaultChatAgent`、`trustedExtensionAuthAccess`、`builtInExtensionsEnabledWithAutoUpdates`，内置扩展目录不得含 `github` / `github-base` / `github-authentication` / `microsoft-authentication`；
- 打包后的 Windows 应用实际启动 55 秒，日志命中 `ERR_INVALID_PACKAGE_CONFIG`、`Uncaught Exception`、`Could not locate the bindings file`、`Cannot find module` 任一即失败。

## 触发方式

- **推送 `v*` 标签**：标签以上游 VS Code 版本命名，当前为 `v1.143.1-p3`（上游 `1.143.1`）。同一上游版本的自有重建在同一标签后追加 `-pN`，例：`v1.143.1` → `v1.143.1-p1` → `v1.143.1-p2` → `v1.143.1-p3`；工作流会剥掉 `-pN` 后定位上游 tag。
- **手动触发**：`workflow_dispatch`，可指定上游版本与是否预发布。

> `v1.143.1`（2026-10-27 发布）发行包有缺陷：ASAR 含 748 个重叠条目，会崩溃扩展宿主，该 Release 已删除。当前发行版是 `v1.143.1-p3`。

## 版本策略

- 每次发布钉一个上游 tag（如 1.143.1），补丁按钉版应用；
- 同一上游版本的多次重建不升级钉版，只递增 `-pN`；
- 升级流程：更新钉版 → 逐补丁检查锚点 → 全量构建 → 冒烟；
- 长期维护成本：53 号补丁跨 30 个文件（28 修改 + 2 删除），上游每次重构都会引发 rebase（与 VSCodium 同处境，接受）。

## 产物

文件名带版本号（`picket-code-<tag>-<os>-<arch>.<ext>`），版本既由标签区分，也写在文件名里；GitHub Release 资产与镜像上的文件名完全一致。

| 平台 | 产物 | 校验 |
|---|---|---|
| Linux (x64) | `picket-code-<tag>-linux-x64.tar.gz` | `picket-code-<tag>-SHA256SUMS` |
| Windows (x64) | `picket-code-<tag>-win32-x64.zip` | `picket-code-<tag>-SHA256SUMS` |

归档内的顶层目录不带版本号：`picket-code-win32-x64/`、`picket-code-linux-x64/`。

## 镜像

Release 资产会 `rclone copy` 到 Cloudflare R2 桶 `picket-releases`，对外通过 `https://picket-code.noware.cn` 提供（该域名同时承载文档站，`/picket-code-*` 路径由下载 Worker 直出对象）。示例（tag `v1.143.1-p3`）：

- `https://picket-code.noware.cn/picket-code-v1.143.1-p3-win32-x64.zip`
- `https://picket-code.noware.cn/picket-code-v1.143.1-p3-linux-x64.tar.gz`
- `https://picket-code.noware.cn/picket-code-v1.143.1-p3-SHA256SUMS`

```bash
curl -fSL https://picket-code.noware.cn/picket-code-v1.143.1-p3-SHA256SUMS -o SHA256SUMS
sha256sum -c --ignore-missing SHA256SUMS
```

- 镜像保留最近 **3 个版本**，更早的版本只在 GitHub Releases；
- 没有 `latest` 别名：文件名含版本，一个 URL 的内容永不改变，因此 URL 永久有效且可长期缓存（`cache-control: immutable`）；
- 旧的无版本 URL（`/picket-code-win32-x64.zip`、`/SHA256SUMS`）已废弃，不提供兼容，请求返回 404。

## 计划中的打包升级

- AppImage 与 deb（Linux）、dmg（macOS）、NSIS 安装器（Windows）；
- 代码签名；
- macOS（darwin）在 P0 验证后加入发行矩阵；
- CI 矩阵加入 ARM64。
