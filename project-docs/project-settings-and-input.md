# Project Settings and Input

Status: Confirmed from `project.godot`

## Application

| Setting | Value | Architectural relevance |
|---|---|---|
| Project name | `A Cut Above` | Display/export identity |
| Feature tags | `4.6`, `Mobile` | Godot compatibility and renderer feature selection |
| Main scene | UID for `Minimum Viable Game.tscn` | Authoritative runtime root |
| Maximum FPS | 144 | Main-loop cap |
| Icon | `res://icon.svg` | Application icon |

## Autoload

```text
model="*res://Data Structures/Model.gd"
```

The leading `*` enables the autoload as a scene-tree node. Scripts access it with the lowercase global name `model`.

## Display

| Setting | Value |
|---|---:|
| Viewport width | 1920 |
| Viewport height | 1080 |
| Window mode | 3 |
| Handheld orientation | 1 |
| VSync mode | 0 |

The MVP HUD uses full-viewport Control layouts authored around this project resolution.

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

The high tick rate and body limits are closely related to the grass system’s many individual collision bodies. See [Performance architecture](performance.md).

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
| `/` | MVP HUD | Toggle captured/visible mouse |
| H | MVP HUD | Show or hide the HUD |
| 1 / 2 / 3 | MVP root | Day / Evening / Night |
| 7 / 8 / 9 | MVP root | Clear / Foggy / Rain |

HUD buttons expose most of the time/weather functions without requiring the numeric shortcuts.

### Development or noncanonical actions

| Action | Current consumer |
|---|---|
| `Day`, `Sunset`, `Night` | Footage demo script |
| `mower_1`, `mower_2`, `mower_3` | Footage demo script |
| `dev_hud` | Legacy `Mowing Section/Mower/Mower.gd` |
| `Toggle Mouse Capture` | Legacy `Main.gd` |
| `Save` | Disabled grid save/load test path |
| `Cloud_Decrease`, `Cloud_Increase`, `Testing` | No project-script consumer found |

The `Day`, `Night`, and related terms also appear as weather/time preset names; that is separate from consuming the named input actions.

## Export presets

| Preset | Platform | Recorded export target |
|---|---|---|
| Android | Android | APK outside the project |
| itch IO | Web | Web export directory outside the project |
| Windows Desktop | Windows Desktop | Versioned executable directory outside the project |

Exported builds and output folders are not part of the developer documentation source analysis.
