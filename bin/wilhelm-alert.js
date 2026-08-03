#!/usr/bin/env node
// Screams when your coding agent finishes a task.
//
// This is the cross-platform core. Node is the only runtime every supported
// agent already depends on, so it's the one place all three OSes meet.
//
//   node wilhelm-alert.js [--source claude] [--mode turbo]
//
// Modes: light (sound) | middle (sound + popup) | turbo (+ shake)
//
// Every failure path still exits 0. A joke plugin that breaks an agent's
// hook chain stops being a joke.

'use strict';

const { spawn, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const ASSETS = path.join(ROOT, 'assets');
const SOUNDS = path.join(ROOT, 'sounds');
const PLATFORM = process.platform; // darwin | win32 | linux

const warn = (...lines) => lines.forEach((l) => process.stderr.write(`${l}\n`));

// ---------------------------------------------------------------- arguments

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const [key, inline] = argv[i].split('=');
    if (!key.startsWith('--')) continue;
    const name = key.slice(2);
    out[name] = inline !== undefined ? inline : argv[++i];
  }
  return out;
}
const args = parseArgs(process.argv.slice(2));

// ------------------------------------------------------------------- config

function configPath() {
  if (PLATFORM === 'win32') {
    const base = process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
    return path.join(base, 'wilhelm-alert', 'config');
  }
  const base = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
  return path.join(base, 'wilhelm-alert', 'config');
}

function readConfig() {
  try {
    const text = fs.readFileSync(configPath(), 'utf8');
    const config = {};
    for (const line of text.split(/\r?\n/)) {
      const match = line.match(/^\s*([A-Za-z_]+)\s*=\s*(.*?)\s*$/);
      if (match && !line.trim().startsWith('#')) config[match[1]] = match[2];
    }
    return config;
  } catch {
    return {};
  }
}
const config = readConfig();

// The config file matters more than the environment here: a hook runs inside
// the agent's process, so an export in the user's shell never reaches us.
const VALID_MODES = new Set(['light', 'middle', 'turbo']);
let mode = args.mode || process.env.WILHELM_ALERT_MODE || config.mode || 'light';
if (!VALID_MODES.has(mode)) {
  warn(`wilhelm-alert: unknown mode '${mode}' (want light|middle|turbo), using light`);
  mode = 'light';
}

// Codex sets PLUGIN_ROOT *and* CLAUDE_PLUGIN_ROOT for plugin compatibility,
// so the Codex-only variable has to be checked first or every Codex run
// would be misread as Claude. Agents without a plugin system pass --source.
function detectSource() {
  if (args.source) return args.source;
  if (process.env.WILHELM_ALERT_SOURCE) return process.env.WILHELM_ALERT_SOURCE;
  if (process.env.CURSOR_AGENT || process.env.CURSOR_TRACE_ID) return 'cursor';
  if (process.env.PLUGIN_ROOT) return 'codex';
  if (process.env.CLAUDE_PLUGIN_ROOT) return 'claude';
  return 'generic';
}
const source = detectSource();

// ----------------------------------------------------------------- resolving

function firstExisting(dir, basenames) {
  let entries;
  try {
    entries = fs.readdirSync(dir);
  } catch {
    return null;
  }
  for (const base of basenames) {
    const hit = entries.find((f) => f.toLowerCase().startsWith(`${base}.`));
    if (hit) return path.join(dir, hit);
  }
  return null;
}

function resolveSound() {
  const override = args.sound || process.env.WILHELM_ALERT_SOUND || config.sound;
  if (override) return fs.existsSync(override) ? override : null;
  return firstExisting(SOUNDS, ['wilhelm-scream']);
}

function resolveImage() {
  const direct = firstExisting(ASSETS, [`scream-${source}`, 'scream-generic']);
  if (direct) return direct;
  // Falling back to *any* face keeps a manual `wilhelm-alert` run from
  // silently doing nothing just because no generic image was ever added.
  try {
    const any = fs
      .readdirSync(ASSETS)
      .filter((f) => /^scream-.*\.(png|jpe?g|gif|svg|heic|webp)$/i.test(f))
      .sort();
    if (any.length) return path.join(ASSETS, any[0]);
  } catch {
    /* no assets directory */
  }
  return null;
}

