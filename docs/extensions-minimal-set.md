# 内置扩展最小集

Picket Code 只内置**最小必要**的扩展：降低攻击面、移除微软/Copilot 相关组件与遥测、缩小发行体积，并且**默认离线**——发行版不包含任何需要访问互联网的扩展。被移除的扩展如需使用，可从受控市场（Open VSX 镜像 + 白名单，见 P0-3）按需安装。

数据来源：上游 `microsoft/vscode@1.142.0` 的 `extensions/`（97 个目录）与 `product.json` 的 `builtInExtensions`（3 个构建时下载的 JS 调试扩展）。

## 决策原则

1. **只保留编辑器离不开的核心**：Web 基础栈语言服务（TS/JS、JSON、CSS、HTML、Markdown）、Git 本地版本控制、配置/扩展编辑、引用/搜索/合并/调试基础、主题与图标、JS 调试三件套。
2. **移除一切需要联网或依赖云服务的扩展**：GitHub 集成（issues/PR 面板）、GitHub OAuth 认证、VS Code 隧道/端口转发、内置浏览器——这些扩展启动或使用时都会访问互联网，与信创内网/离线/无遥测定位冲突。
3. **移除微软/云组件**：`copilot`（GitHub Copilot Chat）、`microsoft-authentication`。
4. **移除内部测试扩展**：`vscode-*` 测试/着色/API 扩展。
5. **不内置非核心语言语法与工具链**：需要时从受控市场按需安装，减小体积与攻击面。
6. **只保留默认主题与图标**，移除冗余主题。

## 保留集（32 个）

### 核心（29 个，仓库内目录）

| 扩展 | 作用 |
|---|---|
| configuration-editing | 设置与 JSON 编辑辅助 |
| extension-editing | 扩展配置编辑 |
| emmet | HTML/CSS 快速编写 |
| references-view | 查找引用/实现 |
| search-result | 搜索结果浏览器 |
| merge-conflict | 合并冲突处理 |
| debug-auto-launch | Node 自动调试 |
| debug-server-ready | 服务就绪调试 |
| media-preview | 媒体文件预览 |
| markdown-basics | Markdown 语法 |
| markdown-language-features | Markdown 语言服务 |
| markdown-math | Markdown 数学公式 |
| mermaid-markdown-features | Markdown Mermaid 图 |
| prompt-basics（prompt） | prompt 文件语法 |
| theme-defaults | 浅色+深色默认主题 |
| theme-modern-icons | 图标主题 |
| git / git-base | 本地版本控制（仅用户主动执行 Git 命令时才联网） |
| npm | npm 脚本运行器（本地） |
| terminal-suggest | 终端命令补全 |
| ipynb / notebook-renderers | Notebook 支持 |
| typescript-basics / typescript-language-features / javascript | TS/JS 栈 |
| types | 内置类型声明 |
| css / css-language-features | CSS 栈 |
| html / html-language-features | HTML 栈 |
| json / json-language-features | JSON 栈 |

### 构建时下载（3 个）

- ms-vscode.js-debug、ms-vscode.js-debug-companion、ms-vscode.vscode-js-profile-table（本地调试，不联网）

## 移除（65 个）

| 类别 | 数量 | 示例 | 是否可恢复安装 |
|---|---|---|---|
| 语言语法 | 41 | python、php、shellscript、sql、go、rust、java、cpp 等 | 是，从受控市场 |
| 工具链 | 4 | grunt、gulp、jake、docker | 是 |
| **联网/云服务（必须移除）** | **5** | **github、github-base、github-authentication、tunnel-forwarding、simple-browser** | **否——默认离线，按需开放** |
| 微软/云组件（必须移除） | 2 | copilot、microsoft-authentication | 否——策略排除 |
| 内部测试 | 4 | vscode-api-tests、vscode-colorize-tests、vscode-colorize-perf-tests、vscode-test-resolver | 否 |
| 冗余主题 | 9 | theme-monokai、theme-seti、theme-solarized-* 等 | 是 |

> 注：语言语法类（含 SQL/Python）是否保留，按银行数据开发场景在发布前复核（见 `docs/design.md` 第 9 章）。

## 机制

- `build/extensions-remove.list`：每行一个扩展目录名；`build/build.sh` 在 `npm ci`/`gulp` 前删除这些目录。
- JS 调试三件套由 `product.json` 的 `builtInExtensions` 配置，构建期从各自 GitHub Release 直接下载 vsix（不经 Open VSX），不受本清单影响。
- 恢复某扩展：从清单删除对应行后重建，或后续从受控市场安装。

## 下一步

- 将同一清单接入受控市场白名单（P0-3）。
- 在下一个发布标签上用裁剪后的源码树重新验证构建。