# Global Model and Runtime State

Status: Current playable runtime, with partially integrated future state

## Definition

`Data Structures/Model.gd` is configured in `project.godot` as:

```text
model="*res://Data Structures/Model.gd"
```

The script extends `Node`, declares `class_name Model`, and is accessed by runtime scripts through the lowercase autoload name `model`.

## Responsibilities

The model currently combines:

- Canonical mower runtime state.
- Mowing/cuttings state.
- Older mower-selection metadata.
- Job-offer prototype state.
- Placeholder UI information.
- Save/profile extension points.

It is the only configured application-wide manager.

## Current state fields

### Mower behavior

| Field | Default | Current role |
|---|---:|---|
| `speed` | 10 | Read by all canonical mower controllers; set by MVP HUD |
| `blade_length` | 1 | Used by the legacy mower blade-width function |
| `mower_fuel` | 100 | Shared fuel value across mower instances |
| `mower_fuel_idle_counter` | 0 | Accumulates idle and movement fuel use |
| `idle_fuel_use` | 26 | Counter threshold before one fuel unit is removed |
| `mower_position` | `Vector3()` | Updated each canonical mower physics frame |
| `mower_grid_position` | Uninitialized `Vector2` | Reserved; no active writer found |

### Grass cuttings

| Field | Default | Current role |
|---|---:|---|
| `stored_cuttings` | 0 | Has getter and setter; no active MVP consumer |
| `cuttings_in_mower` | 0 | Has getter and setter; no active MVP consumer |

The older mowing UI calls `model.get_cuttings()`, but that method does not exist. It is therefore not a valid consumer of the current API.

### Mower selection metadata

```gdscript
var current_mower:String = "Small Gas Mower"
```

The adjacent `mower_scene_references` dictionary only resolves `"Small Gas Mower"` to the older `Mower_Normal.tscn`. Other entries are null.

This lookup belongs to the legacy mower architecture. The current MVP keeps its own canonical lookup:

```text
push -> Push Mower.tscn
powered -> Non Rider Mower.tscn
rider -> Mower Rider.tscn
```

Future development is expected to move the selected canonical mower and persistent mower data into the model. The current `Assets/Vehicles and Mowers/Mowers` scenes are the foundation for that work; the older lookup should not define the new schema.

### Job offers

```gdscript
var job_offers:Dictionary = {}
```

The model exposes:

- `add_job_offer()`
- `remove_job_offer()`
- `get_all_job_offers()`

The partially integrated job manager, generator, offer, and display scripts use this dictionary as their shared offer registry.

## Public API groups

### Canonical runtime API

- `get_speed()` / `set_speed()`
- `get_mower_fuel()` / `set_mower_fuel()`
- `get_mower_fuel_idle_counter()` / `set_mower_fuel_idle_counter()`
- `is_mower_fuel_idle_counter()`
- `increment_mower_fuel_idle_counter()`
- `set_mower_position()` / `get_mower_position()`

### Present but not integrated into the MVP

- Blade-length getters/setters.
- Cuttings getters/setters.
- Job-offer registry methods.
- `get_game_time()`
- `get_game_weather()`
- `get_game_money()`

The three information getters currently return empty strings.

### Incomplete persistence API

- `save_game_data(file_name)` constructs a local dictionary but neither returns nor writes it.
- `load_game_data(file_name)` is empty.
- `get_game_profile_object()` is empty.

These methods must not be documented as a functioning save service.

## Active consumers

| Consumer | State used |
|---|---|
| `mower_rider.gd` | Speed, fuel, fuel counter, mower position |
| `non_rider_mower.gd` | Speed, fuel, fuel counter, mower position |
| `push_mower.gd` | Speed, fuel, fuel counter, mower position |
| `MVP.gd` | Speed |
| `mvp_hud.gd` | Initial speed |

## Partially integrated consumers

- Job manager, generator, offer, and display.
- Main-area information bar.
- Mowing information UI.
- New-game/profile prototype.
- Legacy `Mower.gd`.

## Input behavior

The model’s `_input()` toggles captured/visible mouse mode when `ui_accept` is pressed. This operates globally whenever the autoload receives input and is separate from the MVP HUD’s `/` key handling.

## Persistence and compatibility

The autoload persists only for the current process. It does not currently persist across application launches.

Once a real save format uses model fields:

- Field renames and type changes may require migrations.
- Canonical mower identifiers should be stable.
- Scene paths should not be the sole persistent identity for owned equipment.
- Runtime-only node references and transient counters should be separated from durable profile data.

There is no authoritative released save schema in the current repository.

## Change impact

Changes to Model methods can affect the playable mowers immediately and the partially integrated job/UI/save systems later. Before removing a method, check both current-main reachability and direct source references.
