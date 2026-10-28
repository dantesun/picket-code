// 构建后处理：移除未被使用的字体 preload 标签，消除浏览器控制台警告
import { readdir, readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

const distDir = join(process.cwd(), 'docs/.vitepress/dist')
const pattern = /<link rel="preload" href="[^"]*\.woff2"[^>]*>\n?/g

async function walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name)
    if (entry.isDirectory()) {
      await walk(p)
    } else if (entry.name.endsWith('.html')) {
      const html = await readFile(p, 'utf8')
      const next = html.replace(pattern, '')
      if (next !== html) {
        await writeFile(p, next)
        console.log('[postbuild] stripped woff2 preload:', p.replace(distDir, ''))
      }
    }
  }
}

walk(distDir)
