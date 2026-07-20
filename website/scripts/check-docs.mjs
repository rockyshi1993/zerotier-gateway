import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const websiteDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const rootDir = resolve(websiteDir, '..');
const docsDir = join(rootDir, 'docs');
const read = (file) => readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
const errors = [];

const requiredDocs = [
  'index.md',
  'quick-start.md',
  'verification.md',
  'install.md',
  'upgrade.md',
  'ubuntu.md',
  'windows.md',
  'remote.md',
  'proxy.md',
  'exit-node.md',
  'proxy-public.md',
  'proxy-multi-server.md',
  'proxy-rules.md',
  'rate-limit.md',
  'publish-site.md',
  'relay.md',
  'troubleshooting.md',
  'security.md',
  'rollback.md',
  'release.md'
];

for (const name of requiredDocs) {
  if (!existsSync(join(docsDir, name))) {
    errors.push(`缺少文档页面: docs/${name}`);
  }
}

const markdownFiles = [
  join(rootDir, 'README.md'),
  ...readdirSync(docsDir)
    .filter((name) => extname(name) === '.md')
    .map((name) => join(docsDir, name))
];

for (const file of markdownFiles) {
  const content = read(file);
  const relative = file.slice(rootDir.length + 1).replaceAll('\\', '/');
  const fenceCount = (content.match(/^```/gm) ?? []).length;
  if (fenceCount % 2 !== 0) {
    errors.push(`${relative}: Markdown 代码块未闭合`);
  }
  if (/[A-Z]:\\(?:Users|Worker)\\/i.test(content)) {
    errors.push(`${relative}: 包含个人机器绝对路径`);
  }

  const linkPattern = /!?\[[^\]]*\]\(([^)]+)\)/g;
  for (const match of content.matchAll(linkPattern)) {
    const rawTarget = match[1].trim().replace(/^<|>$/g, '');
    if (!rawTarget || /^(?:https?:|mailto:|#|\/)/i.test(rawTarget)) {
      continue;
    }
    const target = decodeURIComponent(rawTarget.split('#', 1)[0]);
    if (!target) {
      continue;
    }
    const resolved = resolve(dirname(file), target);
    if (!existsSync(resolved)) {
      errors.push(`${relative}: 链接目标不存在 -> ${rawTarget}`);
    }
  }
}

const readme = read(join(rootDir, 'README.md'));
const readmeLines = readme.trimEnd().split('\n').length;
if (readmeLines < 120 || readmeLines > 200) {
  errors.push(`README 行数应为 120~200，当前为 ${readmeLines}`);
}

const quickStart = read(join(docsDir, 'quick-start.md'));
const stepCount = (quickStart.match(/^## \d+\. /gm) ?? []).length;
if (stepCount !== 7) {
  errors.push(`快速开始应有 7 个编号步骤，当前为 ${stepCount}`);
}

const home = read(join(docsDir, 'index.md'));
const homeFrontmatter = home.match(/^---\n([\s\S]*?)\n---/)?.[1] ?? '';
for (const match of homeFrontmatter.matchAll(/^\s*link:\s*(\/[^\s#]+)\s*$/gm)) {
  if (match[1] !== '/' && !match[1].endsWith('.html')) {
    errors.push(`首页公开任务链接必须显式对应静态 HTML: ${match[1]}`);
  }
}

const userDocs = markdownFiles
  .filter((file) => !file.endsWith('release.md'))
  .map((file) => ({ file, content: read(file) }));
const directEditPatterns = [
  /(?:编辑|打开|修改|同步|改成|填写|设置).{0,30}\.env/gi,
  /\.env.{0,30}(?:编辑|修改|同步|改成|填写|设置)/gi
];
for (const { file, content } of userDocs) {
  const relative = file.slice(rootDir.length + 1).replaceAll('\\', '/');
  for (const line of content.split('\n')) {
    if (/(?:无需|不需要|禁止|不要).{0,40}(?:\.env|配置文件)/i.test(line)) {
      continue;
    }
    for (const pattern of directEditPatterns) {
      pattern.lastIndex = 0;
      const match = line.match(pattern);
      if (match) {
        errors.push(`${relative}: 用户文档仍包含手工配置动作 -> ${match[0]}`);
      }
    }
  }
  const assignment = content.match(/^(?:PROXY|DIRECT|UBUNTU|HOME_PC|WORK_PC|RELAY|REMOTE_PORTS)[A-Z_]*=/m);
  if (assignment) {
    errors.push(`${relative}: 用户文档仍包含配置字段块 -> ${assignment[0]}`);
  }
}

const verification = read(join(docsDir, 'verification.md'));
const historicalValidationAnchors = [
  'sudo bash scripts/ubuntu/health-check.sh',
  'sudo systemctl is-active zerotier-one',
  'sudo zerotier-cli listnetworks',
  'ping -n 20 10.246.77.20',
  'ping -n 20 10.246.77.10',
  'enable-remote-desktop.ps1 -Apply',
  'Test-NetConnection 10.246.77.10 -Port 3389',
  'Test-NetConnection 10.246.77.20 -Port 3389',
  '.\\scripts\\windows\\test-proxy.ps1',
  'https://api.ipify.org',
  'https://www.google.com/generate_204'
];
for (const anchor of historicalValidationAnchors) {
  if (!verification.includes(anchor)) {
    errors.push(`安装与互访验证缺少历史关键命令: ${anchor}`);
  }
}

for (const requiredLink of ['verification.md', 'exit-node.md', 'proxy-public.md', 'proxy-multi-server.md']) {
  if (!readme.includes(requiredLink) || !quickStart.includes('verification.md') && requiredLink === 'verification.md') {
    errors.push(`README/快速开始缺少关键任务入口: ${requiredLink}`);
  }
}

for (const requiredLink of ['upgrade.md', 'rate-limit.md', 'publish-site.md']) {
  if (!readme.includes(requiredLink)) {
    errors.push(`README 缺少新增任务入口: ${requiredLink}`);
  }
}

const multiServer = read(join(docsDir, 'proxy-multi-server.md'));
for (const command of ['manage-proxy-pool.ps1 -Action Add', '127.0.0.1:20808', '-Action Enable -Apply', '-Action Status']) {
  if (!multiServer.includes(command)) errors.push(`多代理页缺少自动切换步骤: ${command}`);
}

const rateLimit = read(join(docsDir, 'rate-limit.md'));
for (const command of ['manage-rate-limit.sh add --apply', 'manage-rate-limit.sh test --name', 'manage-rate-limit.sh remove --name']) {
  if (!rateLimit.includes(command)) errors.push(`限速页缺少命令: ${command}`);
}

const exitNode = read(join(docsDir, 'exit-node.md'));
const exitNodeRequiredFacts = [
  'manage-exit-node.sh enable',
  'manage-exit-node.sh enable --apply',
  'manage-exit-node.sh status',
  'manage-exit-node.sh test',
  'manage-exit-node.sh disable --apply',
  '0.0.0.0/0',
  'Allow Default',
  '移动数据',
  '不需要开放公网 `10808/tcp`',
  'Windows 默认不会因此全局走 VPN',
  'https://api.ipify.org',
  'https://api64.ipify.org',
  'IPv4-only',
  'Ubuntu 的公网出口 IP'
];
for (const fact of exitNodeRequiredFacts) {
  if (!exitNode.includes(fact)) errors.push(`私有 Exit Node 页缺少关键事实: ${fact}`);
}
for (const consumer of [
  { file: 'docs/proxy.md', content: read(join(docsDir, 'proxy.md')) },
  { file: 'docs/proxy-public.md', content: read(join(docsDir, 'proxy-public.md')) },
  { file: 'docs/verification.md', content: verification },
  { file: 'docs/troubleshooting.md', content: read(join(docsDir, 'troubleshooting.md')) },
  { file: 'docs/security.md', content: read(join(docsDir, 'security.md')) }
]) {
  if (!consumer.content.includes('exit-node.md')) errors.push(`${consumer.file}: 缺少私有 Exit Node 入口`);
}
const windowsTemplate = read(join(rootDir, 'templates', 'windows', 'zerotier-network.local.conf.tmpl'));
if (!windowsTemplate.includes('allowDefault=0')) {
  errors.push('Windows ZeroTier 模板必须保持 allowDefault=0，避免默认全局走 Exit Node');
}

const publishSite = read(join(docsDir, 'publish-site.md'));
const publishSiteRequiredFacts = [
  '外网浏览器',
  '公网 Ubuntu',
  '网站电脑',
  '全部管理命令都在公网 Ubuntu 的仓库目录执行',
  '没有公网可达的 Ubuntu',
  '无需编辑 `.env` 或脚本文件',
  'http://203.0.113.10:18080',
  'https://site.example.com',
  '每个站点使用不同的 `--name`',
  'IP+端口模式还必须使用不同的公网端口',
  '域名模式使用不同的域名',
  '确认项目 unit、目标 TCP 和本机转发',
  '检查目标 TCP、HTTP、HTTPS 和证书',
  '不要直接公开 RDP、SSH、数据库或管理后台'
];
for (const fact of publishSiteRequiredFacts) {
  if (!publishSite.includes(fact)) errors.push(`公网站点页缺少首次成功事实: ${fact}`);
}

const publishSiteHeadings = [
  '## 先判断是否适用',
  '## 看懂连接方向',
  '## A. 公网 IP + 端口',
  '## B. 域名 + 自动 HTTPS',
  '## 添加多个站点',
  '## 更新、删除和高级配置',
  '## 实现与安全边界',
  '## 安全判断'
];
let previousPublishHeadingIndex = -1;
for (const heading of publishSiteHeadings) {
  const index = publishSite.indexOf(heading);
  if (index === -1) {
    errors.push(`公网站点页缺少章节: ${heading}`);
  } else if (index <= previousPublishHeadingIndex) {
    errors.push(`公网站点页章节顺序错误: ${heading}`);
  } else {
    previousPublishHeadingIndex = index;
  }
}

const publishSection = (start, end) => {
  const startIndex = publishSite.indexOf(start);
  if (startIndex === -1) return '';
  const endIndex = publishSite.indexOf(end, startIndex + start.length);
  return publishSite.slice(startIndex, endIndex === -1 ? publishSite.length : endIndex);
};
const requireTokensInOrder = (label, content, tokens) => {
  let offset = 0;
  for (const token of tokens) {
    const index = content.indexOf(token, offset);
    if (index === -1) {
      errors.push(`公网站点页${label}缺少或顺序错误: ${token}`);
      return;
    }
    offset = index + token.length;
  }
};

const publishIpSection = publishSection('## A. 公网 IP + 端口', '## B. 域名 + 自动 HTTPS');
requireTokensInOrder('无域名路径', publishIpSection, [
  'nc -vz 10.246.77.30 3000',
  'manage-publish.sh add-ip',
  '--name mysite',
  '--listen-port 18080',
  '--target-ip 10.246.77.30',
  '--target-port 3000',
  'manage-publish.sh add-ip',
  '--name mysite',
  '--listen-port 18080',
  '--target-ip 10.246.77.30',
  '--target-port 3000',
  '--apply',
  'manage-publish.sh status --name mysite',
  'manage-publish.sh test --name mysite',
  'http://203.0.113.10:18080'
]);

const publishDomainSection = publishSection('## B. 域名 + 自动 HTTPS', '## 添加多个站点');
requireTokensInOrder('域名路径', publishDomainSection, [
  'site.example.com',
  'TCP `80`、`443`',
  'manage-publish.sh add-domain',
  '--name mysite',
  '--domain site.example.com',
  '--target-ip 10.246.77.30',
  '--target-port 3000',
  '--staging',
  'manage-publish.sh add-domain',
  '--name mysite',
  '--domain site.example.com',
  '--target-ip 10.246.77.30',
  '--target-port 3000',
  '--staging',
  '--apply',
  'manage-publish.sh status-domain --name mysite',
  'manage-publish.sh test-domain --name mysite',
  'manage-publish.sh update-domain --name mysite --production',
  'manage-publish.sh update-domain --name mysite --production --apply',
  'https://site.example.com'
]);

for (const command of [
  'manage-publish.sh update-ip --name mysite --target-port 8080 --apply',
  'manage-publish.sh remove --name mysite --apply',
  'manage-publish.sh remove-domain --name mysite --apply',
  '--source-cidr 198.51.100.25/32',
  '--basic-auth-user visitor'
]) {
  if (!publishSite.includes(command)) errors.push(`公网站点页缺少管理命令或选项: ${command}`);
}

const changelog = read(join(rootDir, 'CHANGELOG.md'));
for (const change of ['no-restart 管理升级命令', '127.0.0.1:20808', '按客户端 IP 与代理端口', '公网 IP+端口映射']) {
  if (!changelog.includes(change)) errors.push(`CHANGELOG 未发布段缺少新增能力: ${change}`);
}

const proxyRules = read(join(docsDir, 'proxy-rules.md'));
for (const command of ['configure-proxy-rules.ps1', 'winget install sing-box', 'sing-box run -c']) {
  if (!proxyRules.includes(command)) {
    errors.push(`代理排除规则缺少可执行步骤: ${command}`);
  }
}

const relay = read(join(docsDir, 'relay.md'));
for (const command of [
  'systemctl is-active zerotier-gateway-relay-home-3389.socket',
  "ss -lntp | grep -E '10.246.77.1:(443|444)'",
  'Test-NetConnection 10.246.77.1 -Port 443',
  'nc -vz 10.246.77.10 3389'
]) {
  if (!relay.includes(command)) {
    errors.push(`中转页缺少历史关键验证命令: ${command}`);
  }
}

const install = read(join(docsDir, 'install.md'));
if ((install.match(/^```/gm) ?? []).length > 0) {
  errors.push('安装总览不应复制快速开始的完整命令块');
}

