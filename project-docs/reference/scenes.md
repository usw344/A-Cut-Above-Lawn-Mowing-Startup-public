# Scene Reference

Status: Repository scene map  
Scope: Project-owned gameplay scenes and important integrated addon scenes

## Reading this reference

“Referenced by” describes confirmed text or UID relationships. A scene with no incoming path reference is not automatically unused; it may be opened directly in the editor, be loaded by UID, or be retained as a prototype.

## Current playable scene graph

### Minimum Viable Game

| Property | Value |
|---|---|
| Path | `Game/M.V.P/Minimum Viable Game.tscn` |
| Root | `Minimum Viable Game : Node3D` |
| Script | `Game/M.V.P/MVP.gd` |
| Role | Authoritative current runtime root |
| Loaded by | `project.godot` main-scene UID |

Important children:

- Rider Mower instance.
- Custom Gridmap instance.
- CanvasLayer with MVP HUD.
- Ambient AudioStreamPlayer.
- Embedded mountain-range backdrop.
- Preset Manager/Sky3D instance.

Important connections:

- Rider mower `collided` → Custom Gridmap collision handler.
- Ten MVP HUD signals → MVP controller methods.

### MVP HUD

| Property | Value |
|---|---|
| Path | `Game/M.V.P/MVP_HUD.tscn` |
| Root | `MVP_HUD : Control` |
| Script | `Game/M.V.P/mvp_hud.gd` |
| Role | Current controls and development statistics |
| Instanced by | Minimum Viable Game |

Contains 27 nodes, including mower selection, performance label, time and speed sliders, reset, time/weather presets, controls, and third-party license panels.

### Custom Gridmap

| Property | Value |
|---|---|
| Path | `Mowing Section/Mowing Area/Mowing Ground/Custom Gridmap solution/custom_gridmap.tscn` |
| Root | `Custom Gridmap : Node3D` |
| Script | `custom_gridmap.gd` |
| Role | Mowable-grid runtime and terrain container |
| Instanced by | MVP and footage scenes |

Important children:

- Mowing Area static body.
- Hidden Start Area static body.
- Canonical Terrain Manager instance.

### Terrain Manager

| Property | Value |
|---|---|
| Path | `Mowing Section/Mowing Area/Mowing Ground/Custom Gridmap solution/Terrain Manager.tscn` |
| Root | `Ground : MeshInstance3D` |
| Script | `Terrain Manager.gd` |
| Role | Canonical terrain and environmental foliage |
| Instanced by | Custom Gridmap |

Contains a ground mesh, hidden generation helper, and 216 baked environmental MultiMesh nodes.

### Preset Manager

| Property | Value |
|---|---|
| Path | `Weather/Preset Manager/Preset Manager.tscn` |
| Root | `PresetManager : Node3D` |
| Script | `Weather/Preset Manager/preset_manager.gd` |
| Role | Canonical time/weather and Sky3D integration |
| Instanced by | Minimum Viable Game |

Important children:

- Sky3D WorldEnvironment.
- Sun and moon lights.
- Skydome.
- TimeOfDay.
- Rain Handler instance.

### Rain Handler

| Property | Value |
|---|---|
| Path | `Weather/Handlers/Rain Handler.tscn` |
| Root | `Rain Handler : Node3D` |
| Script | `Weather/Handlers/rain_handler.gd` |
| Role | Rain particles, following, and audio crossfade |
| Instanced by | Preset Manager |

Children:

- Near Rain.
- Far Rain.
- Rain AudioStreamPlayer.

### Rain particles

| Property | Value |
|---|---|
| Path | `Weather/particles/rain_particles.tscn` |
| Root | `RainParticles : GPUParticles3D` |
| Role | Reusable canonical rain emitter |
| Instanced by | Rain Handler and footage scenes |

## Canonical mower scenes

### Mower Rider

| Property | Value |
|---|---|
| Path | `Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn` |
| Root | `CharacterBody3D` |
| Script | `mower_rider.gd` |
| Role | Initial and selectable rider mower |
| Used by | MVP and footage scenes |

Children include a current camera, collision shape, multipart visual instance, development label, spotlight, and 3D audio.

### Rider Mower (In Parts)

| Property | Value |
|---|---|
| Path | `Mower Scenes/Rider Mower (In Parts).tscn` |
| Root | `LawnTractor01 : MeshInstance3D` |
| Script | `rider_mower_(in_parts).gd` |
| Role | Rider visual-part animation |
| Instanced by | Mower Rider |

Contains bag, steering wheel, four wheel meshes, and a retained Timer connection to `straighten_wheel`. The current script no longer declares that method; active steering return occurs in `_physics_process()`. This stale connection should be reviewed before cleanup.

### Non Rider Mower

| Property | Value |
|---|---|
| Path | `Assets/Vehicles and Mowers/Mowers/Non Rider Mower.tscn` |
| Root | `CharacterBody3D` |
| Script | `non_rider_mower.gd` |
| Role | Selectable powered walk-behind mower |
| Used by | MVP preload and Footage Normal |

Instances `Non Rider Mower Mesh.tscn`.

### Push Mower

| Property | Value |
|---|---|
| Path | `Assets/Vehicles and Mowers/Mowers/Push Mower.tscn` |
| Root | `Push Mower : CharacterBody3D` |
| Script | `push_mower.gd` |
| Role | Selectable manual push mower |
| Used by | MVP preload and Footage Normal |

