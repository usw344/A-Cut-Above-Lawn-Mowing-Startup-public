# Startup and Runtime Flow

Status: **Current** — verified 2026-08-19 by `Dev tools/Validation/Flow Test.tscn`.

## Launch

1. Godot loads `project.godot`.
2. Autoloads are created **in declaration order**:
   `model` → `WorldClock` → `JobManager` → `GameSettings` → `AppUI` → `GameSession`.
   - `JobManager._ready()` starts its 0.25 s market poll timer on a *stopped*
     default clock.
   - `GameSettings._ready()` applies its defaults.
   - `AppUI._ready()` builds the notification layer (CanvasLayer 120) and the
     transition (CanvasLayer 128).
   - **`GameSession._ready()` hands `ACAWorldClockTimeProvider` to
     `JobManager.set_time_provider()`.** This is what starts the job market.
     It also connects `begin_job_requested`, `job_accepted` and `job_generated`.
3. `run/main_scene` = `res://Game/App/Main Menu Screen.tscn`.

## Main Menu

`Main Menu Screen.tscn` instances `main_menu_scenery.tscn`, which already
composes `main_menu.tscn` inside its `MenuSafeOverlay` CanvasLayer. The host
finds the menu by type (`MainMenuScreen`) rather than by a path the scenery
package owns.

- CONTINUE is greyed out unless `/root/SaveService` exists and reports a save.
- OPTIONS opens the Settings component on the host's own `Menu UI` CanvasLayer.
- NEW GAME calls `GameSession.start_new_game()`.

## New game

```
JobManager.debug_clear_all()
WorldClock.start_new_world()        # 08:00, Spring, Clear, running
money = STARTING_MONEY (250)
JobManager.set_time_provider(...)   # re-anchor arrivals to the new world
JobManager.seed_initial_offers(2)   # day one is not an empty board
go_to_town()
```

## Scene transitions

Every transition goes through `GameSession._swap_scene()`:

1. `AppUI.set_transition_title(...)` then `AppUI.cover()`
2. `await AppUI.screen_covered`
3. `get_tree().call_deferred("change_scene_to_file", path)`
4. two frames
5. `AppUI.reveal()`

Concurrent requests are ignored while `GameSession.is_changing_scene()`.

## Town

`Town Screen.tscn` → `BusinessTown.tscn`. The town raycasts against pick layer 9
**from `_physics_process`** (required with threaded 3D physics). Clicking the
Job Office opens `ACAJobBoard`, which `ACABusinessHUD._ready()` already bound to
the `JobManager` autoload.

The host feeds the HUD real money and `set_calendar(day, clock, weather)` at 2 Hz.

## Accept and begin

- ACCEPT → `JobManager.accept_job(id)` → job moves Available → Current, status
  `ACCEPTED`, `accepted_game_time` stamped. Offer expiry stops applying.
- BEGIN JOB → `JobManager.begin_new_job(id)` → status `IN_PROGRESS`, emits
  `begin_job_requested(job)` **and stops**.
- `GameSession._on_begin_job_requested()` performs the transition the Job System
  deliberately refuses to do.

## Mowing scene initialization

`Game/M.V.P/Minimum Viable Game.tscn`, `MVP._ready()`:

1. The save handoff is taken FIRST, so a resumed contract can rebuild the
   property it was saved on rather than a fresh one.
2. `Property.build(...)` — the whole property, generated at the world ORIGIN
   from `ACAPropertyParams.for_job(job)`. Lawn size comes from
   `job.grid_size.x` (96 / 144 / 192).
3. Ambient audio starts.
4. The mower is placed at `property.mower_start_transform()`, just off the lawn
   edge facing across it, at the real terrain height.
5. `ACAMowerCutter` is created and the mower's `collided` signal is routed to it.
6. Preset Manager given the ambient player for rain ducking, and the terrain's
   own height at the lawn centre as the fog ground reference.
7. Legacy MVP HUD hidden (`hud.visible = false`).
8. `_setup_job_runtime()`:
   - `preset_manager.apply_world_state_immediate(weather, hour)`
   - connects `WorldClock.weather_changed` and
     `ACALawn.mowing_progress_changed`
   - restores the saved cut state, if there is one

`Gameplay UI.tscn` (a child of the scene) then shows the Job Intro with real
contract data and brings up the production HUD.

### Property construction

Features are chosen from the seed, the terrain bakes with their offsets already
applied, the lawn lays out one cell per square world unit and asks the features
which are mowable, feature nodes are added, then grass and foliage are placed.
All synchronous; every query is valid the moment `build()` returns.

A Small Lawn is 96 × 96 = 9,216 cells; a Large Lawn is 192 × 192 = 36,864. The
cells are BYTES, not nodes: the property has one physics body, the terrain's
height map. See [Property, terrain and lawn](systems/property-and-lawn.md).

## Active gameplay loop

`MVP._physics_process`:
- pushes the mower position into the Preset Manager (rain emitter follows)
- `_tick_job_runtime(delta)`: accumulates `GameSession.add_job_elapsed(delta)`,
  and every 0.5 s pushes `lawn().mowed_fraction()` into
  `JobManager.update_job_progress()`

`gameplay_ui._process` pushes progress, fuel, clock text and weather into the HUD.

Cutting: mower `collided` → `ACAMowerCutter.on_blades_active()` →
`ACALawn.mow_deck(previous, current, deck)`. The signal is unchanged — it still
fires every physics frame while the engine runs and stops when the tank is empty
— but the payload is ignored and the cut is decided by GEOMETRY: the machine's
deck rectangle, swept along the ground it actually covered. `mow_deck()` returns
how many cells really changed, so the O(1) counter cannot drift.

## Completion

One authoritative path. Natural 100% (`mowing_progress_changed` reaching 1.0) and
the development helper (`dev_complete_current_job()`, F10) both call
`MVP._finish_job()`:

```
GameSession.complete_current_job(completion, elapsed)
  JobManager.update_job_progress(id, completion)
  JobManager.complete_job(id)      # Current -> Past, COMPLETED, timestamped
  add_money(base_pay)
  AppUI.notify_money(...)
  emit job_settled(summary)
```

`gameplay_ui._on_job_settled()` closes the whole pause stack, hides the HUD, and
shows the Job Complete screen. Its RETURN TO TOWN button calls
`GameSession.go_to_town()`.

If the mowing scene is opened standalone with no Gameplay UI, `MVP._on_job_settled()`
returns to town itself rather than stranding the player.

## Pause stack

`PauseMenu` reads Escape and pauses the tree. Stack order in
`Gameplay UI.tscn` is Pause → Settings → Controls Help → Confirmation Dialog;
later siblings receive `_unhandled_input` first, so the topmost modal consumes
Escape. `_maybe_unpause()` only unpauses when nothing else in the stack is open.

Restart / Abandon / Quit-to-menu each go through a confirmation dialog.
Abandon calls `JobManager.discard_current_job()` — not completion, no pay, and
**not** recorded as business history.
