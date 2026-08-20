# Important Script Reference

Status: **Current** — 2026-08-19. Paths are `res://`-relative.

## Application layer (autoloads)

| Script | class_name | Autoload | Owns |
|---|---|---|---|
| `Game/App/game_session.gd` | `ACAGameSession` | `GameSession` | Screen routing, money, job stopwatch, **the completion pathway** |
| `Game/World/world_clock.gd` | `ACAWorldClock` | `WorldClock` | Game minutes, day, season, current weather preset |
| `Game/App/app_ui.gd` | — | `AppUI` | Persistent transition + notification layers, **and cursor ownership** |
| `Game/App/game_settings.gd` | `ACAGameSettings` | `GameSettings` | Presentation settings and applying them |
| `Main Area/ACA_JobSystem/job_system/manager/job_manager.gd` | `ACAJobManager` | `JobManager` | Every job |
| `Data Structures/Model.gd` | `Model` | `model` | Mower speed/blade, cuttings, mower selection, and the fuel **level** (storage only) |
| `Game/App/mower_fuel.gd` | `ACAMowerFuel` | `MowerFuel` | **THE fuel rules** — burn rates, empty, the refuel interface, development Auto Refuel |

`Game/World/world_clock_time_provider.gd` (`ACAWorldClockTimeProvider`) is the
bridge between the two. It is constructed in `GameSession._ready()`.

## Screen hosts

| Script | Attached to | Does |
|---|---|---|
| `Game/App/main_menu_screen.gd` | `Game/App/Main Menu Screen.tscn` | Routes menu options; owns menu Settings + Controls Help; finds the menu by type |
| `Game/App/town_screen.gd` | `Game/App/Town Screen.tscn` | Feeds money and `set_calendar()` into `ACABusinessHUD` |
| `Game/App/gameplay_ui.gd` | `Game/App/Gameplay UI.tscn` | `ACAGameplayUI`, **extends `ACAPauseLayer`**. HUD, intro, results; the mowing↔UI boundary |
| `Game/App/pause_layer.gd` | `Game/App/Pause Layer.tscn` **and** `Gameplay UI.tscn` | `ACAPauseLayer` — THE pause stack. One implementation for both screens. |
| `Game/App/control_bindings.gd` | — | `ACAControlBindings` — the real key bindings, `MOWING` / `TOWN` / `MENU` |
| `Game/App/audio_mix.gd` | — | `ACAAudioMix` — bus names and `TRIM_DB`, **the audio mix**. Not a node. Trims are measured by the Audio Mix Probe. |
| `UI/Credits/credits_loader.gd` | — | `ACACreditsLoader` — scans `res://Credits/`. **The one configured path is `CREDITS_DIRECTORY`.** |
| `UI/Credits/credits.gd` | `UI/Credits/Credits.tscn` | `CreditsScreen` — list + verbatim text, opened from the Main Menu |

## Gameplay runtime

| Script | class_name | Notes |
|---|---|---|
| `Game/M.V.P/MVP.gd` | — | Mowing scene root. Sizes the grid from the contract, applies world time/weather, reports progress, owns `_finish_job()` and the **dev-only** helpers. |
| `Mowing Section/.../custom_gridmap.gd` | `Custom_Gridmap` | Grid construction, mowing, `save_object()`/`load_object()`, progress counters |
| `Mowing Section/.../MultiMesh Chunk.gd` | `Multi_Mesh_Chunk` | Per-chunk MultiMeshes + per-instance collision. **Not a scene node** — constructed with `.new()`. |
| `Mowing Section/.../Terrain Manager.gd` | — | Ground mesh + baked environment MultiMeshes |
| `Assets/Vehicles and Mowers/Mowers/mower_rider.gd` | — | Rider mower. `POWERED = true`. Emits `collided`, or `fuel_empty` when the tank is dry. |
| `Assets/Vehicles and Mowers/Mowers/non_rider_mower.gd` | — | Powered walk-behind. `POWERED = true`. |
| `Assets/Vehicles and Mowers/Mowers/push_mower.gd` | — | Push mower. **`POWERED = false`** — a manual reel mower. No fuel, no `fuel_empty`. |
| `Weather/Preset Manager/preset_manager.gd` | `preset_manager` | The project-facing weather API. **Routes**; the look is in the adapter below. |
| `Weather/Visual/weather_visual_adapter.gd` | `ACAWeatherVisualAdapter` | **THE mowing look.** Time profile x weather layer. No tweens. |
| `Weather/Visual/town_light_adapter.gd` | `ACATownLightAdapter` | The town look. Light only; never edits `BusinessTown.tscn`. |
| `Weather/Handlers/rain_handler.gd` | `Rain_Handler` | Rain particles, mower follow, ambience ducking |

All three mowers expose `look_sensitivity()` = authored base × the player's
Settings multiplier. **Read that, not `mouse_sensitivity` directly.** Vertical
inversion comes from `GameSettings.invert_look_y()` — never hard-code it.

Look-feel tunables on every mower (`@export`, top of the script):
`mouse_yaw_smoothing`, `mouse_pitch_smoothing`, `min/max_camera_pitch_degrees`.
Higher smoothing = tighter. Rider 18/32, walk-behinds 26/32. **These are
gameplay values; the trailer has its own cinematic rig — do not slow them down
for video.**

## Media tooling (development only)

