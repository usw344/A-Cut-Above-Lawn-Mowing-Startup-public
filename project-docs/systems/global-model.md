# Global Model and Runtime State

Status: **Current, but deliberately narrow** — reconciled 2026-08-30.

`model` is one compatibility autoload, not the application's general state
container. New state belongs to its owning authority: `WorldClock` owns time
and weather, `JobManager` owns jobs, `GameSession` owns routing and money,
`MowerFuel` owns fuel rules, and the business autoloads own equipment, resources
and progression. See [application layer](../application-layer.md).

## Definition

`Data Structures/Model.gd` is configured as:

```text
model="*res://Data Structures/Model.gd"
```

It extends `Node`, declares `class_name Model`, and is accessed through the
lowercase autoload name `model`.

## Responsibilities

The model retains compatibility state used by the canonical mower controllers:

- authored/shared speed and blade-length values;
- the current fuel level and legacy fuel counters;
- mower position;
- legacy mower-selection metadata and cuttings fields.

`MowerFuel` owns the rules for consuming/refilling fuel even though the level is
stored on `model`, because the existing save block persists those fields.
`Equipment` owns current mower-type ownership and selection; the model's
`mower_scene_references` points to the older `Mower_Normal` architecture and
must not define the current schema.

The placeholder `get_game_time()`, `get_game_weather()` and `get_game_money()`
methods are superseded. Call `WorldClock` and `GameSession` instead. The model's
`save_game_data()` / `load_game_data()` / `get_game_profile_object()` methods
are incomplete stubs; `SaveService` is the functioning save owner.

## Current state fields

| Field | Current role |
|---|---|
| `speed` | Authored base read by canonical controllers; development speed control can set it |
| `blade_length` | Legacy blade-width compatibility field |
| `mower_fuel` | Float fuel level, read/written through `MowerFuel` rules |
| `mower_fuel_idle_counter` / `idle_fuel_use` | Retained legacy save fields; current fuel consumption is delta-time based |
| `mower_position` | Updated by canonical mower controllers |
| `mower_grid_position` | Reserved; no current writer |
| `stored_cuttings` / `cuttings_in_mower` | Compatibility getters/setters; `Clippings` owns current bag and yard state |
| `current_mower` / `mower_scene_references` | Legacy selection metadata; current selection is `Equipment` plus stable IDs |

The legacy `job_offers` dictionary and its `Job_Offer` methods were removed with
the old job prototype. `ACAJobManager` is the current job registry.

## Public API groups

### Compatibility API used by current runtime

- `get_speed()` / `set_speed()`
- `get_mower_fuel()` / `set_mower_fuel()`
- `get_mower_fuel_idle_counter()` / `set_mower_fuel_idle_counter()`
- `is_mower_fuel_idle_counter()` / `increment_mower_fuel_idle_counter()`
- `set_mower_position()` / `get_mower_position()`

### Present but not authoritative

Blade-length and cuttings accessors remain for compatibility. The placeholder
information getters remain, but return empty values and must not be used for
application state.

## Active consumers

| Consumer | State used |
|---|---|
| `mower_rider.gd` | speed, fuel, fuel counters, mower position |
| `non_rider_mower.gd` | speed, fuel, fuel counters, mower position |
| `push_mower.gd` | speed, position; the push mower does not consume fuel |
| `MVP.gd` and the legacy development HUD | compatibility speed and development readouts |
| `MowerFuel` | fuel level storage, with rules owned by that autoload |
| `SaveService` | reads the durable model fields into the `mower` save block |

## Input and cursor behavior

The model's `ui_accept` bridge asks `AppUI.toggle_mouse_capture()`. It does not
assign `Input.mouse_mode` directly. `AppUI` is the only cursor writer; modal
holds make the cursor visible while a screen's context remains captured or
visible underneath.

## Persistence and compatibility

`model` persists only for the current process. Cross-launch persistence belongs
to `SaveService`, which reads the model's compatibility fields alongside the
authoritative `WorldClock`, `JobManager`, `GameSession`, economy and business
sections. Stable canonical mower identifiers are `rider`, `powered`, and
`push`; scene paths and legacy selection names are not a new save schema.

Changes to model methods can affect the playable mowers immediately. Before
removing a method, check both current controller consumers and direct save/test
references.
