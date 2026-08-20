# Architecture Decisions and Open Questions

Status: Confirmed decisions plus review queue
Decisions recorded: 2026-08-02, updated **2026-08-19**

## Confirmed decisions

### D-001 — Authoritative runtime — **SUPERSEDED 2026-08-19**

Was: `Minimum Viable Game.tscn` is the authoritative playable architecture.

**Now:** the authoritative runtime is the **application layer** —
`GameSession` / `WorldClock` / `JobManager` autoloads routing between
`Main Menu Screen.tscn`, `Town Screen.tscn` and `Minimum Viable Game.tscn`.
`run/main_scene` is `res://Game/App/Main Menu Screen.tscn`.

`Minimum Viable Game.tscn` is now *the mowing runtime*, one screen of three.
See [application layer](application-layer.md).

`Main.tscn` was moved to `Soft Delete/`.

### D-002 — Application systems integration — **RESOLVED 2026-08-19**

Menus, jobs, economy (money only) and the full HUD are **integrated**, not
partial. The loop runs end to end and is covered by
`Dev tools/Validation/Flow Test.tscn` (54 assertions).

Still genuinely absent: save/load, spending, upgrades, reputation.

### D-003 — Canonical terrain

Decision:

The custom `Terrain Manager.tscn` and `Terrain Manager.gd` are canonical.

Terrain3D is not planned for the final game.

**Executed 2026-08-19:** the Terrain3D addon is not installed at all; its orphaned
content (`Terrain/Footage-Demo Data/`, `Game/Demo/Footage/`) was moved to
`Soft Delete/`. `Terrain/Meshes/` is ACTIVE and stayed.

Remaining: `export_presets.cfg` still lists a non-existent
`res://addons/terrain_3d/` tree.

### D-004 — Canonical mower architecture

Decision:

The three mower scenes under `Assets/Vehicles and Mowers/Mowers/` are canonical.

The older `Mower_Normal` and `Model.mower_scene_references` approach is legacy.

Consequences:

- Future mower selection, upgrades, and persistence build on the canonical scenes.
- The model should eventually store the selected mower and durable mower data using stable canonical identifiers.

### D-005 — Canonical weather and sky

Decision:

The custom Preset Manager and Rain Handler form the canonical weather direction. Sky3D is the canonical sky system.

GodotWeatherSystem is removed and not expected to return. GodotSky is historical and replaced.

Consequences:

- Current weather direction is unchanged; the Preset Manager was **not** replaced.
- **Added 2026-08-19:** the *current weather preset* is now persistent application
  state on `WorldClock`; scenes re-apply it through the Preset Manager on load.
- Snow / heavy-rain resources are authored but not yet reachable from
  `apply_weather_preset()`. Not cleanup debt — active design (see R-011).
- Stale GodotSky public text should be updated separately.

### D-006 — Obsolete ODT

Decision:

`Documentation.odt` is obsolete Godot 4 migration-era planning material.

Consequences:

- It is not a source for internal documentation.
- Repository code, the MVP graph, confirmed decisions, and these pages are authoritative.
- The ODT may be removed in later cleanup.

### D-007 — Public website boundary

Decision:

`docs/index.html` is a public portfolio/landing page, not the implementation roadmap.

Consequences:

- Its roadmap does not determine architecture or development order.
- It may lag current development.
- It remains manually maintained for public presentation.

## Review flags

These items are documented but still need future technical or design decisions.

### R-001 — Model schema for canonical mowers

Decide:

- Stable mower IDs.
- Selected mower field.
- Owned equipment representation.
- Base data versus upgrades.
- Per-mower fuel/storage state.
- Save compatibility rules.

### R-002 — First authoritative save schema

Decide:

- Profile file format and version.
- Atomic writes/backups.
- Default and optional fields.
- Job/grid serialization scope.
- Migration policy.
- Whether transient job offers persist.

### R-003 — Job acceptance and gameplay bridge — **RESOLVED 2026-08-19**

- An offer becomes an accepted contract through `ACAJobManager.accept_job()`.
  **The same `ACAJob` instance persists**; no parallel "gameplay job" object exists.
- `MVP._grid_size_for_current_job()` reads `job.grid_size.x` and passes it to
  `Custom_Gridmap.test_custom_gridmap()`.
- Completion state lives in `ACAJobManager` (`past_jobs`, status `COMPLETED`,
  `completed_game_time`).
- Pay is settled by `GameSession.complete_current_job()`, which adds
  `job.base_pay` and emits a `job_settled` summary.
