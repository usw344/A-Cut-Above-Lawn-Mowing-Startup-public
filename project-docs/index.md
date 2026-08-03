# A Cut Above: Mow & Grow — Developer Documentation

Status: Internal developer documentation  
Last repository review: 2026-08-02  
Authoritative playable entry point: `res://Game/M.V.P/Minimum Viable Game.tscn`

## Purpose

This documentation describes the current Godot 4 architecture, the systems already present in the repository, their integration status, and known legacy or cleanup areas.

It is intentionally separate from `docs/index.html`. The `docs/` root is the public GitHub Pages site; its presentation copy and roadmap are not authoritative engineering plans.

`Documentation.odt` is obsolete migration-era material and is not a source for these pages.

## Status vocabulary

- **Current playable runtime** — loaded directly or transitively by `Minimum Viable Game.tscn`.
- **Partially integrated** — meaningful implementation exists, but the current playable runtime does not complete or expose the whole flow.
- **Tooling or demo** — intended for development, editor assistance, performance observation, or media capture.
- **Legacy** — retained for compatibility or historical reference but superseded by a canonical implementation.
- **Deprecated** — no longer part of the intended game direction.
- **Cleanup debt** — safe removal may be appropriate later, but only after a separate reference and runtime validation pass.

An unreferenced file is not automatically called unused. Status is based on scene reachability, explicit resource references, implementation completeness, and confirmed project direction.

## Canonical systems

- Runtime composition: `Game/M.V.P/Minimum Viable Game.tscn`
- Global runtime state: `Data Structures/Model.gd` as the `model` autoload
- Mowers: scenes under `Assets/Vehicles and Mowers/Mowers/`
- Grass cutting: the custom grid and `Multi_Mesh_Chunk` implementation
- Terrain and foliage: the custom `Terrain Manager.tscn` and `Terrain Manager.gd`
- Sky: the open-source Sky3D addon
- Weather: `Weather/Preset Manager` and `Weather/Handlers/Rain Handler`
- Runtime interface: `Game/M.V.P/MVP_HUD.tscn`

## Documentation map

### Project and architecture

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
- [Save and load](systems/save-and-load.md)

### Reference and maintenance

- [Scene reference](reference/scenes.md)
- [Important script reference](reference/important-scripts.md)
- [Plugins and third-party systems](plugins-and-third-party.md)
- [Performance architecture](performance.md)
- [Legacy, deprecated, demo, and experimental areas](legacy-and-experimental.md)

## Authority and maintenance rules

When code and documentation disagree:

1. Verify the configured main scene and the scene/script/resource graph.
2. Treat the repository and confirmed project decisions as authoritative.
3. Update these internal pages with the implementation change.
4. Do not infer current architecture from `docs/index.html` or `Documentation.odt`.

When adding a new system page, identify:

- Its status.
- Its owning scene or autoload.
- Its inputs and outputs.
- Its dependencies.
- Its save-state implications.
- Its performance implications.
- Which implementation is canonical if alternatives exist.
