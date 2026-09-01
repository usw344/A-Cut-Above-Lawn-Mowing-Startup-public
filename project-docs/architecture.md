# Architecture and System Relationships

Status: **Current** — source-verified 2026-08-30 (game-feel and debugger pass).
Entry point: `res://Game/App/Main Menu Screen.tscn`

## Layering

The application is three layers. Keep them separate.

```
APPLICATION   GameSession  WorldClock  SaveService  AppUI  GameSettings
              Economy  MowerUpgrades  MowerFuel  Equipment  Clippings  Business
              Territory  Agreements  Portfolio                 (autoloads)
              owns: routing, session state, time and weather STATE, the market,
                    file I/O, and THE completion pathway

DOMAIN        JobManager (ACAJobManager)     ACAProperty + ACALawn
              model (legacy shared state)    preset_manager -> environment
              owns: game state. Never changes scenes. Never touches UI.

PRESENTATION  res://UI/**   ACAJobBoard   ACABusinessHUD   ACABusinessServices
              displays state, emits intent. Owns no game state.
```

Integration between layers lives in exactly three host scripts:
`Game/App/main_menu_screen.gd`, `Game/App/town_screen.gd`,
`Game/App/gameplay_ui.gd`.

## Autoloads

Registered in `project.godot`, in load order.

| Autoload | Script | Owns |
|---|---|---|
| `model` | `Data Structures/Model.gd` | LEGACY shared state: mower speed, fuel level, blade length |
| `MowerFuel` | `Game/App/mower_fuel.gd` | Fuel RULES. Storage stays on `model` |
| `WorldClock` | `Game/World/world_clock.gd` | Authoritative game time, season, weather STATE |
| `JobManager` | `Main Area/ACA_JobSystem/.../job_manager.gd` | Job domain state, offers, expiry, history |
| `GameSettings` | `Game/App/game_settings.gd` | Player settings and their application |
| `AppUI` | `Game/App/app_ui.gd` | Transitions, notifications, cursor ownership |
| `GameSession` | `Game/App/game_session.gd` | Routing, session state, **the one money balance**, completion |
| `SaveService` | `Game/App/save_service.gd` | File I/O. Owns no domain state |
| `Economy` | `Game/Economy/economy_manager.gd` | Market conditions, events, prices |
| `MowerUpgrades` | `Game/Economy/mower_upgrades.gd` | Per-mower upgrade levels and their effects |
| `Equipment` | `Game/Economy/equipment.gd` | Owned mower types, attachments, autonomous equipment |
| `Clippings` | `Game/Economy/clippings.gd` | Bag, yard, compost and clipping sales |
| `Business` | `Game/Economy/business.gd` | Reputation, customers, competitors, schedule and yard state |
| `Territory` | `Game/Business/service_territory.gd` | Owned regions and regional job filtering |
| `Agreements` | `Game/Business/service_agreements.gd` | Recurring service agreements |
| `Portfolio` | `Game/Business/portfolio.gd` | Portfolio metadata and captured images |

## Runtime composition

```mermaid
flowchart TD
    Project["project.godot"] --> Menu["Game/App/Main Menu Screen.tscn"]

    subgraph Autoloads
        Clock["WorldClock"]
        Jobs["JobManager"]
        Session["GameSession"]
        Save["SaveService"]
        Econ["Economy"]
        Upg["MowerUpgrades"]
        Fuel["MowerFuel"]
    end

    Session -->|"set_time_provider"| Jobs
    Session -->|"pay_multiplier_provider"| Jobs
    Clock -->|"day_changed"| Econ
    Jobs -->|"begin_job_requested(job)"| Session

    Menu -->|"new_game"| Session
    Session -->|"go_to_town"| Town["Game/App/Town Screen.tscn"]
    Town --> BT["BusinessTown.tscn"]
    BT --> Board["ACAJobBoard"] --> Jobs
    BT --> Services["ACABusinessServices"]
    Services --> Econ
    Services --> Upg
    Services --> Fuel
    Services -->|"try_spend"| Session

    Session -->|"go_to_mowing"| MVPScene["Game/M.V.P/Minimum Viable Game.tscn"]
    MVPScene --> MVP["MVP.gd"]
    MVPScene --> Mower["Current mower scene"]
    MVPScene --> Property["Property (ACAProperty)"]
    MVPScene --> Presets["Preset Manager"]
    MVPScene --> GPUI["Gameplay UI.tscn"]

    Mower -->|"collided(collision_array)"| Cutter["ACAMowerCutter"]
    Cutter -->|"swept deck geometry"| Property
    Mower --> Upg
    Mower --> Fuel
    Property --> Chunks["ACATerrain / ACALawn / features / grass / foliage"]

    Property -->|"mowing_progress_changed"| MVP
    MVP -->|"complete_current_job"| Session
    Session -->|"job_settled(summary)"| GPUI
    GPUI -->|"go_to_town"| Session

    Clock --> MVP --> Presets
    Presets --> EnvAdapter["ACAWeatherVisualAdapter"]
    EnvAdapter --> Package["ACASky3DEnvironment (addon)"]
    Package --> Sky3D["vanilla Sky3D"]
    Package --> Rig["ACAPrecipitationRig"]
```

