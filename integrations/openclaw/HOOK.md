---
name: wilhelm-alert
description: "Plays an alert sound when a /stop command is issued"
metadata:
  { "openclaw": { "emoji": "🔊", "events": ["command:stop"], "requires": { "bins": ["node"] } } }
---

# wilhelm-alert

Plays `bin/wilhelm-alert` from this repo when the `/stop` command fires.

**Known limitation:** OpenClaw has no built-in event for "agent task finished."
`command:stop` only observes a user manually typing `/stop` — it will not fire
when the agent simply finishes answering. The docs point at a typed plugin
hook (`before_agent_finalize`) for that case, which needs the Plugin SDK
rather than the lightweight hook loader — out of scope here.

In practice this mostly doesn't matter: OpenClaw's `coding-agent` skill runs
Codex / Claude Code / OpenCode as the actual background worker, and those
CLIs already fire their own completion hooks (see `../codex` and
`../claude-code`). Wire the sound in at that layer and it will play when the
underlying coding agent finishes, regardless of OpenClaw orchestrating it.
