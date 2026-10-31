# 从源码构建

> 构建分两个阶段（对齐 VSCodium 流水线）：先编译、后打包，两阶段互不串行重跑。

## 两阶段构建

```bash
# 1. 编译阶段：clone 钉版 → 裁剪扩展 → 打补丁 → npm ci → 上游 min 构建
bash build/build.sh <vscode-version> <picket-code-version> <linux|win32> [x64|arm64]

# 2. 打包阶段：解包 → 重命名 → 归档
bash build/linux/package.sh <linux> [x64|arm64]     # Linux
bash build/win32/package.sh <win32> [x64|arm64]     # Windows
```

示例（`picket-code-version` 可写成标签形式，脚本会去掉前缀 `v`）：

```bash
bash build/build.sh 1.143.1 v1.143.1 linux x64
bash build/linux/package.sh linux x64
```

编译阶段会克隆 `microsoft/vscode@<vscode-version>`、按 `build/extensions-remove.list` 裁剪内置扩展、应用补丁（`build/product.json` 改名 / 关遥测 / Open VSX 市场、copilot 移除等），构建并产出 `vscode.tar.gz` 供打包阶段消费。

## 补丁体系

补丁执行器 `build/apply-patches.sh` 是唯一补丁入口（`build.sh` 只调用它一次），顺序为 product.json merge → 52 → 53 → 54 → 56 → 57 → 58 → 61：

| 补丁 | 内容 |
|---|---|
| product.json merge（内嵌 python3） | 品牌 `picket-code / Picket Code`、`removeTelemetry: true`、Open VSX 市场、内置更新器关闭（`updateUrl` 置 `null` 后被删除，更新器以「no update URL」退出）；值为 `null` 的键从上游 `product.json` 中删除（`defaultChatAgent` 等） |
| **52** JSON 删除 | copilot 全量删除（177 条物理路径，缺失即 exit 4 显式报错） |
| **53** 引用清理 | Copilot 引用清理，30 个文件（28 修改 + 2 删除） |
| **54** 禁用 node 编译缓存 | `shouldGenerateNodeCompileCache` 返回 false（win32 EBUSY + 缓存产物不确定） |
| ~~**55**~~ **已退役** | 文件已删除。原先解包 30 个包只为绕开 asar 写入竞态，56 号修复后解包清单回到上游 11 条，`.asar.unpacked` 相应变小 |
| **56** 串行化 asar 插入 | `build/lib/asar.ts` 中串行化 `Filesystem.insertFile`：`asar@3.2.0` 在 await 完整性哈希前记录 offset，并发插入拿到同一 offset，Windows 构建机上约 20% 条目（751 / 3,765）读回成别的文件 |
| **57** 无 Copilot 包的 agent host | 拆分 `copilotApiService.ts` 为 `copilotApiTypes.ts`（无 Copilot 依赖的 DI 缝）+ `copilotApiServiceImpl.ts`（本构建不加载）、新增 `localModelSetupTypes.ts`，`noCopilotServices.ts` 注册 no-op 实现 |
| **58** 容忍缺失的 `defaultChatAgent` | `defaultAccount.ts` 在 `product.json` 没有 `defaultChatAgent` 时返回中性配置，不再注册默认账号 provider |
| **61** 构建脚本适配 | 6 处锚点替换：`dirs.ts` / gulpfile 过滤、AppX 与 signtool 容错、内置扩展改从 GitHub 取 |

每个补丁先 `git apply --check` 再应用，锚点失效即报错退出。

> 落地状态（2026-10-28）：在 vscode `1.143.1`（`e646868227c`）上实测 52 删除 177/177 路径、53/54/56/57/58/61 全部干净应用。

设计原则：**补丁锚点断言**——每个补丁断言锚点文本；上游升级导致锚点失效时显式报错，不静默错补。

## CI 门禁

发行工作流在 `package` 阶段对每个平台产物三项检查，任一失败即中止发行：

| 检查 | 内容 |
|---|---|
| 归档布局 | `node build/check-asar.mjs` 解析产出的 `node_modules.asar`：不允许两个非空条目共用同一 offset、不允许条目指向数据区之外、数据区必须正好被条目铺满 |
| 账号残留 | `product.json` 不得含 `defaultChatAgent` / `trustedExtensionAuthAccess` / `builtInExtensionsEnabledWithAutoUpdates`；`extensions/` 不得含 `github` / `github-base` / `github-authentication` / `microsoft-authentication` |
| 真实启动 | 启动打包后的 Windows 应用 55 秒，日志命中 `ERR_INVALID_PACKAGE_CONFIG`、`Uncaught Exception`、`Could not locate the bindings file`、`Cannot find module` 任一即失败 |

这套门禁的由来：asar 写入竞态曾让 `tar/package.json` 读回一段 LICENSE 文本，agent host 以 `ERR_INVALID_PACKAGE_CONFIG` 崩溃，而归档本身"看起来"完好。

## 可复现构建（G6 分级验收）

当前流水线没有任何确定性构建措施，同一 tag 两次构建的产物差异是必然的（时间戳类与内容类差异）。验收按三级承诺：

| 级别 | 定义 | 承诺阶段 |
|---|---|---|
| **L1 关键产物哈希一致** | `resources/app/out`、`product.json` 等核心产物 sha256 一致；归档外层允许差异 | P0 即可承诺 |
| **L2 内容级一致** | 解包后逐文件比对，剥离时间戳类字段后一致 | P1 后 |
| **L3 字节级完全一致** | 归档与文件字节全等（`SOURCE_DATE_EPOCH` 贯穿等） | 后续工程项，不作 P0 承诺 |

## 发行流水线

推送 `v*` 标签（或手动 `workflow_dispatch`）触发 GitHub Actions 发行工作流，四段流水线：`versions → compile（linux / win32 矩阵）→ package → release`，随后 `r2-sync` 用 `rclone copy` 把资产镜像到 Cloudflare R2 桶 `picket-releases`，再裁剪成只保留最近 3 个版本。详见[发行与版本](/guide/releases)。

## 目录速览

| 路径 | 职责 |
|---|---|
| `build/build.sh` | 编译阶段：契约自检 → clone 钉版 → 裁扩展 → 打补丁 → npm ci（重试 5 次）→ min 构建 |
| `build/linux/package.sh` | Linux 解包 → 重命名 → tar.gz |
| `build/win32/package.sh` | Windows 解包 → 杀占用进程 / 清只读属性 → 重试 mv → 三级压缩 |
| `build/apply-patches.sh` | 补丁唯一执行入口（product.json merge → 52 → 53 → 54 → 56 → 57 → 58 → 61） |
| `build/check-asar.mjs` | CI 断言：解析产出的 `node_modules.asar`，检查条目偏移重叠 / 数据区错位 |
| `build/extensions-remove.list` | 内置扩展最小集清单（保留 32 + 构建期 3，移除 65） |
| `build/patches/` | 补丁文件与 `apply-list.txt`（55 已退役，文件已删除） |
| `build/product.json` | 品牌、遥测开关、市场、更新器开关（关闭） |
