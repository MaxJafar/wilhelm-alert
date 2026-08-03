# assets/

The faces that pop up in `middle` and `turbo` mode. Drop image files here
named after the agent — the script picks them up automatically:

| File | Pops up when |
| --- | --- |
| `scream-claude.png` | Claude Code finishes |
| `scream-codex.png` | Codex finishes |
| `scream-generic.png` | fallback for anything else |

Any extension Quick Look can render works (`.png`, `.jpg`, `.svg`, `.gif`).
Square images look best — the popup is a Quick Look panel.

Want a different face for another tool? Name it `scream-<source>.png` and
run with `WILHELM_ALERT_SOURCE=<source>`.

No images are bundled with this repo — supply your own (see the trademark
note in the main README before you go redrawing anyone's logo).
