# Application Layer

Status: **Current** — added 2026-08-19. This is the layer that turns the
individual systems into one running game. Read this page first.

## Why it exists

Before this layer, every system worked on its own and none of them were
connected: nothing owned scene transitions, nothing supplied a world clock, and
nothing listened to `ACAJobManager.begin_job_requested`. Because the Job System
had no time provider it ran on a stopped default clock, so **no job offer could
ever be generated.**

## Autoloads (order matters)

Declared in `project.godot` in this order; later ones depend on earlier ones.

| # | Name | Script | Role |
|---|---|---|---|
| 1 | `model` | `Data Structures/Model.gd` | Legacy global state: mower speed, blade length, cuttings, selected mower, and the fuel **level**. |
| 2 | `MowerFuel` | `Game/App/mower_fuel.gd` | **Authoritative** fuel RULES. Reads and writes `model.mower_fuel`. |
| 3 | `WorldClock` | `Game/World/world_clock.gd` | **Authoritative** world time, season, weather preset. |
| 4 | `JobManager` | `Main Area/ACA_JobSystem/job_system/manager/job_manager.gd` | **Authoritative** owner of every job. |
| 5 | `GameSettings` | `Game/App/game_settings.gd` | Presentation settings + applying them. |
| 6 | `AppUI` | `Game/App/app_ui.gd` | Persistent UI: transitions + notifications. |
| 7 | `GameSession` | `Game/App/game_session.gd` | Screen routing, money, the completion pathway. |
| 8 | `SaveService` | `Game/App/save_service.gd` | Save/load. See [save and load](systems/save-and-load.md). |

`GameSession._ready()` is what hands `ACAWorldClockTimeProvider` to
`JobManager.set_time_provider()`. Without that call the job market is dead.

