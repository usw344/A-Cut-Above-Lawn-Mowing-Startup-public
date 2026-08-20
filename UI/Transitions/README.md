# Transitions

## Purpose
A fullscreen fade layer for Town -> Job, Job -> Town, Menu -> Town. It hides
the moment the host swaps content, and nothing else.

## Main Scene
`res://UI/Transitions/Transition.tscn` (root: **`CanvasLayer`**, layer 128)

## Main Script
`transition.gd` (`class_name TransitionLayer`)

## Public API
```gdscript
fade_to_black(duration: float = -1.0)     # -1.0 uses default_duration
fade_from_black(duration: float = -1.0)
fade_out_and_in(hold: float = 0.15)

cover_immediately()   reveal_immediately()
is_covered() -> bool  is_busy() -> bool

set_title(title: String, subtitle: String = "")   # shown while covered
clear_title()
```

## Signals
```gdscript
screen_covered        # fully black - swap content NOW
transition_finished   # fully clear again
```

## The contract
```
1. Host calls fade_to_black()
2. Screen reaches fully covered
3. screen_covered emits
4. Host changes game content
5. Host calls fade_from_black()
6. transition_finished emits
```
```gdscript
transition.screen_covered.connect(_swap_to_job_scene, CONNECT_ONE_SHOT)
transition.fade_to_black()
```
`fade_out_and_in()` does step 5 itself after `hold` seconds - use it when the
host work in step 4 is instant.

## Hard-Coded Dependencies
The shared theme, on the `Screen` child. Nothing else.

## Expected Host Data
Nothing. Optionally a title/subtitle for a "travelling to..." beat.

## Copying / Integration Notes
- The root is a `CanvasLayer`, not a `Control`, so it draws over every other
  CanvasLayer without depending on node order. Parent it to anything.
- `process_mode = ALWAYS` - transitions still run over a paused tree, which
  is the usual case when leaving a pause menu.
- While covered it blocks mouse input so clicks cannot reach the content
  being swapped underneath.
- The cover colour is the palette near-black, not pure black. Exported as
  `cover_colour`; `default_duration` is 0.35 s.

## Known Limitations
- Fade only - no wipes, irises or shader transitions.
- One transition at a time; starting a new one kills the running tween.
