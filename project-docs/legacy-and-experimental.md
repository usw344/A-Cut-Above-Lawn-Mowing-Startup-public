# Legacy, Deprecated, Demo, and Experimental Areas

Status: **Current** — cleanup pass completed 2026-08-19.

## Where legacy lives now

Everything confirmed legacy has been **moved out of `res://`** into the workspace
folder `Soft Delete/`, a sibling of `Working Repository/`. That location is
deliberate: Godot no longer imports or resolves any of it.

**Nothing was deleted.** Original relative paths are preserved, so restoring is a
straight copy back. Per-item reason, evidence, dependencies checked and restore
notes are in **`Soft Delete/MANIFEST.md`**.

86 files were quarantined. Post-move regression: Flow Test 54/54, UI Smoke 54/54,
Job System Tests 110/110, headless and GPU.

## What left the project

| Group | Superseded by |
|---|---|
| `Main.tscn` / `Main.gd` | `Game/App/Main Menu Screen.tscn` |
| `Main Area/Old Main Area/` | `Main Area/ACA_BusinessTown/` |
| `UI/Main Screen - old/` | `UI/Main Menu/` + the scenic backdrop |
| `Managers/Job manager/` (`Job_Offer`, `Job`, `Job_Generator`, `Job_Manager`, `Job_Offer_Display`) | `ACAJobManager` / `ACAJob` |
| `Managers/Simulation Manager/Game Time Manager/` (an empty stub) | `WorldClock` |
| `Data Structures/Job Data Structure/`, `Job_Type.gd` | `ACAJob`, `ACAJobEnums` |
| `Mowing Section/UI/` (Information UI) | `UI/Gameplay HUD/` |
| `Mowing Section/…/Grass Grid Item/` | `Multi_Mesh_Chunk` |
| `Mowing Section/…/Mowing Object/` | the mowing scene + `GameSession` |
| `Game/Demo/Footage/` + `Terrain/Footage-Demo Data/` | nothing — the **Terrain3D addon is not installed**, so they cannot function |
| `backupmowingarea`, `errors.txt` | stray files at the project root |

### Side effects of the removals

- `Data Structures/Model.gd` lost its dead `job_offers` dictionary and the
  `Job_Offer`-typed `add_job_offer()` / `remove_job_offer()` /
  `get_all_job_offers()`. Nothing called them, and they were the only thing tying
  `Model.gd` to the old prototype. **Restoring that prototype requires putting
  this block back.**
- Removing `Grass Grid Item/` fixed a real parse error: its `.tscn` carried a
  duplicate embedded copy of the script declaring the same
  `class_name Grass_Grid_Item`, producing
  `Class "Grass_Grid_Item" hides a global script class` on every project scan.

## Still in the project — tooling and demo, intentionally unreferenced

These are **not** legacy. Do not treat "no inbound references" as a reason to
remove them.

| Path | What it is |
|---|---|
| `Dev tools/Mesurement`, `Performance Monitor`, `Print_Handler` | Development instruments |
| `Dev tools/Validation/` | The validation harness — see [validation and dev tools](validation-and-dev-tools.md) |
| `Main Area/ACA_JobSystem/demo/` | Standalone Job System demo (uses `ACAJobDebugTimeProvider`, **not** the game clock) |
| `Main Area/ACA_JobSystem/tests/` | Job System suite, 110 assertions, green |
| `Main Area/ACA_JobSystem/tools/BuildJobUI` | Regenerates the Job Board scenes from `job_ui_style.gd` |
| `UI/Demo/UI Demo.tscn` | Component showcase for the UI package |
| `UI/Scenic Background for Menus/**/tests/` | Scenery package tests |

## Uncertain — investigated, left in place

| Path | Why it stayed |
|---|---|
| `Data Structures/Game Profile.gd` | `class_name Game_Profile`, unused, but a real save-data structure (version / profile name / data). Reviewed as part of the save system rather than quarantined ahead of it. |
| `Weather/precipitation/*.tres`, `Weather/particles/snow_particles.tscn` | Authored snow / heavy-rain content not yet reachable from `apply_weather_preset()`. Active design direction, not legacy. |
| `Shaders/Tree Movements.gdshader`, `default_env.tres` | Unreferenced, tiny, ambiguous origin. |
| `Main Area/ACA_BusinessTown/Materials/glass.tres`, `Generated/*.tscn` | Part of the town package's authored set; package cohesion. |
| `addons/sky_3d/assets/resources/MoonRender.tscn` | **Third party — conservative.** Broken (missing `shaders/SimpleMoon.gdshader` in this copy of the addon) and unreferenced, but editing an addon folder invites confusion on update. It is the project's only remaining scene-load failure. |

## Not legacy — actively used, despite appearances

- `Terrain/Meshes/` (91 MB) — the ground mesh and colour map used by
  `Custom Gridmap solution/Terrain Manager.tscn`. **Do not remove.** Only
  `Terrain/Footage-Demo Data/` was Terrain3D orphan.
- `Mowing Section/Mower/Mower_Normal/` — referenced by `Model.gd`'s
  `mower_scene_references` dictionary through `load()`, which no scene graph shows.
- Every `job_system/` script — used via `class_name`, not by path.
- `UI/Theme/ui_theme.gd` — used via `class_name UITheme` from every component.

## Documentation that is NOT authoritative

- `docs/index.html` — public GitHub Pages site.
- `Documentation.odt` — obsolete migration-era material.
- `generated-doc-site/`, `mkdocs.yml` — generated output and its config.

## Cleanup debt cleared

`export_presets.cfg` listed 196 files across its two `export_files` arrays, of
which **181 did not exist**: the whole `res://addons/terrain_3d/` tree, the
quarantined `Terrain/Footage-Demo Data/` files, and a few foliage assets that are
not in the repository. Each entry was checked against the filesystem; the dead
ones were removed and the 15 real ones kept. Preset settings were not touched.
