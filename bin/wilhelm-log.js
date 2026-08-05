#!/usr/bin/env node
// Shows why the scream did or didn't fire.
//
//   wilhelm-log              last 25 entries
//   wilhelm-log --all        everything kept
//   wilhelm-log --fired      only the ones that screamed
//   wilhelm-log --skipped    only the ones that were suppressed
//   wilhelm-log --path       print the log file location
//   wilhelm-log --clear      wipe the history

'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

function stateDir() {
  if (process.platform === 'win32') {
    const base = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
    return path.join(base, 'wilhelm-alert');
  }
  const base = process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local', 'state');
  return path.join(base, 'wilhelm-alert');
}

const HISTORY_FILE = path.join(stateDir(), 'history.jsonl');
const flags = new Set(process.argv.slice(2).filter((a) => a.startsWith('--')));

if (flags.has('--path')) {
  process.stdout.write(`${HISTORY_FILE}\n`);
  process.exit(0);
}

if (flags.has('--clear')) {
  try {
    fs.rmSync(HISTORY_FILE);
    process.stdout.write('History cleared.\n');
  } catch {
    process.stdout.write('Nothing to clear.\n');
  }
  process.exit(0);
}

let lines;
try {
  lines = fs.readFileSync(HISTORY_FILE, 'utf8').trim().split('\n').filter(Boolean);
} catch {
  process.stdout.write(
    'No history yet.\n' +
      'The log is written whenever an agent hook runs — finish a task and check again.\n'
  );
  process.exit(0);
}

let entries = lines
  .map((line) => {
    try {
      return JSON.parse(line);
    } catch {
      return null;
    }
  })
  .filter(Boolean);

if (flags.has('--fired')) entries = entries.filter((e) => e.fired);
if (flags.has('--skipped')) entries = entries.filter((e) => !e.fired);
if (!flags.has('--all')) entries = entries.slice(-25);

if (!entries.length) {
  process.stdout.write('No matching entries.\n');
  process.exit(0);
}

// ANSI only when attached to a terminal, so piping to a file stays clean.
const tty = process.stdout.isTTY;
const dim = (s) => (tty ? `\x1b[2m${s}\x1b[0m` : s);
const bold = (s) => (tty ? `\x1b[1m${s}\x1b[0m` : s);
const green = (s) => (tty ? `\x1b[32m${s}\x1b[0m` : s);
const grey = (s) => (tty ? `\x1b[90m${s}\x1b[0m` : s);

const localTime = (iso) => {
  try {
    return new Date(iso).toLocaleString(undefined, {
      month: 'short',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  } catch {
    return iso;
  }
};

process.stdout.write(`\n${bold('wilhelm-alert history')} ${dim(HISTORY_FILE)}\n\n`);

for (const entry of entries) {
  const marker = entry.fired ? green('🔊 SCREAMED') : grey('·  skipped ');
  const bits = [
    entry.source && `source=${entry.source}`,
    entry.event && `event=${entry.event}`,
    entry.model && `model=${entry.model}`,
    entry.mode && `mode=${entry.mode}`,
    // Explicit about 0 rather than truthy: muted is the one volume worth
    // reporting, and it is the one a truthiness check would throw away.
    Number.isFinite(entry.volume) && entry.volume !== 100 && `volume=${entry.volume}`,
    entry.session && `session=${entry.session}`,
    entry.label && `label=${entry.label}`,
  ].filter(Boolean);

  process.stdout.write(`${dim(localTime(entry.at))}  ${marker}  ${entry.reason || ''}\n`);
  if (bits.length) process.stdout.write(`${' '.repeat(19)}${dim(bits.join('  '))}\n`);
}

const fired = entries.filter((e) => e.fired).length;
process.stdout.write(
  `\n${dim(`${entries.length} shown · ${fired} screamed · ${entries.length - fired} suppressed`)}\n\n`
);
