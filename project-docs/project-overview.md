# Project Overview

Status: Current repository overview  
Godot project feature version: 4.6  
Project name: A Cut Above

## Current playable scope

The repository currently launches directly into a playable mowing demonstration. The player can:

- Drive one of three mower variants.
- Cut a generated grid of grass.
- Reset the mowing area.
- Change mower speed.
- Switch between mower types.
- Select time-of-day and weather presets.
- Observe basic FPS, memory, and CPU statistics.

Menus, job generation, profiles, saving/loading, economy, upgrades, and a fuller HUD have implementations or scaffolding in the repository, but they are not completely integrated into the current playable flow.

## Entry point

`project.godot` sets:

```text
run/main_scene="uid://b85h5nq688wra"
```

That UID belongs to:

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
