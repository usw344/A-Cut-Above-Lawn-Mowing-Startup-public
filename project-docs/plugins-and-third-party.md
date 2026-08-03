# Plugins and Third-Party Systems

Status: Current and deprecated dependency record

## Sky3D

| Property | Value |
|---|---|
| Path | `addons/sky_3d/` |
| Plugin name | Sky3D |
| Version | 2.0 |
| Author metadata | J. Cuéllar, Cory Petkovsek, Contributors |
| Enabled | Yes |
| Runtime status | Active and canonical |

Sky3D supplies:

- Atmospheric sky.
- Sun and moon lights.
- Skydome.
- Time of day.
- Clouds.
- Fog.
- Sky textures and shaders.

The project’s Preset Manager is the canonical wrapper around Sky3D for time and weather behavior.

Sky3D license text is present in the addon and reproduced in the MVP HUD credits.

## Historical GodotSky

The older Godot Sky plugin by StayAtHomeDev was replaced by Sky3D.

It is:

- Not present as an active addon.
- Not a current dependency.
- Not planned to return.

The root README statement saying the public version excludes “GodotSky” is stale historical text. It should be corrected in a future public-documentation cleanup, not interpreted as describing the current Sky3D integration.

## Terrain3D

| Property | Value |
|---|---|
| Path | `addons/terrain_3d/` |
| Plugin name | Terrain3D |
| Version | 1.0.0 |
| Authors | Cory Petkovsek and Roope Palmroos |
| Enabled | No |
| Runtime status | Deprecated experimental system |

Terrain3D includes:

- C++ GDExtension binaries for several platforms.
- Editor plugin scripts and UI.
- Brushes, icons, importer tools, and shader examples.
- Terrain3D resources under `Terrain/Footage-Demo Data/`.

It remains serialized into footage/demo scenes, but it is no longer planned for the final game. The custom Terrain Manager is canonical.

Terrain3D is cleanup debt. Removal needs a dedicated validation pass because the repository still contains:

- Terrain3D nodes.
- Terrain3D typed resources.
- Export references.
- Credits and license content.
- Platform binaries.

## Terrain Splitter

| Property | Value |
|---|---|
| Path | `addons/terrain_splitter/` |
| Plugin name | Terrain Splitter |
| Version | 1.0 |
| Author metadata | Gemini |
| Enabled | No |
| Status | Development/editor tool |

The plugin:

- Adds a Split Terrain control for selected `MeshInstance3D` nodes.
- Partitions first-surface triangles into X/Z chunks.
- Preserves available normals and UVs.
- Optionally wraps output in static bodies with trimesh collisions.
- Uses editor UndoRedo.

It is not a runtime dependency of the MVP.

## Jolt Physics

Jolt is selected through project settings:

```text
3d/physics_engine="Jolt Physics"
```

There is no separate project addon directory for it. It is an engine-level project dependency and is central to the grass collision workload.

Two body-limit key variants remain in `project.godot`; their effective Godot 4.6 behavior should be confirmed before settings cleanup.

## Removed GodotWeatherSystem

The addon directory is absent. Four precipitation resources still reference:

- Missing addon rain/snow particle scene paths.
- Missing `PrecipitationResource.cs`.

The addon is not expected to return. The custom Preset Manager and Rain Handler are canonical.

## Asset licenses and credits

Known license locations include:

- `addons/sky_3d/LICENSE.txt`
- `addons/sky_3d/ThirdParty.md`
- Sky3D third-party Milky Way and moon texture licenses.
- `addons/terrain_3d/LICENSE.txt`
- Terrain3D and Sky3D text in the MVP HUD credit panels.

Before removing a deprecated addon, confirm whether distributed builds still require its license or asset attribution because copied or derived assets may remain.

## Plugin enablement authority

`project.godot` is authoritative for editor plugin enablement. At the time of this review:

```text
enabled=PackedStringArray("res://addons/sky_3d/plugin.cfg")
```

Presence under `addons/` alone does not mean a plugin is active.