const config = read(join(websiteDir, 'rspress.config.ts'));
for (const route of requiredDocs.map((name) => name === 'index.md' ? "link: '/'" : `link: '/${name.replace(/\.md$/, '')}'`)) {
  if (route.includes("'/release'") || route.includes("'/'")) {
    continue;
  }
  if (!config.includes(route)) {
    errors.push(`Rspress sidebar 缺少路由: ${route}`);
  }
}

const release = read(join(docsDir, 'release.md'));
if (release.includes('没有 GitHub Actions 工作流')) {
  errors.push('发布文档仍声称没有 GitHub Actions，与 Pages 工作流矛盾');
}
for (const releaseFact of ['.github/workflows/pages.yml', 'npm run verify', 'Source', 'GitHub Actions']) {
  if (!release.includes(releaseFact)) errors.push(`发布文档缺少 Pages 验收事实: ${releaseFact}`);
}

const accessibility = read(join(docsDir, 'public', 'site-accessibility.js'));
for (const semantic of [".rp-home-feature__card--clickable", "setAttribute('role', 'link')", "setAttribute('tabindex', '0')", "event.key !== 'Enter' && event.key !== ' '"]) {
  if (!accessibility.includes(semantic)) errors.push(`首页任务卡片缺少键盘/语义增强: ${semantic}`);
}
if (!accessibility.includes('a[href], button, [role="link"], [role="button"]')) {
  errors.push('Rspress 交互元素缺少 Enter 冒泡保护');
}
for (const semantic of ['ztg-skip-link', "setAttribute('role', 'main')", "setAttribute('role', 'navigation')", "document.createElement('h1')", "main.id = 'main-content'"]) {
  if (!accessibility.includes(semantic)) errors.push(`站点缺少页面语义增强: ${semantic}`);
}

if (errors.length > 0) {
  console.error('文档检查失败:');
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`文档检查通过：${markdownFiles.length} 个 Markdown 文件，README ${readmeLines} 行，快速开始 ${stepCount} 步。`);
