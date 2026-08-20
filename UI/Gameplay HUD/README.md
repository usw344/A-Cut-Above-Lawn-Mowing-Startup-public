# Gameplay HUD

## Purpose
The in-play information layer: which job, how far through it, fuel, time of
day, weather. Deliberately restrained - four corners only, the middle of the
screen stays clear for the lawn and mower.

## Main Scene
`res://UI/Gameplay HUD/Gameplay HUD.tscn` (root: `Control`, full rect)

## Main Script
`gameplay_hud.gd` (`class_name GameplayHUD`)

## Public API
```gdscript
set_job_name(value: String)          # "Miller Residence"
set_job_size(value: String)          # "Medium Lawn"
set_reward(value: int)               # 240 -> "$240"

set_progress(value: float)           # 0.0 - 1.0, animated
set_progress_immediate(value: float) # 0.0 - 1.0, snaps
set_fuel(value: float)               # 0.0 - 1.0, animated
set_status(value: String)            # caption above the bar, default "MOWING"

set_game_time(value: String)         # "09:41" - already formatted
set_weather(value: String)           # "Clear"

show_hud()  hide_hud()  is_hud_visible() -> bool
set_pause_hint_visible(value: bool)
progress() -> float    fuel() -> float
```
Percentages are **0.0 - 1.0**, not 0 - 100. Values are clamped, so calling
`set_progress()` every frame with a raw ratio is safe.

## Signals
```gdscript
pause_requested       # the ESC chip was clicked
low_fuel_entered      # fuel dropped past low_fuel_threshold (default 0.2)
low_fuel_exited       # fuel came back above it
```
The low-fuel pair is a convenience for firing a toast; ignore it if you like,
the gauge recolours itself either way.

## Hard-Coded Dependencies
`res://UI/Theme/Game UI.theme.tres` on the root node. Nothing else.

## Expected Host Data
A job name, a size label, a payout int, and two 0-1 ratios (mowed fraction,
fuel fraction). Plus optional pre-formatted clock text and a weather word.
The HUD never reads the mower, the lawn or any job model.

## Copying / Integration Notes
- Add under a `CanvasLayer` in the host HUD. Root `mouse_filter` is IGNORE,
  so it never steals clicks; only the ESC chip is clickable.
- The HUD does **not** read the Escape key. It emits `pause_requested` when
  its chip is clicked. Keep Escape in the host or in `Pause Menu.tscn`.
- Exported knobs: `low_fuel_threshold`, `critical_fuel_threshold`,
  `bar_tween_time`.

## Known Limitations
- Long job names are ellipsised, not wrapped (verified with a 34-character
  name). The panel is a fixed 360 px wide.
- `set_game_time()` takes formatted text; the HUD does not simulate a clock.
  `UITheme.format_clock(seconds)` is available if you have raw seconds.