// ------------------------------------------------------------------ playback

function detach(command, commandArgs) {
  try {
    const child = spawn(command, commandArgs, {
      detached: true,
      stdio: 'ignore',
      windowsHide: true,
    });
    child.unref();
    return true;
  } catch {
    return false;
  }
}

function playSound(file) {
  if (PLATFORM === 'darwin') return detach('afplay', [file]);

  if (PLATFORM === 'win32') {
    // SoundPlayer handles WAV only; MediaPlayer covers mp3/m4a. Pick by
    // extension so both work without shipping a codec.
    const script = /\.wav$/i.test(file)
      ? `(New-Object Media.SoundPlayer '${file}').PlaySync()`
      : `Add-Type -AssemblyName presentationCore;` +
        `$p=New-Object System.Windows.Media.MediaPlayer;` +
        `$p.Open([uri]'${file}');$p.Play();Start-Sleep -Seconds 5`;
    return detach('powershell', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', script]);
  }

  for (const [player, playerArgs] of [
    ['paplay', [file]],
    ['aplay', ['-q', file]],
    ['ffplay', ['-nodisp', '-autoexit', '-loglevel', 'quiet', file]],
  ]) {
    if (spawnSync('sh', ['-c', `command -v ${player}`], { stdio: 'ignore' }).status === 0) {
      return detach(player, playerArgs);
    }
  }
  warn('wilhelm-alert: no audio player found (tried paplay, aplay, ffplay)');
  return false;
}

function showPopup(image) {
  const seconds = args.seconds || process.env.WILHELM_ALERT_POPUP_SECONDS || config.seconds || '2.4';

  if (PLATFORM === 'darwin') {
    const build = spawnSync(path.join(ROOT, 'bin', 'wilhelm-build'), ['overlay'], {
      encoding: 'utf8',
    });
    const binary = (build.stdout || '').trim();
    if (binary && fs.existsSync(binary)) {
      return detach(binary, ['--image', image, '--mode', mode, '--seconds', String(seconds)]);
    }
    warn('wilhelm-alert: could not build the overlay (needs Xcode command line tools).');
    return false;
  }

  if (PLATFORM === 'win32') {
    return detach('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      path.join(ROOT, 'app', 'overlay-windows.ps1'),
      '-Image', image,
      '-Mode', mode,
      '-Seconds', String(seconds),
    ]);
  }

  // Linux: tkinter ships with most python3 installs and is the only
  // toolkit reliably present across desktops.
  for (const python of ['python3', 'python']) {
    if (spawnSync('sh', ['-c', `command -v ${python}`], { stdio: 'ignore' }).status === 0) {
      const check = spawnSync(python, ['-c', 'import tkinter'], { stdio: 'ignore' });
      if (check.status === 0) {
        return detach(python, [
          path.join(ROOT, 'app', 'overlay-linux.py'),
          '--image', image,
          '--mode', mode,
          '--seconds', String(seconds),
        ]);
      }
    }
  }
  warn('wilhelm-alert: no overlay on this system (needs python3 with tkinter).');
  return false;
}

// ---------------------------------------------------------------------- main

const sound = resolveSound();
if (sound) {
  playSound(sound);
} else {
  warn(
    'wilhelm-alert: no sound file found.',
    `  Drop one at ${path.join(SOUNDS, 'wilhelm-scream.wav')} (or .mp3/.aiff),`,
    '  or set WILHELM_ALERT_SOUND=/path/to/sound'
  );
}

if (mode !== 'light') {
  const image = resolveImage();
  if (image) {
    showPopup(image);
  } else {
    warn(
      `wilhelm-alert: no popup image for '${source}' — showing nothing.`,
      `  Add one at ${path.join(ASSETS, `scream-${source}.png`)} (see assets/README.md)`
    );
  }
}

process.exit(0);
