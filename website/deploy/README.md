# 部署到 Cloudflare Pages + 下载 Worker（noware.cn）

Picket Code 官网是纯静态站点（VitePress 构建产物），托管在 **Cloudflare Pages**，域名绑定 **`picket-code.noware.cn`**，构建由 **GitHub** 触发。发行包等大文件放 **Cloudflare R2**，由同一个域名下的 **Worker** 直出。

> **实际部署状态（2026-10-28，Git 集成已完成）**：Pages 项目 `picket-code` 已接入 GitHub（`dantesun/picket-code`，production branch `main`），每次 push 到 `website/**` 自动构建上线；自定义域名 `picket-code.noware.cn` 已绑定并生效（active），SSL 由 Google Trust Services 签发（有效期至 2027-01-26）。构建配置：Root directory `website`，Build command `npm ci && npm run docs:build`，Output directory `docs/.vitepress/dist`。

## 总体架构

```
GitHub（源码 + website/ 站点 + infra/worker/download）
    │ push 触发
    ├──────────────► Cloudflare Pages（构建 VitePress 静态站点）
    │                     │ 自定义域名
    │                     ▼
    │            picket-code.noware.cn（SSL、CDN、WAF 全自带）
    │                     ▲
    └──────────────► Cloudflare Worker（/picket-code-* 路由，仅 CI 部署）
                          │ 读取
                          ▼
                  Cloudflare R2 桶 picket-releases（发行包 + SHA256SUMS）
```

同一个主机名承担两件事，靠路径分流：

| 路径 | 提供者 | 内容 |
|---|---|---|
| `/picket-code-*` | Worker `picket-downloads`（`infra/worker/download`） | R2 桶 `picket-releases` 中的发行包与校验和 |
| 其余全部路径 | Cloudflare Pages（`picket-code` 项目） | VitePress 文档站 |

Worker 的路由 `picket-code.noware.cn/picket-code-*` 命中时优先于 Pages，因此站点其余路径不受影响。

## 一、把站点放进仓库

把本 `website/`（或本目录内容）放入 `dantesun/picket-code` 仓库根目录，提交后推送：

```bash
# 在仓库根目录（示例：放到 website/ 子目录）
git add website/
git commit -m "chore: add official website (VitePress)"
git push
```

## 二、Cloudflare Pages 接入

1. 打开 Cloudflare Dashboard → **Workers & Pages → Create → Pages → Connect to Git**；
2. 选择 `dantesun/picket-code` 仓库；
3. 构建配置：

| 配置项 | 值 |
|---|---|
| Production branch | `main` |
| Root directory | `website` |
| Build command | `npm ci && npm run docs:build` |
| Build output directory | `docs/.vitepress/dist` |
| Framework preset | `None`（VitePress 暂无预设，手动填写即可） |

4. 点击 **Save and Deploy**，首次构建约 1–2 分钟。

> 站点更新流程：每次 `git push` 到 main（或 PR 合并），Pages 自动重新构建上线；PR 自动生成预览链接，方便审阅文档改动。

## 三、绑定子域名 picket-code.noware.cn

1. Pages 项目 → **Custom domains → Set up a custom domain**，输入 `picket-code.noware.cn`（已完成）；
2. **创建 DNS 记录**（已通过 API 创建，若重建：Cloudflare Dashboard → 域名 `noware.cn` → DNS → 添加记录）：
   - 类型：`CNAME`
   - 名称：`picket-code`
   - 目标：`picket-code.pages.dev`
   - 代理状态：**开启（橙色云朵）**
   - TTL：自动
3. 保存后 Cloudflare 自动为域名签发 SSL 证书（Google CA，约 1–15 分钟），状态从 pending → active；
4. 生效后即可通过 `https://picket-code.noware.cn` 访问（已完成，证书有效期至 2027-01-26）。

## 四、下载资源：R2 桶 + 下载 Worker（已落地）

### 1. 下载地址的形式

对象键就是文件名，文件名带版本（示例 tag `v1.143.1-p4`）：

- `https://picket-code.noware.cn/picket-code-v1.143.1-p4-win32-x64.zip`
- `https://picket-code.noware.cn/picket-code-v1.143.1-p4-linux-x64.tar.gz`
- `https://picket-code.noware.cn/picket-code-v1.143.1-p4-SHA256SUMS`

