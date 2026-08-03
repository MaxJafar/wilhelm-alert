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

function stateDir() {
  if (PLATFORM === 'win32') {
    const base = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
    return path.join(base, 'wilhelm-alert');
  }
  const base = process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local', 'state');
  return path.join(base, 'wilhelm-alert');
}
const HISTORY_FILE = path.join(stateDir(), 'history.jsonl');
const LAST_FIRE_FILE = path.join(stateDir(), 'last-fire');

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

// ------------------------------------------------------- the agent's payload

// Agents pipe a JSON event on stdin. Reading it is what makes the log useful
// (which event, which session, which model) and is also how we tell a real
// end-of-turn from session teardown.
function readStdinPayload() {
  // A TTY means a human ran this by hand; there is no payload coming and a
  // blocking read would hang the terminal.
  if (process.stdin.isTTY) return null;
  const chunks = [];
  const buffer = Buffer.alloc(65536);
  const deadline = Date.now() + 200;
  try {
    while (Date.now() < deadline && chunks.length < 32) {
      let bytes;
      try {
        bytes = fs.readSync(0, buffer, 0, buffer.length, null);
      } catch (err) {
        if (err.code === 'EAGAIN') continue; // pipe open but empty
        break; // EOF, EBADF, closed stdin — nothing more to read
      }
      if (bytes === 0) break;
      chunks.push(Buffer.from(buffer.subarray(0, bytes)));
    }
  } catch {
    return null;
  }
  const text = Buffer.concat(chunks).toString('utf8').trim();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
const payload = readStdinPayload() || {};

// The hook payload carries no model name, but the transcript does. Read only
// the tail so this stays cheap on a long conversation.
function modelFromTranscript(transcriptPath) {
  if (!transcriptPath) return null;
  try {
    const { size } = fs.statSync(transcriptPath);
    const window = Math.min(size, 65536);
    const fd = fs.openSync(transcriptPath, 'r');
    const buffer = Buffer.alloc(window);
    fs.readSync(fd, buffer, 0, window, Math.max(0, size - window));
    fs.closeSync(fd);
    const lines = buffer.toString('utf8').split('\n').reverse();
    for (const line of lines) {
      if (!line.includes('"model"')) continue;
      try {
        const entry = JSON.parse(line);
        const model = entry?.message?.model || entry?.model;
        if (typeof model === 'string' && model) return model;
      } catch {
        /* partial line at the window edge */
      }
    }
  } catch {
    /* no transcript, or unreadable */
  }
  return null;
}

// -------------------------------------------------------------------- logging

function appendHistory(entry) {
  try {
    fs.mkdirSync(stateDir(), { recursive: true });
    fs.appendFileSync(HISTORY_FILE, `${JSON.stringify(entry)}\n`);

    // Trim from the front once it gets long, so this never grows unbounded.
    const { size } = fs.statSync(HISTORY_FILE);
    if (size > 512 * 1024) {
      const kept = fs.readFileSync(HISTORY_FILE, 'utf8').trim().split('\n').slice(-400);
      fs.writeFileSync(HISTORY_FILE, `${kept.join('\n')}\n`);
    }
  } catch {
    /* logging must never break the hook chain */
  }
}

function record(fired, reason, extra = {}) {
  appendHistory({
    at: new Date().toISOString(),
    fired,
    reason,
    source,
    mode,
    event: payload.hook_event_name || null,
    session: payload.session_id ? String(payload.session_id).slice(0, 8) : null,
    end_reason: payload.reason || null,
    cwd: payload.cwd || process.cwd(),
    model: modelFromTranscript(payload.transcript_path),
    pid: process.pid,
    ...extra,
  });
}

// -------------------------------------------------------------- should we fire

// Only end-of-turn events should scream. SessionEnd fires on teardown —
// including `resume` when another instance takes the session over, and
// `clear` — which is why launching the app or opening a link used to trigger
// it. Guarded here as well as in hooks.json so a stale cached hook config
// can't resurrect the behaviour.
const NON_TURN_EVENTS = new Set(['SessionEnd', 'SessionStart', 'Notification', 'PreCompact']);

function suppressionReason() {
  const event = payload.hook_event_name;
  if (event && NON_TURN_EVENTS.has(event)) {
    return `ignored ${event}${payload.reason ? ` (${payload.reason})` : ''}`;
  }
  // Claude Code sets this when a Stop hook is already driving the turn;
  // firing again would stack screams on one completion.
  if (payload.stop_hook_active === true) return 'stop hook already active';

  // Two hooks landing together (Stop plus a session event, or two agents at
  // once) would otherwise scream twice for one finish.
  const minInterval = Number(config.min_interval_ms ?? 3000);
  if (minInterval > 0) {
    try {
      const last = Number(fs.readFileSync(LAST_FIRE_FILE, 'utf8').trim());
      const gap = Date.now() - last;
      if (Number.isFinite(last) && gap < minInterval) {
        return `debounced (${gap}ms since last, min ${minInterval}ms)`;
      }
    } catch {
      /* no previous fire recorded */
    }
  }
  return null;
}

function markFired() {
  try {
    fs.mkdirSync(stateDir(), { recursive: true });
    fs.writeFileSync(LAST_FIRE_FILE, String(Date.now()));
  } catch {
    /* non-fatal */
  }
}

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

// --force is the escape hatch for testing: it skips the debounce and the
// event filter so a manual run always screams.
const forced = args.force !== undefined || process.env.WILHELM_ALERT_FORCE === '1';
const suppressed = forced ? null : suppressionReason();

if (suppressed) {
  record(false, suppressed);
  process.exit(0);
}

markFired();
record(true, forced ? 'forced' : 'end of turn');

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
