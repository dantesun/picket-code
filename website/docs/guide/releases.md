# 发行与版本

> 推送 `v*` 标签（或手动 `workflow_dispatch`）触发 GitHub Actions 发行工作流，四段流水线自动产出双平台发行包。

## 发行流水线

```
versions ──► compile(linux) ──┐
             compile(win32) ──┼──► package(linux) ──┐
                              │    package(win32) ──┼──► release
                              └─────────────────────┘
```

| 阶段 | 职责 |
|---|---|
| **versions** | 解析上游 VS Code tag 与 Node 版本（从上游 `.nvmrc` 读取） |
| **compile** | linux / win32 矩阵：钉版 tag 处克隆 `microsoft/vscode` → 裁剪内置扩展 → 应用补丁 → `npm ci` → 上游 min 构建，产出 `vscode.tar.gz` |
| **package** | 按平台解包、重命名为 `picket-code-*`、归档并生成 `SHA256SUMS` |
| **release** | 将产物发布到 GitHub Release |

## 触发方式

- **推送 `v*` 标签**：如 `v1.143.1`（Release 标签以上游 VS Code 版本命名；旧预发布 `v1.143.1-p5` 已退役）；
- **手动触发**：`workflow_dispatch`，可指定上游版本与是否预发布。

## 版本策略

- 每次发布钉一个上游 tag（如 1.143.1），补丁按钉版应用；
- 升级流程：更新钉版 → 逐补丁检查锚点 → 全量构建 → 冒烟；
- 长期维护成本：53 号补丁 212KB、跨 26 文件，上游每次重构都会引发 rebase（与 VSCodium 同处境，接受）。

## 产物

| 平台 | 产物 | 校验 |
|---|---|---|
| Linux (x64) | `picket-code-linux-x64-<version>.tar.gz` | `SHA256SUMS` |
| Windows (x64) | `picket-code-win32-x64-<version>.zip` | `SHA256SUMS` |

## 规划中的打包升级

- AppImage 与 deb（Linux）、dmg（macOS）、NSIS 安装器（Windows）；
- 代码签名；
- macOS（darwin）在 P0 验证后加入发行矩阵；
- CI 矩阵加入 ARM64。