`MowerFuel` sits directly after `model` because it is the only thing that may
decide how fast fuel burns — see
[mowers and controls](systems/mowers-and-controls.md#fuel--reworked-2026-08-19-milestone-9).
The level stays on `model` so SaveService and every existing caller are
unchanged.

---

## GameSession — `Game/App/game_session.gd` (`ACAGameSession`)

**RESPONSIBILITIES** — exactly three:
1. Which screen the application is on, and every scene transition.
2. Durable session state not owned elsewhere: money, session-active, job stopwatch.
3. **THE ONE authoritative job-completion pathway.**

It does **not** own job state (`ACAJobManager` does), world time or weather
(`ACAWorldClock` does), the mowing grid (`Custom_Gridmap` does), or presentation.

**PUBLIC API**
```
start_new_game()                                  end_session()
go_to_main_menu()  go_to_town()  go_to_mowing()
current_screen() -> Screen        is_changing_scene() -> bool
money() -> int                    add_money(amount)
current_job() -> ACAJob           current_job_id() -> StringName
has_active_job() -> bool          job_elapsed_seconds() -> float
add_job_elapsed(delta)            set_job_elapsed(seconds)
complete_current_job(completion, elapsed_seconds = -1.0) -> bool
abandon_current_job() -> bool
to_save_dict() / from_save_dict(data)
```

**SIGNALS**
`screen_changed(screen)`, `session_started()`, `session_ended()`,
`money_changed(amount)`, `scene_change_started(target_screen)`,
`job_settled(summary: Dictionary)`

`job_settled` carries everything a results screen needs, so UI never reaches into
job internals: `job_id, job_name, job_size, completion, elapsed_seconds,
base_pay, bonus, total`.

**SCREENS** — `Screen.{NONE, MAIN_MENU, TOWN, MOWING}` mapped to:
- `res://Game/App/Main Menu Screen.tscn`
- `res://Game/App/Town Screen.tscn`
- `res://Game/M.V.P/Minimum Viable Game.tscn`

**SCENE TRANSITIONS** — `_swap_scene()` covers the screen via `AppUI`, waits for
`screen_covered`, calls `change_scene_to_file` deferred, waits two frames, then
reveals. Concurrent requests are ignored while `is_changing_scene()`.

---

## WorldClock — `Game/World/world_clock.gd` (`ACAWorldClock`)

**STATUS:** Authoritative. There is no other clock. Scenes adapt to it.

**THE ONE TUNING VALUE:** `game_minutes_per_real_second` (default `6.0` — a 24h
game day takes four real minutes). Do not hard-code time conversions anywhere else.

**PUBLIC API**
```
start_new_world(start_minutes = 08:00)   set_running(value)   is_running()
game_minutes() -> float      hour_of_day() -> float (0..23.99, for Sky3D)
day_index() -> int           day_number() -> int (1-based)
clock_text() -> "09:41"      timestamp_text() -> "Spring Day 12  09:15"
season() / set_season(value)
weather_preset() -> String   set_weather(preset)   cycle_weather()
advance_minutes(m) / advance_hours(h) / advance_to_hour(hour)
to_save_dict() / from_save_dict(data)
```

**SIGNALS:** `time_changed(game_minutes)`, `day_changed(day_index)`,
`season_changed(season)`, `weather_changed(preset)`, `running_changed(running)`

**WEATHER:** `WEATHER_PRESETS = ["Clear", "Foggy", "Rain"]` — these strings are
what `preset_manager.apply_weather_preset()` understands. Weather lives here
because the only thing the application needs to persist is *which preset is
current*; the Preset Manager remains the sky/weather adapter and is not replaced.

**PROCESS MODE:** `PAUSABLE` — pausing the tree stops game time, deliberately.

---

## ACAWorldClockTimeProvider — `Game/World/world_clock_time_provider.gd`

Subclass of `ACAJobTimeProvider`. The Job System's documented integration point,
now filled in. **This is the only provider a real session should ever use;**
`ACAJobDebugTimeProvider` is for the standalone Job System demo and tests.

---

## AppUI — `Game/App/app_ui.gd`

Holds the two components that must outlive a scene change: the `TransitionLayer`
(CanvasLayer 128) and the `NotificationCenter` (CanvasLayer 120, under the
transition so a fade covers toasts too). It also owns the **mouse cursor**.

```
cover(duration = -1)   reveal(duration = -1)   is_covered()
set_transition_title(title, subtitle = "")     clear_transition_title()
notify_info / notify_success / notify_warning / notify_money (title, message)
clear_notifications()   notifications() -> NotificationCenter
transition() -> TransitionLayer
set_notifications_suppressed(bool)   notifications_suppressed() -> bool
```

`set_notifications_suppressed()` is **development / media tooling**: while set,
every `notify_*` above is dropped instead of queued. Trailer Capture uses it so
a toast cannot land in the middle of a cinematic shot. Normal gameplay never
sets it, and no notification was removed or weakened to make the trailer work.
**SIGNAL:** `screen_covered()` — the swap is safe now.

### Cursor ownership — THE one place that writes `Input.mouse_mode`

```
set_mouse_context(mode)   mouse_context()   effective_mouse_mode()
hold_mouse(token)         release_mouse(token)   is_mouse_held()
clear_mouse_holds()       toggle_mouse_capture()
lock_mouse_context(mode)  unlock_mouse_context()      # trailer tooling only
```

Two inputs decide the cursor:

| | Set by | Meaning |
|---|---|---|
| **context** | a screen host or a mower `_ready()` | what this screen wants when nothing modal is up — mowing `CAPTURED`, town/menu `VISIBLE` |
| **holds** | any modal that needs a cursor | while ≥1 hold exists the cursor is `VISIBLE` regardless of context |

Tokens in use: `MOUSE_HOLD_PAUSE` (the pause stack), `MOUSE_HOLD_RESULTS` (the
Job Complete screen — the mowing context is CAPTURED, so its button would be
unclickable otherwise), `debug_hud` (F3).

`GameSession._swap_scene()` calls `clear_mouse_holds()`: a hold belongs to the
screen that took it, and that screen is about to be freed.

`toggle_mouse_capture()` is the ENTER binding (`Model._input`). It is **inert
while a hold exists** — otherwise confirming a pause-menu button with ENTER would
grab the cursor back. Nothing else in the project may assign `Input.mouse_mode`.
`effective_mouse_mode()` is the logical answer and is what the tests assert on,
because a headless DisplayServer is never really captured.

Notifications fire on real domain events only: contract accepted, new offer while
in town, payment received, low fuel, settings applied, contract abandoned.

---

## GameSettings — `Game/App/game_settings.gd`

Keys match the Settings component's dictionary exactly, so
`settings.set_values(GameSettings.values())` and
`GameSettings.apply(settings.values())` both work directly.

| Key | Applied how |
|---|---|
| `mouse_sensitivity` | `mouse_sensitivity_scale()`, read by every mower's `look_sensitivity()` |
| `invert_look_y` | `invert_look_y()`, read by every mower's look code. Default **OFF** (mouse up looks up). |
| `quality` | `root.scaling_3d_scale` via `QUALITY_RENDER_SCALE` |
| `fullscreen` | `DisplayServer.window_set_mode` |
| `resolution` | `DisplayServer.window_set_size` (ignored while fullscreen) |
| `master_volume` | `Master` bus |
| `mower_volume` | `Mower` bus |
| `ambience_volume` | `Ambience` **and** `Weather` buses |

All volume keys go through `ACAAudioMix.apply_volume()`, which combines the
slider with that bus's authored trim — see
[weather, time and audio](systems/weather-time-and-audio.md#audio). The bus
layout is `res://default_bus_layout.tres`. R-014 was closed 2026-08-19; before
that only `Master` existed and two of these were inert.

**PERSISTED** to `settings.json` in `SaveService.storage_root()`, written when the
player presses Apply. It lives with the save system so both honour the same
storage-root override, but it is a property of the installation rather than of a
save, so it is a separate file.

---

## Screen hosts

| Scene | Script | Does |
|---|---|---|
| `Game/App/Main Menu Screen.tscn` | `main_menu_screen.gd` | Hosts `main_menu_scenery.tscn` (which already composes `main_menu.tscn` inside its `MenuSafeOverlay`). Finds the menu **by type**, not by path. Routes menu intent. Owns a Settings + Controls Help layer. Looks up `/root/SaveService` at runtime so it works with or without a save system. |
| `Game/App/Town Screen.tscn` | `town_screen.gd` | Hosts `BusinessTown.tscn`. Feeds real money and `set_calendar(day, clock, weather)` into `ACABusinessHUD` at 2 Hz. Job routing already happens inside the town. |
| `Game/App/Gameplay UI.tscn` | `gameplay_ui.gd` (`ACAGameplayUI`) | The gameplay UI stack, instanced **into** the mowing scene. The single integration boundary between the mowing runtime and the UI components. Extends `ACAPauseLayer`. |
| `Game/App/Pause Layer.tscn` | `pause_layer.gd` (`ACAPauseLayer`) | THE pause stack. Instanced by the Town Screen; inherited by `ACAGameplayUI`. |

`gameplay_ui.gd` expects its `gameplay_host` export to provide:
`mowing_progress()`, `mower_fuel_fraction()`, `restart_current_job()`,
`dev_toggle_debug_hud()`. `MVP.gd` implements all four.

---

## ACAPauseLayer — `Game/App/pause_layer.gd`

**STATUS:** Authoritative. There is exactly one pause menu implementation.

Wants four children by name: `Pause Menu`, `Settings`, `Controls Help`,
`Confirmation Dialog`. `Pause Layer.tscn` supplies them for the Town;
`Gameplay UI.tscn` already had them, so `ACAGameplayUI` **inherits** the class.

**PUBLIC API**
```
open_pause()  close_pause()  is_pause_open()  pause_stack_open()
close_pause_stack()          set_escape_pause_enabled(enabled)
set_pause_context(text)      set_job_actions_available(available)
set_pause_option_enabled(option, enabled)   is_pause_option_enabled(option)
control_bindings() -> PackedStringArray     # override per screen
ask(title, message, confirm_text, on_confirm)
```
**SIGNALS:** `pause_opened()`, `pause_closed()`, `restart_job_requested()`

It owns resume, save, settings, controls help, abandon and quit-to-menu.
Restart needs the mowing host, so it only emits `restart_job_requested`.

**ORDER MATTERS.** Closing the pause menu emits `closed`, which asks whether the
stack is empty; if the replacement panel is not open yet the answer is "yes" and
the screen resumes underneath it. Always open the incoming panel **before**
closing the outgoing one. This was a real bug (tree unpaused behind Settings).

**Per-screen differences** are expressed only through the option flags and
`control_bindings()`:

| | Mowing | Town |
|---|---|---|
| RESTART | enabled with a contract | never — no lawn on screen |
| ABANDON | enabled with a contract | enabled only if a contract is open |
| resume cursor | `CAPTURED` | `VISIBLE` |
| bindings | `ACAControlBindings.MOWING` | `ACAControlBindings.TOWN` |

## ACAControlBindings — `Game/App/control_bindings.gd`

`MOWING` / `TOWN` / `MENU` row sets for the Controls Help component. One place,
so the three screens cannot drift. The component's own demo defaults are never
used.

## Runtime flow

```
Main Menu Screen ──NEW GAME──▶ GameSession.start_new_game()
                                 │ JobManager.debug_clear_all()
                                 │ WorldClock.start_new_world()   (08:00, Spring, Clear)
                                 │ money = STARTING_MONEY (250)
                                 │ JobManager.seed_initial_offers(2)
                                 ▼
                              Town Screen  ── Job Office ──▶ ACAJobBoard (already bound to JobManager)
                                                                 │ ACCEPT  -> JobManager.accept_job(id)
                                                                 │ BEGIN   -> JobManager.begin_new_job(id)
                                                                 ▼
                              JobManager emits begin_job_requested(job)  ← the Job System stops here
                                                                 ▼
                              GameSession._on_begin_job_requested → go_to_mowing()
                                                                 ▼
       Minimum Viable Game.tscn: grid sized from job.grid_size.x, world time + weather
       applied through preset_manager, Gameplay UI shows Job Intro then the HUD
                                                                 ▼
       100% mowed  ─or─  dev_complete_current_job() (F10)  →  MVP._finish_job()
                                                                 ▼
                              GameSession.complete_current_job(completion, elapsed)
                                 │ JobManager.update_job_progress(id, completion)
                                 │ JobManager.complete_job(id)   ← job becomes history
                                 │ add_money(base_pay)
                                 │ emits job_settled(summary)
                                 ▼
                              Job Complete screen → RETURN TO TOWN → GameSession.go_to_town()
```

## KNOWN ISSUES

- The town re-lights from `WorldClock` through `ACATownLightAdapter` as of
  2026-08-19 (R-013 closed). It still has no rain particles and no sun elevation
  arc — see [weather, time and audio](systems/weather-time-and-audio.md).
- The town's Z-fighting was fixed 2026-08-19 (R-021). It was flush geometry, not
  depth precision: kerbs, pavement slabs, the car park and the park paths were
  authored level with their neighbours to the millimetre. **If you edit
  `BusinessTown.tscn`, re-run `coplanar_probe.gd`** — it reports any new pair of
  meshes sharing a face plane before anything is rendered. See
  [validation and development tools](validation-and-dev-tools.md#finding-z-fighting--two-tools-one-answer).
- `addons/sky_3d/assets/resources/MoonRender.tscn` fails to load — this copy of
  the addon is missing `shaders/SimpleMoon.gdshader`. Nothing in the project loads
  it. Pre-existing; left alone because it is third-party.
- Settings persistence, the Load Game picker and quick save/load (F5/F9) are all
  wired; see [save and load](systems/save-and-load.md).
