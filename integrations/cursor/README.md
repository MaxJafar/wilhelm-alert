# Cursor

Cursor has no plugin marketplace to install into, so wire the hook up by hand.

Copy [hooks.json](hooks.json) to `~/.cursor/hooks.json` (or
`<project>/.cursor/hooks.json` for one project only) and replace the
placeholder with the real path to this folder.

If you already have a `~/.cursor/hooks.json`, merge the `stop` entry into
your existing `hooks` object rather than overwriting the file.

Cursor fires two events at the end of a turn:

- `stop` — the agent loop ended. This is the one you want.
- `afterAgentResponse` — fires after *each* assistant message, so on a long
  multi-step task it screams repeatedly. Use it only if you enjoy that.

The `--source cursor` flag is what picks the face: unlike Claude Code and
Codex, Cursor sets no environment variable this script can detect, so the
hook has to say who it is. Add `assets/scream-cursor.png` to give it its own
face — otherwise it falls back to whichever face is available.
