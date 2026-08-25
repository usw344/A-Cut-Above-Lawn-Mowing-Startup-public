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

Sky3D licence text is present in the addon and reproduced verbatim in `res://Credits/` (`Sky3D_licence.txt`, `Sky3D_Shaders_licence.txt`, `Sky3D_Milky_Way_Texture_licence.txt`, `Sky3D_Moon_Texture_licence.txt`), which is what the player-facing Credits screen reads.

## Historical GodotSky

The older Godot Sky plugin by StayAtHomeDev was replaced by Sky3D.

It is:

- Not present as an active addon.
- Not a current dependency.
- Not planned to return.

The root README statement saying the public version excludes “GodotSky” is stale historical text. It should be corrected in a future public-documentation cleanup, not interpreted as describing the current Sky3D integration.

## Terrain3D — NOT INSTALLED

| Property | Value |
|---|---|
| Path | *(absent)* |
| Enabled | No — the addon folder does not exist |
| Runtime status | **Removed.** `ACATerrain` generates the ground procedurally. |

As of 2026-08-19 `addons/` contains only `sky_3d`. The Terrain3D addon was
already gone; the orphaned content that depended on it
(`Terrain/Footage-Demo Data/`, `Game/Demo/Footage/`) was moved to the workspace
`Soft Delete/` folder because it could not load without the addon.

`export_presets.cfg` used to enumerate the whole `res://addons/terrain_3d/` tree.
Those 181 dead entries were removed on 2026-08-19; the presets themselves were
not otherwise changed.

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

It is not a runtime dependency of the mowing scene.

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

**Player-facing credits live in `res://Credits/`** and are shown by the Main
Menu CREDITS screen. Adding one is a file copy — see
[HUD, menus and interface](systems/ui-hud-and-menus.md) for the naming
convention. The originals stay where they are; the Credits folder holds copies.

Known license locations include:

- `addons/sky_3d/LICENSE.txt`
- `addons/sky_3d/ThirdParty.md`
- Sky3D third-party Milky Way and moon texture licenses.
- `res://Credits/*_licence.txt` — the player-facing copies (**start here**).
- Terrain3D and Sky3D text formerly in the legacy MVP HUD credit panels (now a
  development-only layer, toggled with F3).
- `addons/terrain_3d/LICENSE.txt` **no longer exists** — the addon is not installed.
  If any Terrain3D-derived asset is ever redistributed, attribution must be
  restored from upstream.

Before removing a deprecated addon, confirm whether distributed builds still require its license or asset attribution because copied or derived assets may remain.

## Known issue — Sky3D

`addons/sky_3d/assets/resources/MoonRender.tscn` **fails to load**: it references
`res://addons/sky_3d/shaders/SimpleMoon.gdshader`, which is missing from this copy
of the addon (`shaders/` contains only `AtmFog.gdshader` and
`SkyMaterial.gdshader`). Nothing in the project loads `MoonRender.tscn`, so this
is cosmetic, but it is the project's only remaining scene-load failure. Left
alone deliberately: it is third-party, and editing an addon folder invites
confusion on the next addon update. Fix by updating/reinstalling Sky3D.

## Plugin enablement authority

`project.godot` is authoritative for editor plugin enablement. At the time of this review:

```text
enabled=PackedStringArray("res://addons/sky_3d/plugin.cfg")
```

Presence under `addons/` alone does not mean a plugin is active.

## `addons/aca_sky3d_environment/` — project-owned, addon-shaped

Added session 7. **Not third party** — this project wrote it — but it lives
under `addons/` because it is deliberately built to be copied into another
project that has a vanilla Sky3D.

| | |
|---|---|
| Depends on | vanilla Sky3D **2.1-dev**, Godot 4.6 |
| Depends on A Cut Above | **nothing**, enforced by `Environment Test` |
| Bundles assets | **none** — every mesh, material and wave is built in code |
| Install order | Sky3D first, then this package, then restart the editor once |

It does not vendor Sky3D. The intended model is: install vanilla Sky3D, install
this, get an atmospheric system.

`Environment Test` scans every file in the package for this project's
directories and autoload names and fails if any appear, so the boundary cannot
quietly rot.

### Why Sky3D is never edited, even where it is inconvenient

The shipped `AtmFog.gdshader` has its sky-exclusion line commented out, so its
fog cannot be pushed hard without washing the sky. The fix is not to edit the
addon — it is to keep that quad subtle and let Godot's own Environment fog,
which has `fog_sky_affect`, carry the range. See
[Weather, Time of Day, and Audio](systems/weather-time-and-audio.md).

Verify the addon is untouched with:

```
diff -rq "Working Repository/addons/sky_3d" "Milestone Backups/04 Save-System Working/addons/sky_3d"
```