因为文件名含版本，一个 URL 对应的对象永不覆盖，Worker 因此返回 `cache-control: public, max-age=31536000, immutable`，可被 CDN 与客户端长期缓存。桶里**没有** `latest` 别名，旧的无版本对象（`picket-code-win32-x64.zip`、`SHA256SUMS`）已删除且不再生成，请求返回 404（不提供兼容）。

### 2. R2 桶与保留策略

- 桶：`picket-releases`（Worker 用 `RELEASES` 绑定）；
- 上传：`release.yml` 的 `r2-sync` 任务从已发布的 Release 下载 `picket-code-*` 资产，`rclone copy release/ r2:picket-releases/`（用 `copy` 而非 `sync`，避免删除历史版本）；
- 保留：`.github/scripts/prune-r2.sh` 只保留最近 **3 个版本**（`KEEP=3`，按 tag 的 `vX.Y.Z` + `-pN` 排序），更早的版本不承诺长期可下载；
- 凭据：GitHub Secrets `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_ENDPOINT`。

### 3. 下载 Worker

- 代码：`infra/worker/download`（`wrangler.toml`：worker 名 `picket-downloads`，路由 `picket-code.noware.cn/picket-code-*`，zone `noware.cn`，R2 绑定 `RELEASES` → `picket-releases`）；
- 行为：只接受 `GET` / `HEAD`，只服务以 `picket-code-` 开头且不含 `..` 的键，支持 Range（断点续传），未命中即 404；
- 缓存：Cloudflare 默认**不缓存 Worker 响应**，因此完整 GET 会写入边缘缓存（`caches.default`，键为 URL），R2 只在每个位置的首次下载时被读一次；响应头 `x-picket-cache: HIT|MISS` 说明本次是否是边缘直出。Range 请求与 HEAD 不入缓存。填充缓存用**第二次 R2 读取**而不是 `tee` 客户端响应，避免慢客户端把 200 MB 的差值堆在 Worker 内存里；`cache.put` 失败不影响下载；
- 部署：**只从 CI 部署**——`.github/workflows/deploy-worker.yml` 在 `infra/worker/download/**` 或该 workflow 自身变更时，以及手动 `workflow_dispatch` 时执行 `wrangler deploy`。

> **不要在本地 `wrangler deploy`**：Cloudflare API Token 只存在 GitHub Actions（Secret `CF_API_TOKEN`，Account ID 取仓库变量 `CF_ACCOUNT_ID`），本地部署会绕开唯一的凭据来源与审计路径。改完 worker 代码后 push 或手动触发该 workflow 即可。

## 五、备用方案：Wrangler 直接上传站点

不想接 Git 时，可用 Wrangler 直接上传 Pages 构建产物（`wrangler.toml.example`）。注意这只适用于**站点**，下载 Worker 仍只从 CI 部署（见上节）：

```bash
npm install -g wrangler
wrangler login
cd website && npm ci && npm run docs:build
wrangler pages deploy docs/.vitepress/dist --project-name=picket-code
```

## 六、GitHub Actions 一键部署（备用）

`deploy/.github/workflows/deploy-pages.yml.example` 提供了 GitHub Actions 直传 Pages 的完整示例，需在仓库 Secrets 中配置：

| Secret | 说明 |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token（权限：Workers Scripts Edit / Pages Edit） |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare 账户 ID |

## 站点内的下载链接与变量

- 站内下载链接指向镜像主机 `https://picket-code.noware.cn`，文件名形如 `picket-code-<tag>-<os>-<arch>.<ext>`；文档中的具体示例版本写在 `website/docs/guide/download.md`、`website/docs/guide/releases.md`，发版后按需更新示例；
- 仓库变量 `R2_PUBLIC_BASE_URL` 决定 Release 说明顶部的镜像链接（未设置时该步骤跳过，Release 只保留 GitHub 链接）；
- 站点的下载脚本（`build/download-verify.sh|ps1|bat`）不带版本时自行解析 GitHub 最新 release，因此脚本本身无需随版本改动；
- 如需让下载按钮动态读取最新版本，可后续在 Pages Functions 中加一层 `api/latest-release`，从 GitHub API 读取最新 tag。
