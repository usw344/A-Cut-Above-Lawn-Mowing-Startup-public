# Validation and Development Tools

Status: **Current**. All of this is development-only and must never gate release
gameplay.

## Automated validation

Godot executable used for all of these: **4.6.1 stable**.

| Tool | Run with | Checks |
|---|---|---|
| `Dev tools/Validation/validate_all.gd` | `godot --headless --path . --script "res://Dev tools/Validation/validate_all.gd"` | Loads every `.gd` and `.tscn` under `res://`. Exit 1 on any failure. |
| `Dev tools/Validation/Flow Test.tscn` | `godot --headless --path . "res://Dev tools/Validation/Flow Test.tscn"` | The full application loop, 54 assertions. Also runs with a real renderer (drop `--headless`). |
| `Dev tools/Validation/UI Smoke Test.tscn` | `godot --headless --path . "res://Dev tools/Validation/UI Smoke Test.tscn"` | Loads, instantiates and drives the public API of every component in `res://UI/`, 60 assertions. |
| `Dev tools/Validation/Screenshot Tour.tscn` | `godot --path . "res://Dev tools/Validation/Screenshot Tour.tscn" -- "--tour-output=<dir>"` | Walks the real loop, saves a PNG per screen. **Needs a real renderer** — it captures the viewport, so `--headless` does not work. |
| `Dev tools/Validation/Save Test.tscn` | `godot --headless --path . "res://Dev tools/Validation/Save Test.tscn" -- "--save-root=<dir>"` | Save/load resume tests A, B, C plus robustness, 59 assertions. **Always pass `--save-root`** so it never writes outside the working folder. |
| `Dev tools/Validation/Pause Test.tscn` | `godot --headless --path . "res://Dev tools/Validation/Pause Test.tscn" -- "--save-root=<dir>"` | The pause stack in **both** screens, cursor ownership, and the mower look convention. 49 headless / 54 with a renderer. **Pass `--save-root`.** |
| `Dev tools/Validation/Credits Test.tscn` | `godot --path . "res://Dev tools/Validation/Credits Test.tscn"` | The credits loader against a throwaway `user://` fixture, the real `res://Credits/` folder, and the Credits screen opened from the Main Menu. 40 assertions. |
| `Dev tools/Validation/Weather Test.tscn` | `godot --headless --path . "res://Dev tools/Validation/Weather Test.tscn" -- "--save-root=<dir>"` | The weather/time VISUAL layer: the composition RULE (including R-020 at four hours), fog is not a white wall, readability limits, clock ownership, convergence, persistence, the precipitation rig, and that the quality levels genuinely differ. **75 assertions.** |
| `Dev tools/Validation/Weather Matrix.tscn` | `godot --path . "res://Dev tools/Validation/Weather Matrix.tscn" -- "--matrix-output=<dir>"` | Renders 4 times x 3 weathers in the real mowing scene + 6 town shots, and logs fps per combination. **Needs a real renderer.** Look at the images. |
| `Dev tools/Validation/Sky Probe.tscn` | `godot --path . "res://Dev tools/Validation/Sky Probe.tscn" -- "--sky-output=<dir>"` | Renders **just the sky** for each shipped weather look, plus a sweep of `clouds_cumulus_size`. **Needs a real renderer.** Use it to judge a cloud parameter in one run instead of one 33-second trailer per guess. |
| `Dev tools/Validation/Sun Probe.tscn` | `godot --headless --path . "res://Dev tools/Validation/Sun Probe.tscn"` | Prints Sky3D's sun/moon altitude per half hour. Used to place the time-of-day anchors; re-run it if the Skydome's latitude/date/mode change. |
| `Dev tools/Validation/Fuel Test.tscn` | `godot --headless --path . "res://Dev tools/Validation/Fuel Test.tscn" -- "--save-root=<dir>"` | The real fuel system: burn rates, time-vs-tick, empty stops the wheels AND the blades, refuel recovers, Auto Refuel both ways, the HUD gauge, save/load of a partial and an empty tank, and the Push Mower being manual. 56 assertions. **Pass `--save-root`.** |
| `Dev tools/Validation/Audio Mix Probe.tscn` | `godot --headless --path . "res://Dev tools/Validation/Audio Mix Probe.tscn" -- "--save-root=<dir>"` | **Measures** the mix: plays the real scene in Clear / Foggy / Rain at idle and mowing and reports the peak level each bus reaches, then asserts the relationships. 15 assertions. Re-run it after changing a source level or a bus trim. |
| `Dev tools/Validation/Trailer Test.tscn` | `godot --headless --path . "res://Dev tools/Validation/Trailer Test.tscn"` | The Trailer Capture scene's STRUCTURAL contract: it loads, the presentation adapters exist, the storyboard is in order and inside 35-48s with varied shot lengths, the adapters put back everything they borrow, gameplay tuning is untouched, the mowing shots are slower than gameplay, and it is not the main scene. 101 assertions. |
| `Dev tools/Validation/Town Probe.tscn` | `godot --path . "res://Dev tools/Validation/Town Probe.tscn" -- "--town-output=<dir>"` | Grazing-angle close-ups of the real Business Town, each rendered TWICE with the camera's far plane nudged so depth ties can be counted. **Needs a real renderer.** |
| `Dev tools/Validation/coplanar_probe.gd` | `godot --headless --path . --script "res://Dev tools/Validation/coplanar_probe.gd" -- "--coplanar-scene=<scene>"` | Finds Z-fighting BEFORE it is rendered: reports every pair of meshes that share a face plane while overlapping on the other two axes. |
| `Main Area/ACA_JobSystem/tests/JobSystemTests.tscn` | `godot --headless --path . "res://Main Area/ACA_JobSystem/tests/JobSystemTests.tscn"` | The Job System's own suite, 110 assertions. |
| `Dev tools/Validation/environment_test.gd` | `godot --headless --path . --script "res://Dev tools/Validation/environment_test.gd"` | Guards the REUSABLE environment package: that it contains no A Cut Above paths or class names, bundles no binary assets, composes with nothing bound, measures fog height from the declared ground, survives interrupted transitions, and that its quality levels remove real work. **28 assertions.** |
| `Dev tools/Validation/Economy Test.tscn` | `godot --headless --path . "res://Dev tools/Validation/Economy Test.tscn" -- "--save-root=<dir>"` | The market, the shops and the upgrades — plus a **90-day simulation** and a **6-seed x 365-day sweep** that print what the market actually did. `--economy-days=` and `--economy-seeds=` widen the sweep. **93 assertions.** **Pass `--save-root`.** |
| `Dev tools/Validation/Upgrade Probe.tscn` | `godot --headless --path . "res://Dev tools/Validation/Upgrade Probe.tscn" -- "--save-root=<dir>"` | **Drives the real mowers** with real `Input` actions and measures displacement per second and fuel burned per second, stock against upgraded, for all three machines. **15 assertions.** |
| `Dev tools/Validation/Town Services Probe.tscn` | `godot --headless --path . "res://Dev tools/Validation/Town Services Probe.tscn" -- "--save-root=<dir>"` | Drives the Supply Store, Mower Workshop and Business Office through their **real `Button` nodes** — checks what they say, presses them, and checks what changed. **29 assertions.** |
| `Dev tools/Validation/pond_test.gd` | `godot --headless --path . --script "res://Dev tools/Validation/pond_test.gd"` | The EXPERIMENTAL pond carver: non-destructiveness, the density refusal, geometry, normals, shape controls, the exclusion API, collision, and the edge cases an integrator will hit (a pond bigger than the mesh, one straddling its boundary, one centred off it entirely, zero irregularity, a bathtub bank, a null mesh). **37 assertions.** No renderer needed. |
| `Dev tools/Validation/docs_audit.gd` | `godot --headless --path . --script "res://Dev tools/Validation/docs_audit.gd"` | Checks the DOCUMENTATION against the repository: every `res://` path exists, relative links resolve, the mkdocs nav and the page set agree, and no page mentions a class or path this build removed. **5 checks.** |
| `Dev tools/Validation/Flicker Probe.tscn` | `godot --path . "res://Dev tools/Validation/Flicker Probe.tscn" -- "--flicker-output=<dir>"` | **Measures temporal instability** in the Town: holds the camera still and reports the mean absolute difference between consecutive frames, under three conditions it forces itself. **Needs a real renderer.** |
| `addons/aca_sky3d_environment/demo/Environment Demo.tscn` | `godot --path . "res://addons/aca_sky3d_environment/demo/Environment Demo.tscn" -- "--demo-shots=<dir>"` | The environment package's STANDALONE demo — loads none of the game. Renders the whole quality x weather x time matrix (36 shots) and quits. **Needs a real renderer.** |
| `Mowing Section/Experimental/Pond/Pond Demo.tscn` | `godot --path . "res://Mowing Section/Experimental/Pond/Pond Demo.tscn" -- "--pond-shots=<dir>"` | The pond prototype's standalone scene. Renders a review set, then prints the density-refusal and exclusion-API results. **Needs a real renderer.** |

