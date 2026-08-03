# sounds/

Put your alert sound here as `wilhelm-scream.mp3` (or `.wav` / `.aiff`) and
`bin/wilhelm-alert` will pick it up automatically. No file is bundled in this
repo — the actual Wilhelm scream recording is a copyrighted sound effect, so
it isn't included/redistributed here. Options:

- Supply your own copy of the file under this name.
- Point `WILHELM_ALERT_SOUND` at any sound file you already have, anywhere
  on disk (skip this folder entirely).
- Use any other short alert sound instead — the script doesn't care what it
  actually sounds like.