- Scene transitions are owned by `GameSession`; the fullscreen transition is
  owned by `AppUI`. `ACAJobManager` still never changes scenes.

### R-004 — Economy and upgrades

Decide:

- Player balance ownership.
- Store/equipment data.
- Upgrade definitions and application.
- Relationship between model speed/blade fields and specific mower data.
- Reward/balance rules.

### R-005 — Production HUD composition — **RESOLVED 2026-08-19**

- Production interface: the `res://UI/` package, composed by
  `Game/App/Gameplay UI.tscn` (`gameplay_ui.gd`), plus `ACAJobBoard` and
  `ACABusinessHUD` in the town.
- **Development-only:** the MVP HUD, retained, hidden on load, toggled with F3.
- **Removed** to `Soft Delete/`: Mowing Information UI, Information Bar,
  Job Offer Display, the old menu prototypes.

### R-006 — Terrain generation workflow

The canonical Terrain Manager scene currently contains baked MultiMeshes while its script contains toggled generation tools.

Decide:

- Editor plugin/tool versus runtime generation.
- Deterministic seeds.
- Generated-scene ownership.
- Bake and rebuild procedure.
- Collision requirements for decorative foliage.

### R-007 — Weather formalization

Decide:

- Hard-coded presets versus custom resources.
- Weather/time state ownership.
- Save/load representation.
- Quality levels.
- Snow’s future.
- Audio bus structure.

### R-008 — Physics limit key

Confirm which Jolt maximum-body setting Godot 4.6 uses before removing or reconciling the duplicate key.

### R-009 — Grass artifact review — **PARTLY RESOLVED 2026-08-19**

- The duplicate embedded/external `Grass_Grid_Item` scripts were the cause of a
  real `Class "Grass_Grid_Item" hides a global script class` parse error on every
  project scan. The whole `Grass Grid Item/` folder was unused and moved to
  `Soft Delete/`; the error is gone.
- **Still open:** the two similarly named mowed-grass mesh resources
  (`Mowed_Grass_OBJ.obj` vs `Mowed_Grass_With_LOD_attempt1.res` — only the
  second is loaded by `Multi_Mesh_Chunk`).

### R-010 — Rider-parts Timer

Confirm whether the Timer and stale `straighten_wheel` connection can be removed now that steering return occurs continuously in `_update_steering()`.

### R-011 — Snow

The removed addon resources are deprecated, but the local `snow_particles.tscn` remains technically independent. Decide whether snow remains in scope.

### R-012 — Main Area attachment — **CLOSED 2026-08-19**

Moot: `Main Area/Old Main Area/` was superseded by `ACA_BusinessTown` and moved
to `Soft Delete/`.

### R-013 — Town lighting from the world clock — **RESOLVED 2026-08-19**

Was: the town did not re-light from `WorldClock`. Resolved by driving its
existing lights through `ACATownLightAdapter` — see the full entry below.

### R-014 — Audio bus structure — **RESOLVED 2026-08-19**

`res://default_bus_layout.tres` now ships `Master / Mower / Ambience / Weather /
UI`, every player is routed to one in its own scene, and `ambience_volume` /
`mower_volume` reach real buses. See the full entry below.

### R-015 — Export presets — **RESOLVED 2026-08-19**

`export_presets.cfg` enumerated 196 files in its two `export_files` lists, of
which **181 did not exist** — the whole `res://addons/terrain_3d/` tree, the
quarantined `Terrain/Footage-Demo Data/` files, and several foliage assets
(`SM_Grass_A1/A2`, `SM_Pine_A1`) that are not in the repository either.

Every entry was checked against the filesystem; the 181 dead ones were removed
and the 15 real ones kept. The three presets (Android, itch IO / Web, Windows
Desktop) and all their other settings were left untouched.

### D-005 — Weather looks are composed, not enumerated — **DECIDED 2026-08-19**

Four time profiles x three weather layers, with `scale` multiplying the time
value and `set` replacing it. Twelve looks from seven small tables. The
alternative — twelve hand-written presets — cannot express "evening rain is
still evening" without duplicating every evening value into every weather.

### D-006 — The visual adapter uses no Tweens — **DECIDED 2026-08-19**

One per-tick exponential approach towards the composed target instead. Time
drifts continuously, so a fixed-duration tween would be restarted forever;
overlapping weather changes cannot strand a stale tween; and convergence is
guaranteed from any state including a mid-transition load. The previous
implementation ran ~40 parallel tweens per weather change, three of which drove
setters that spawn their own internal tweens.

### R-013 — Town lighting — **RESOLVED 2026-08-19**

