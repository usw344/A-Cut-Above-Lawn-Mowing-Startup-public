# Legacy, Deprecated, Demo, and Experimental Areas

Status: **Current** — reconciled 2026-08-30; cleanup pass 2026-08-19 and lawn/
terrain retirement 2026-08-20.

## Where legacy lives now

Everything confirmed legacy has been **moved out of `res://`** into the workspace
folder `Soft Delete/`, a sibling of `Working Repository/`. That location is
deliberate: Godot no longer imports or resolves any of it.

**Nothing was deleted.** Original relative paths are preserved, so restoring is a
straight copy back. Per-item reason, evidence, dependencies checked and restore
notes are in **`Soft Delete/MANIFEST.md`** and, for the lawn and terrain, in
**`Soft Delete/2026-08-20 Legacy Lawn and Terrain/MANIFEST.md`**.

86 files were quarantined in the first pass. Post-move regression: Flow Test
54/54, UI Smoke 54/54, Job System Tests 110/110, headless and GPU.

## The lawn and terrain retirement (2026-08-20)

`Custom_Gridmap`, `Multi_Mesh_Chunk`, the authored `Terrain Manager`, the imported
grass meshes and the 91 MB `Terrain/Meshes/` folder all left the project when
`Mowing Section/Property/` replaced them. Each was confirmed unreferenced by
grepping every `.gd`, `.tscn`, `.tres`, `.gdshader` and `.cfg` under `res://` for
its paths and class names first.

The **historical post-move regression on 2026-08-20** was: `validate_all` 150 scripts / 89 of 90 scenes
(the known `MoonRender.tscn`), Flow 54/54, Save 59/59, Fuel 56/56, Pause 49/49,
Weather 75/75, Trailer 102/102, Mowing 19/19, Property 52/52, Pond 37/37, UI
Smoke 60/60, Job System 110/110, Economy 93/93.

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
| `Mowing Section/…/Grass Grid Item/` | the chunked MultiMesh lawn, itself retired on 2026-08-20 |
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
| `Dev tools/Developer Debugger/` | Development-only H debugger, mounted by `ACAPauseLayer` |
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

- `Mowing Section/Experimental/Pond/` — the carver is no longer experimental.
  `ACAPondFeature` is built on it and every generated pond comes from its shape
  function. The demo scene and `Pond Test` still stand on their own.
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

## Dead files found in session 7

### `Weather/precipitation/*.tres`

`rain.tres`, `heavy_rain.tres`, `snow.tres`, `heavy_snow.tres` all declare
`script_class="PrecipitationResource"` and reference
`res://addons/GodotWeatherSystem/scripts/PrecipitationResource.cs` and
`res://addons/GodotWeatherSystem/particles/rain_particles.tscn`.

**That addon is not installed.** `res://addons/` contains `sky_3d` and
`aca_sky3d_environment` and nothing else. Nothing in the project loads these
resources — a repository-wide search finds no reference outside the four files
themselves.

Classification: **LEGACY, dead.** Left in place rather than removed, in keeping
with the rule that a documentation classification does not by itself justify
deleting files. They are also the whole of the project's "snow support" (R-011).

### The authored rain particle scene

`Weather/particles/rain_particles.tscn` was removed in session 7. The rain is
now three `GPUParticles3D` layers built in code by `ACAPrecipitationRig`, so
there is no particle scene to keep in sync — and nothing for a redistributable
package to have to copy.

The old scene's `Far Rain` instance was the same scene as `Near Rain` scaled by
**24**, over a `RibbonTrailMesh` 0.2 units wide. That is a 4.8-unit-wide white
ribbon per raindrop, and it is why the pre-session-7 rain looked like scratches
on a film print.

## Experimental

### Pond prototype — `Mowing Section/Experimental/Pond/`

The standalone `ACAPond` node and `Pond Demo.tscn` remain complete, tested
experimental/demo content. The shared `ACAPondCarver` is also used by the
production `ACAPondFeature` built into generated job properties. See [Pond
Prototype](systems/pond-prototype.md) for the boundary between those paths.
