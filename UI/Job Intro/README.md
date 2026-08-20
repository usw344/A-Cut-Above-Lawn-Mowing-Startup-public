# Job Intro

## Purpose
The beat between accepting a contract and gameplay becoming visible. Doubles
as a loading mask: the background is opaque, so the host can build or stream
the job scene behind it unseen.

## Main Scene
`res://UI/Job Intro/Job Intro.tscn` (root: `Control`, full rect)

## Main Script
`job_intro.gd` (`class_name JobIntroScreen`)

## Public API
```gdscript
show_job(job_name: String, job_size: String,
         reward: int, estimated_minutes: int)   # fills in AND shows

set_contract_type(value: String)   # "Residential Contract"
set_status(value: String)          # "PREPARING EQUIPMENT..."

show_intro()  hide_intro()  is_open() -> bool
```

## Signals
```gdscript
intro_shown    # entrance finished
intro_hidden   # exit finished - safe to start gameplay
```

## Hard-Coded Dependencies
`res://UI/Theme/Game UI.theme.tres` on the root node. Nothing else.

## Expected Host Data
Job name, size label, payout int, estimated minutes int. Plus whatever status
text the host wants to display while it works.

## Copying / Integration Notes
- **There is no loading infrastructure here.** No `ResourceLoader`, no
  progress tracking. `set_status()` is a plain text setter; the host writes
  its real loading step and calls `hide_intro()` when the work is done.
```gdscript
intro.show_job(job.customer_name, job.size_label, job.pay, job.minutes)
intro.set_status("Preparing equipment...")
await build_the_lawn()
intro.hide_intro()
```
- The status line breathes gently while open, as a sign of life during a
  load. Set `animate_status = false` for a static label.
- `process_mode = ALWAYS`; `mouse_filter` STOP swallows clicks while up.

## Known Limitations
- No background art or job photo - it is a typographic title card.
- Content block is a fixed 520 px wide; long names wrap to two lines.
