# 部署到 Cloudflare Pages（noware.cn）

Picket Code 官网是纯静态站点（VitePress 构建产物），托管在 **Cloudflare Pages**，域名绑定 **noware.cn**，构建由 **GitHub** 触发。大文件（发行包、截图等）走 **R2** 存储。

> **实际部署状态（2026-10-28，Git 集成已完成）**：Pages 项目 `picket-code` 已接入 GitHub（`dantesun/picket-code`，production branch `main`），每次 push 到 `website/**` 自动构建上线；自定义域名 `picket-code.noware.cn` 已绑定并生效（active），SSL 由 Google Trust Services 签发（有效期至 2027-01-26）。构建配置：Root directory `website`，Build command `npm ci && npm run docs:build`，Output directory `docs/.vitepress/dist`。

## 总体架构

```
GitHub（源码 + website/ 站点）
    │ git push 触发
    ▼
Cloudflare Pages（构建 VitePress 静态站点）
    │ 自定义域名
    ▼
noware.cn / www.noware.cn（SSL、CDN、WAF 全自带）

Cloudflare R2：发行包 / 截图 / 大资源（download.noware.cn）
```

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

## 四、R2 承载下载资源（可选）

发行包目前发布在 GitHub Releases（作为唯一事实来源）。如需国内加速或统一资源出口，可用 R2 做镜像：

1. 创建 R2 桶 `picket-code-dist`，开启 **Public access（r2.dev 或自定义域）**；
2. 自定义域：`download.noware.cn`（CNAME 指向桶的 r2.dev 域名）；
3. 上传发行包与 `SHA256SUMS`；
4. （可选）用 Workers 做下载统计 / 重定向：`download.noware.cn/<version>/<file>` → R2 对象或 GitHub Releases。

同步脚本示例（GitHub Actions + rclone，将 Release 附件镜像到 R2）：

```yaml
# .github/workflows/mirror-r2.yml（示例）
name: Mirror releases to R2
on:
  release:
    types: [published]
jobs:
  mirror:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: rclone/actions/rclone-action@v1
        with:
          args: sync :s3:<bucket> --config <(echo "[s3]")  # 按需配置 R2 S3 兼容端点
```

> R2 的 S3 兼容端点与凭据在 Cloudflare Dashboard → R2 → 桶 → Settings 中查看；GitHub Secrets 中配置 `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`（即 R2 API Token）。

## 五、备用方案：Wrangler 直接上传

不想接 Git 时，可用 Wrangler 直接上传构建产物（`wrangler.toml.example`）：

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

## 环境变量与占位符

- 站点内下载链接当前指向 GitHub Releases（`https://github.com/dantesun/picket-code/releases`），版本号 `v1.143.1` 位于 `docs/guide/download.md`，发版后按需更新；
- 如需让下载按钮动态读取最新版本，可后续在 Pages Functions 中加一层 `api/latest-release`，从 GitHub API 读取最新 tag。
