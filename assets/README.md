# assets/

The faces that pop up in `middle` and `turbo` mode. The default Codex and
Claude Code faces are included here, and the script picks them up automatically:

`wilhelm-scream-banner.png` is the README artwork and is not used as a popup
face.

| File | Pops up when |
| --- | --- |
| `scream-claude.png` | Claude Code finishes |
| `scream-codex.png` | Codex finishes |
| `scream-generic.png` | fallback for anything else |

To replace a face, copy the image (right-click → Copy Image), then:

```bash
./bin/wilhelm-face claude
```

That drops it straight in at the right name and downscales anything huge.
Or just save files here yourself.

Square images look best — the overlay is a square panel. `.png`, `.jpg`,
`.gif`, and `.svg` all render. Transparent PNGs look sharp against the
rounded corners.

Want a different face for another tool? Name it `scream-<source>.png` and
run with `WILHELM_ALERT_SOURCE=<source>`.

The bundled faces are user-supplied parody artwork. Replace them with your own
images if you prefer (see the trademark note in the main README before you go
redrawing anyone's logo).
