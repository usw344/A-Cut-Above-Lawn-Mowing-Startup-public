# Project Overview

Status: **Current repository overview** — 2026-08-30
Godot project feature version: 4.6 (verified against Godot 4.6.1 stable)
Project name: A Cut Above: Mow & Grow

## Current playable scope

The repository launches into a complete, connected application loop:

**Main Menu → New Game → Town → Job Board → accept a real generated contract →
Job Intro → Mowing → completion → Job Complete → return to Town → the contract is
recorded in business history.**

Working today:

- Radial main menu over a 3D scenic backdrop; Settings and Controls Help.
- A persistent world clock (time, day, season) and weather preset that survive
  every scene change.
- A seeded job market: offers arrive on game time, expire on game time, and are
  accepted, begun, progressed and completed through one authoritative manager.
- The procedural property is sized from the accepted contract (96/144/192),
  with logical one-unit lawn cells, terrain, features, grass and foliage.
- Drive one of three mower variants with distinct handling profiles and cut the
  generated lawn through deck geometry. The production pond is a property
  feature; its standalone demo remains experimental.
- Production HUD, job intro, fullscreen transitions, results screen, pause menu,
  settings, controls help, confirmation dialogs, notification toasts.
- Money, fuel purchases, mower ownership, upgrades, clippings, business history,
  territories, recurring agreements and portfolio metadata are integrated and
  persisted through additive save sections.
- Developer Debugger (H), precision view (C), workmanship callouts, six
  deterministic obstacle layouts, and legacy generation compatibility.
- A development fast-completion helper (F10) that uses the real completion path.

## Entry point

`project.godot` sets:

```text
run/main_scene="res://Game/App/Main Menu Screen.tscn"
```

**Changed 2026-08-19** — the entry point was previously the MVP mowing bench.
That scene is still the mowing runtime, now reached through the job flow.
`Main.tscn` is not the current entry point.

## Architectural style

The project is primarily:

- Scene-oriented.
- Organized by gameplay domain.
- Signal-driven at scene boundaries.
- Dependent on small authoritative autoloads with explicit ownership: session,
  clock, jobs, economy, equipment, business and save services.
- Focused on `MultiMesh` for grass and environmental foliage.
- Built around runtime scene composition rather than a central dependency container.

The current MVP root owns orchestration. Specialized child scenes own mower behavior, grass state, environment rendering, HUD behavior, and weather.

## Top-level layout

| Path | Purpose | Current status |
|---|---|---|
| `Game/M.V.P/` | Mowing runtime, property host and development HUD | Current playable runtime |
| `Assets/Vehicles and Mowers/` | Canonical mower wrappers, controllers, meshes, and audio | Current playable runtime |
| `Mower Scenes/` | Multipart rider mower visual implementation | Current rider visual dependency |
| `Mowing Section/` | Procedural property, logical lawn, features and standalone pond demo | Mixed current and experimental |
| `Weather/` | Canonical weather presets, rain behavior, particles, and removed-addon remnants | Mixed current and deprecated |
| `Terrain/` | Remaining support assets; runtime terrain is procedural | Mixed current and deprecated |
| `Data Structures/` | Legacy model and job data structures | Mixed current and legacy |
| `Managers/` | Job prototypes and simulation-manager scaffolding | Partially integrated |
| `UI/` | Player-facing screens and HUD components | Current playable runtime |
| `Main Area/` | Job system and business town | Current playable runtime |
| `Game/Demo/Footage/` | Trailer and screenshot capture worlds | Tooling/demo |
| `Dev tools/` | Timing, monitoring, and proposed print helpers | Tooling/partial |
| `addons/` | Sky3D, deprecated Terrain3D, and Terrain Splitter | Mixed |
| `docs/` | Public website plus internal developer documentation | Mixed audiences |

## Canonical technology choices

| Concern | Canonical choice |
|---|---|
| Runtime world | Main Menu → Town → `Minimum Viable Game.tscn` |
| Shared runtime state | `GameSession`, `WorldClock`, `JobManager` and domain autoloads |
| Mower implementation | `Assets/Vehicles and Mowers/Mowers/` |
| Mowing | `ACALawn` compact cell state plus `ACAMowerCutter` |
| Terrain/foliage | `ACATerrain`, `ACALawnGrass`, `ACAForest`, all procedural |
| Sky | Sky3D |
| Weather | Preset Manager plus Rain Handler |
| Physics | Jolt Physics |

## Known scope boundaries

Current limitations include no snow implementation, no water volume/float
simulation, no serial-numbered duplicate mower fleet, no neighbourhood route
contract type, and deterministic rather than simulated off-screen work. Supply
Store, Mower Workshop, and Business HQ are real service routes where wired; any
remaining placeholder destination is documented as such in the town reference.

## Build and platform configuration

Export presets exist for:

- Android.
- Web/itch.io.
- Windows Desktop.

The project uses a 1920×1080 viewport, fullscreen mode, a 240 FPS cap, disabled VSync, Jolt physics, occlusion culling, and mobile texture compression.

See [Project settings and input](project-settings-and-input.md) for the exact settings relevant to architecture and performance.

## Documentation boundaries

The following are not engineering authorities:

- `Documentation.odt` — obsolete Godot 4 migration-era planning material.
- `docs/index.html` — public marketing/portfolio site whose roadmap may lag development.
- The root `README.md` statement about excluding “GodotSky” — stale historical text referring to a replaced plugin.

The repository, the configured main scene, confirmed project decisions, and these internal pages are the intended architecture sources.