The town now re-lights from `WorldClock` through `ACATownLightAdapter`
(`Weather/Visual/town_light_adapter.gd`), bound by `town_screen.gd`.

It changes light only — directional light colour/energy, a yaw sweep around the
*authored* sun basis, the procedural sky gradient, ambient, exposure and fog.
`BusinessTown.tscn` is not edited, Sky3D is not put in the town, and SSAO,
colour grading, geometry and the camera rig are untouched. Every resource is
duplicated before it is written. The `Day` profile is the authored town exactly,
so the reference look is unchanged.

Reviewed against six rendered town shots. Still missing, deliberately: rain
particles in the town, and a real sun elevation arc. `light_from_world_clock =
false` on the Town Screen reverts it.

### R-017 — Sky3D time-of-day anchors are configuration-dependent — **NEW 2026-08-19**

`ACAWeatherVisualAdapter.TIME_ANCHORS` is calibrated against the sun altitude
curve THIS Skydome produces (realistic mode, latitude 16: sun up ~06:35-17:05).
If the Skydome's latitude, date or celestial mode changes, the anchors are wrong
and "Evening" can land after dark. Re-run `Dev tools/Validation/Sun Probe.tscn`
and move them. Not a bug; a coupling worth knowing about.

### R-016 — Rain audio attribution is unknown — **NEW 2026-08-19**

`Assets/Sounds/rain-sound-188158.wav` has no attribution anywhere in the
repository, and its source could not be established from the file alone. It is
deliberately **not** credited in `res://Credits/` rather than credited to a
guessed author. Confirm the source, then drop a `_licence.txt` into `Credits/`.

The other three sounds (`Ambience Sound.wav`, `Powered Lawn Mower SFX.wav`,
`Push Lawn Mower SFX.wav`) have the same problem and the same answer.

### D-003 — One pause stack, inherited rather than instanced — **DECIDED 2026-08-19**

The Town needed the same pause menu as the mowing screen. `ACAPauseLayer` holds
the whole implementation; `Pause Layer.tscn` gives it to the Town, and
`ACAGameplayUI` **extends** it rather than instancing it. That keeps every node
name in `Gameplay UI.tscn` where the existing tests already look for them, and
still leaves exactly one implementation. Per-screen differences are expressed
only through option flags and `control_bindings()`.

### D-004 — Cursor ownership belongs to AppUI — **DECIDED 2026-08-19**

Scattering `Input.mouse_mode` writes across menu buttons is what caused the
original bug. The cursor is now a context (per screen) plus refcounted holds
(per modal), owned by `AppUI`, and nothing else writes it. Resume does not
"re-capture" — it releases a hold and lets the current screen's context decide,
which is the only reason one pause menu is correct in both the town and mowing.

### D-007 — The trailer drives the game, it does not imitate it — **DECIDED 2026-08-19**

`Trailer Capture.tscn` runs the real menu, the real town, a real generated
contract, the canonical mower under its own physics, the real grid being cut and
the real completion pathway. The orchestration is a fixed seed, a frozen clock,
a chosen contract, `Input.action_press` for driving, and the development
fast-completion — all of it inside `trailer_director.gd`.

Rejected: a separate "trailer scene" built to look like the game. It would have
drifted from the game the first time anything changed, and it would have proved
nothing.

### D-008 — The trailer camera is a separate rig — **DECIDED 2026-08-19**

`ACACinematicCamera` is not a gameplay camera and gameplay cameras are not
allowed to become cinematic to serve it. That coupling is exactly what
Milestone 5 had to undo.

### R-018 — Trailer coverage gaps — **NARROWED 2026-08-19 (Milestone 10)**

Still true and accepted for a 33-second cut:

- the town has no rain particles, so the weather hero shot is in the mowing
  scene;
- mowing progress reads as a low percentage during the cinematic shots — 33
  seconds cannot cut 36,864 blades. The Job Complete screen is the payoff;
- no music. The clip is captured with game audio and scored later.

Closed by Milestone 10: the underwhelming shots, the missing storm clouds, the
opening that hid the real menu, and the mower that crawled.

## Documentation update rule

When a review flag is resolved:

1. Record the decision and date here.
2. Update the affected system page.
3. Update scene/script status tables.
4. Do not silently reclassify a second implementation as active.

### D-009 — Fuel rules have one owner; storage stays on `model` — **DECIDED 2026-08-19**