### Why these are scenes, not `--script`

`--script` replaces the main loop, so **the autoloads are never created** and
`WorldClock` / `JobManager` / `GameSession` do not exist. Anything that needs the
real application must run as a scene. `validate_all.gd` is the exception — it
only touches `ResourceLoader`.

### Why the runners use a boot shim

`Dev tools/Validation/runner_boot.gd` (and the older `flow_test_boot.gd`)
instantiate the runner and parent it to `/root`. A scene change frees
`current_scene`; a runner living there would be freed mid-test. Anything driving
scene transitions must use the shim.

### Pause Test coverage

Everything Milestone 5 changed and no older suite touches.

- **Settings:** `invert_look_y` exists, defaults OFF, round-trips through
  `GameSettings` and through the Settings component.
- **Mowers:** all three canonical scenes instantiate and expose
  `look_sensitivity()` plus both smoothing exports.
- **Town:** pause layer present, RESTART not offered, pause opens and pauses the
  tree, cursor freed, Settings and Controls Help layer and unlayer without
  resuming underneath, save from pause, resume restores the **VISIBLE** cursor.
- **Mowing:** cursor captured before pausing, **pause releases the mouse**,
  resume **restores the captured mouse**, ENTER cannot steal the cursor back
  while paused.
- **Look direction** (needs a real renderer — the controllers only read the mouse
  while the cursor is CAPTURED, and headless never is): mouse up pitches up,
  mouse down pitches down, Invert Y flips exactly that, mouse right turns right,
  pitch stays clamped. The smoothing-value guards run headless too.
