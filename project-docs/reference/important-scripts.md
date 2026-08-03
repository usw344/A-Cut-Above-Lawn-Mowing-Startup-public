# Important Script Reference

Status: Responsibilities and integration reference

## Current playable orchestration

| Script | Extends | Responsibility | Important dependencies |
|---|---|---|---|
| `Game/M.V.P/MVP.gd` | `Node3D` | Startup, mower selection, grid reset, HUD requests, ambience, weather following | `model`, mower scenes, Custom Gridmap, Preset Manager |
| `Game/M.V.P/mvp_hud.gd` | `Control` | MVP controls, signals, performance text, credits | `model`, MVP signal connections |
| `Data Structures/Model.gd` | `Node` | Global mower/job/runtime state | All canonical mower controllers; partial job/UI/save systems |

### `MVP.gd`

Important methods:

- `_ready()`
- `_physics_process()`
- `_input()`
- `_on_mvp_hud_mower_change_selected()`
- `_on_mvp_hud_reset_map_and_location()`
- Time/weather signal handlers

Important preloads:

- Three canonical mower scenes.
- Custom Gridmap scene for reset.

### `mvp_hud.gd`

Important outputs:

- Mower selection.
- Reset.
- Speed.
- Time slider and presets.
- Weather presets.

It reads performance monitors every physics frame and does not own game-state persistence.

## Canonical mower scripts

| Script | Extends | Distinct behavior |
|---|---|---|
| `Assets/Vehicles and Mowers/Mowers/mower_rider.gd` | `CharacterBody3D` | Smoothed yaw/pitch, P mode, rider visual animation, powered audio |
| `non_rider_mower.gd` | `CharacterBody3D` | Direct mouse rotation, powered audio |
| `push_mower.gd` | `CharacterBody3D` | Direct mouse rotation, motion-driven push-mower audio |
| `Mower Scenes/rider_mower_(in_parts).gd` | `MeshInstance3D` | Wheels, steering, and visual engine pulsation |

Shared public signal contract:

- `collided`
- `fuel_empty`

Shared model dependencies:

- Speed.
- Fuel and fuel counter.
- Mower position.

## Mowing scripts

### `custom_gridmap.gd`

Extends: `Node3D`  
Class: `Custom_Gridmap`

Responsibility:

- Whole-grid setup.
- Chunk partitioning and lookup dictionaries.
- Start/mowing area sizing.
- Grass collision routing.
- Grid save/load dictionaries.

Important public methods:

- `test_custom_gridmap()`
- `set_grid_paramters()`
- `make_grid()`
- `custom_grid_map_collision_handler()`
- `get_mower_inital_position()`
- `reset_start_area_global_position()`
- `save_object()`
- `load_object()`

### `MultiMesh Chunk.gd`

Extends: `Node3D`  
Class: `Multi_Mesh_Chunk`

Responsibility:

- Per-chunk grass coordinates.
- Mowed/unmowed MultiMeshes.
- Individual grass collision bodies.
- Collision-name encoding.
- Chunk save/load dictionaries.

Important methods:

- `setup_chunk()`
- `generate_collision()`
- `mow_item_by_name()`
- `make_multimesh()`
- `get_for_rendering()`
- `save_object()`
- `load_object()`

### `Terrain Manager.gd`

Extends: `Node3D`, attached to a `MeshInstance3D`

Responsibility:

- Canonical terrain/foliage generation and baking tools.
- Foliage database.
- High/low variant selection.
- Ring layout.
- Ground-mesh sampling.
- Generation-time overlap avoidance.
- Decorative grass LOD and far overlay.

Exports:

- `toogle_run`
- `toggle_clear`
- `low_poly`

The active scene uses serialized MultiMeshes; `_ready()` does not regenerate them.

## Weather, time, and audio scripts

### `preset_manager.gd`

Extends: `Node3D`  
Class: `preset_manager`

Responsibility:

- Time-of-day presets and tweens.
- Weather-preset routing.
- Sky3D atmosphere/cloud/fog/light transitions.
- Rain Handler integration.
- Ambient-player forwarding.

Exports:

