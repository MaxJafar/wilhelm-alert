# wilhelm-alert

Your agent finishes a task. It screams. You look up.

That's it. That's the plugin.

It's the [Wilhelm scream](https://en.wikipedia.org/wiki/Wilhelm_scream) —
the stock sound effect that's been in a few hundred movies — fired from
your coding agent's "task complete" hook. Works with Claude Code and Codex
as a real installable plugin, plus hook config for Antigravity and OpenClaw.

## Modes

| Mode | What happens |
| --- | --- |
| `light` | Just the scream. Tasteful. Restrained. Cowardly. |
| `middle` | The scream, plus a popup of the model itself screaming at you. |
| `turbo` | The scream, the popup, and the popup shakes like it's being attacked. |

Set it in the mini app (`pnpm setup`), or in `~/.config/wilhelm-alert/config`.

The face that pops up matches whichever agent called it — Claude Code gets
the Claude one, Codex gets the Codex one. Auto-detected, no config needed.

The popup is a small borderless overlay in the corner of the screen. It
doesn't steal focus, so it can't eat the keystroke you were mid-way through
typing, and clicking it dismisses it early.

## Setup

```bash
pnpm install
pnpm setup
```

`pnpm setup` opens a little app: pick your mode, hit **Test it** to hear it,
and install into Claude Code or Codex with a button. No browser, no
localhost, no menu bar clutter.

Prefer the terminal? The mode lives in `~/.config/wilhelm-alert/config`:

```bash
mkdir -p ~/.config/wilhelm-alert && echo 'mode=turbo' > ~/.config/wilhelm-alert/config
```

Use the config file rather than an `export` in your shell profile — hooks
run inside the *agent's* environment, so a variable you set in your terminal
usually never reaches them. `WILHELM_ALERT_MODE` still overrides everything
for one-off tests.

Either way, feed it two things it doesn't ship with:

**A scream.** Drop `sounds/wilhelm-scream.mp3` (`.wav`/`.aiff` fine too), or
point `WILHELM_ALERT_SOUND` at any audio file. The real Wilhelm scream is a
copyrighted sound effect, so you bring your own — see
[sounds/README.md](sounds/README.md).

**Faces**, if you want `middle` or `turbo`. Copy an image to your clipboard
and run:

```bash
./bin/wilhelm-face claude    # then again with: codex
```

It saves to `assets/scream-<name>.png` and shrinks anything oversized. You
can also drop files in [assets/](assets/README.md) by hand.

Then check it works:

```bash
WILHELM_ALERT_MODE=turbo ./bin/wilhelm-alert
```

## Install it into your agent

`pnpm setup` does this with a button. By hand:

### Claude Code

```bash
claude plugin marketplace add ./
claude plugin install wilhelm-alert@wilhelm-alert-marketplace
```

### Codex CLI

```bash
codex plugin marketplace add .
codex plugin add wilhelm-alert@wilhelm-alert-marketplace
```

**After changing anything** — a new sound, new faces, edited code — run
`claude plugin update wilhelm-alert@wilhelm-alert-marketplace`. Agents run
a *copied* snapshot of this folder, pinned by the version in `plugin.json`,
so edits are invisible to them until you bump the version and update. This
is the single most confusing thing about the whole project.

Both hook `Stop` (and `SessionEnd` on Codex) via
[hooks/hooks.json](hooks/hooks.json). One hook file serves both, because
Codex helpfully sets `CLAUDE_PLUGIN_ROOT` for plugin compatibility.

### Antigravity

No plugin format to hook into yet, so do it by hand: drop
[integrations/antigravity/hooks.json](integrations/antigravity/hooks.json)
into `.agents/` in your workspace or `~/.gemini/config/`, with the path to
`bin/wilhelm-alert` filled in.

### OpenClaw

[integrations/openclaw/](integrations/openclaw/). OpenClaw has no "task
finished" event at all — only `command:stop` when you manually type `/stop`.
But its `coding-agent` skill runs Codex or Claude Code as the actual worker,
so installing the plugin above already makes it scream. Problem solved by
someone else's architecture.

## Things that will go wrong

**It worked when I ran it, but the agent stays silent.** You changed the
repo and didn't bump + update the plugin. See the note above.

**Nothing happens at all.** You didn't add a sound file. See above.

**No overlay, just the scream.** The overlay is a tiny Swift program built
on first use, so it needs Xcode command line tools (`xcode-select --install`).
Without them it falls back to a plain Quick Look panel, and turbo loses its
shake. First build takes ~2s and is then cached in `~/.cache/wilhelm-alert`.

**Linux:** sound works (`paplay`/`aplay`/`ffplay`), popup opens via
`xdg-open` but won't auto-close, no overlay or shake, and no mini app —
edit the config file directly. **Windows:** no.

The turbo shake used to need Accessibility permission, back when it rattled
a Quick Look window that belonged to someone else. The overlay owns its own
window now, so it shakes itself and asks you for nothing.

Every failure path exits 0 on purpose. A joke plugin that breaks your
agent's hook chain is no longer a joke, it's a bug report.

## Trademarks, since this is public

The popup images are yours to supply, and the fun ones are inevitably going
to be somebody's logo with a mouth drawn on it. That's parody, and parody of
a logo is not the same as a license to use it — this project doesn't claim
any rights to Anthropic's, OpenAI's, or anyone else's marks, isn't affiliated
with or endorsed by them, and ships no such images itself. Draw what you
like on your own machine; think twice before committing it to a public repo
with someone's brand on it.

## License

[Apache-2.0](LICENSE). It's a pet project that makes a computer scream —
take it, fork it, make it worse.
