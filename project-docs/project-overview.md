# Project Overview

Status: **Current repository overview** — 2026-08-19
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
- The mowing grid is sized from the accepted contract (96/144/192).
- Drive one of three mower variants and cut a generated grid of grass.
- Production HUD, job intro, fullscreen transitions, results screen, pause menu,
  settings, controls help, confirmation dialogs, notification toasts.
- Money: a starting balance and contract payouts.
- A development fast-completion helper (F10) that uses the real completion path.

Not yet implemented: save/load, spending, upgrades, reputation, completion
deadlines, and any economy simulation driving market strength. The town's
Supply Store, Mower Dealer and Business HQ are placeholder destinations.

## Entry point

`project.godot` sets:

```text
run/main_scene="res://Game/App/Main Menu Screen.tscn"
```

**Changed 2026-08-19** — the entry point was previously the MVP mowing bench.
That scene is still the mowing runtime, now reached through the job flow.

The entry scene is:

```text
res://Game/M.V.P/Minimum Viable Game.tscn
```

`Main.tscn` is not the current entry point.

## Architectural style

The project is primarily:

- Scene-oriented.
- Organized by gameplay domain.
- Signal-driven at scene boundaries.
- Dependent on a single global state autoload.
- Focused on `MultiMesh` for grass and environmental foliage.
- Built around runtime scene composition rather than a central dependency container.

The current MVP root owns orchestration. Specialized child scenes own mower behavior, grass state, environment rendering, HUD behavior, and weather.

## Top-level layout

| Path | Purpose | Current status |
|---|---|---|
| `Game/M.V.P/` | Authoritative playable world and MVP HUD | Current playable runtime |
| `Assets/Vehicles and Mowers/` | Canonical mower wrappers, controllers, meshes, and audio | Current playable runtime |
| `Mower Scenes/` | Multipart rider mower visual implementation | Current playable runtime |
| `Mowing Section/` | Grass grid, chunk state, cutting, older mower, and mowing UI | Mixed current and legacy |
| `Weather/` | Canonical weather presets, rain behavior, particles, and removed-addon remnants | Mixed current and deprecated |
| `Terrain/` | Canonical terrain mesh plus deprecated Terrain3D footage data | Mixed current and deprecated |
| `Data Structures/` | Global model and proposed profile/job data structures | Mixed current and partial |
| `Managers/` | Job prototypes and simulation-manager scaffolding | Partially integrated |
| `UI/` | Main-menu and new-game prototypes | Partially integrated |
| `Main Area/` | Proposed business-area abstraction and information bar | Partially integrated |
| `Game/Demo/Footage/` | Trailer and screenshot capture worlds | Tooling/demo |
| `Dev tools/` | Timing, monitoring, and proposed print helpers | Tooling/partial |
| `addons/` | Sky3D, deprecated Terrain3D, and Terrain Splitter | Mixed |
| `docs/` | Public website plus internal developer documentation | Mixed audiences |

## Canonical technology choices

| Concern | Canonical choice |
|---|---|
| Runtime world | `Minimum Viable Game.tscn` |
| Shared runtime state | `model` autoload |
| Mower implementation | `Assets/Vehicles and Mowers/Mowers/` |
| Mowing | Custom grid plus `Multi_Mesh_Chunk` |
| Terrain/foliage | Custom `Terrain Manager` |
| Sky | Sky3D |
| Weather | Preset Manager plus Rain Handler |
| Physics | Jolt Physics |

## Partially integrated game systems

The following are real repository systems, not merely ideas:

- Main menu and new-game interfaces.
- Job offer generation and display.
- Job and mowing data containers.
- Save-object dictionary methods.
- Profile scaffolding and `user://saves` directory setup.
- Money, cuttings, fuel, and information-bar UI concepts.
- Upgrade and persistent mower-state direction in the global model.

Their remaining work is chiefly integration, completion, state ownership, validation, and polish.

## Build and platform configuration

Export presets exist for:

- Android.
- Web/itch.io.
- Windows Desktop.

The project uses a 1920×1080 viewport, fullscreen mode, a 144 FPS cap, disabled VSync, Jolt physics, occlusion culling, and mobile texture compression.

See [Project settings and input](project-settings-and-input.md) for the exact settings relevant to architecture and performance.

## Documentation boundaries

The following are not engineering authorities:

- `Documentation.odt` — obsolete Godot 4 migration-era planning material.
- `docs/index.html` — public marketing/portfolio site whose roadmap may lag development.
- The root `README.md` statement about excluding “GodotSky” — stale historical text referring to a replaced plugin.

The repository, the configured main scene, confirmed project decisions, and these internal pages are the intended architecture sources.
