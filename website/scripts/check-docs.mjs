import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  REQUIRED_DOCS,
  unclosedCodeFences,
  validateLocalMarkdownLinks,
  validateScriptRefs,
  validateRspressRoutes,
  validateHomepageRoutes,
  validateKeyContracts
} from './check-docs-core.mjs';

const websiteDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const rootDir = resolve(websiteDir, '..');
const docsDir = join(rootDir, 'docs');
const read = (path) => readFileSync(join(rootDir, path), 'utf8').replace(/\r\n/g, '\n');
const errors = [];

for (const page of REQUIRED_DOCS) {
  if (!existsSync(join(docsDir, page))) errors.push(`Missing page: docs/${page}`);
}
if (errors.length) {
  console.error('Documentation check failed:\n' + errors.map(x => `- ${x}`).join('\n'));
  process.exit(1);
}

const files = [join(rootDir, 'README.md'), ...readdirSync(docsDir)
  .filter(name => extname(name) === '.md').map(name => join(docsDir, name))];
for (const file of files) {
  const rel = file.slice(rootDir.length + 1).replaceAll('\\', '/');
  const content = readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
  if (unclosedCodeFences(content)) errors.push(`${rel}: unclosed Markdown code fence`);
  for (const message of validateLocalMarkdownLinks(file, content, rootDir)) errors.push(`${rel}: ${message}`);
  for (const message of validateScriptRefs(content, rootDir)) errors.push(`${rel}: ${message}`);
  if (/[A-Z]:\\(?:Users|Worker)\\/i.test(content)) errors.push(`${rel}: personal absolute path in docs`);
}

const config = read('website/rspress.config.ts');
for (const message of validateRspressRoutes(config, docsDir)) errors.push(`rspress.config.ts: ${message}`);
for (const message of validateHomepageRoutes(read('docs/index.md'), docsDir)) errors.push(`docs/index.md: ${message}`);
for (const message of validateKeyContracts(read)) errors.push(message);

const workflow = read('.github/workflows/pages.yml');
for (const path of ['"scripts/**"', '"templates/**"', '"config/**"', '"VERSION"']) {
  if (!workflow.includes(path)) errors.push(`Pages workflow does not track changes to ${path}`);
}
if (!workflow.includes('npm run verify')) errors.push('Pages workflow must run npm run verify (includes check:built)');
if (!config.includes('/zerotier-gateway/site-accessibility.js')) {
  errors.push('Rspress static enhancement URL is not rooted under GitHub Pages base');
}

if (errors.length) {
  console.error(`Documentation check failed (${errors.length}):`);
  errors.forEach(error => console.error(`- ${error}`));
  process.exit(1);
}
console.log(`Documentation static checks passed: ${files.length} Markdown files; route, script, version and safety contracts checked.`);