- `custom_gridmap_path`
- `time_preset_transition_duration`

### `rain_handler.gd`

Extends: `Node3D`  
Class: `Rain_Handler`

Responsibility:

- Near/far rain emission.
- Rain transition tween.
- Mower-following position.
- Rain audio.
- Ambient audio ducking.

Important public methods:

- `set_ambience_sound_player()`
- `set_mower_global_position()`
- `start_rain()` / `stop_rain()`
- `start_rain_instant()` / `stop_rain_instant()`

## Job and economy scripts

| Script | Class | Responsibility | Status |
|---|---|---|---|
| `Managers/Job manager/job_manager.gd` | `Job_Manager` | Offer ownership, model synchronization, display lifecycle | Partially integrated |
| `Job Generator/Job Generator.gd` | `Job_Generator` | Timed offer generation and prototype balancing | Partially integrated |
| `Job Offer/Job Offer.gd` | `Job_Offer` | Offer fields, timeout, acceptance placeholder | Partially integrated |
| `Job Display/Job_offer_display.gd` | `Job_Offer_Display` | Browse, refresh, decline, timeout display | Partially integrated |
| `Job/job.gd` | `Job` | Intended accepted-job type | Skeleton |
| `Data Structures/Job_Type.gd` | `Job_Type` | Difficulty/size categories | Prototype data |
| `Job_Data.gd` | `Job_Data_Container` | Proposed level/job state and save dictionary | Prototype data |

Job signals:

- Generator: `job_offer_waiting`, `remove_job_offer`.
- Offer: `remove_offer`.
- Display: `decline_offer`, `close_menu_signal`.

## Profile and save scripts

| Script | Responsibility | Status |
|---|---|---|
| `Data Structures/Game Profile.gd` | Versioned profile-name/data container | Present, not instantiated by working flow |
| `UI/Main Screen/New Game Menu/New Game.gd` | Name validation and `user://saves` directory setup | Stops before serialization/transition |
| `Mowing Object.gd` | Intended accepted-job/grid/save wrapper | Incomplete |

## Interface scripts

| Script | Responsibility | Status |
|---|---|---|
| `UI/Main Screen/Main Menu/main_menu.gd` | Emits New/Load/Options requests | Partially integrated |
| `UI/Main Screen/Menu Hierarchy.gd` | Intended menu action router | Empty handlers |
| `Main Area/Information Bar/Information Bar.gd` | Time/weather/money/settings display | Partially integrated |
| `Mowing Section/UI/Information UI.gd` | Fuel/cuttings/time display | Partially integrated; cuttings API mismatch |

## Tooling and demo scripts

| Script | Responsibility | Status |
|---|---|---|
| `Game/Demo/Footage/footage.gd` | Trailer/capsule capture controls and mower switching | Tooling/demo |
| `Dev tools/Mesurement.gd` | Millisecond/microsecond timing helper | Tooling; unconnected |
| `Dev tools/Performance Monitor.gd` | FPS/memory/player/chunk display | Tooling; unconnected |
| `Dev tools/Print_Handler.gd` | Proposed centralized printing | Empty and not an autoload |
| `addons/terrain_splitter/terrain_splitter.gd` | Editor mesh splitting into chunks | Disabled editor tool |

## Legacy project scripts

| Script | Reason for legacy status |
|---|---|
| `Main.gd` | Attached to the old non-main `Main.tscn` |
| `Mowing Section/Mower/Mower.gd` | Superseded by canonical three-mower controllers |
| `Grass Grid Item.gd` | Adjacent scene embeds a duplicate script and no active system uses the type |
| `Managers/Simulation Manager/Game Time Manager/Game Time Manager.gd` | No implemented time simulation |

## Sky3D addon scripts

The active integration depends primarily on:

- `addons/sky_3d/src/Sky3D.gd`
- `Skydome.gd`
- `TimeOfDay.gd`
- Supporting date, orbit, scatter, and math classes.
- `addons/sky_3d/shaders/SkyMaterial.gdshader`

These are third-party implementation details. Project code should normally interact through the Preset Manager rather than spreading additional direct Sky3D property access across unrelated systems.
