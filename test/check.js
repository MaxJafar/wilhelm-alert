#!/usr/bin/env node
// Guards the traps this project actually fell into, rather than testing
// things that were never going to break. Every check below corresponds to a
// bug that shipped at least once.
//
//   pnpm check
//
// Skips gracefully when a toolchain is missing (no Swift on Linux, no
// PowerShell on a bare Mac) so it stays useful everywhere.

'use strict';

const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const results = { pass: 0, fail: 0, skip: 0 };

const green = (s) => (process.stdout.isTTY ? `\x1b[32m${s}\x1b[0m` : s);
const red = (s) => (process.stdout.isTTY ? `\x1b[31m${s}\x1b[0m` : s);
const grey = (s) => (process.stdout.isTTY ? `\x1b[90m${s}\x1b[0m` : s);

function ok(label) {
  results.pass += 1;
  console.log(`  ${green('ok')}   ${label}`);
}
function fail(label, detail) {
  results.fail += 1;
  console.log(`  ${red('FAIL')} ${label}`);
  if (detail) String(detail).split('\n').forEach((l) => console.log(`         ${l}`));
}
function skip(label, why) {
  results.skip += 1;
  console.log(`  ${grey('skip')} ${label} ${grey(`(${why})`)}`);
}
function section(name) {
  console.log(`\n${name}`);
}
function check(label, fn) {
  try {
    const problem = fn();
    if (problem) fail(label, problem);
    else ok(label);
  } catch (err) {
    fail(label, err.message);
  }
}
function has(command) {
  const probe = process.platform === 'win32' ? 'where' : 'which';
  return spawnSync(probe, [command], { stdio: 'ignore' }).status === 0;
}
function readJson(rel) {
  return JSON.parse(fs.readFileSync(path.join(ROOT, rel), 'utf8'));
}

// ------------------------------------------------------------- manifests

section('Manifests');

const MANIFESTS = [
  'package.json',
  '.claude-plugin/plugin.json',
  '.claude-plugin/marketplace.json',
  '.codex-plugin/plugin.json',
  '.agents/plugins/marketplace.json',
  'hooks/hooks.json',
];

for (const file of MANIFESTS) {
  check(`${file} is valid JSON`, () => {
    readJson(file);
    return null;
  });
}

// A plugin cache is keyed by version. If the manifests disagree, an agent can
// sit on a stale copy while the repo looks updated.
check('versions agree across manifests', () => {
  const versions = {
    'package.json': readJson('package.json').version,
    '.claude-plugin/plugin.json': readJson('.claude-plugin/plugin.json').version,
    '.codex-plugin/plugin.json': readJson('.codex-plugin/plugin.json').version,
  };
  const distinct = [...new Set(Object.values(versions))];
  if (distinct.length !== 1) {
    return Object.entries(versions).map(([f, v]) => `${f} = ${v}`).join('\n');
  }
  return null;
});

// ------------------------------------------------------------ hook events

section('Hook events');

// SessionEnd fires on teardown — including reason=resume when another
// instance takes the session over — so hooking it screamed on app launch.
const FORBIDDEN_EVENTS = ['SessionEnd', 'SessionStart', 'Notification', 'PreCompact'];

check('hooks.json only hooks end-of-turn events', () => {
  const events = Object.keys(readJson('hooks/hooks.json').hooks || {});
  const bad = events.filter((e) => FORBIDDEN_EVENTS.includes(e));
  if (bad.length) return `hooks these non-completion events: ${bad.join(', ')}`;
  if (!events.includes('Stop')) return 'no Stop hook at all';
  return null;
});

check('hook command is cross-platform', () => {
  const raw = fs.readFileSync(path.join(ROOT, 'hooks/hooks.json'), 'utf8');
  // A bare path to the shell shim can't run on Windows; it has to go via node.
  if (!raw.includes('node ')) return 'hook does not invoke node, so it cannot run on Windows';
  if (!raw.includes('${CLAUDE_PLUGIN_ROOT}')) return 'hook does not use ${CLAUDE_PLUGIN_ROOT}';
  return null;
});

// -------------------------------------------------------- script shadowing

section('pnpm script names');