Instances `Push Mower Mesh.tscn`.

### Mower mesh scenes

| Scene | Role | Status |
|---|---|---|
| `Non Rider Mower Mesh.tscn` | Imported/preserved powered mower visual hierarchy | Current component |
| `Push Mower Mesh.tscn` | Imported/preserved push mower visual hierarchy | Current component |

These scenes are large because they serialize visual mesh hierarchies. Gameplay behavior belongs to their CharacterBody wrapper scenes.

## Partially integrated application scenes

### Main-menu group

| Scene | Root | Script | Status and role |
|---|---|---|---|
| `UI/Main Screen/Menu Hierarchy.tscn` | `Control` | `Menu Hierarchy.gd` | Menu container; custom menu actions not wired |
| `UI/Main Screen/Main Menu/Main Menu.tscn` | `Control` | `main_menu.gd` | New/Load/Options buttons; emits unconsumed signals |
| `UI/Main Screen/New Game Menu/New Game.tscn` | `Control` | `New Game.gd` | Profile-name entry and saves-directory setup |

No scene transition connects this group to the current MVP.

### Main Area

| Scene | Root | Script | Status and role |
|---|---|---|---|
| `Main Area/Main Area.tscn` | `Main Area : Node3D` | None attached | Proposed business/storefront abstraction |
| `Main Area/Information Bar/Information Bar.tscn` | `CanvasLayer` | `Information Bar.gd` | Proposed time/weather/money/settings bar |

### Mowing and job UI

| Scene | Root | Script | Status and role |
|---|---|---|---|
| `Mowing Section/UI/Information UI.tscn` | `Control` | `Information UI.gd` | Fuel/cuttings/time HUD prototype |
| `Managers/Job manager/Job Display/Job_offer_display.tscn` | `Control` | `Job_offer_display.gd` | Offer browsing and decline UI; Accept not wired |

## Job scene group

| Scene | Root | Important children/connections | Status |
|---|---|---|---|
| `Managers/Job manager/job_manager.tscn` | `Job Manager : Node3D` | Job Generator; offer display CanvasLayer; generator signals | Partially integrated root |
| `Job Generator/Job Generator.tscn` | `Job Generator : Node3D` | Add Job Timer → generator callback | Partially integrated component |
| `Job Offer/job_offer.tscn` | `Job Offer : Node3D` | Script only | Wrapper exists; generator constructs class directly |
| `Job/job.tscn` | `Job : Node3D` | Script only | Accepted-job placeholder |
| `Data Structures/Job Data Structure/Job Data Structure.tscn` | `Node3D` | `Job_Data.gd` | Data wrapper; no incoming scene path |

## Mowing support and prototype scenes

| Scene | Root | Status |
|---|---|---|
| `Mowing Section/Mowing Area/MultiMesh Chunk/MultiMesh Chunk.tscn` | `Node3D` | Wrapper scene is not instantiated; its script class is active through `.new()` |
| `Mowing Section/Mowing Area/Mowing Object/Mowing Object.tscn` | `Node3D` | Incomplete job/grid/save wrapper |
| `Mowing Section/Mowing Area/Mowing Ground/Grass Grid Item/Grass Grid Item.tscn` | `Node3D` | Unconnected experiment with embedded duplicate script |

## Legacy mower scene

| Property | Value |
|---|---|
| Path | `Mowing Section/Mower/Mower_Normal/Mower_Normal.tscn` |
| Root | `Small Gas Mower : CharacterBody3D` |
| Script | `Mowing Section/Mower/Mower.gd` |
| Status | Legacy compatibility/historical implementation |

It is referenced by the old `Model.mower_scene_references` dictionary but not used by the MVP.

## Demo and capture scenes

| Scene | Root | Main composition | Status |
|---|---|---|---|
| `Game/Demo/Footage/Footage.tscn` | `Footage : Node3D` | Terrain3D, custom grid, rider mower, rain, Sky3D | Media-capture demo |
| `Footage_Normal.tscn` | `Footage_Normal : Node3D` | Three mowers, Terrain3D, custom grid, Sky3D, timer | Media-capture demo |
| `Footage_Rain.tscn` | `Footage : Node3D` | Terrain3D, custom grid, rider, rain, Sky3D | Media-capture demo |

These scenes retain deprecated Terrain3D dependencies for footage history. They are not alternate canonical game worlds.

## Development scenes

| Scene | Root | Purpose | Status |
|---|---|---|---|
| `Dev tools/Mesurement.tscn` | `Mesurement : Node` | Timing helper wrapper | Tooling; no incoming reference |
| `Dev tools/Performance Monitor.tscn` | `Performance Monitor : Control` | FPS, memory, player and chunk diagnostics | Tooling; no incoming reference |
| Terrain3D addon menu/tool scenes | Various Controls/Nodes | Third-party editor tooling | Deprecated with Terrain3D |

## Other and historical scenes

| Scene | Status |
|---|---|
| `Main.tscn` | Older minimal root; not configured main scene |
| `Managers/Simulation Manager/Game Time Manager/Game Time Manager.tscn` | Timer-based skeleton; no implemented behavior |
| `Weather/particles/snow_particles.tscn` | Local snow emitter retained but not integrated into canonical weather |
| Sky3D `MoonRender.tscn` | Addon support resource; not directly part of MVP scene graph |
