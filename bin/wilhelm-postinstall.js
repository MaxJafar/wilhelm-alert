#!/usr/bin/env node
// Pre-builds the macOS overlay so the first alert doesn't pay for a compile.
// Windows and Linux have nothing to build — their overlays are scripts.
//
// Always exits 0: a failed pre-build is a slower first alert, not a broken
// install, and `pnpm install` shouldn't fail over it.

'use strict';

const { spawnSync } = require('node:child_process');
const path = require('node:path');

if (process.platform === 'darwin') {
  spawnSync(path.resolve(__dirname, 'wilhelm-build'), ['overlay'], { stdio: 'ignore' });
}

process.exit(0);