- **Results:** completing with the pause menu still open closes the stack,
  disables Escape-to-pause, unpauses, and keeps a usable cursor for the RETURN
  button; the following transition leaves no stale cursor hold.

Cursor assertions read `AppUI.effective_mouse_mode()` — the *logical* state.
`Input.mouse_mode` is never written on a headless DisplayServer, so asserting on
it would prove nothing.

### Credits Test coverage

Two halves, deliberately:

1. **The loader**, against a fixture folder the test writes and deletes under
   `user://`. It never edits a real licence file — a test must not be a reason
   to touch attribution text. Covers: the `_licence` convention, multi-word
   titles, the tolerated `_license` / `_credit` / `_credits` endings, ignoring a
   README / an unrelated `.txt` / a bare `licence.txt`, deterministic ordering,
   verbatim text with line breaks and non-ASCII preserved, and a missing file
   returning empty rather than crashing.
2. **The real folder and screen**: `res://Credits/` scans, Sky3D / Terrain3D /
   Godot Engine are credited, the Sky3D text is the real licence, the old MVP
   HUD credits nodes are gone, CREDITS from the Main Menu opens the screen, every
   folder entry is listed, long text is wrapped inside a scrollable pane, and
   BACK returns to the menu.

### Fuel Test coverage

The old implementation had three faults at once — a per-PHYSICS-TICK counter at
576 Hz (a tank in ~4 seconds), a silent refill to 100 in every controller, and
no mower-type distinction. All three are behavioural, so all three are asserted
behaviourally rather than by reading the source.

