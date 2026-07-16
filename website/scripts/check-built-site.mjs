import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const websiteDir = resolve(import.meta.dirname, '..');
const distDir = join(websiteDir, 'dist');
const indexPath = join(distDir, 'index.html');
const errors = [];

if (!existsSync(indexPath)) {
  errors.push('缺少构建首页: website/dist/index.html');
} else {
  const html = readFileSync(indexPath, 'utf8');
  const internalLinks = new Set(
    [...html.matchAll(/href="(\/zerotier-gateway\/[^"?#]*)/g)].map((match) => match[1])
  );
  for (const href of internalLinks) {
    const relative = href.slice('/zerotier-gateway/'.length);
    const target = relative === '' ? join(distDir, 'index.html') : join(distDir, relative);
    if (!existsSync(target)) errors.push(`生成首页链接没有静态目标: ${href}`);
  }
  for (const route of ['quick-start','remote','proxy']) {
    const href = `/zerotier-gateway/${route}.html`;
    if (!html.includes(`href="${href}"`)) errors.push(`生成首页缺少可直达链接: ${href}`);
  }
  for (const route of ['quick-start','remote','proxy','verification','proxy-multi-server','rate-limit','publish-site']) {
    if (!existsSync(join(distDir, `${route}.html`))) errors.push(`首页任务没有生成静态目标: ${route}.html`);
  }
  if (!html.includes('site-accessibility.js')) errors.push('生成首页没有加载无障碍增强脚本');
}

if (errors.length > 0) {
  console.error('构建站点检查失败:');
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log('构建站点检查通过：首页公开链接均对应静态文件。');
