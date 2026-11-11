import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  unclosedCodeFences,
  getMarkdownTargets,
  validateLocalMarkdownLinks,
  extractScriptRefs,
  validateScriptRefs,
  validateRspressRoutes,
  validateHomepageRoutes,
  validateKeyContracts,
  validateBehaviorContracts
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


test('source-linked behavior contracts pass and reject unsafe regressions', () => {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
  const realRead = path => readFileSync(join(root, path), 'utf8');
  assert.deepEqual(validateBehaviorContracts(realRead), []);

  function checkRegression(path, edit, expected) {
    const broken = source => source === path ? edit(realRead(source)) : realRead(source);
    const failures = validateBehaviorContracts(broken);
    assert.ok(failures.some(x => x.includes(expected)), 'Expected regression not caught: ' + expected);
  }
  checkRegression('docs/proxy-multi-server.md',
    s => s.replace('install-zerotier.sh', 'install.sh'),
    'multi-server must authorize');
  checkRegression('docs/windows.md',
    s => s.replace("show-diagnostics.ps1 -FindProcess 'ZeroTier'", 'show-diagnostics.ps1'),
    'docs/windows.md must give actionable');
  checkRegression('docs/troubleshooting.md',
    s => s.replace('不保证一定转为 DIRECT', '保证转为 DIRECT'),
    'Opening UDP 9993');
  checkRegression('scripts/windows/setup.ps1',
    s => s.replace('if ($Rollback) {', 'if ($UnsupportedRollback) {'),
    'Windows firewall rollback');
  checkRegression('scripts/ubuntu/manage-domain.sh',
    s => s.replace('certificate trust was NOT verified', 'certificate trust was verified'),
    'Domain test logs');
  checkRegression('docs/release.md',
    s => s.replace('git tag -a "$RELEASE_TAG"', 'git tag -a v1.3.0'),
    'Release guide');
});
