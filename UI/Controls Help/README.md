# Controls Help

## Purpose
A readable control reference so someone seeing the game for the first time
knows what to press. Shown from Settings, or once at the start of a job.

## Main Scene
`res://UI/Controls Help/Controls Help.tscn` (root: `Control`, full rect)

## Main Script
`controls_help.gd` (`class_name ControlsHelp`)

## Public API
```gdscript
open()  close()  is_open() -> bool
set_title(value: String)                 # default "MOWER CONTROLS"
set_bindings(rows: PackedStringArray)    # replaces the whole list
```

## Signals
```gdscript
closed    # CLOSE pressed, Escape, or backdrop click
```

## The bindings format
One string per row, key and description split by a single `|`:
```
"W / S|Drive Forward / Reverse"
"MOUSE|Steer & Look"
```
A row with no `|` becomes a section heading:
```
"MOWING"
```
The default list is `DEFAULT_BINDINGS` near the top of the script. Edit it
there for a permanent change, or call `set_bindings()` at runtime to swap in
gamepad prompts. Rows rebuild immediately.

## Hard-Coded Dependencies
`res://UI/Theme/Game UI.theme.tres` on the root node. Nothing else - rows are
built from code, so there is no row scene to keep in sync.

## Expected Host Data
Nothing. Optionally, the real bindings as a `PackedStringArray`.

## Copying / Integration Notes
- This overlay does **not** read `InputMap` and does not know the real
  bindings of the host. If the game gains rebindable controls, feed the real
  values in with `set_bindings()` rather than making this component query
  InputMap.
- `close_on_click_outside` is exported and defaults to `true`.
- `process_mode = ALWAYS`.

## Known Limitations
- Text only; no key-cap art or controller glyphs.
- The key column is a fixed 132 px, so very long key names will overflow it.
