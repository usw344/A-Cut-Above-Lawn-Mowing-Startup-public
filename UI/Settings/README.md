# Settings

## Purpose
A polished settings screen covering gameplay, graphics, audio and controls.
**Presentation only.**

## Main Scene
`res://UI/Settings/Settings.tscn` (root: `Control`, full rect)

## Main Script
`settings.gd` (`class_name SettingsMenu`)

## Public API
```gdscript
open()  close()  is_open() -> bool
set_values(values: Dictionary)   # accepts any subset; unknown keys ignored
values() -> Dictionary
```

## Signals
```gdscript
apply_requested(settings: Dictionary)
back_requested
controls_requested
value_changed(key: String, value: Variant)   # live, as controls move
```

## The settings dictionary
```
"mouse_sensitivity"  float   0.1 - 3.0   (1.0 = default)
"quality"            int     index into QUALITY_OPTIONS
"fullscreen"         bool
"resolution"         int     index into RESOLUTION_OPTIONS
"master_volume"      float   0.0 - 1.0
"ambience_volume"    float   0.0 - 1.0
"mower_volume"       float   0.0 - 1.0
```
`values()` also returns read-only `"quality_name"` and `"resolution_name"`
strings for convenience. Volumes are linear 0-1, **not** decibels - convert
with `linear_to_db()` on the host side.

## Hard-Coded Dependencies
`res://UI/Theme/Game UI.theme.tres` on the root node. It does **not** preload
the Controls Help overlay; it emits `controls_requested` instead.

## Expected Host Data
Whatever the host stores as its config. `set_values()` takes any subset, so
you can pass the whole config dictionary straight in.

## Copying / Integration Notes
- **Nothing is applied here.** No `DisplayServer`, `ProjectSettings`,
  `AudioServer` or file access. The host acts on `apply_requested`:
```gdscript
settings.apply_requested.connect(func(s: Dictionary) -> void:
    AudioServer.set_bus_volume_db(bus, linear_to_db(s["master_volume"]))
    config.save())
```
- The single exception is local layout logic: the Resolution dropdown is
  disabled while Fullscreen is on, because that combination is meaningless.
- Dropdown contents are constants at the top of `settings.gd`
  (`QUALITY_OPTIONS`, `RESOLUTION_OPTIONS`). Edit them there.
- `process_mode = ALWAYS`; Escape emits `back_requested`.

## Known Limitations
- No key rebinding, no per-setting reset, no unsaved-changes warning.
- Two fixed columns at 760 px wide; fits 1280x720 without scrolling.
- Values are not persisted anywhere.
