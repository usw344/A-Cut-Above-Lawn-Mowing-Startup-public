# Legacy, Deprecated, Demo, and Experimental Areas

Status: Evidence-backed maintenance inventory

## Classification rule

This page does not authorize deletion. Cleanup requires a separate task that verifies references, serialized resources, exports, licenses, and any desired historical/demo preservation.

## Confirmed deprecated systems

### Terrain3D

Status: Deprecated experimental system; cleanup debt

Evidence:

- The custom Terrain Manager is the confirmed canonical direction.
- Terrain3D is not an enabled editor plugin.
- Terrain3D runtime nodes occur in explicit footage/demo scenes, not the main scene.
- The system was found unnecessary and overly complex for project needs.

Remaining areas:

- `addons/terrain_3d/`
- `Terrain/Footage-Demo Data/`
- Terrain3D nodes/resources in footage scenes.
- Export and credit references.

### GodotWeatherSystem remnants

Status: Deprecated removed-addon resources; cleanup debt

Files:

- `Weather/precipitation/rain.tres`
- `heavy_rain.tres`
- `snow.tres`
- `heavy_snow.tres`

Evidence:

- They reference missing addon paths and a missing C# resource class.
- The addon is not expected to return.
- Canonical weather uses local particles, Preset Manager, and Rain Handler.

### Historical GodotSky reference

Status: Stale public text

The root README refers to an older plugin by StayAtHomeDev. Sky3D replaced it and is the active sky system.

## Confirmed legacy implementations

### Older mower architecture

Files:

- `Mowing Section/Mower/Mower.gd`
- `Mowing Section/Mower/Mower_Normal/Mower_Normal.tscn`
- `Model.mower_scene_references`

Status: Legacy compatibility and historical reference

Canonical replacement:

- Three mower scenes under `Assets/Vehicles and Mowers/Mowers/`.

The model’s future persistent mower fields should build on the canonical scene set rather than reviving the old lookup design.

### Old Main scene

Files:

- `Main.tscn`
- `Main.gd`

Status: Legacy entry-point candidate

Evidence:

- `project.godot` points to the MVP by UID.
- The scene only wraps mouse-capture testing.

### `Documentation.odt`

Status: Obsolete migration-era planning document

It is not an architecture or design authority and was not used to generate these pages. It may be removed in a future cleanup task.

### `backupmowingarea`

Status: Likely archival early mowing implementation

Evidence:

- No Godot-recognized extension.
- No incoming reference found.
- References missing historical asset paths.
- Calls model APIs absent from the current model.
- Uses a pre-custom-grid per-object placement approach.

## Demo and tooling—not obsolete gameplay

### Footage scenes

Status: Intentional media-capture tools

- `Game/Demo/Footage/Footage.tscn`
- `Footage_Normal.tscn`
- `Footage_Rain.tscn`
- `footage.gd`

Their script explicitly identifies them as trailer/capsule-art scenes. They retain deprecated Terrain3D composition but should be classified as demo tooling until media-preservation needs are decided.

### Terrain Splitter

Status: Disabled editor tool

It is not a runtime system. Its presence is intentional unless the editor workflow no longer needs it.

### Dev tools

Status: Unconnected tooling or scaffolding

- `Mesurement.gd/.tscn`
- `Performance Monitor.gd/.tscn`
- `Print_Handler.gd`

`Print_Handler.gd` says it is a global autoload, but `project.godot` does not configure it.

## Partially integrated—not legacy

The following must not be dismissed as obsolete:

- Main menu and new-game UI.
- Job manager, generator, offer, accepted-job, and display.
- Game Profile and Job Data structures.
- Grid/chunk save dictionaries.
- Mowing Information UI and Information Bar.
- Economy, equipment, and upgrade foundations.
- Full-HUD components.

They contain meaningful implementation intended for future integration.

## Duplicates and uncertain artifacts

### Grass Grid Item duplication

Files:

- `Grass Grid Item.gd`
- `Grass Grid Item.tscn`

The scene embeds a near-copy of the adjacent script rather than referencing it. No active system uses the scene or class. Canonical ownership is unresolved; review before removal or reuse.

### Mowed-grass resource variants

Potential pair:

- `Assets/Mowed_Grass_With_LOD_attempt1.res`
- `Assets/Grass/Mowed_Grass_With_LOD_attempt1.res`

The active chunk script loads the second path. The resources were not parsed or compared as binaries/imported resources. Treat the root version as a possible duplicate requiring asset-level review.

### Rider-parts Timer connection

`Rider Mower (In Parts).tscn` connects Timer timeout to `straighten_wheel`, while the current script has no such method. Current steering return happens in `_update_steering()`. Confirm in the editor/runtime before removing the Timer or connection.

### Tree movement shader

`Shaders/Tree Movements.gdshader` has no detected project resource reference. It may be a prepared shader or abandoned experiment. Asset/material intent is unresolved.

### Local snow particle scene

`Weather/particles/snow_particles.tscn` is not integrated into canonical weather. Unlike the old precipitation resources, the local particle scene itself does not depend on the missing addon. Decide whether snow remains planned before classifying it as cleanup.

### Jolt settings

Two body-limit key names with different values remain in `project.godot`. This is likely migration/configuration debt, but the effective key must be confirmed in Godot 4.6 before modification.

## Public website boundary

`docs/index.html` is an active public landing page, not legacy code. Its roadmap content is non-authoritative for engineering sequence and may be updated manually on a different schedule.
