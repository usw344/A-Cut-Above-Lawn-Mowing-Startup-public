# Scene Reference

Status: **Current** — 2026-08-30. Paths are `res://`-relative.

## Application screens

### Main Menu Screen — the entry point

| Property | Value |
|---|---|
| Path | `Game/App/Main Menu Screen.tscn` |
| Root | `Main Menu Screen : Node` |
| Script | `Game/App/main_menu_screen.gd` |
| Configured as | `run/main_scene` |

Children: `Scenery` (instance of `main_menu_scenery.tscn`, which **already
contains** `main_menu.tscn` in its `MenuSafeOverlay`), and a `Menu UI` CanvasLayer
(layer 20) holding `Settings`, `Controls Help`, `Load Game` and `Credits`.

The host locates the menu by type (`MainMenuScreen`), not by path.

### Town Screen

| Property | Value |
|---|---|
| Path | `Game/App/Town Screen.tscn` |
| Root | `Town Screen : Node3D` |
| Script | `Game/App/town_screen.gd` |
| Children | `Pause Layer`, then `BusinessTown` (instance of `BusinessTown.tscn`) |

`town_screen.gd` also creates a `Town Light Adapter` child at runtime when
`light_from_world_clock` is on.

`Pause Layer` is **first** on purpose: `_unhandled_input` runs in reverse tree
order, so the town gets Escape before the pause menu does. That lets Escape close
a building panel or clear a selection first, and only open pause when the town
has nothing to dismiss.

### Pause Layer

| Property | Value |
|---|---|
| Path | `Game/App/Pause Layer.tscn` |
| Root | `Pause Layer : CanvasLayer` (layer 40, `PROCESS_MODE_ALWAYS`) |
| Script | `Game/App/pause_layer.gd` (`ACAPauseLayer`) |
| Children | `Pause Menu`, `Settings`, `Controls Help`, `Confirmation Dialog`, runtime-mounted `Developer Debugger` |

The same four component instances `Gameplay UI.tscn` holds. `ACAGameplayUI`
**inherits** `ACAPauseLayer` rather than instancing this scene, which is why the
node names in `Gameplay UI.tscn` are unchanged.

### Gameplay UI

| Property | Value |
|---|---|
| Path | `Game/App/Gameplay UI.tscn` |
| Root | `Gameplay UI : CanvasLayer` (layer 10) |
| Script | `Game/App/gameplay_ui.gd` (`ACAGameplayUI`, extends `ACAPauseLayer`) |
| Instanced by | `Minimum Viable Game.tscn`, with `gameplay_host = NodePath("..")` |

Child order is significant (later siblings get `_unhandled_input` first):
Gameplay HUD → Job Intro → Job Complete → Pause Menu → Settings → Controls Help →
Confirmation Dialog.

## Gameplay

### Minimum Viable Game — the mowing runtime

| Property | Value |
|---|---|
| Path | `Game/M.V.P/Minimum Viable Game.tscn` |
| Root | `Minimum Viable Game : Node3D` |
| Script | `Game/M.V.P/MVP.gd` |
| Reached by | `GameSession.go_to_mowing()` |

Children: `Property` (`ACAProperty`), `Rider Mower`, `CanvasLayer/MVP_HUD`
(dev-only, hidden), `AudioStreamPlayer` (ambience), `PresetManager (Sky3D)`,
`Gameplay UI`. `Mower Cutter` (`ACAMowerCutter`) is added in code.

Connections: thirteen MVP HUD signals to controller methods on the root. The
mower's `collided` signal is connected IN CODE to the cutter, because the cutter
is created at runtime and re-bound whenever the player switches machines.

The root exposes `property()` and `lawn()`, so `SaveService`, the trailer
director and the validation runners never reach for a node by name.

**No longer the main scene** (it was until 2026-08-19). It can still be opened
standalone from the editor: with no active contract it generates a default
property and returns to town itself on completion.

### MVP HUD — development only

| Property | Value |
|---|---|
| Path | `Game/M.V.P/MVP_HUD.tscn` |
| Root | `MVP_HUD : Control` |
| Instanced by | Minimum Viable Game |
| Visibility | **Hidden on load**; no key binding (the Developer Debugger took over **H**); opened by tooling via `MVP.dev_toggle_debug_hud()` |

