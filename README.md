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

```bash
export WILHELM_ALERT_MODE=turbo   # light | middle | turbo (default: light)
```

The face that pops up matches whichever agent called it — Claude Code gets
the Claude one, Codex gets the Codex one. Auto-detected, no config needed.

## Setup

```bash
pnpm install
```

Then feed it two things it doesn't ship with:

**A scream.** Drop `sounds/wilhelm-scream.mp3` (`.wav`/`.aiff` fine too), or
point `WILHELM_ALERT_SOUND` at any audio file. The real Wilhelm scream is a
copyrighted sound effect, so you bring your own — see
[sounds/README.md](sounds/README.md).

**Faces**, if you want `middle` or `turbo`. Drop `assets/scream-claude.png`
and `assets/scream-codex.png` — see [assets/README.md](assets/README.md).

Then check it works:

```bash
WILHELM_ALERT_MODE=turbo ./bin/wilhelm-alert
```

## Install it into your agent

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

**The turbo shake does nothing.** macOS won't let a random script move
windows around until you grant Accessibility permission to whatever's
running it (System Settings → Privacy & Security → Accessibility). Until
then, turbo is just middle mode with extra confidence. The script no-ops
quietly instead of erroring.

**Nothing happens at all.** You didn't add a sound file. See above.

**Linux:** sound works (`paplay`/`aplay`/`ffplay`), popup opens via
`xdg-open` but won't auto-close, shake doesn't exist. **Windows:** no.

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
