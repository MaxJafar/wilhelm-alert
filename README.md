# wilhelm-alert

Apache-2.0, pnpm-managed plugin that plays an alert sound when a coding
agent finishes a task. Ships as a real **Claude Code plugin** and a real
**Codex CLI plugin** (both installable via their native marketplace
systems), plus hook config for Antigravity and a best-effort integration
for OpenClaw.

No daemon, no polling — each tool just runs `bin/wilhelm-alert` itself via
its own "task finished" hook.

## Install (pnpm)

```bash
pnpm install
```

There's nothing to build — this package is scripts and plugin manifests,
no compile step.

## 1. Add a sound file

No audio is bundled (see [sounds/README.md](sounds/README.md) for why).
Drop a file at `sounds/wilhelm-scream.mp3` (`.wav`/`.aiff` also work), or
set `WILHELM_ALERT_SOUND=/path/to/file`.

Test it directly:

```bash
./bin/wilhelm-alert
```

## 2. Install the plugin

### Claude Code

```bash
claude plugin marketplace add ./
claude plugin install wilhelm-alert@wilhelm-alert-marketplace
```

Once published to a git host, others install it the normal way:

```bash
claude plugin marketplace add <owner>/<repo>
claude plugin install wilhelm-alert@wilhelm-alert-marketplace
```

This registers a `Stop` hook (fires when Claude finishes responding) via
[hooks/hooks.json](hooks/hooks.json), declared in
[.claude-plugin/plugin.json](.claude-plugin/plugin.json) /
[.claude-plugin/marketplace.json](.claude-plugin/marketplace.json).

### Codex CLI

```bash
codex plugin marketplace add .
codex plugin add wilhelm-alert@wilhelm-alert-marketplace
```

Declared in [.codex-plugin/plugin.json](.codex-plugin/plugin.json) /
[.agents/plugins/marketplace.json](.agents/plugins/marketplace.json).
It reuses the same [hooks/hooks.json](hooks/hooks.json) as the Claude Code
plugin — Codex sets `CLAUDE_PLUGIN_ROOT` for compatibility alongside its
own `PLUGIN_ROOT`, so one hook file works for both. Fires on `Stop` and
`SessionEnd`.

### Antigravity

No plugin/marketplace format confirmed yet — wire the hook in manually.
Drop [integrations/antigravity/hooks.json](integrations/antigravity/hooks.json)
into `.agents/` in your workspace or `~/.gemini/config/`, with the path to
`bin/wilhelm-alert` filled in. Fires on the `Stop` event (execution loop
terminates).

### OpenClaw

See [integrations/openclaw/](integrations/openclaw/). OpenClaw has no
built-in "task finished" event, only `command:stop` for a manual `/stop`.
In practice OpenClaw's `coding-agent` skill runs Codex/Claude Code/OpenCode
as the real worker, so installing the plugin above already covers it.

## How it works

`bin/wilhelm-alert` finds a sound file and plays it (`afplay` on macOS,
`paplay`/`aplay`/`ffplay` on Linux), then exits immediately — it always
exits 0, even with no sound configured, so it never blocks or fails an
agent's hook chain. Windows isn't supported.

## Repo layout

```
bin/wilhelm-alert          the player script itself
hooks/hooks.json           shared Stop/SessionEnd hook definition
.claude-plugin/            Claude Code plugin + marketplace manifests
.codex-plugin/             Codex CLI plugin manifest
.agents/plugins/           Codex CLI marketplace manifest
integrations/antigravity/  manual hook config for Antigravity
integrations/openclaw/     best-effort hook + explanation of the limitation
sounds/                    put your own sound file here (gitignored)
```

## Before publishing

This scaffold ships with placeholder author info (`"Your Name"`) in
`package.json`, `NOTICE`, and both `plugin.json` files, and empty
`repository`/`homepage` fields in `package.json` — fill those in, then
`git init` (if you haven't already) and push to a host before running
`claude plugin marketplace add <owner>/<repo>` from elsewhere. Publishing
to the npm registry (`npm publish` / `pnpm publish`) is a separate,
deliberate step — nothing here does that for you.
