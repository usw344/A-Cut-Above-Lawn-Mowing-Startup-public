# A Cut Above: Mow & Grow — Developer Documentation

Status: Internal developer documentation
Last repository review: **2026-08-20** (session 7: reusable environment package, town lighting, economy and upgrades, pond prototype, documentation audit)
Configured entry point: **`res://Game/App/Main Menu Screen.tscn`**

## Purpose

This documentation describes the current Godot 4.6 architecture, the systems in
the repository, their integration status, and known legacy or cleanup areas.
It is written for future AI coding agents: prefer structured technical facts
over prose.

It is separate from `docs/index.html`, which is the public GitHub Pages site and
is not an authoritative engineering plan. `Documentation.odt` is obsolete
migration-era material and is not a source for these pages.

## Read this first

If you are an AI coding agent picking this project up, read in this order and
stop as soon as you have what you need:

1. **[Application layer](application-layer.md)** — the autoloads, screen
   routing, the world clock, and the one job-completion pathway. Most
   integration questions are answered here.
2. **[Architecture](architecture.md)** — the layering, the runtime graph, and
   **the boundaries that must not be crossed**.
3. **The system page for whatever you are touching** — see the map below.
4. **[Reference](reference/important-scripts.md)** — exact paths, class names
   and owners.
5. **[Decisions and open questions](decisions-and-open-questions.md)** — why
   something is the way it is, and what is still unresolved. Check here before
   "fixing" anything that looks odd.
6. **[Validation and development tools](validation-and-dev-tools.md)** — how to
   prove you did not break it.

The workspace root also has `CURRENT_STATUS.md` (where the project is now) and
`CLAUDE_WORKLOG.md` (chronological history). **These pages describe the system;
the worklog describes how it got here. Do not put history in here.**

## Status vocabulary

- **Current** — part of the running application.
- **Tooling / demo** — for development, editor assistance, performance
  observation, or media capture. Unreferenced by design.
- **Legacy** — superseded. Anything confirmed legacy has been moved **out of
  `res://`** to the workspace `Soft Delete/` folder; see
  [legacy and experimental](legacy-and-experimental.md).
- **Uncertain** — investigated, not confidently classifiable, left in place and
  documented.

An unreferenced file is not automatically unused. GDScript `class_name` and
`load()` calls do not appear as scene references.

## Canonical systems

| Concern | Canonical implementation |
|---|---|
| Entry point | `Game/App/Main Menu Screen.tscn` |
| Application flow | `GameSession` autoload — `Game/App/game_session.gd` |
| World time / weather state | `WorldClock` autoload — `Game/World/world_clock.gd` |
| Jobs | `JobManager` autoload — `Main Area/ACA_JobSystem/` (`ACAJobManager`) |
| Town | `Main Area/ACA_BusinessTown/BusinessTown.tscn` |
| Mowing runtime | `Game/M.V.P/Minimum Viable Game.tscn` + `MVP.gd` |
| Grass cutting | `Custom_Gridmap` + `Multi_Mesh_Chunk` |
| Terrain / foliage | `Custom Gridmap solution/Terrain Manager.tscn` |
| Money | `GameSession` — **the one balance** |
| Market and prices | `Economy` autoload — `Game/Economy/economy_manager.gd` |
| Mower upgrades | `MowerUpgrades` autoload — `Game/Economy/mower_upgrades.gd` |
| Town services | `Main Area/ACA_BusinessTown/UI/business_services.gd` |
| Sky | `addons/sky_3d` — third party, **read-only** |
| Weather routing | `Weather/Preset Manager` + `Weather/Handlers/Rain Handler` |
| Weather LOOK | `addons/aca_sky3d_environment/` (reusable package) via `Weather/Visual/weather_visual_adapter.gd`; `town_light_adapter.gd` for the town |
| Rain particles | `ACAPrecipitationRig`, built in code inside the package |
| Ponds | `Mowing Section/Experimental/Pond/` — **EXPERIMENTAL, unused by gameplay** |
| Player UI | `res://UI/` driven by `Game/App/gameplay_ui.gd` |
| Pause stack | `Game/App/pause_layer.gd` (`ACAPauseLayer`) — one implementation, both screens |
| Cursor ownership | `AppUI` — the only writer of `Input.mouse_mode` |
| Credits | `res://Credits/` scanned by `UI/Credits/credits_loader.gd` |
| Trailer capture | `Game/Demo/Trailer/` — development / media tooling only |
| Legacy global state | `model` autoload — `Data Structures/Model.gd` |

## Documentation map

### Project and architecture

- [Application layer](application-layer.md) ← start here
- [Project overview](project-overview.md)
- [Architecture and system relationships](architecture.md)
- [Startup and runtime flow](runtime-flow.md)
- [Project settings and input](project-settings-and-input.md)
- [Architecture decisions and open questions](decisions-and-open-questions.md)

### Systems

- [Global model and runtime state](systems/global-model.md)
- [Mowers and player controls](systems/mowers-and-controls.md)
- [Mowing grid and grass removal](systems/mowing-grid.md)
- [Terrain and foliage](systems/terrain-and-foliage.md)
- [Weather, time of day, and audio](systems/weather-time-and-audio.md)
- [HUD, menus, and interface systems](systems/ui-hud-and-menus.md)
- [Jobs and economy](systems/jobs-and-economy.md)
- [Pond prototype](systems/pond-prototype.md) — **experimental**
- [Save and load](systems/save-and-load.md)

### Reference and maintenance

- [Scene reference](reference/scenes.md)
- [Important script reference](reference/important-scripts.md)
- [Plugins and third-party systems](plugins-and-third-party.md)
- [Performance architecture](performance.md)
- [Legacy, deprecated, demo, and experimental areas](legacy-and-experimental.md)
- [Validation and development tools](validation-and-dev-tools.md)

## Authority and maintenance rules

When code and documentation disagree, **the repository wins**:

1. Verify `project.godot` (main scene, autoloads) and the scene/script graph.
2. Treat the repository and confirmed project decisions as authoritative.
3. Update these pages with the implementation change.
4. Do not infer current architecture from `docs/index.html` or `Documentation.odt`.
