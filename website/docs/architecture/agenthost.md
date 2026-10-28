# AgentHost 与 iCode 集成

> AgentHost 是 VS Code 内置的 agent 宿主平台：provider 注册、会话、审批、日志、AHP 传输。Picket Code 将其裁剪为"零 provider + 编排核心"，并注入 iCode 作为唯一 provider。

## AgentHost 关键事实（源码级）

| 事实 | 位置 | 含义 |
|---|---|---|
| agent 注册点只有两处 | `agentHostMain.ts`、`agentHostServerMain.ts` 的 `startAgentHost()` | 注入 iCode 只需改这两处 |
| 零 provider 不抛错 | `agentHostProviderService.ts`；`agentHostSessionLifecycle.ts` 有 `getProviders().length > 0` 守卫 | 删除全部 provider 后 host 可正常启动 |
| 首个注册者自动成为默认 | `registerProvider()` | 注册 iCode 即默认 |
| 注册门控模式 | Claude 用 env 开关 + SDK 可达性；Codex 用 env/配置 + SDK 可达性 | iCode 门控仿照：配置开关 + 二进制可达性 |

## 52/53 复用方案

- 下载 VSCodium `patches/52-ext-copilot-remove-it.json` 与 `53-ext-copilot-remove-it.patch`，随钉版固定；
- **52 号**：177 条物理删除路径（含 80+ 测试文件），workbench 路径 0 条；
- **53 号**：26 文件引用清理（provider 注册块整段删除、`providerConfigurations: []`、SDK 依赖删除、OTel 钩子 no-op）；
- `mockAgent.ts` 在 53 中被就地裁剪后保留，作 iCode 适配器参考；
- 落地状态（2026-10-27）：执行器 `build/apply-patches.sh` 是唯一补丁入口，顺序为 product.json merge → 52 → 53 → 54 → 55 → 61；在 vscode `1.143.1`（`e646868227c`）上实测 52 删除 177/177 路径、53/54/55/61 全部干净应用。

## iCode 适配器四件套（P3）

```
src/vs/platform/agentHost/node/icode/
├── icodeAgent.ts            # 实现 IAgent；从裁剪后 mockAgent 抄结构
├── icodeAppServerClient.ts  # spawn 常驻子进程；参考 node/codex/codexAppServerClient.ts
├── icodeLaunchConfig.ts     # 解析系统 icode 或内置 Python 运行时
└── icodeMapEvents.ts        # 事件映射：markdown/tool/审批/diff/idle/usage
```

- IAgent 是内部接口而非扩展 API：**必须 fork 上游代码实现适配**，不能以扩展方式接入；
- mockAgent 位于 `test/` 且依赖测试 fixture，不能整体搬进生产代码；复制结构后按生产标准重写。

## 常驻 app-server（P4，iCode 侧新增）

| 现状 | 目标 |
|---|---|
| `icode run "<prompt>" --agent QA --json`：one-shot，一次往返即退出 | `icode app-server`：常驻进程，JSON-RPC 流式会话 |
| 无增量上下文、无工具回调 | 支持多轮、工具审批、diff 预览、中断恢复 |
| 会话状态在 CLI 进程内 | 会话状态由 AgentHost 会话 DB 管理 |

审批语义必须完整映射：iCode workflow 的 manual 审批 ↔ AgentHost 的 `pending_confirmation` 信号。

## 聊天 UI 路线（已拍板）

- agentHost 聊天面板在 **workbench 核心代码**（`agentHost.contribution.ts` 注册十几个 contribution，`AfterRestored` 阶段启动 host），不在 `extensions/copilot` 内；
- 删除 copilot 扩展后，聊天 shell 仍在；iCode 注册后**可能直接渲染 iCode 会话**；
- 决策：先用 **P2.5 验证核心面板直连**（用裁剪 mockAgent 注册 mock provider），通过则不引入外部 AHP client / 自建扩展；失败再评估替代路线。
