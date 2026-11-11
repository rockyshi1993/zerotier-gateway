import { existsSync } from 'node:fs';
import { dirname, extname, isAbsolute, relative, resolve, sep } from 'node:path';

// This module contains pure-ish document checks that are testable without Rspress.
// Avoid checks that enforce prose lengths, numbered-step counts, or particular legacy wording.
export const REQUIRED_DOCS = [
  'index.md', 'install.md', 'quick-start.md', 'verification.md', 'ubuntu.md',
  'windows.md', 'remote.md', 'proxy.md', 'exit-node.md', 'proxy-public.md',
  'proxy-multi-server.md', 'proxy-rules.md', 'rate-limit.md', 'publish-site.md',
  'relay.md', 'troubleshooting.md', 'security.md', 'upgrade.md', 'rollback.md', 'release.md'
];

export function unclosedCodeFences(markdown) {
  // Match actual fence delimiters on their own lines, not literal text inside snippets.
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  let fence = null;
  for (const line of lines) {
    const match = line.match(/^\s{0,3}(`{3,}|~{3,})(?:\s*[^`~]*)?$/);
    if (!match) continue;
    const marker = match[1][0], length = match[1].length;
    if (!fence) fence = { marker, length };
    else if (fence.marker === marker && length >= fence.length) fence = null;
  }
  return Boolean(fence);
}

