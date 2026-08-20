# Scene Reference

Status: **Current** — 2026-08-19. Paths are `res://`-relative.

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
| Children | `Pause Menu`, `Settings`, `Controls Help`, `Confirmation Dialog` |

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

Children: `Rider Mower`, `Custom Gridmap`, `CanvasLayer/MVP_HUD` (dev-only,
hidden), `AudioStreamPlayer` (ambience), `Mountain Range Backdrop`,
`PresetManager (Sky3D)`, `Gameplay UI`.

Connections: mower `collided` → `Custom Gridmap.custom_grid_map_collision_handler`;
ten MVP HUD signals → controller methods on the root.

**No longer the main scene** (it was until 2026-08-19). It can still be opened
standalone from the editor: with no active contract it falls back to a 256 grid
and returns to town itself on completion.

### MVP HUD — development only

| Property | Value |
|---|---|
| Path | `Game/M.V.P/MVP_HUD.tscn` |
| Root | `MVP_HUD : Control` |
| Instanced by | Minimum Viable Game |
| Visibility | **Hidden on load**; toggled with **F3** |

Retained as a diagnostics/development layer. Its weather buttons write to
`WorldClock`, not to the scene.

### Custom Gridmap

| Property | Value |
|---|---|
| Path | `Mowing Section/Mowing Area/Mowing Ground/Custom Gridmap solution/custom_gridmap.tscn` |
| Script | `custom_gridmap.gd` (`Custom_Gridmap`) |
| Instanced by | Minimum Viable Game |

Contains `Mowing Area`, `Start Area`, and the Terrain Manager. Chunks are
`Multi_Mesh_Chunk` **objects**, not scene nodes; their MultiMesh instances are
parented under `Mowing Area`.

### Terrain Manager

| Property | Value |
|---|---|
| Path | `Mowing Section/Mowing Area/Mowing Ground/Custom Gridmap solution/Terrain Manager.tscn` |
| Instanced by | `custom_gridmap.tscn` |
| Depends on | `Terrain/Meshes/1x1 Ground Main Mesh.mesh`, `Terrain/Meshes/Gound 1x1 ColourMap.png` — **ACTIVE, do not remove** |

### Mowers

| Path | Notes |
|---|---|
| `Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn` | Authored into the mowing scene; the initial active mower |
| `Assets/Vehicles and Mowers/Mowers/Non Rider Mower.tscn` | Preloaded by `MVP.gd`, swapped in via the dev HUD |
| `Assets/Vehicles and Mowers/Mowers/Push Mower.tscn` | Preloaded by `MVP.gd`, swapped in via the dev HUD |
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
| `Dev tools/Validation/Pause Test.tscn` | Pause stack + cursor + look, 49 / 54 |
| `Dev tools/Validation/Credits Test.tscn` | Credits loader and screen, 40 assertions |
| `Dev tools/Validation/Weather Test.tscn` | Weather/time visuals **and the audio bus structure**, 56 assertions |
| `Dev tools/Validation/Fuel Test.tscn` | The real fuel system, 56 assertions |
| `Dev tools/Validation/Audio Mix Probe.tscn` | **Measures** bus peak levels per weather state, 15 assertions |
| `Dev tools/Validation/Trailer Test.tscn` | Trailer static contract, 98 assertions |
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