## The boundaries that must not be crossed

1. **`ACAJobManager` never changes scenes.** `begin_new_job()` validates, marks
   the job `IN_PROGRESS`, emits `begin_job_requested(job)` and stops.
   `GameSession` does the transition.
2. **There is one completion pathway.** Real 100% mowing and the development
   fast-completion helper both reach `GameSession.complete_current_job()`.
3. **There is one money balance.** `GameSession` holds it. `Economy` and
   `MowerUpgrades` PRICE things; neither keeps a wallet. Every payment goes
   through `GameSession.try_spend()`, which cannot go negative.
4. **The Job System does not know the economy exists.** The application layer
   injects `pay_multiplier_provider`, exactly as it injects the time provider.
5. **`res://addons/sky_3d/` is read-only.** The environment package reads and
   writes its public properties and modifies nothing inside it.

## Ownership

### Mowing scene root (`MVP.gd`)

Cross-system orchestration: property creation, mower placement and switching,
lawn reset, ambient audio startup, time and weather requests, and telling the weather
system where the camera and the ground are. It does not own grass behaviour,
mower movement or the sky.

### Global model

`model` is LEGACY shared mutable state — mower speed, fuel level, blade length,
position. New systems do not add to it. `MowerFuel` owns the fuel RULES while
`model` merely stores the level, which is why a save restore or a test writing
`model.set_mower_fuel()` is seen immediately.

### Mower scenes

`Assets/Vehicles and Mowers/Mowers/` — the three canonical machines. Each owns
its motion, look, gravity, audio and collision emission, declares `POWERED` and
a stable `MOWER_ID`, and multiplies its authored values by
`MowerUpgrades.*_multiplier(MOWER_ID)`. The authored base is never overwritten.

### Property and logical lawn

`ACAProperty` owns the synchronous build order: property parameters, procedural
terrain, logical lawn, feature exclusions/nodes, grass, foliage and boundary.
`ACATerrain` supplies the baked height field and the property's solid terrain
body. `ACALawn` stores one-unit cell flags and the cut-mask texture; it has no
per-grass nodes or physics bodies. `ACAMowerCutter` converts each machine's
movement into a swept `ACAMowerDeck` geometry query. `mow_swath()` and
`mow_disc()` remain media/tooling helpers and are not called by normal driving.

### Economy and upgrades

See [Jobs and Economy](systems/jobs-and-economy.md). The market moves on
`WorldClock.day_changed` and at no other time.

### Weather and environment

See [Weather, Time of Day, and Audio](systems/weather-time-and-audio.md).
`preset_manager` remains the project-facing API; the LOOK is composed by a
reusable addon.

## Canonical and superseded implementations

| Domain | Canonical | Superseded / legacy |
|---|---|---|
| Runtime world | Application screens: Main Menu → Town → `Minimum Viable Game.tscn` | `Main.tscn` |
| Mowers | `Assets/Vehicles and Mowers/Mowers/` | `Mower Scenes/`, `Mowing Section/Mower/` |
| Terrain | `ACATerrain`, procedural | authored Terrain Manager (retired), Terrain3D (removed) |
| Weather look | `addons/aca_sky3d_environment/` | in-adapter tables (session 7) |
| Rain particles | `ACAPrecipitationRig` (code-built) | authored `rain_particles.tscn` (removed) |
| Precipitation resources | — | `Weather/precipitation/*.tres`, **dead** |
| Sky | Sky3D | historical GodotSky plugin |
| Ponds | `ACAPondFeature` in generated properties, using `ACAPondCarver` | standalone `ACAPond` / `Pond Demo.tscn` |

`Weather/precipitation/*.tres` reference `res://addons/GodotWeatherSystem/`,
which is not installed. Nothing loads them. See
[Legacy and Experimental](legacy-and-experimental.md).

## What is NOT built

Stated plainly so it is not mistaken for an omission:

- **Multiple serialised copies of one mower type.** `Equipment` owns mower
  types, while `MowerUpgrades` stores per-type upgrades; serial-numbered fleets
  are not modelled.
- **A fuel inventory.** Fuel is bought into the tank, not into cans.
- **Water volumes.** Pond collision is static bed geometry. Nothing floats.
- **Snow.** `Weather/precipitation/snow*.tres` are dead files, not a feature.