`MowerFuel` (`Game/App/mower_fuel.gd`) owns the burn rates, what empty means,
the refuel interface and the development Auto Refuel toggle. The LEVEL stays in
`model.mower_fuel`, because that is what SaveService already persists and what
every existing caller reads — so save/load needed no change and there is still
exactly one place the number lives.

Rejected: moving the value into the new node and having `model` delegate. Two
owners of one number is worse than one owner of the rules and one of the bytes.

### D-010 — Powered and manual are a property of the CONTROLLER — **DECIDED 2026-08-19**

Each canonical controller declares `const POWERED` and exposes `is_powered()`.
The Push Mower is a manual reel mower — silent when stopped, blades turned by
its wheels, and the development HUD's own menu calls the other walk-behind
"Push Power Powered" — so it declares `false` and simply never calls
`MowerFuel.consume()`. It has no `fuel_empty` signal, because it has nothing to
emit one for.

Rejected: giving every mower fuel because they happened to share the code. The
type means something.

### D-011 — The audio mix is bus trims, not per-frame rules — **DECIDED 2026-08-19**

Source levels are authored once, `ACAAudioMix.TRIM_DB` sets the balance between
families of sources, and the player's sliders scale a bus on top of that. No
weather check exists inside any mower controller and none may be added.

The trims are **measured**: `Dev tools/Validation/Audio Mix Probe.tscn` plays
the real scene in each weather state and reports the peak level each bus
reaches. See the audio section of `systems/weather-time-and-audio.md`.

### R-014 — Audio bus structure — **RESOLVED 2026-08-19**

Was: two volume settings that were stored and inert.

`res://default_bus_layout.tres` adds `Mower`, `Ambience`, `Weather` and `UI`
under `Master`. Routing is set on the `AudioStreamPlayer` nodes in their own
scenes. `master_volume` -> Master, `mower_volume` -> Mower, `ambience_volume` ->
**both** Ambience and Weather; no separate Weather slider was added, because
there is no case for turning the rain down but not the birds.

Nothing plays on the `UI` bus yet. It exists so the first UI sound has a home
rather than landing on Master by default.

One real bug fell out of the same pass: `Rain_Handler` wrote **absolute**
decibels on to the ambience player (`ambience_clear_db = 0.0`) which is authored
at -16.855 dB, so the first Rain -> Clear transition raised the ambience by
nearly 17 dB and left it there permanently. The duck is now relative to the
level captured when the player is handed over.

### R-019 — Fuel has no source and no economy — **NEW 2026-08-19**

`MowerFuel.refuel()` / `refuel_full()` exist and work, but nothing in the game
sells fuel: there is no gas can, no station and no purchase. A powered mower
that empties mid-contract can currently only be recovered by the development
refuel (F7) or by Auto Refuel.

Deliberate for this pass — the milestone was the fuel *behaviour*, not the
economy around it. Whatever mechanic eventually supplies fuel has exactly one
call to make.

### D-012 — Presentation APIs drive the real code path — **DECIDED 2026-08-19**

The trailer's opening shot needed the menu to look hovered. It calls
`MainMenuScreen.preview_hover_option()`, which forwards to the radial menu's own
`_on_item_mouse_entered()` — the same function a mouse triggers.

Rejected: a second "trailer" style on the menu items, and a captured image of
the menu. Either would have drifted from the real menu the first time it
changed, and the whole point of this trailer is that it is the game.

### D-013 — The trailer's hidden setup does not count as footage — **DECIDED 2026-08-19**

`_hold_clock()` stops the storyboard clock while a beat prepares its shot behind
a covered screen. Three beats need it: entering the town, becoming a storm (the
sky adapter and the rain fade need about three seconds), and clearing the storm
again.

The alternative was cutting straight into a half-finished transition, which is
what Milestone 8 did. The 33 seconds the viewer sees are 33 seconds of footage.

### D-014 — The trailer repositions the mower BETWEEN shots — **DECIDED 2026-08-19**

At 42 units a second a four-second shot crosses most of a 210-unit lawn, so
every shot needs somewhere fresh to start. The director places the mower at the
head of a new lane at each hard cut — the equivalent of moving the actor and the
camera between takes. Within a shot it drives itself the whole way under its own
physics, and the earlier lanes stay in frame as cut stripes.

Rejected: sliding the mower through the world during a shot, and slowing it down
so one start position lasted the whole trailer.

### R-020 — The trailer's storm sky is warm, not grey — **RESOLVED FOR THE TRAILER 2026-08-19 (Milestone 12)**

Rain composes over the time profile by SCALING it, which is the rule that makes
"evening rain still evening" (D-005). At the hero shot's 15:24 that leaves the
storm distinctly sepia rather than the blue-grey a storm usually reads as.

