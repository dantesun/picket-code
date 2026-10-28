# 快速开始

> 面向 AI 编码 agent 的加固版 VS Code 发行版——受控扩展、私有模型网关、按项目沙箱，开箱即用。

Picket Code 是 [Code - OSS](https://github.com/microsoft/vscode) 的发行版（fork），以干净、无遥测的二进制分发。它面向在可信、按项目隔离的环境中运行 AI 编码 agent 的团队，内置 [iCode](https://github.com/openJiuwen-ai/iCode) 作为唯一编码 agent——典型场景是银行 / 信创内网。

## 1. 下载

从 [GitHub Releases](https://github.com/dantesun/picket-code/releases) 下载对应平台的压缩包，或使用[一键下载安装命令](/guide/download)（自动校验 SHA256）。

| 平台 | 压缩包 | 启动方式 |
|---|---|---|
| Linux (x64) | `picket-code-linux-x64-<version>.tar.gz` | `./picket-code` |
| Windows (x64) | `picket-code-win32-x64-<version>.zip` | `Picket Code.exe` |

## 2. 解压

**Linux**

```bash
tar -xzf picket-code-linux-x64-v1.143.1.tar.gz
cd picket-code-linux-x64
```

**Windows**

解压 zip 到目标目录（如 `D:\picket-code`）。

## 3. 启动

```bash
# Linux
./picket-code

# Windows
Picket Code.exe
```

无需安装、无需联网注册，核心编辑体验完全离线。

## 4. 配置模型（F4）

首次启动 iCode 时按 **F4** 添加模型配置：

1. 按 `F4` 打开模型配置面板；
2. 添加你的模型端点——推荐指向自托管网关（如 LiteLLM），让 agent 只访问你控制的端点；
3. 保存后即可在聊天面板中使用 iCode。

> 模型一律 BYO（自带），Picket Code 不内置任何模型服务。

## 5. 可选：启用按项目沙箱

生产 / 内网环境建议配合沙箱使用：

- **devcontainer 模板**：把 agent 的终端、构建与文件操作约束在项目内；
- **出站防火墙配置**：默认拒绝出站，白名单放行网关端点；
- **AgentHost 路径授权**：workbench 侧 `agentHostSandboxPathGrant` 等机制随核心保留。

## 下一步

- [下载与安装](/guide/download)——一键脚本与 AI 提示词安装
- [扩展策略](/guide/extensions)——内置最小集与受控市场
- [从源码构建](/guide/build-from-source)——两阶段构建管线
- [设计总览](/architecture/overview)——整体设计思路
