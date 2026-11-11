import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { REQUIRED_DOCS } from './check-docs-core.mjs';

const websiteDir = resolve(import.meta.dirname, '..');
const distDir = join(websiteDir, 'dist');
const base = '/zerotier-gateway/';
const failures = [];
const page = (name) => join(distDir, name);
if (!existsSync(page('index.html'))) failures.push('Missing index.html');

for (const markdown of REQUIRED_DOCS) {
  if (markdown === 'index.md') continue;
  const html = markdown.replace(/\.md$/, '.html');
  if (!existsSync(page(html))) failures.push(`Missing built route: ${html}`);
}

const asset = page('site-accessibility.js');
if (!existsSync(asset)) failures.push('Static site-accessibility.js not copied from docs/public');

if (existsSync(distDir)) {
  const htmlFiles = readdirSync(distDir).filter(file => file.endsWith('.html') && file !== '404.html');
  for (const name of htmlFiles) {
    const content = readFileSync(page(name), 'utf8');
    // Avoid false positives for third-party assets or absolute external URLs.
    for (const match of content.matchAll(/\b(?:href|src)=(['"])(.*?)\1/g)) {
      const raw = match[2];
      if (!raw.startsWith(base)) continue;
      let pathname;
      try { pathname = decodeURIComponent(raw.slice(base.length).split(/[?#]/, 1)[0]); }
      catch { failures.push(`${name}: invalid URL encoding ${raw}`); continue; }
      if (!pathname) pathname = 'index.html';
      if (pathname.endsWith('/')) pathname += 'index.html';
      if (!existsSync(page(pathname))) failures.push(`${name}: broken built URL ${raw}`);
    }
    if (!content.includes(`${base}site-accessibility.js`)) {
      failures.push(`${name}: missing base-rooted accessibility asset`);
    }
  }
  if (!htmlFiles.length) failures.push('No generated HTML pages');
}

if (failures.length) {
  console.error(`Built documentation validation failed (${failures.length}):`);
  failures.forEach(message => console.error(`- ${message}`));
  process.exit(1);
}
console.log('Built site validation passed: all expected static routes and referenced GitHub Pages assets exist.');
