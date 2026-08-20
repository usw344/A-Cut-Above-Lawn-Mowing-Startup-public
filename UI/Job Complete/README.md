# Job Complete

## Purpose
End-of-job results card: completion, elapsed time, contract pay, optional
bonus, and the total counting up. Provides the closure beat after mowing.

## Main Scene
`res://UI/Job Complete/Job Complete.tscn` (root: `Control`, full rect)

## Main Script
`job_complete.gd` (`class_name JobCompleteScreen`)

## Public API
```gdscript
show_results(
    customer_name: String,
    completion: float,        # 0.0 - 1.0
    elapsed_seconds: float,   # 522.0 -> "08:42"
    base_pay: int,            # 240
    bonus: int = 0)           # row hides when 0

hide_results()
is_open() -> bool
finish_animation()            # snap entrance + count-up to the end
set_button_text(value: String)
```

## Signals
```gdscript
return_to_town_requested   # the button was pressed
results_shown              # entrance animation finished
```

## Hard-Coded Dependencies
`res://UI/Theme/Game UI.theme.tres` on the root node. Nothing else.

## Expected Host Data
Customer name, a 0-1 completion ratio, raw elapsed seconds, and the payout
split into base and bonus ints. Bonus is optional presentation - pass 0 (the
default) if the production game has no bonus concept and the row disappears.

## Copying / Integration Notes
- The screen does **not** complete the job, pay the player, or change scene.
  It emits `return_to_town_requested` and stops.
- `process_mode = ALWAYS`, so it animates over a paused tree.
- Clicking anywhere while the numbers roll calls `finish_animation()`, so the
  screen never feels like it is holding the player up.
- Timings are exported: `count_up_time`, `entrance_time`, `entrance_slide`.

## Known Limitations
- The scrim is partial alpha on purpose, so the finished lawn stays visible
  behind the card. Raise it in the scene if you want a harder cut.
- No star rating or grade concept - add it as another row if the production
  game grows one.