if (!has('pnpm')) {
  skip('script names are not pnpm built-ins', 'pnpm not installed');
} else {
  const scripts = Object.keys(readJson('package.json').scripts || {});
  const shadowed = [];
  let probeWorked = false;

  for (const name of scripts) {
    if (name === 'postinstall') continue; // lifecycle hook, never typed by hand
    // pnpm is a .cmd on Windows, which Node cannot spawn without a shell.
    const out = spawnSync('pnpm', ['help', name], { encoding: 'utf8', shell: process.platform === 'win32' });
    const text = `${out.stdout || ''}${out.stderr || ''}`;
    // A built-in prints its own usage; anything else reports no match. An
    // empty result means the probe never ran, so treat it as unknown rather
    // than reporting every script as shadowed.
    if (!text.trim()) continue;
    probeWorked = true;
    if (!text.includes('No results')) shadowed.push(name);
  }

  if (!probeWorked) {
    skip('script names are not pnpm built-ins', 'could not run pnpm help');
  } else {
    check('script names are not pnpm built-ins', () =>
      shadowed.length
        ? `pnpm would run its own command instead of these scripts: ${shadowed.join(', ')}`
        : null
    );
  }
}

// -------------------------------------------------------------- filesystem

section('Files');

check('every bin entry exists', () => {
  const bins = readJson('package.json').bin || {};
  const missing = Object.entries(bins)
    .filter(([, rel]) => !fs.existsSync(path.join(ROOT, rel)))
    .map(([name, rel]) => `${name} -> ${rel}`);
  return missing.length ? missing.join('\n') : null;
});

check('shell entry points are executable', () => {
  if (process.platform === 'win32') return null; // no POSIX mode bits
  const scripts = ['bin/wilhelm-alert', 'bin/wilhelm-build', 'bin/wilhelm-app',
                   'bin/wilhelm-settings', 'bin/wilhelm-face', 'bin/wilhelm-update',
                   'bin/wilhelm-log'];
  const notExecutable = scripts.filter((rel) => {
    const full = path.join(ROOT, rel);
    if (!fs.existsSync(full)) return true;
    return !(fs.statSync(full).mode & 0o111);
  });
  return notExecutable.length ? `not executable: ${notExecutable.join(', ')}` : null;
});

check('every agent in the roster has a face', () => {
  const sources = ['claude', 'codex', 'cursor', 'antigravity', 'openclaw'];
  const missing = sources.filter(
    (s) => !fs.existsSync(path.join(ROOT, 'assets', `scream-${s}.png`))
  );
  return missing.length ? `no face for: ${missing.join(', ')}` : null;
});

// ----------------------------------------------------------------- syntax

section('Syntax');

const JS_FILES = [
  'bin/wilhelm.js', 'bin/wilhelm-alert.js', 'bin/wilhelm-log.js',
  'bin/wilhelm-postinstall.js', 'test/check.js',
];
for (const file of JS_FILES) {
  check(`${file} parses`, () => {
    const out = spawnSync(process.execPath, ['--check', path.join(ROOT, file)], { encoding: 'utf8' });
    return out.status === 0 ? null : (out.stderr || '').trim();
  });
}

const PS_FILES = [
  'app/Settings.ps1', 'app/overlay-windows.ps1',
  'bin/wilhelm-update.ps1', 'bin/wilhelm-app.ps1', 'bin/wilhelm-face.ps1',
];
const pwsh = ['pwsh', 'powershell'].find(has);
if (!pwsh) {
  skip(`${PS_FILES.length} PowerShell scripts parse`, 'no PowerShell available');
} else {
  for (const file of PS_FILES) {
    check(`${file} parses`, () => {
      const script =
        `$e=$null;[System.Management.Automation.Language.Parser]::ParseFile(` +
        `'${path.join(ROOT, file).replace(/'/g, "''")}',[ref]$null,[ref]$e)|Out-Null;` +
        `if($e.Count){$e|ForEach-Object{Write-Output ("line "+$_.Extent.StartLineNumber+": "+$_.Message)};exit 1}`;
      const out = spawnSync(pwsh, ['-NoProfile', '-Command', script], { encoding: 'utf8' });
      return out.status === 0 ? null : (out.stdout || out.stderr || '').trim();
    });
  }
}

if (!has('python3')) {
  skip('app/overlay-linux.py parses', 'python3 not available');
} else {
  check('app/overlay-linux.py parses', () => {
    const out = spawnSync('python3', ['-m', 'py_compile', path.join(ROOT, 'app/overlay-linux.py')], {
      encoding: 'utf8',
    });
    return out.status === 0 ? null : (out.stderr || '').trim();
  });
}

// -------------------------------------------------------------------- XAML

section('Windows panel');

const settingsSource = fs.readFileSync(path.join(ROOT, 'app/Settings.ps1'), 'utf8');