**The shipped look is unchanged, and deliberately so** — greying it further
would start replacing the time profile instead of scaling it, which is the thing
the composition rule exists to prevent.

What changed is that the argument now has somewhere else to live.
`ACAWeatherVisualAdapter.set_presentation_override()` takes one extra layer,
composed last, empty in normal gameplay; `ACATrailerWeatherAdapter` installs a
blue-grey storm through it for one shot and clears it afterwards. The trailer
gets its storm, the game keeps its rule, and neither has to argue with the other.

Still open only as a question about the GAME: if the shipped storm is ever
judged wrong on its own terms, that is a change to WEATHER_LAYERS, not to this
override.

## Session 5 — Town Z-fighting and the next-generation trailer

### R-021 — Town Z-fighting — **RESOLVED 2026-08-19 (Milestone 11)**

The Business Town had visible Z-fighting. It was NOT depth precision: the town
camera is orthographic with `near = 0.5` / `far = 240`, so its depth resolution
is about 1.4e-5 world units — four orders of magnitude finer than any offset in
the scene.

The cause was **exactly flush faces**. The town's pavements, kerbs, car park and
park paths are authored as flat `BoxMesh` decals, and several were placed level
with their neighbour to the millimetre, so the two surfaces resolve to the same
depth and the winner is decided per pixel by floating-point rounding. The worst
offenders were long: `FrontageWest` / `KerbNorthW` shared a plane over sixteen
units, `FrontageSouth` / `KerbSouthE` the same, `ParkingPad` / `LotKerb` over
eight, and the park's four path crossings shared their tops outright.

Fixed by breaking flushness, not by a render setting: kerbs sit 0.02 proud of
the slab they edge and are 0.06 shorter, the pavement slabs lost 0.02 at each
edge, the car park is 0.01 taller than the road stub crossing its corner, and
the park's cross paths were shortened to BUTT the through paths — back-to-back
faces cull, coplanar faces fight. Everything is a millimetre-scale change at
town scale.

Measured with `Town Probe`: 214-655 depth-tie pixels per shot before, 0-11
after.

### D-015 — A trailer is a PRESENTATION, not a recording — **DECIDED 2026-08-19**

Supersedes the strict reading of D-007. Real game CONTENT is still required —
the real menu, the real town, real contracts, the real mower model and its
animations, the real grid losing real grass, the real weather system, the real
HUD, the real completion pathway. Normal gameplay SIMULATION is not.

For the length of a shot, `ACATrailerMowerAdapter` switches the controller's
`_physics_process` off and owns the transform. This is what fixed the failure
V2 could not: the rider is authored two units above the lawn and falls into
place, so any shot starting at a reposition could catch it dropping, and at 1.4x
gameplay speed it could launch.

The consequence worth having: **`model.speed` is no longer written at all.**
Shot speed belongs to the adapter, so a capture cannot change gameplay tuning
even by accident. `Trailer Test` greps the director's source to keep it that way.

Rejected: tuning the gameplay mower until it filmed well. That is the bug
Milestone 5 fixed, pointed at a different system.

### D-016 — Staged mowing goes through the grid's own cut — **DECIDED 2026-08-19**

The mower adapter owns the transform, so there are no slide collisions and the
grid would never be told anything was cut. And a Large Lawn is 36,864 blades, so
forty seconds of footage cannot cut a visible fraction of it by driving.

`Custom_Gridmap.mow_swath()` selects by geometry and then runs exactly the
bookkeeping a collision would — the same `mow_item_silent`, the same MultiMesh
rebuild, the same counter, the same `mowing_progress_changed`. The grass that
disappears is really gone, the HUD percentage is true, and a save taken
mid-trailer would round-trip. What is staged is only WHICH blades and WHEN.

Rejected: a trailer-only grass shader unrelated to the mowing system, and
faking the HUD number.

### D-017 — Framing is measured, not eyeballed — **DECIDED 2026-08-19**

Every trailer review PNG logs the mower's projected screen position and its
visual size as fractions of the frame. Three things made guessing from
screenshots cost a full run per shot: a camera offset is in the mower's LOCAL
frame, the aim is computed separately, and a follow camera lags its nominal
offset by roughly `speed / damp` world units — which on the fast beats was
silently adding fifteen to twenty-five units to the working distance.

It measures the VISUAL AABB, not the node origin. The rider's origin sits below
and behind the machine, so a close shot that frames the bodywork beautifully
reports its origin off-screen — which is exactly what the first version of the
readout did report.

