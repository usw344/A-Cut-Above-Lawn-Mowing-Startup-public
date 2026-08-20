# Pause Menu

## Purpose
The pause interface: resume, restart, settings, abandon, quit.

## Main Scene
`res://UI/Pause Menu/Pause Menu.tscn` (root: `Control`, full rect)

## Main Script
`pause_menu.gd` (`class_name PauseMenu`)

## Public API
```gdscript
open()  close()  toggle()  is_open() -> bool
set_context(job_name: String)     # optional subtitle under "PAUSED"
```

## Signals
```gdscript
opened                    # overlay became visible  -> pause the game HERE
closed                    # overlay became hidden   -> unpause HERE

resume_requested
restart_job_requested
settings_requested
abandon_job_requested
quit_to_menu_requested
```
Only RESUME also closes the menu. The other four leave it open on purpose, so
the host can layer a confirmation dialog or the settings screen over it, then
call `close()` once the player has actually committed.

## Hard-Coded Dependencies
`res://UI/Theme/Game UI.theme.tres` on the root node. **Nothing else** - the
menu does not preload the Settings screen or the Confirmation Dialog.

## Expected Host Data
Nothing, other than an optional job name for the subtitle.

## Copying / Integration Notes
- **Escape handling lives here by default.** Two exported flags control it:
  `open_on_escape` and `close_on_escape`, both `true`. Set both to `false`
  in the inspector if the host game already owns Escape (likely, if it also
  uses Escape to release a captured mouse). Input is only consumed when the
  menu actually acts on it.
- The menu never sets `get_tree().paused`. Do that on `opened` / `closed`:
```gdscript
pause_menu.opened.connect(func() -> void:
    get_tree().paused = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
```
- `process_mode = ALWAYS`, so it keeps working while the tree is paused.

## Known Limitations
- No gamepad glyphs; buttons are text only.
- Fixed 380 px card width.