Retained as a diagnostics/development layer. Its weather buttons write to
`WorldClock`, not to the scene.

### Property

| Property | Value |
|---|---|
| Path | authored as a bare `Node3D` in the mowing scene |
| Script | `Mowing Section/Property/aca_property.gd` (`ACAProperty`) |
| Instanced by | Minimum Viable Game |

There is no property SCENE. Everything under it, `Terrain`, `Lawn`, `Grass`,
`Foliage` and any feature nodes such as `Pond Water`, is generated in `build()`
from `ACAPropertyParams`. Nothing about a property is authored, and nothing
about it is saved as geometry.

See [Property, terrain and lawn](../systems/property-and-lawn.md).

### Mowers

| Path | Notes |
|---|---|
| `Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn` | Authored editor fallback; the production default machine |
| `Assets/Vehicles and Mowers/Mowers/Non Rider Mower.tscn` | Preloaded by `MVP.gd`, selected through `Equipment` or swapped by the dev HUD |
| `Assets/Vehicles and Mowers/Mowers/Push Mower.tscn` | Preloaded by `MVP.gd`, selected through `Equipment` or swapped by the dev HUD |
| `Mowing Section/Mower/Mower_Normal/Mower_Normal.tscn` | Referenced by `Model.gd`'s `mower_scene_references` through `load()` |

### Weather

| Path | Notes |
|---|---|
| `Weather/Preset Manager/Preset Manager.tscn` | Contains Sky3D (Skydome, TimeOfDay) and the Rain Handler. Instanced in the mowing scene as `PresetManager (Sky3D)`. |
| `Weather/Handlers/Rain Handler.tscn` | Near/far GPU rain particles |
| `Weather/Handlers/Rain Handler.tscn` | Rain audio and the ownership of `ACAPrecipitationRig`. **The authored particle scene is gone** — the rain is three layers built in code by the environment package |
| `Weather/particles/snow_particles.tscn` | Authored, **not yet reachable** from `apply_weather_preset()` |

## Town

| Path | Notes |
|---|---|
| `Main Area/ACA_BusinessTown/BusinessTown.tscn` | Root `ACABusinessTown`. Own `WorldEnvironment`, `Sun`, `FillLight`, `CameraRig`, `BusinessHUD`. Does **not** use Sky3D. |
| `Buildings/JobOffice.tscn` | `building_id = job_office` — the only one wired to a real destination |
| `Buildings/SupplyStore.tscn`, `MowerDealer.tscn`, `BusinessHQ.tscn`, `FutureLot.tscn` | Placeholder destinations |
| `UI/BusinessHUD.tscn` | Title bar, building panel, placeholder screen, embedded Job Board |
| `UI/BuildingPanel.tscn`, `UI/PlaceholderScreen.tscn` | Supporting UI |

## Job system UI

| Path | Notes |
|---|---|
| `Main Area/ACA_JobSystem/job_system/ui/JobBoard.tscn` | `ACAJobBoard`. Bound to the `JobManager` autoload by `ACABusinessHUD._ready()`. |
| `Main Area/ACA_JobSystem/job_system/ui/JobCard.tscn` | `ACAJobCard` |

## UI package (`res://UI/`)

`Gameplay HUD`, `Job Intro`, `Job Complete`, `Pause Menu`, `Settings`,
`Controls Help`, `Dialogs/Confirmation Dialog`, `Notifications` (+ `Notification
Toast`), `Transitions/Transition`, `Main Menu/main_menu` (+ `radial_menu`),
`Scenic Background for Menus/scenery/scenes/main_menu_scenery`, `Demo/UI Demo`.

Every component scene assigns `res://UI/Theme/Game UI.theme.tres` to its root.
That path is the one to re-point if the UI folder ever moves.

## Tooling and demo scenes

