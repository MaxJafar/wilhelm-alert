#!/usr/bin/env node
// Dispatches a task to whichever implementation this OS has, so the pnpm
// scripts are identical everywhere and the docs don't need a Windows column
// for every command.
//
//   node bin/wilhelm.js app|panel|update|face

'use strict';

const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const target = process.argv[2];
const rest = process.argv.slice(3);

const POSIX = {
  app: ['bin/wilhelm-app', ['--open']],
  panel: ['bin/wilhelm-settings', []],
  update: ['bin/wilhelm-update', []],
  face: ['bin/wilhelm-face', []],
  build: ['bin/wilhelm-build', ['overlay']],
};

const WINDOWS = {
  app: 'bin/wilhelm-app.ps1',
  panel: 'app/Settings.ps1',
  update: 'bin/wilhelm-update.ps1',
  face: 'bin/wilhelm-face.ps1',
  // Nothing to compile: the Windows overlay and panel are both scripts.
  build: null,
};

if (!target || !(target in POSIX)) {
  process.stderr.write(`usage: wilhelm.js <${Object.keys(POSIX).join('|')}>\n`);
  process.exit(2);
}

function run(command, args) {
  const result = spawnSync(command, args, { stdio: 'inherit', cwd: ROOT });
  process.exit(result.status === null ? 1 : result.status);
}

if (process.platform === 'win32') {
  if (WINDOWS[target] === null) {
    process.stdout.write('Nothing to build on Windows — the overlay and panel are scripts.\n');
    process.exit(0);
  }
  const script = path.join(ROOT, WINDOWS[target]);
  if (!fs.existsSync(script)) {
    process.stderr.write(`wilhelm: ${target} is not available on Windows yet.\n`);
    process.exit(1);
  }
  // -Root keeps the scripts working no matter where they're invoked from.
  run('powershell', [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', script,
    '-Root', ROOT,
    ...rest,
  ]);
}

if (process.platform === 'darwin') {
  const [script, defaults] = POSIX[target];
  run(path.join(ROOT, script), [...defaults, ...rest]);
}

// Linux has the alert, the overlay and the log, but no panel to open.
// Linux has the alert, the overlay and the log — but no panel to open.
if (target === 'update') {
  run(path.join(ROOT, 'bin/wilhelm-update'), rest);
}
if (target === 'build') {
  process.stdout.write('Nothing to build on Linux — the overlay is a script.\n');
  process.exit(0);
}

const linuxHint = {
  app: 'There is no Linux panel yet.',
  panel: 'There is no Linux panel yet.',
  face: 'Save images to assets/scream-<agent>.png by hand.',
};

process.stderr.write(
  `wilhelm: ${linuxHint[target] || 'Not available on this platform.'}\n` +
    `  Set your mode directly instead:\n` +
    `    mkdir -p ~/.config/wilhelm-alert\n` +
    `    echo 'mode=turbo' > ~/.config/wilhelm-alert/config\n`
);
process.exit(1);
