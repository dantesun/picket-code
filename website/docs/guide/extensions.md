# 扩展策略

> Picket Code 只内置**最小必要**的扩展：降低攻击面、移除微软 / Copilot 相关组件与遥测、缩小发行体积，并且**默认离线**。

数据来源：上游 `microsoft/vscode@1.142.0` 的 `extensions/`（97 个目录）与 `product.json` 的 `builtInExtensions`（3 个构建时下载的 JS 调试扩展）。

## 决策原则

1. **只保留编辑器离不开的核心**：Web 基础栈语言服务（TS/JS、JSON、CSS、HTML、Markdown）、Git 本地版本控制、配置 / 扩展编辑、引用 / 搜索 / 合并 / 调试基础、主题与图标、JS 调试三件套。
2. **移除一切需要联网或依赖云服务的扩展**：GitHub 集成、GitHub OAuth 认证、VS Code 隧道 / 端口转发、内置浏览器。
3. **移除微软 / 云组件**：`copilot`（GitHub Copilot Chat）、`microsoft-authentication`。
4. **移除内部测试扩展**：`vscode-*` 测试 / 着色 / API 扩展。
5. **不内置非核心语言语法与工具链**：需要时从受控市场按需安装。
6. **只保留默认主题与图标**，移除冗余主题。

## 保留集（32 个）

### 核心（29 个，仓库内目录）

| 扩展 | 作用 |
|---|---|
| configuration-editing / extension-editing | 设置与 JSON / 扩展配置编辑 |
| emmet | HTML/CSS 快速编写 |
| references-view / search-result / merge-conflict | 引用 / 搜索结果 / 合并冲突 |
| debug-auto-launch / debug-server-ready | Node 自动调试 / 服务就绪调试 |
| media-preview | 媒体文件预览 |
| markdown-basics / markdown-language-features / markdown-math / mermaid-markdown-features | Markdown 语言服务与图表 |
| prompt-basics（prompt） | prompt 文件语法 |
| theme-defaults / theme-modern-icons | 默认主题与图标 |
| git / git-base | 本地版本控制（仅用户主动执行 Git 命令时才联网） |
| npm / terminal-suggest | npm 脚本运行器 / 终端命令补全 |
| ipynb / notebook-renderers | Notebook 支持 |
| typescript-basics / typescript-language-features / javascript / types | TS/JS 栈 |
| css / html / json 及其 language-features | CSS / HTML / JSON 栈 |

### 构建时下载（3 个）

- `ms-vscode.js-debug`、`ms-vscode.js-debug-companion`、`ms-vscode.vscode-js-profile-table`（本地调试，不联网）

## 移除（65 个）

| 类别 | 数量 | 示例 | 是否可恢复安装 |
|---|---|---|---|
| 语言语法 | 41 | python、php、shellscript、sql、go、rust、java、cpp 等 | 是，从受控市场 |
| 工具链 | 4 | grunt、gulp、jake、docker | 是 |
| **联网 / 云服务（必须移除）** | **5** | **github、github-base、github-authentication、tunnel-forwarding、simple-browser** | **否——默认离线，按需开放** |
| 微软 / 云组件（必须移除） | 2 | copilot、microsoft-authentication | 否——策略排除 |
| 内部测试 | 4 | vscode-api-tests 等 | 否 |
| 冗余主题 | 9 | theme-monokai、theme-seti、theme-solarized-* 等 | 是 |

> 语言语法类（含 SQL / Python）是否保留，按银行数据开发场景在发布前复核（见[设计总览](/architecture/overview)风险章节）。

## 受控市场（P0-3 规划）

- 默认市场：**Open VSX**，可指向自建镜像；
- 白名单策略：受控市场 + 扩展签名校验；
- 恢复某扩展：从 `build/extensions-remove.list` 删除对应行后重建，或从受控市场按需安装。

## 机制

- `build/extensions-remove.list`：每行一个扩展目录名；`build/build.sh` 在 `npm ci` / `gulp` 前删除这些目录。
- JS 调试三件套由 `product.json` 的 `builtInExtensions` 配置，构建期从各自 GitHub Release 直接下载 vsix（不经 Open VSX），不受本清单影响。
