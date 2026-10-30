# 路线图

与 P0 产品分析（项目 Wiki）对齐：**条件进入，P0 验证先行**。整体设计思路见 `docs/design.md`。

## P0——验证闭环（当前）

| # | 能力 | 交付物 | 状态 |
|---|---|---|---|
| 1 | 干净构建管线 | VSCodium 式构建管线。MVP：**Linux (x64) + Windows (x64)** 无遥测二进制；macOS 在 P0 验证后加入 | 已在仓库——MVP 范围：linux + win32（`build/build.sh` 编译 + `build/<platform>/package.sh` 打包 + `release.yml` 四段流水线）；内置扩展最小集（默认离线）已完成（`docs/extensions-minimal-set.md`） |
| 2 | iCode 一等公民集成 | AgentHost 集成：注册 iCode 为唯一 provider（P3 骨架 + P4 常驻 app-server）；UI 走核心聊天面板（P2.5 先行验证） | 规划中，见 `docs/design.md` 第 6 章 |
| 3 | 私有网关层 | 基于 LiteLLM 的网关封装 + 受控市场 MVP（Open VSX 镜像 + 白名单）+ 默认拒绝出站的沙箱配置 | 规划中 |

验证方式：10–20 名种子用户；基线指标为「安装 → 首个任务通过率」。不预设硬性阈值与排期。

## Non-goals（P0）

- 不做自有模型。
- 不做云托管沙箱。
- 不兼容微软官方市场。
- 不与 Cursor 比拼原始智能。

## 后续

- 打包升级：AppImage / deb、dmg、NSIS 安装器、代码签名。
- macOS（darwin）在 P0 验证后加入发行矩阵。
- 远程开发（WSL / SSH）：前置是自有 reh server 产物 + `product.json` 的 `commit`/`updateUrl`。微软的 Remote 扩展闭源且按 commit 从微软更新服务器取服务端，无法直接复用；实现分析与缺口见 `docs/remote-wsl-extension-analysis.md`。
- CI 矩阵加入 ARM64。
- 可复现构建：G6 分级验收（L1 关键产物哈希一致 → L2 内容级一致 → L3 字节级一致，见 `docs/design.md` 5.5）。
- 核验微软 Private Marketplace 对非官方 fork 的开放度。