export function stripCodeFences(markdown) {
  // Prevent code examples such as [example](...) from being interpreted as document links.
  return markdown.replace(/^\s{0,3}(```|~~~)[^\n]*\n[\s\S]*?^\s{0,3}\1\s*$/gm, '');
}

export function getMarkdownTargets(markdown) {
  const content = stripCodeFences(markdown);
  const targets = [];
  for (const match of content.matchAll(/!?\[[^\]]*\]\(([^)]+)\)/g)) {
    targets.push(match[1].trim().replace(/^<|>$/g, ''));
  }
  return targets;
}

export function validateLocalMarkdownLinks(file, markdown, rootDir) {
  const failures = [];
  for (const raw of getMarkdownTargets(markdown)) {
    if (!raw || /^(?:https?:|mailto:|data:|#)/i.test(raw)) continue;
    // Root-relative URLs are Rspress routes; validated against the config and built site separately.
    if (raw.startsWith('/')) continue;
    let target;
    try { target = decodeURIComponent(raw.split(/[?#]/, 1)[0]); }
    catch { failures.push(`Invalid URL encoding: ${raw}`); continue; }
    if (!target) continue;
    const candidate = resolve(dirname(file), target);
    const back = relative(rootDir, candidate);
    if (isAbsolute(back) || back === '..' || back.startsWith(`..${sep}`)) {
      failures.push(`Link escapes project: ${raw}`);
    } else if (!existsSync(candidate)) {
      failures.push(`Missing target: ${raw}`);
    }
  }
  return failures;
}

export function extractScriptRefs(markdown) {
  const normalized = markdown.replaceAll('\\', '/');
  const refs = new Set();
  for (const hit of normalized.matchAll(/(scripts\/(?:ubuntu|windows)\/[\w./-]+\.(?:sh|ps1))/gm)) {
    refs.add(hit[1].replace(/^\.\//, ''));
  }
  return [...refs];
}

export function validateScriptRefs(markdown, rootDir) {
  return extractScriptRefs(markdown)
    .filter((item) => !existsSync(resolve(rootDir, item)))
    .map((item) => `Referenced script missing: ${item}`);
}

export function extractRspressRoutes(config) {
  const routes = new Set();
  for (const hit of config.matchAll(/\blink:\s*['"](\/[^'"]+)['"]/g)) routes.add(hit[1]);
  return [...routes];
}

export function validateRspressRoutes(config, docsDir) {
  return extractRspressRoutes(config)
    .filter((route) => !route.includes('*'))
    .map((route) => route.replace(/[?#].*$/, '').replace(/\.html$/, ''))
    .filter((route) => route !== '/' && !existsSync(resolve(docsDir, `${route.replace(/^\//, '')}.md`)))
    .map((route) => `Navigation route does not exist: ${route}`);
}

export function validateHomepageRoutes(homeMarkdown, docsDir) {
  const failures = [];
  const fm = homeMarkdown.match(/^---\n([\s\S]*?)\n---/)?.[1] || '';
  for (const hit of fm.matchAll(/^\s*link:\s*(\/[^\s#]+)\s*$/gm)) {
    const page = hit[1].replace(/^\//, '').replace(/\.html$/, '');
    if (page && !existsSync(resolve(docsDir, `${page}.md`))) failures.push(`Home route missing: ${hit[1]}`);
  }
  return failures;
}

export function validateKeyContracts(read) {
  const failures = [];
  const requireContent = (path, tokens) => {
    const source = read(path);
    for (const token of tokens) if (!source.includes(token)) failures.push(`${path} missing contract: ${token}`);
  };
  requireContent('docs/quick-start.md', ['install-zerotier.sh', 'install-proxy.sh', 'zerotier-cli listnetworks', 'api.ipify.org']);
  const start = read('docs/quick-start.md');
  if (start.indexOf('install-zerotier.sh') >= start.indexOf('install-proxy.sh')) {
    failures.push('Quick start must authorize ZeroTier before binding sing-box to the managed IP');
  }
  requireContent('docs/remote.md', ['不需要 Ubuntu', 'ZeroTier', 'RDP']);
  requireContent('docs/exit-node.md', ['0.0.0.0/0', 'Allow Default', 'disable --apply', 'https://api.ipify.org', 'https://api64.ipify.org', 'Central', 'Android']);
  requireContent('docs/proxy-public.md', ['TLS', '认证', '安全组']);
  requireContent('docs/security.md', ['TLS', '凭据', 'UFW', 'allowDefault=0']);
  requireContent('docs/proxy-rules.md', ['DirectDomainSuffixes', 'domain_suffix', 'PAC', 'sing-box']);
  requireContent('docs/rollback.md', ['Allow Default', 'Central', 'disable --apply']);
  const version = read('VERSION').trim();
  if (!version) failures.push('VERSION is blank');
  if (version && !read('README.md').includes(version)) failures.push(`README does not declare current version: ${version}`);
  if (version && !read('docs/index.md').includes(version)) failures.push(`Home does not declare current version: ${version}`);
  return failures;
}


// Source-linked guardrails complement (rather than replace) executable OS tests.
// Do not use prose-length or step-number constraints as correctness proofs.
export function validateBehaviorContracts(read) {
  const errors = [];
  const multi = read('docs/proxy-multi-server.md');
  const quick = read('docs/quick-start.md');
  const trouble = read('docs/troubleshooting.md');
  const windows = read('docs/windows.md');
  const upgrade = read('docs/upgrade.md');
  const publish = read('docs/publish-site.md');
  const rollbackDoc = read('docs/rollback.md');
  const release = read('docs/release.md');
  const setup = read('scripts/windows/setup.ps1');
  const domain = read('scripts/ubuntu/manage-domain.sh');

  for (const [label, source] of [['quick-start', quick], ['multi-server', multi]]) {
    // Only executable command lines count; prose mentioning a script is not evidence
    // that the install guide actually instructs users to run it.
    const join = source.search(/^\s*sudo bash scripts\/ubuntu\/install-zerotier\.sh(?:\s|$)/m);
    const proxy = source.search(/^\s*sudo bash scripts\/ubuntu\/install-proxy\.sh(?:\s|$)/m);
    if (join < 0 || proxy < 0 || join >= proxy ||
        source.indexOf('zerotier-cli listnetworks', join) > proxy ||
        !source.includes('zerotier-cli listnetworks')) {
      errors.push(label + ' must authorize and inspect ZeroTier before installing sing-box');
    }
  }
  if (!multi.includes('PAC / 本地分流客户端接入节点池尚无自动组合流程')) {
    errors.push('Multi-server guide must not claim automatic PAC/local-rules proxy-pool integration');
  }
  if (multi.includes('按提示把代理入口设为')) {
    errors.push('Multi-server guide uses an unsupported init-config proxy-pool selection');
  }

  for (const [path, source] of [['docs/windows.md', windows], ['docs/upgrade.md', upgrade]]) {
    if (/^\s*\.\\scripts\\windows\\show-diagnostics\.ps1\s*$/m.test(source) ||
        !/^\s*\.\\scripts\\windows\\show-diagnostics\.ps1\s+-FindProcess\b/m.test(source)) {
      errors.push(path + ' must give actionable show-diagnostics.ps1 parameters');
    }
  }
  if (/^\s*sudo bash scripts\/ubuntu\/install\.sh(?:\s|$)/m.test(trouble)) {
    errors.push('Proxy troubleshooting must not blindly rerun the full gateway installer');
  }
  if (/对端应变为 .*DIRECT/.test(trouble) || !trouble.includes('不保证一定转为 DIRECT')) {
    errors.push('Opening UDP 9993 must not promise a DIRECT connection');
  }
  if (!trouble.includes('公网 mixed 代理没有内建 TLS')) {
    errors.push('Troubleshooting must not recommend unencrypted public proxy as a generic speed fix');
  }

  if (!publish.includes('staging 时') || !publish.includes('curl --insecure') ||
      !publish.includes('生产检查不使用') || !publish.includes('证书链')) {
    errors.push('Domain publishing docs must distinguish staging handshake from trusted production TLS');
  }
  if (!domain.includes('curl_tls+=(--insecure)') ||
      !domain.includes('certificate trust was NOT verified') ||
      !domain.includes('certificate verification enabled')) {
    errors.push('Domain test logs must distinguish staging (insecure) from production certificate verification');
  }

  const rollbackPos = setup.indexOf('if ($Rollback) {');
  const envPos = setup.indexOf('$config = Read-ZtgEnv');
  if (rollbackPos < 0 || envPos < 0 || rollbackPos > envPos ||
      !setup.slice(rollbackPos, envPos).includes('Remove-ZtgFirewallRules')) {
    errors.push('Windows firewall rollback must run without requiring a valid .env');
  }
  if (!rollbackDoc.includes('不依赖 ' + String.fromCharCode(96) + '.env' + String.fromCharCode(96))) {
    errors.push('Rollback docs must describe config-independent Windows cleanup');
  }
  if (!release.includes('RELEASE_TAG') || /git tag -a v1\.3\.0/.test(release)) {
    errors.push('Release guide must not instruct recreating the existing v1.3.0 tag');
  }
  return errors;
}