| Path | Notes |
|---|---|
| `Dev tools/Validation/Flow Test.tscn` | Full-loop test, 54 assertions |
| `Dev tools/Validation/UI Smoke Test.tscn` | UI component test, 60 assertions |
| `Dev tools/Validation/Save Test.tscn` | Save/load, 59 assertions |
| `Dev tools/Validation/Pause Test.tscn` | Pause stack + cursor + look, 49 headless / 54 renderer |
| `Dev tools/Validation/Debugger Probe.tscn` | Real H input in Town and mowing, 39 / 39 |
| `Dev tools/Validation/Handling Probe.tscn` | Three machine profiles and precision view, 21 / 21 |
| `Dev tools/Validation/Layout Probe.tscn` | Six layout rules, determinism and safety, 15 / 15 |
| `Dev tools/Validation/Workmanship Probe.tscn` | Coverage/contact callouts, 4 / 4 |
| `Dev tools/Validation/Credits Test.tscn` | Credits loader and screen, 40 assertions |
| `Dev tools/Validation/Weather Test.tscn` | Weather/time visuals **and the audio bus structure**, 106 assertions |
| `Dev tools/Validation/Fuel Test.tscn` | The real fuel system, 59 assertions |
| `Dev tools/Validation/Audio Mix Probe.tscn` | **Measures** bus peak levels per weather state, 15 assertions |
| `Dev tools/Validation/Trailer Test.tscn` | Trailer static contract, 102 assertions |
| `Dev tools/Validation/Town Probe.tscn` | Grazing-angle town shots plus a depth-tie diff. Needs a renderer. |
| `Dev tools/Validation/Weather Matrix.tscn` | 4 times x 3 weathers + town; needs a renderer |
| `Dev tools/Validation/Sun Probe.tscn` | Sky3D sun altitude per half hour |
| `Dev tools/Validation/Sky Probe.tscn` | The sky alone, per weather look + a cloud-parameter sweep; needs a renderer |
| `Dev tools/Validation/Screenshot Tour.tscn` | Per-screen capture; needs a renderer |
| `Game/Demo/Trailer/Trailer Capture.tscn` | The automatic trailer. **Never the main scene.** |
| `Main Area/ACA_JobSystem/tests/JobSystemTests.tscn` | 110 assertions |
| `Main Area/ACA_JobSystem/demo/JobSystemDemo.tscn` | Standalone Job System demo |
| `Main Area/ACA_JobSystem/tools/BuildJobUI.tscn` | Regenerates the Job Board scenes |
| `Dev tools/Performance Monitor.tscn`, `Dev tools/Mesurement.tscn` | Instruments |
| `UI/Demo/UI Demo.tscn` | UI component showcase |

## Removed from the project

`Main.tscn`, `Main Area/Old Main Area/*`, `UI/Main Screen - old/*`,
`Managers/**`, `Data Structures/Job Data Structure/*`, `Mowing Section/UI/*`,
`Grass Grid Item/*`, `Mowing Object/*`, `Game/Demo/Footage/*` — all in the
workspace `Soft Delete/` folder. See its `MANIFEST.md`.

## Known issue

`addons/sky_3d/assets/resources/MoonRender.tscn` fails to load (missing
`SimpleMoon.gdshader` in this copy of the addon). Nothing loads it.

## Development / media scenes

### Trailer Capture

| Property | Value |
|---|---|
| Path | `Game/Demo/Trailer/Trailer Capture.tscn` |
| Root | `Trailer Capture : Node` (`runner_boot.gd` shim) |
| Runner | `Game/Demo/Trailer/trailer_director.gd` (`ACATrailerDirector`) |
| Reached by | opening it and pressing Play. **Never** as `run/main_scene`. |

Uses the same boot shim as the validation runners so the director survives the
scene changes it drives. Its presentation layer lives in
`Game/Demo/Trailer/Presentation/` -- a mower adapter, a lawn adapter, a weather
adapter, a UI director and the cinematic camera. See
`Game/Demo/Trailer/README.md`.

## Added in session 7

| Scene | Purpose |
|---|---|
| `addons/aca_sky3d_environment/demo/Environment Demo.tscn` | The environment package's STANDALONE demo. Builds its own ground, camera and Sky3D at runtime; loads none of the game |
| `Mowing Section/Experimental/Pond/Pond Demo.tscn` | The pond prototype's standalone scene. **Experimental** |
| `Dev tools/Validation/Economy Test.tscn` | The economy, shops and upgrades, plus a 90-day simulation |
| `Dev tools/Validation/Flicker Probe.tscn` | Measures temporal instability in the Town |

`Main Area/ACA_BusinessTown/UI/business_services.gd` (`ACABusinessServices`) has
**no scene**: the Supply Store, Business Office and Mower Workshop are built in
code and parented to a `CanvasLayer` created by `town_screen.gd` on first use.