| Script | class_name | Notes |
|---|---|---|
| `Game/Demo/Trailer/trailer_director.gd` | `ACATrailerDirector` | The ~44s automatic trailer. Storyboard in `BEATS`, shot speeds, the deterministic world. **Not the main scene.** |
| `Game/Demo/Trailer/Presentation/cinematic_camera.gd` | `ACACinematicCamera` | Trailer camera: `static` / `follow` / `orbit` / `rail`, lens moves, camera-local DOF. Deliberately separate from the gameplay cameras. |
| `Game/Demo/Trailer/Presentation/trailer_mower_adapter.gd` | `ACATrailerMowerAdapter` | Owns the REAL rider's transform for a shot (`set_physics_process(false)`), still feeding its visual script and the fuel system. Ground height is measured, not raycast. |
| `Game/Demo/Trailer/Presentation/trailer_lawn_adapter.gd` | `ACATrailerLawnAdapter` | Staged cutting through the grid's own `mow_swath()` -- real cut, real counters |
| `Game/Demo/Trailer/Presentation/trailer_weather_adapter.gd` | `ACATrailerWeatherAdapter` | The blue-grey storm and rain readability, through `set_presentation_override()`. Restores everything. |
| `Game/Demo/Trailer/Presentation/trailer_ui_director.gd` | `ACATrailerUIDirector` | Which UI layer each beat shows, and nothing else |
| `Dev tools/Validation/sky_probe.gd` | — | Renders the sky alone per weather look, plus a cloud-parameter sweep. Found the `clouds_cumulus_size` bug. |

## Job system (`Main Area/ACA_JobSystem/job_system/`)

| Script | class_name | Notes |
|---|---|---|
| `data/job.gd` | `ACAJob` | `Resource`. Pure data. Rebuildable from `(seed, generator_version)`. |
| `data/job_enums.gd` | `ACAJobEnums` | Status, LawnSize, PropertyType, Season, Economy, Climate + display names |
| `data/game_time.gd` | `ACAGameTime` | Formatting helpers over game minutes |
| `config/job_balance.gd` | `ACAJobBalance` | **All tunables.** Grid sizes, pay, offer duration, arrival bands, `GENERATOR_VERSION` |
| `config/job_catalog.gd` | `ACAJobCatalog` | Site names per property type |
| `generation/job_generator.gd` | `ACAJobGenerator` | Deterministic. **Draw order is part of the contract** — bump `GENERATOR_VERSION` instead of reordering. |
| `market/job_market.gd` | `ACAJobMarket` | season+economy+climate → strength 0..5 |
| `time/job_time_provider.gd` | `ACAJobTimeProvider` | The world-time boundary |
| `debug/debug_time_provider.gd` | `ACAJobDebugTimeProvider` | **Demo/tests only. Not the game clock.** |
| `ui/job_board.gd` | `ACAJobBoard` | Available / Current / Past; read-only view |
| `ui/job_card.gd` | `ACAJobCard` | One contract row |
| `ui/job_ui_style.gd` | `ACAJobUIStyle` | Board styling (palette matched to `UITheme`) |

## Town (`Main Area/ACA_BusinessTown/`)

| Script | class_name | Notes |
|---|---|---|
| `business_town.gd` | `ACABusinessTown` | Click-picking on layer 9 **from `_physics_process`** (required with threaded 3D physics). Emits `business_action_requested`. |
| `Camera/business_camera.gd` | `ACABusinessCamera` | Orthographic focus rig |
| `Buildings/interactive_building.gd` | `ACAInteractiveBuilding` | `@tool`; hover/select via transforms only, never material edits |
| `UI/business_hud.gd` | `ACABusinessHUD` | Title bar, building panel, placeholder screen, embedded Job Board. `set_calendar(day, clock, weather)` |
| `UI/building_panel.gd` | `ACABuildingPanel` | Location card |
| `UI/placeholder_screen.gd` | `ACAPlaceholderScreen` | Stand-in destination |

## UI package (`res://UI/`)

`UI/Theme/ui_theme.gd` → `UITheme` (constants + static helpers only).
Components: `GameplayHUD`, `JobIntroScreen`, `JobCompleteScreen`, `PauseMenu`,
`SettingsMenu`, `ControlsHelp`, `ConfirmationPrompt`, `NotificationCenter`,
`NotificationToast`, `TransitionLayer`, `MainMenuScreen`, `RadialMainMenu`,
`MainMenuScenery`.

None of them reference a game scene, a job, or a manager.

## Development tooling

| Script | Notes |
|---|---|
| `Dev tools/Validation/validate_all.gd` | Loads every script and scene |
| `Dev tools/Validation/flow_test.gd` | The 54-assertion loop test |
| `Dev tools/Validation/ui_smoke_test.gd` | The 54-assertion UI test |
| `Dev tools/Validation/screenshot_tour.gd` | Per-screen PNG capture (needs a renderer) |
| `Dev tools/Validation/runner_boot.gd` | Parents a runner to `/root` so it survives scene changes |
| `Dev tools/Performance Monitor.gd` | `Performance_Monitor` |
| `Dev tools/Mesurement.gd` | `Mesurment` (note the spelling) |
| `Dev tools/Print_Handler.gd` | `Print_Handler` |

## Moved out of the project

`Job_Manager`, `Job_Generator`, `Job_Offer`, `Job`, `Job_Offer_Display`,
`Job_Type`, `Job_Data_Container`, `Grass_Grid_Item`, the old Main Area,
Information Bar, Information UI, Mowing Object, and the old main-menu screens are
all in the workspace `Soft Delete/` folder. See its `MANIFEST.md`.

`Data Structures/Game Profile.gd` (`Game_Profile`) **is still in the project** —
unused, but a real save-data structure held for the save system.
