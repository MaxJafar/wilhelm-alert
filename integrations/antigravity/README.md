# Antigravity

Antigravity has a real lifecycle-hook system. Copy [hooks.json](hooks.json)
to one of its customization roots and replace the placeholder with the
absolute path to this folder:

- `~/.agents/hooks.json` — every workspace
- `<workspace>/.agents/hooks.json` — one project only

If you already have a `hooks.json` there, merge the `wilhelm-alert` key into
it rather than overwriting the file. Top-level keys are hook *names*, and
Antigravity merges handlers from every named hook for the same event, so
several can coexist.

## Which event

`Stop` — "handlers running when the execution loop terminates". The others
are `PreToolUse`, `PostToolUse`, `PreInvocation` and `PostInvocation`; a
completion alert on any of those would fire constantly.

`Stop` takes a **flat list** of handler objects. Only `PreToolUse` and
`PostToolUse` use the `matcher` + `hooks` wrapper, so don't copy that shape
here.

## Two things worth knowing

**Hooks block the agent loop.** They run synchronously, so a slow hook stalls
the agent. `wilhelm-alert` starts the sound and overlay detached and returns
immediately, and the `timeout` is a backstop.

**`Stop` is a contract, not a notification.** Antigravity reads a JSON
object from the hook's stdout and re-enters the loop if it says
`{"decision": "continue"}`. `wilhelm-alert` answers `{"decision": "stop"}`
so the agent stops normally — it emits that *only* for Antigravity, because
Claude Code also reads stdout on `Stop` and would try to interpret it.

## Payload

Antigravity uses camelCase (protojson) where Claude Code and Codex use
snake_case, so the log reads both spellings. Its `Stop` payload carries
`conversationId`, `workspacePaths`, `transcriptPath`, `modelName`,
`executionNum`, `terminationReason` and `fullyIdle`.

`modelName` is given outright, so Antigravity is the one agent where the
history log doesn't have to read the model out of a transcript.