check('every FindName lookup exists in the XAML', () => {
  const declared = new Set(
    [...settingsSource.matchAll(/x:Name="([^"]+)"/g)].map((m) => m[1])
  );
  const looked = [...settingsSource.matchAll(/FindName\('([^']+)'\)/g)].map((m) => m[1]);
  const missing = [...new Set(looked)].filter((n) => !declared.has(n));
  return missing.length ? `looked up but never declared: ${missing.join(', ')}` : null;
});

check('XAML tags are balanced', () => {
  const match = settingsSource.match(/\$xaml = @'\r?\n([\s\S]*?)\r?\n'@/);
  if (!match) return 'could not locate the XAML here-string';
  const xaml = match[1];
  const stack = [];
  const tag = /<\/?([A-Za-z][\w.:]*)([^>]*?)(\/?)>/g;
  let m;
  while ((m = tag.exec(xaml)) !== null) {
    const [full, name, , selfClosing] = m;
    if (full.startsWith('<!--')) continue;
    if (full.startsWith('</')) {
      if (stack.pop() !== name) return `closing </${name}> does not match the open tag`;
    } else if (!selfClosing) {
      stack.push(name);
    }
  }
  return stack.length ? `never closed: <${stack.join('>, <')}>` : null;
});

// --------------------------------------------------------------- behaviour

section('Alert behaviour');

// Run against throwaway config/state so a developer's real history and mode
// are never touched by the test suite.
const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'wilhelm-check-'));
const sandboxEnv = {
  ...process.env,
  XDG_STATE_HOME: path.join(sandbox, 'state'),
  XDG_CONFIG_HOME: path.join(sandbox, 'config'),
  LOCALAPPDATA: path.join(sandbox, 'state'),
  APPDATA: path.join(sandbox, 'config'),
  WILHELM_ALERT_MODE: 'light', // never open a window during tests
};

function runAlert(payload, extraArgs = []) {
  return spawnSync(process.execPath, [path.join(ROOT, 'bin/wilhelm-alert.js'), ...extraArgs], {
    input: payload === null ? '' : JSON.stringify(payload),
    env: sandboxEnv,
    encoding: 'utf8',
  });
}

function historyEntries() {
  const file = path.join(sandbox, 'state', 'wilhelm-alert', 'history.jsonl');
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l));
}

check('a Stop event fires the alert', () => {
  const out = runAlert({ hook_event_name: 'Stop', session_id: 'test0001' }, ['--force']);
  if (out.status !== 0) return `exited ${out.status}`;
  const last = historyEntries().at(-1);
  return last && last.fired ? null : 'nothing was recorded as fired';
});

check('SessionEnd(resume) is suppressed', () => {
  const out = runAlert({ hook_event_name: 'SessionEnd', reason: 'resume', session_id: 'test0002' });
  if (out.status !== 0) return `exited ${out.status}`;
  const last = historyEntries().at(-1);
  if (!last) return 'nothing was recorded at all';
  return last.fired ? 'it screamed on session teardown' : null;
});

check('a repeat within the debounce window is suppressed', () => {
  runAlert({ hook_event_name: 'Stop', session_id: 'test0003' }, ['--force']);
  const out = runAlert({ hook_event_name: 'Stop', session_id: 'test0003' });
  if (out.status !== 0) return `exited ${out.status}`;
  const last = historyEntries().at(-1);
  return last && !last.fired ? null : 'a second stop screamed immediately after the first';
});

check('every failure path still exits 0', () => {
  const cases = [
    ['unknown mode', ['--mode', 'nonsense', '--force']],
    ['missing sound', ['--sound', '/definitely/not/here.wav', '--force']],
    ['garbage on stdin', ['--force']],
  ];
  const broken = [];
  for (const [name, args] of cases) {
    const out = spawnSync(process.execPath, [path.join(ROOT, 'bin/wilhelm-alert.js'), ...args], {
      input: name === 'garbage on stdin' ? 'not json at all' : '',
      env: sandboxEnv,
      encoding: 'utf8',
    });
    // A non-zero exit here would break the calling agent's hook chain.
    if (out.status !== 0) broken.push(`${name} exited ${out.status}`);
  }
  return broken.length ? broken.join('\n') : null;
});

fs.rmSync(sandbox, { recursive: true, force: true });

// ------------------------------------------------------------------ report

const total = results.pass + results.fail + results.skip;
console.log(
  `\n${results.pass}/${total} passed` +
    (results.skip ? `, ${results.skip} skipped` : '') +
    (results.fail ? `, ${red(`${results.fail} failed`)}` : '')
);
process.exit(results.fail ? 1 : 0);