1. **Rules** (pure API, no scene): a full tank lasts exactly
   `FULL_TANK_DRIVING_SECONDS`; that value sits between the Job System's own
   4.6-minute and 18.4-minute contract estimates; ten 0.2 s steps equal one
   2.0 s step; two seconds burns exactly `rate * 2`; fuel never goes negative;
   `refuel` / `refuel_full` / overfill; `emptied` fires once per transition;
   Auto Refuel defaults OFF, recovers an already-dry tank when switched on, is
   not a fuel lock, and refills after empty; the three controllers report the
   right `is_powered()`.
2. **The real rider in the real scene**: driving burns fuel at a rate matching
   the TIME that passed (a per-tick model would overshoot by ~100x); an empty
   tank stops propulsion *and* the blades and does not refill itself; the
   production HUD gauge matches `MowerFuel.fraction()`; refuelling restores
   both; Auto Refuel OFF sits at zero and ON recovers.
3. **The Push Mower**: moves and cuts on a completely empty tank, and consumes
   nothing when the tank is full.
4. **Save / load**: a partial tank is restored to the exact value (read before
   any frame runs — an idling powered mower legitimately starts burning the
   moment the scene is live), an EMPTY tank loads empty and does not reset to
   100, a restored empty mower still will not drive or cut, and a manual refuel
   recovers it.

### Audio Mix Probe — measuring instead of guessing

"Perceived balance" cannot be asserted; the level each family of sounds reaches
can. The probe samples `AudioServer.get_bus_peak_volume_*_db` per frame in six
states and prints a table. It also proves the specific bug the old mix had: a
Clear -> Rain -> Clear round trip must leave the ambience player at *exactly*
its authored level.

