import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import {
  unclosedCodeFences,
  getMarkdownTargets,
  validateLocalMarkdownLinks,
  extractScriptRefs,
  validateScriptRefs,
  validateRspressRoutes,
  validateHomepageRoutes,
  validateKeyContracts
} from './check-docs-core.mjs';

function fixture(fn) {
  const dir = mkdtempSync(join(tmpdir(), 'ztg-docs-test-'));
  const put = (path, content = '') => { const file = join(dir, path); mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, content); return file; };
  try { return fn(dir, put); } finally { rmSync(dir, { recursive: true, force: true }); }
}

test('paired/unpaired fenced blocks use correct delimiters', () => {
  assert.equal(unclosedCodeFences('# H\n```bash\na\n```\n'), false);
  assert.equal(unclosedCodeFences('```powershell\na\n'), true);
  assert.equal(unclosedCodeFences('~~~\na\n~~~'), false);
});

test('Markdown links inside code blocks are ignored but actual broken links fail', () => fixture((dir, put) => {
  const file = put('docs/index.md', ''); put('docs/ok.md', '# ok');
  assert.deepEqual(getMarkdownTargets('```\n[pretend](missing.md)\n```\n[good](ok.md)'), ['ok.md']);
  assert.deepEqual(validateLocalMarkdownLinks(file, '[good](ok.md)', dir), []);
  assert.deepEqual(validateLocalMarkdownLinks(file, '[bad](missing.md)', dir), ['Missing target: missing.md']);
  assert.deepEqual(validateLocalMarkdownLinks(file, '[bad](../../../outside.md)', dir), ['Link escapes project: ../../../outside.md']);
}));

test('Windows paths are normalized and source paths are checked', () => fixture((dir, put) => {
  put('scripts/windows/init-config.ps1', '');
  assert.deepEqual(extractScriptRefs('.\\scripts\\windows\\init-config.ps1'), ['scripts/windows/init-config.ps1']);
  assert.deepEqual(validateScriptRefs('.\\scripts\\windows\\init-config.ps1', dir), []);
  assert.deepEqual(validateScriptRefs('bash scripts/ubuntu/unknown.sh', dir), ['Referenced script missing: scripts/ubuntu/unknown.sh']);
}));

test('Rspress navigation and homepage routes are independently validated', () => fixture((dir, put) => {
  put('docs/quick-start.md', '');
  assert.deepEqual(validateRspressRoutes("{ link: '/quick-start' }", join(dir, 'docs')), []);
  assert.deepEqual(validateRspressRoutes("{ link: '/missing' }", join(dir, 'docs')), ['Navigation route does not exist: /missing']);
  assert.deepEqual(validateHomepageRoutes('---\nhero:\n  actions:\n    - link: /quick-start.html\n---', join(dir, 'docs')), []);
  assert.deepEqual(validateHomepageRoutes('---\n  link: /missing.html\n---', join(dir, 'docs')), ['Home route missing: /missing.html']);
}));

test('quick-start order and version mismatches are rejected', () => {
  const sample = {
    'docs/quick-start.md':'install-proxy.sh then install-zerotier.sh; zerotier-cli listnetworks; api.ipify.org',
    'docs/remote.md':'不需要 Ubuntu ZeroTier RDP',
    'docs/exit-node.md':'0.0.0.0/0 Allow Default disable --apply https://api.ipify.org https://api64.ipify.org Central Android',
    'docs/proxy-public.md':'TLS 认证 安全组',
    'docs/security.md':'TLS 凭据 UFW allowDefault=0',
    'docs/proxy-rules.md':'DirectDomainSuffixes domain_suffix PAC sing-box',
    'docs/rollback.md':'Allow Default Central disable --apply',
    'VERSION':'1.4.0-dev',
    'README.md':'older version',
    'docs/index.md':'older version'
  };
  const failures = validateKeyContracts(path => sample[path]);
  assert.ok(failures.some(x => x.includes('before binding sing-box')));
  assert.ok(failures.some(x => x.includes('README does not declare current version')));
});
