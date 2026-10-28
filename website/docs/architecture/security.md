# 安全与合规

> 合规是产品属性而非事后加装：人工审批、审计日志、数据边界在架构层内建。

## 默认离线与无遥测

- `product.json`：`removeTelemetry: true`、`enableTelemetry: false`、无微软品牌；
- 内置扩展最小集：移除全部联网扩展（`github`、`github-base`、`github-authentication`、`tunnel-forwarding`、`simple-browser`、`copilot`、`microsoft-authentication`）；
- 验收口径：构建产物反查无遥测端点、无微软市场 URL、无微软登录相关字节；
- 无 Copilot 包：agent host 的运行时 import 图既不含 `@vscode/copilot-api`，也不含 `@github/copilot-sdk`（57 号补丁；`CopilotApiService` 实现留在不被加载的 `copilotApiServiceImpl.ts`，注册的是 `noCopilotServices.ts` 里的 no-op 实现）。

## 无账号、无登录

- 构建剔除 `github`、`github-base`、`github-authentication`、`microsoft-authentication` 四个内置扩展；`product.json` 不再定义 `defaultChatAgent`、`trustedExtensionAuthAccess`、`builtInExtensionsEnabledWithAutoUpdates`（58 号让 `defaultAccount.ts` 在缺少 `defaultChatAgent` 时返回中性配置，不再注册默认账号 provider）；
- 后果：界面没有「登录 GitHub / Microsoft」，没有 Settings Sync，也没有 Publish to GitHub；需要 `github` session 的扩展拿不到任何会话，会自行降级或提示未登录；
- 不受影响：Git over HTTPS / SSH 仍照常工作（凭据来自系统凭据管理器或 SSH agent，与应用内账号体系无关）；
- CI 断言：内置扩展目录与 `product.json` 都不得残留上述扩展名与账号键，命中即失败。

## 金发〔2026〕8号 关键条款映射

| 条款要求 | Picket Code / iCode 落点 | 状态 |
|---|---|---|
| 外部引入生成式模型需网信备案 | iCode BYO 模型，模型归属用户；备案责任在行内 | 产品可覆盖（行内自担） |
| 高风险场景人工复核（第22条） | AgentHost `pending_confirmation` ↔ iCode manual 审批 | 产品内建（待 POC 实测） |
| 日志保存期限不低于业务存续期（第21条） | AgentHost 会话 DB + iCode OTel；留存期策略行内配置 | 待合同与配置验证 |
| 外包合同安全权责、名单制（第18条） | 供应商尽调 + DPA 条款 | 商务待办 |
| 开源台账、供应链防投毒（第19条） | iCode Apache-2.0 可审计；SBOM / 依赖审计需自建 | 缺口 |
| 提示词注入、智能体安全（第25条） | iCode 护栏 + AgentHost 沙箱路径授权 | 待验证 |
| 无头自动化不得绕过审批 | Picket Code 禁用无头审批 bypass 路径 | 设计红线 |

## 扩展门控与受控市场

- 默认 Open VSX，可指向自建镜像；
- 后续叠加白名单策略：受控市场 + 扩展签名校验（见[扩展策略](/guide/extensions)）。

## 沙箱与出站控制

- devcontainer 模板 + 出站防火墙配置：**默认拒绝出站**，白名单放行网关端点；
- AgentHost 沙箱路径授权机制（workbench 侧 `agentHostSandboxPathGrant` 等）随核心保留。

## 报告安全问题

如果你在 Picket Code 中发现安全问题，请通过私密渠道报告，不要公开发 issue：

- **GitHub 私密漏洞报告**：使用仓库 Security 标签页的「Report a vulnerability」按钮；
- 请包含：受影响版本、平台、复现步骤、影响范围；
- 我们会保密处理安全报告，并在 3 个工作日内确认收到。

## 沙箱注意

Picket Code 的构建本身不会对任意代码做沙箱隔离：扩展与 agent 的 skill 脚本以你的用户权限运行。请在 agent 工作负载中使用按项目的 devcontainer 与出站防火墙配置，并在安装前审查第三方扩展与 skill。