The numbers it produced are in
[weather, time and audio](systems/weather-time-and-audio.md#audio). `Weather
Test` carries cheap structural guards (the buses exist, everything routes to
Master, both settings reach their buses) so a missing bus layout fails fast
without running the heavy probe.

### Finding Z-fighting — two tools, one answer

Milestone 11 needed to know WHICH surfaces in the Business Town were fighting,
not just that something was. Two tools, deliberately independent:

**`coplanar_probe.gd`** is analytic and headless. It walks a scene, computes
every `MeshInstance3D`'s world AABB and reports pairs that share a face plane —
same axis, same side, same coordinate — while overlapping on the other two axes.
That is the exact geometric condition for two opaque surfaces to tie in the
depth buffer. Two things to know when reading its output:

- `ymin` pairs are almost always boxes SITTING on the same ground plane. Those
  faces point down and are never drawn; ignore them.
- an AABB face is only a real surface for an axis-aligned box. Trees, bushes,
  cars and rotated props report bounding planes no geometry lies in.

**`Town Probe.tscn`** measures it in pixels. Each shot is rendered twice with
the camera's `far` plane nudged. `near`/`far` appear only in the depth row of
the projection matrix, so the two images are identical EXCEPT where two surfaces
are tied in depth — there the different quantisation flips which one wins. Every
pixel that changes is a Z-fighting pixel, which turns "does this look wrong?"
into a number:

| Shot | Before Milestone 11 | After |
|---|---|---|
| real overview | 214 | **6** |
| car park graze | 362 | **4** |
| car park high | 655 | **4** |
| park path east | 642 | **11** |
| FutureLot sill | 316 | **6** |

What is left is silhouette antialiasing.

**Shadows and SSAO are switched off for both halves of that comparison.** The
directional shadow splits are derived from the camera range, so leaving them on
paints every shadow edge in the town red and buries the real signal — the first
run reported 49,351 "depth ties" in the overview shot, essentially all of them
shadow edges.

### Weather Test coverage

The look is judged from pixels (Weather Matrix); this suite asserts what a
screenshot cannot show.

- **Composition:** every time profile carries the same key set, anchors are
  sorted and cover 00:00-24:00, every hour resolves to a complete look, and the
  RULE holds — evening rain keeps the evening hue scaled down rather than being
  replaced by grey, while clouds and fog come from weather regardless of hour.
- **Readability, as assertions:** night exposure >= 1.0 and moon >= 0.5 in every
  weather, day exposure <= 1.2, ambient fill >= 0.9, and `fog_start > 0` in
  Foggy so the near field never becomes a white wall.
- **Clock ownership:** `sky3d.enable_game_time` is off and the sky is showing
  WorldClock's hour; advancing the clock moves the sky.
- **Convergence:** three weather changes in one frame settle on the LAST one,
  and no Tween node is left behind.
- **Rain:** raining, emitter following the mower, ambience player handed over.
- **Persistence:** weather + time survive Town -> Job and a save/load round
  trip, and the visuals are re-applied to the restored state.
- **Town:** the adapter is bound, its `Day` profile is still the authored town,
  and it shares the sky adapter's anchors.

### Weather Matrix — reviewing the look

Twelve mowing shots (morning/day/evening/night x Clear/Foggy/Rain) plus six town
shots, all from a fixed camera pose so two runs line up. It also prints average
and minimum frame rate per combination — 115-131 fps measured 2026-08-19, with
no weather-specific cost.

Things the screenshot pass has actually caught: an "Evening" anchor placed after
sunset (a black screen with stars), and town fog copied from the mowing scene
rendering the whole town as a white wall.

### Save Test coverage

- **A — town save:** advance time, set weather, save, wipe all live state, load.
  Asserts time, day, weather, money, offer count, and that restored offers have
  not silently lapsed against the restored clock.
- **B — active job save:** accept, enter gameplay, cut a controlled subset, save,
  wipe, load. Asserts the same contract id/pay/status, the grid rebuilt at the
  contract size, **the exact cut count restored**, fuel, weather, world time,
  that the resume handoff was consumed, then keeps mowing and completes.
- **C — completed job save:** save after a completion, wipe, load. Asserts the job
  is still in history, still COMPLETED, and **not active again**.
- **Robustness:** missing slot, corrupt JSON, unknown format version, a save
  missing a required section — each must fail cleanly and leave the application
  usable. Also checks the `.bak` is written and no `.tmp` is left behind.

Test B **pauses the tree** around its measure/save/load window. The mower starts
sitting on the lawn, so live physics keeps cutting grass and burning fuel between
the measurement and the save, which would make the comparison meaningless.
`GameSession` and `AppUI` are `PROCESS_MODE_ALWAYS`, so scene transitions still
work while frozen.

### Flow Test coverage

Boot → autoloads → new game → town → real generated offer → accept → begin →
mowing scene → grid matches contract size → world time preserved → weather
preserved through the Preset Manager → gameplay UI (HUD contents, intro, legacy
HUD hidden, pause open/close) → dev fast-completion → real COMPLETED state and
payout → results screen contents → **RETURN TO TOWN pressed as a real button** →
town reloaded → completed job retained.

It calls the same public methods the UI calls. It never writes private state to
force a PASS.

## Development-only gameplay helpers

In the mowing scene (`Game/M.V.P/MVP.gd`), clearly marked
`_____Dev_Only_Helpers_____`:

| Helper | Key | What it does |
|---|---|---|
| `dev_complete_current_job()` | **F10** | Completes the active contract **through the real pathway** — the same `_finish_job()` that natural 100% mowing calls, which calls `GameSession.complete_current_job()`. Only the driving is skipped; nothing is faked. |
| `dev_set_reported_progress(fraction)` | — | Reports arbitrary progress into `ACAJobManager` without cutting grass. For save/resume testing. |
| `dev_toggle_debug_hud()` | **F3** | Shows/hides the legacy MVP HUD. |
| `dev_refuel_now()` | **F7** | Fills the tank through the real `MowerFuel.refuel_full()`. |
| `dev_toggle_auto_refuel()` | **F8** | Auto Refuel ON/OFF. Also a checkbox on the F3 HUD. |
| `dev_drain_fuel()` | — | Empties the tank, so zero-fuel behaviour can be seen without waiting eight minutes. F3 HUD button. |

Quick save / quick load are **not** development-only — they are real player
controls bound to **F5** / **F9** in `GameSession._unhandled_input()`.

Other in-scene development keys: `1/2/3/4` time-of-day presets, `7/8/9` weather
(these write to `WorldClock`, so the choice survives the next scene change),
`F7` refuel and `F8` Auto Refuel.

## Legacy MVP HUD

`Game/M.V.P/MVP_HUD.tscn` is retained as a **development diagnostics layer**. It
is hidden on load and toggled with F3. Its mower-swap, grid-reset, speed slider,
time and weather controls all still work, and it is the **only** place Auto
Refuel is exposed — that row must never appear on the production HUD. The player-facing UI is the Gameplay
UI stack.

## Reference-graph analysis

Cleanup used a reference graph over paths **and** UIDs, seeded from the real
roots (main scene, autoloads, enabled plugins). Two traps worth remembering:

1. Many paths in this project **contain spaces**, so a whitespace-terminated
   `res://\S+` regex silently misses them. Match the longest prefix that is a
   real file instead.
2. The graph cannot see `class_name` usage. Every candidate must also be grepped
   for its `class_name` before being called unused.

## Trailer Capture — media tooling

`res://Game/Demo/Trailer/Trailer Capture.tscn`. An automatic **~42 second**
trailer that runs the REAL game and then holds on a title card. Open the scene,
start OBS, press Play. Full detail in `Game/Demo/Trailer/README.md`.

```
godot --path . "res://Game/Demo/Trailer/Trailer Capture.tscn"
```

| Flag | |
|---|---|
| `-- "--trailer-shots=<dir>"` | three review PNGs per beat, spread across that beat's own length, plus a framing readout per frame |
| `-- "--trailer-quit"` | quit when it ends, so a run is an automated check |

**It is not the application main scene and must never be set as one.**
`Trailer Test` asserts that.

Controls, none of which are needed for a capture: **R** restart, **SPACE** pause,
**ESC** quit. It never closes Godot on its own.

### V3 — a presentation layer instead of altered gameplay

Trailer V2 tried to prove every shot was ordinary gameplay. It was, and the
footage suffered for it: composition had to be built around whatever the
gameplay controller would do, and because the rider is authored two units above
the lawn and falls into place, a shot starting the instant it was repositioned
could catch it dropping — or, at 1.4x speed, launching.

V3 keeps every piece of REAL GAME CONTENT and drops the requirement that it be
driven by NORMAL GAMEPLAY SIMULATION.

| | |
|---|---|
| **REAL** | the menu and its hover state, the Business Town, `ACAJobManager` generating and awarding a contract, the Job Board's own buttons, the transition and Job Intro screens, the canonical rider with its model, wheels, steering wheel and engine audio, the mowing GRID really losing the grass that disappears, the weather system, the real fuel system, the production HUD, and `GameSession.complete_current_job()` |
| **STAGED** | where the mower is and how fast it moves, which blades get cut and when, how far the storm is pushed, which UI layer is up, and where the camera is |

`Game/Demo/Trailer/Presentation/`:

| Script | class_name | Owns |
|---|---|---|
| `cinematic_camera.gd` | `ACACinematicCamera` | `static` / `follow` / `orbit` / `rail` shots, a separate `look_rail`, lens moves, camera-local DOF |
| `trailer_mower_adapter.gd` | `ACATrailerMowerAdapter` | the mower's transform for the length of a shot |
| `trailer_lawn_adapter.gd` | `ACATrailerLawnAdapter` | which grass is cut, and when |
| `trailer_weather_adapter.gd` | `ACATrailerWeatherAdapter` | how much further than shipped the storm is pushed |
| `trailer_ui_director.gd` | `ACATrailerUIDirector` | exactly which UI layer is on screen |

### What must be restored after a capture

All of it is asserted by `Trailer Test`:

- the mower's controller gets its `_physics_process` back (`release()`);
- `ACAWeatherVisualAdapter`'s presentation override is cleared, and clearing it
  restores the shipped look **exactly**;
- the rain emitter ratios and the near-rain scale go back;
- notifications are un-suppressed and the cursor lock is released;
- **`model.speed` was never written**, so there is nothing to restore. Shot
  speed belongs to the mower adapter. The test greps the director's source for
  `model.set_speed` to keep it that way.

### Two small reusable APIs this added outside the trailer folder

| | |
|---|---|
| `Custom_Gridmap.mow_swath(from, to, half_width)` / `mow_disc()` | the grid's OWN cut — same `mow_item_silent`, same MultiMesh rebuild, same counters, same signal — selected by geometry instead of by a physics contact. Needed because the mower adapter owns the transform, so there are no slide collisions. Nothing in normal gameplay calls it. |
| `ACAWeatherVisualAdapter.set_presentation_override(layer)` | one extra composition layer in the same `scale` / `set` shape as the shipped weather layers, applied last. Empty in normal gameplay. |

### Reviewing it — measuring beats guessing

Every review PNG logs where the mower actually landed:

```
[TRAILER]   09-mower-close-c.png  mower 0.62,0.52  w 0.40 h 0.43
```

x/y are fractions of the viewport (0.5,0.5 is dead centre) and w/h are the
mower's **visual AABB** projected to screen. Not the node origin — the rider's
origin sits below and behind the machine, so a close shot that frames the
bodywork beautifully reports its origin off-screen.

It is what makes framing tractable. An offset is in the mower's local frame, the
aim is somewhere else again, and a follow camera lags by roughly `speed / damp`
world units — on the fast beats that was quietly adding fifteen to twenty-five
units to the working distance and shrinking the mower to a speck.

Three geometry facts about this project that every trailer camera has to respect
are written up in `Game/Demo/Trailer/README.md`: the mowing lawn is a bowl ringed
by twenty-unit trees, the grass is three units tall, and the Business Town is a
MINIATURE on a floating island.

### V3.1 — the mowing shots (Milestone 13)

The mowing section was reworked on its own; the menu, the town pan, the Job
Board and the end card were not touched, and `diff` against Backup 12 shows
exactly three changed files.

| Was | Is |
|---|---|
| the mower planted where its own physics settled — on top of three-unit grass colliders, above a collision box half a unit proud of the visible dirt, so it FLEW | `_measure_ground_y()`: the visible `Mowing Area` plane plus `ACATrailerMowerAdapter.visual_lift()`, measured from the mower's own meshes |
| mowing shots at 38-55 u/s, so every lens had to be far away | 13-24 u/s, SLOWER than gameplay's 30, so every lens can be close. `Trailer Test` guards it |
| five mower angles, one of them a wide plate where the mower was 4% of the frame | three shots, all close, all framing the cut/uncut boundary |
| one bob/roll for every shot | `set_suspension()` per shot — a MOUNTED lens turns a bob into camera shake |

The hero shot is now `mower over the top`: the lens in the driving seat with the
steering wheel in frame, looking forward over the bonnet. It is the closest this
game gets to a first-person view without a first-person camera existing.

## Measuring things a screenshot cannot show

Two tools in this list exist because the thing being judged is not visible in a
single frame, and both were built the same way: decide what the claim actually
is, then find a number that expresses it.

### `Flicker Probe` — the Town's shadows

"The shadows flicker" is a statement about the difference between CONSECUTIVE
FRAMES. A flickering town and a stable one produce identical stills. So the
probe holds the camera still, captures a run of frames and reports the mean
absolute difference between each pair, at 480x270 with NEAREST resampling —
smoothing is exactly what would hide a one-pixel shimmer.

It forces its own conditions rather than inheriting the scene's, because
otherwise changing a scene default silently turns three measurements into three
measurements of the same thing. It restores what it changed.

### `Economy Test`'s 90-day simulation

A green suite proves the economy is CONSISTENT. It says nothing about whether
fuel spends three months at the ceiling or a recession arrives every other week.
The simulation prints the distribution and asserts only on values that would be
absurd rather than merely debatable — and it separates DRIFT from event and
regime STEPS, because measuring them together only proves that events exist.

### `Upgrade Probe` — proving the machine changed, not the dictionary

`Economy Test` asserts that `MowerUpgrades.speed_multiplier("rider")` returns a
bigger number after a purchase. That is a statement about a dictionary.

It is **not** a statement about the mower. A controller could ignore the
multiplier, apply it to the wrong term, or apply it twice, and every one of
those assertions would still pass. The only way to know the machine got faster
is to press the throttle and measure how far it went.

So the probe holds real `Input` actions down, in the real mowing scene, through
the real controllers, and measures — resetting the grid between runs, because
otherwise the second run drives through a lane the first one already cut and the
comparison is between two different worlds. Results are normalised by **elapsed
time**, so a frame-rate difference between runs cannot masquerade as speed.

Measured 2026-08-20:

| | stock | upgraded | change | asked for |
|---|---|---|---|---|
| rider — speed | 14.99 u/s | 19.95 u/s | **+33.0%** | +33% |
| powered — speed | 15.00 u/s | 19.95 u/s | **+32.9%** | +33% |
| push — speed | 15.04 u/s | 19.35 u/s | **+28.7%** | +29% |
| rider — fuel burn | 0.2081 u/s | 0.1458 u/s | **−29.9%** | −30% |
| powered — fuel burn | 0.2084 u/s | 0.1458 u/s | **−30.0%** | −30% |

### The economy sweep

One 90-day run with one seed can be lucky. The sweep walks several seeds a full
year each and asserts on the **worst case across all of them**, so a pathology
that only appears in some markets has somewhere to show up.

Six seeds x 365 days, 2026-08-20: fuel $0.83–$1.60 (the clamp working), drift
4.9–5.9%, events 25–31% of days, and the most common condition occupying 36–49%
of a year — Stable dominates by design without monopolising, and all four
conditions appear in every seed.

### `Town Services Probe` — proving a player can reach the rules

`Economy Test` calls `GameSession.try_spend()` and
`MowerUpgrades.try_purchase()` directly. Those are the right things to
unit-test, and they prove the RULES.

They do not prove a player can reach them. A button could be disabled when it
should not be, wired to nothing, wired to the wrong category, or **show a price
it does not charge** — and every assertion in `Economy Test` would still pass.

So this probe walks the route a player walks: opens each service the way
clicking a building does, finds the actual `Button` nodes, reads their text,
presses them, and checks the world afterwards. The assertions worth naming:

- the refuel button's printed price is the price actually charged;
- a full tank stops offering a refuel at all;
- a broke player gets a **disabled** button, and pressing it anyway leaves them
  with no fuel and no debt;
- the Push Mower tab offers no fuel system;
- the dashboard **follows** the market rather than snapshotting it — asserted on
  the fuel price, which drifts every day, rather than on the condition name,
  which can legitimately still be "Stable" sixty days later. An assertion that
  can pass because nothing happened is not an assertion.
