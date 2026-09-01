# Project Settings and Input

Status: **Current** — confirmed from `project.godot`, 2026-08-30

## Application

| Setting | Value | Architectural relevance |
|---|---|---|
| Project name | `A Cut Above: Claude Work Repo` | Display/export identity |
| Feature tags | `4.6`, `Mobile` | Godot compatibility and renderer feature selection |
| Main scene | `res://Game/App/Main Menu Screen.tscn` | Authoritative runtime root. **Changed 2026-08-19** — was the MVP mowing bench. |
| Maximum FPS | 240 | Main-loop cap |
| Icon | `res://icon.svg` | Application icon |

## Autoloads

**Declaration order matters** — later entries depend on earlier ones.

```text
model="*res://Data Structures/Model.gd"
MowerFuel="*res://Game/App/mower_fuel.gd"
WorldClock="*res://Game/World/world_clock.gd"
JobManager="*uid://dogmb0pup4bhg"          # ACA_JobSystem/job_system/manager/job_manager.gd
GameSettings="*res://Game/App/game_settings.gd"
AppUI="*res://Game/App/app_ui.gd"
GameSession="*res://Game/App/game_session.gd"
SaveService="*res://Game/App/save_service.gd"
Economy="*res://Game/Economy/economy_manager.gd"
MowerUpgrades="*res://Game/Economy/mower_upgrades.gd"
Equipment="*res://Game/Economy/equipment.gd"
Clippings="*res://Game/Economy/clippings.gd"
Business="*res://Game/Economy/business.gd"
Territory="*res://Game/Business/service_territory.gd"
Agreements="*res://Game/Business/service_agreements.gd"
Portfolio="*res://Game/Business/portfolio.gd"
```

The leading `*` enables the autoload as a scene-tree node. Scripts access each by
its global name. `GameSession._ready()` depends on `WorldClock` and `JobManager`
already existing, which is why it is declared last.

See [application layer](application-layer.md) for what each one owns.

## Display

| Setting | Value |
|---|---:|
| Viewport width | 1920 |
| Viewport height | 1080 |
| Window mode | 3 |
| Handheld orientation | 1 |
| VSync mode | 0 |

The UI package is authored around this project resolution (1920x1080).

## Physics

| Setting | Value |
|---|---:|
| 3D physics engine | Jolt Physics |
| Run 3D physics on separate thread | true |
| Physics ticks per second | 576 |
| Maximum physics steps per frame | 100 |
| Physics jitter fix | 1.25 |
| Solver iterations | 4 |
| `jolt_physics_3d/limits/max_bodies` | 1,000,240 |
| `jolt_3d/limits/max_bodies` | 60,240 |

The two differently named Jolt body-limit settings likely come from different configuration eras. Which one Godot 4.6 consumes should be verified before relying on a specific effective limit.

The lawn no longer creates individual grass collision bodies. The high tick
rate supports stable mower movement, fuel and collision timing, while the
property uses one terrain body plus feature/boundary bodies. See [Performance
architecture](performance.md).

**576 ticks per second is a trap for anything that counts frames.** The old fuel
model added a fixed amount per physics tick and emptied a full tank in about
four seconds. Anything that accumulates over time must multiply by `delta`.

## Rendering

| Setting | Value |
|---|---:|
| ETC2/ASTC VRAM import | true |
| Occlusion culling | true |
| Occlusion rays per thread | 800 |

The project does not declare an object pool. Rendering optimization is primarily through MultiMesh, visibility ranges in the custom terrain, and occlusion culling.

## GDScript warnings

Warnings for unassigned and unused variables are disabled. This reduces editor noise in migrated/prototype code but also means these conditions cannot be treated as compiler-enforced cleanup signals.

## Enabled editor plugins

Only Sky3D is enabled:

```text
res://addons/sky_3d/plugin.cfg
```

Terrain3D and Terrain Splitter are present but disabled.

## Input actions

### Actions used by canonical mower controllers

| Action | Default key | Use |
|---|---|---|
| `move_forward` | W | Move along the mower’s forward basis |
| `move_back` | S | Move along the reverse basis |

Although `move_left`, `move_right`, and `jump` are configured, the canonical mower controllers do not consume them. Turning is controlled by mouse motion.

### Current direct-key controls

Some current controls use `InputEventKey.keycode` rather than named input actions:

| Key | Owner | Use |
|---|---|---|
| Mouse movement | Mower controllers | Turn mower and move camera |
| P | Rider mower | Toggle mode that disables vertical camera movement |
| ENTER | `AppUI` through the shared input bridge | Capture/release the mouse; inert while a modal hold exists |
| P | Rider mower | Toggle pitch-lock mode while keeping steering |
| C | Canonical mower controllers | Toggle precision view: closer deck camera and FOV |
| H | `ACAPauseLayer` | Open/close the Developer Debugger in Town or mowing |
| 1 / 2 / 3 / 4 | MVP root | Morning / Day / Evening / Night |
| 7 / 8 / 9 | MVP root | Clear / Foggy / Rain |

F7 refuels and F8 toggles Auto Refuel for development; F10 completes the
current job through the real completion path. HUD buttons expose the same
world functions without requiring numeric shortcuts.

### Development or noncanonical actions

| Action | Current consumer |
|---|---|
| `Day`, `Sunset`, `Night` | Footage demo script |
| `mower_1`, `mower_2`, `mower_3` | Footage demo script |
| `dev_hud` | Legacy `Mowing Section/Mower/Mower.gd` |
| `Toggle Mouse Capture` | Legacy `Main.gd` |
| `Save` | Disabled legacy grid save/load test path |
| `Cloud_Decrease`, `Cloud_Increase`, `Testing` | No project-script consumer found |

The `Day`, `Night`, and related terms also appear as weather/time preset names; that is separate from consuming the named input actions.

## Audio buses

`res://default_bus_layout.tres` (Godot's default path, so it is loaded without a
project setting).

```text
Master
  |- Mower       every mower's AudioStreamPlayer3D
  |- Ambience    the mowing scene's ambience bed
  |- Weather     rain and any future precipitation audio
  +- UI          reserved; nothing plays on it yet
```

Every bus ships at 0 dB. The authored balance is `ACAAudioMix.TRIM_DB`, applied
together with the player's volume sliders, because `AudioServer` has only one
volume per bus. See [weather, time and audio](systems/weather-time-and-audio.md#audio).

## Export presets

| Preset | Platform | Recorded export target |
|---|---|---|
| Android | Android | APK outside the project |
| itch IO | Web | Web export directory outside the project |
| Windows Desktop | Windows Desktop | Versioned executable directory outside the project |

Exported builds and output folders are not part of the developer documentation source analysis.
