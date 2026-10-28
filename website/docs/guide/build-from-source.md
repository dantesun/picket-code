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

示例：

```bash
bash build/build.sh 1.142.0 0.1.0 linux x64
bash build/linux/package.sh linux x64
```

编译阶段会克隆 `microsoft/vscode@<vscode-version>`、按 `build/extensions-remove.list` 裁剪内置扩展、应用补丁（`build/product.json` 改名 / 关遥测 / Open VSX 市场、copilot 移除等），构建并产出 `vscode.tar.gz` 供打包阶段消费。

## 补丁体系

补丁执行器 `build/apply-patches.sh` 是唯一补丁入口（`build.sh` 只调用它一次），顺序为：

1. **product.json merge**（内嵌 python3）：品牌 `picket-code / Picket Code`、`removeTelemetry: true`、Open VSX 市场、更新通道指向本项目 Releases；
2. **52 号 JSON 删除**：copilot 全量删除（177 条物理路径，缺失即 exit 4 显式报错）；
3. **53 / 54 / 55 / 61 号补丁**：逐个 `git apply --check` 后应用——引用清理、禁用 node 编译缓存、解包原生与 AgentHost、构建脚本适配 6 处。

> 落地状态（2026-10-27）：在 vscode `1.143.1`（`e646868227c`）上实测 52 删除 177/177 路径、53/54/55/61 全部干净应用。

设计原则：**补丁锚点断言**——每个补丁断言锚点文本；上游升级导致锚点失效时显式报错，不静默错补。

## 可复现构建（G6 分级验收）

当前流水线没有任何确定性构建措施，同一 tag 两次构建的产物差异是必然的（时间戳类与内容类差异）。验收按三级承诺：

| 级别 | 定义 | 承诺阶段 |
|---|---|---|
| **L1 关键产物哈希一致** | `resources/app/out`、`product.json` 等核心产物 sha256 一致；归档外层允许差异 | P0 即可承诺 |
| **L2 内容级一致** | 解包后逐文件比对，剥离时间戳类字段后一致 | P1 后 |
| **L3 字节级完全一致** | 归档与文件字节全等（`SOURCE_DATE_EPOCH` 贯穿等） | 后续工程项，不作 P0 承诺 |

## 发行流水线

推送 `v*` 标签（或手动 `workflow_dispatch`）触发 GitHub Actions 发行工作流，四段流水线：`versions → compile（linux / win32 矩阵）→ package → release`。详见[发行与版本](/guide/releases)。

## 目录速览

| 路径 | 职责 |
|---|---|
| `build/build.sh` | 编译阶段：契约自检 → clone 钉版 → 裁扩展 → 打补丁 → npm ci（重试 5 次）→ min 构建 |
| `build/linux/package.sh` | Linux 解包 → 重命名 → tar.gz |
| `build/win32/package.sh` | Windows 解包 → 杀占用进程 / 清只读属性 → 重试 mv → 三级压缩 |
| `build/apply-patches.sh` | 补丁唯一执行入口（product.json merge → 52 → 53 → 54 → 55 → 61） |
| `build/extensions-remove.list` | 内置扩展最小集清单（保留 32 + 构建期 3，移除 65） |
| `build/patches/` | 补丁文件与 `apply-list.txt` |
| `build/product.json` | 品牌、遥测开关、市场、更新通道 |
