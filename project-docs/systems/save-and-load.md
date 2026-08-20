# Save and Load

Status: **Implemented** — save format version **1**, added 2026-08-19.

## Owner

`SaveService` — `Game/App/save_service.gd`, autoloaded as **`SaveService`**.

It is the only thing that touches save files. It does not own game state: it asks
each owning system for a dictionary and hands one back on load.

```
SaveService
  ├─ WorldClock.to_save_dict()   / from_save_dict()
  ├─ JobManager.save_state()     / load_state()
  ├─ GameSession.to_save_dict()  / from_save_dict()
  ├─ GameSettings.to_save_dict() / from_save_dict()     (separate file)
  ├─ model  (mower/fuel fields, read directly — Model.gd has no save API)
  │           `mower_fuel` is a FLOAT since Milestone 9. It round trips exactly,
  │           and an EMPTY tank loads empty — the old forced refill to 100 is
  │           gone. `mower_fuel_idle_counter` / `idle_fuel_use` are still
  │           written but nothing reads them; they are legacy fields of the
  │           current save format. See systems/mowers-and-controls.md.
  └─ Custom_Gridmap.mowed_item_names() / restore_mowed_items()
```

## Storage

| Context | Root |
|---|---|
| Production default | `user://saves/` |
| Override | `--save-root=<absolute path>` on the command line |

The override exists so automated tests never write outside the working
directory. It is read once in `SaveService._ready()` from both
`OS.get_cmdline_args()` and `OS.get_cmdline_user_args()`.

```
godot --headless --path . "res://Dev tools/Validation/Save Test.tscn" -- "--save-root=D:/some/dir/saves"
```

Files in the root:

| File | Contents |
|---|---|
| `<slot>.json` | One save |
| `<slot>.json.bak` | The previous version of that save |
| `<slot>.json.tmp` | Only exists mid-write |
| `settings.json` | Presentation settings — global, **not** per-save |

## Write safety

`save_game()` writes temp-then-replace:

1. Serialize and write `<slot>.json.tmp`.
2. If `<slot>.json` exists, copy it to `<slot>.json.bak`.
3. Remove `<slot>.json`, rename `.tmp` to `<slot>.json`.

An interrupted save therefore leaves the previous save intact, plus a stray
`.tmp` that the next write overwrites.

`load_game()` falls back to `<slot>.json.bak` if the main file is missing or
fails to parse. Every failure path returns `false` and pushes an error; nothing
throws.

## Schema — version 1

```jsonc
{
  "save_format_version": 1,
  "saved_at_unix": 1755590000,
  "saved_at_text": "2026-08-19 04:33:20",
  "slot_name": "slot1",

  "profile": {
    "profile_name": "Player",
    "money": 355
  },

  "world": {                       // WorldClock.to_save_dict()
    "minutes": 533.4,              // absolute game minutes since the epoch
    "season": 0,                   // ACAJobEnums.Season
    "weather": "Rain",             // one of WorldClock.WEATHER_PRESETS
    "running": true,
    "minutes_per_real_second": 6.0
  },

  "jobs": {                        // JobManager.save_state()
    "generator_version": 1,
    "market_strength": 4,
    "economy": 2,
    "climate": 1,
    "next_arrival_time": 611.2,    // absolute game minutes; INF -> null
    "available": [ /* job */ ],
    "current":   [ /* job */ ],
    "past":      [ /* job */ ]
  },

  "session": {                     // GameSession.to_save_dict()
    "money": 355,
    "screen": 2,                   // ACAGameSession.Screen — TOWN or MOWING only
    "session_active": true,
    "job_elapsed_seconds": 41.5
  },

  "mower": {                       // read from the `model` autoload
    "current_mower": "Small Gas Mower",
    "speed": 10,
    "blade_length": 1,
    "mower_fuel": 96.4,
    "mower_fuel_idle_counter": 12,
    "idle_fuel_use": 26,
    "stored_cuttings": 0,
    "cuttings_in_mower": 0
  },

  "economy": {                     // OPTIONAL - Economy.to_save_dict()
    "seed": 1837465002,
    "condition": 3,                // ACAEconomyManager.Condition
    "condition_days_left": 7,
    "event_id": "fuel_shortage",   // "" when none
    "event_days_left": 3,
    "event_cooldown": 0,
    "fuel_noise": -0.0142,         // the mean-reverting drift term
    "last_day": 41
  },

  "upgrades": {                    // OPTIONAL - MowerUpgrades.to_save_dict()
    "levels": {
      "rider": {"drive": 2, "fuel_system": 1},
      "push":  {"bearings": 1}
    }
  },

  "mowing": {                      // present ONLY when screen == MOWING
    "job_id": "job_1605987657_v1_48000",
    "grid_size": 96,
    "mowed_items": ["12,4,0,6", "12,4,0,8"],   // "chunk_id,x,y,z"
    "mower_position": [12.5, 2.0, -3.25],
    "mower_rotation": [0.0, 1.57, 0.0]
  }
}
```

### A job

```jsonc
{
  "id": "job_1605987657_v1_48000",
  "seed": 1605987657,
  "generator_version": 1,
  "job_site": "Small Office Grounds",
  "property_type": 1,
  "lawn_size": 1,
  "grid_size_x": 96, "grid_size_y": 96,
  "base_pay": 105,
  "offer_duration_minutes": 195.0,
  "created_game_time": 480.0,
  "expiry_game_time": 675.0,
  "accepted_game_time": 495.2,
  "completed_game_time": -1.0,
  "status": 3,
  "progress": 0.42
}
```

`seed` + `generator_version` are stored even though every generated field is also
stored. That pair reproduces the whole core contract through
`ACAJobGenerator.generate_core()`, so a future migration can regenerate rather
than guess. **Never reorder generator draws without bumping `GENERATOR_VERSION`.**

## What persists — and what deliberately does not

**Persists:** money; world time, day, season, weather preset, time scale; every
available / current / past job with its absolute timestamps; market strength,
economy, climate and the next arrival time; which screen the player was on;
mower selection and fuel/cuttings state; **and, mid-job, exactly which grass
instances have been cut**, plus the mower's position and rotation.

**Does not persist, by design:**

- Nodes, tweens, timers, audio players, particles, any transient visual state.
- The grass grid's full structure. It is **reconstructed** by
  `test_custom_gridmap(grid_size)` and then the saved mowed set is replayed. Only
  the mowed portion is stored, so an untouched Large Lawn costs nothing and a
  fully mowed one costs ~36,864 short strings.
- `Custom_Gridmap.save_object()` / `load_object()` — the pre-existing pair. They
  serialize *every* coordinate of *every* chunk plus two lookup dictionaries
  keyed by `Vector3i`, which is both far larger than necessary and not
  JSON-representable. They were left untouched (still used by nothing) rather
  than removed; see KNOWN LIMITATIONS.
- Settings, which live in their own `settings.json` because they are a property
  of the installation, not of a save.

## Resume

`SaveService.load_game()`:

1. Reads and validates the file (version, required sections).
2. `WorldClock.from_save_dict()`, `JobManager.load_state()`,
   `GameSession.from_save_dict()`, mower fields onto `model`.
3. If `session.screen == MOWING` **and** the current job still exists, it stashes
   the `mowing` block and calls `GameSession.go_to_mowing()`. Otherwise
   `GameSession.go_to_town()`.
4. The mowing scene builds its grid from the restored contract, then calls
   `SaveService.take_pending_mowing_state()` — a one-shot handoff — and applies
   the mowed set and mower transform.

`take_pending_mowing_state()` clears itself, so a later manual visit to the same
job never re-applies a stale grid.

## Public API

```gdscript
SaveService.storage_root() -> String
SaveService.has_any_save() -> bool
SaveService.list_saves() -> Array[Dictionary]   # slot, path, saved_at_*, day, money, valid
SaveService.save_game(slot_name := "") -> bool  # "" -> DEFAULT_SLOT
SaveService.load_game(slot_name) -> bool
SaveService.load_most_recent() -> bool
SaveService.delete_save(slot_name) -> bool
SaveService.take_pending_mowing_state() -> Dictionary
SaveService.save_settings() / load_settings()
```

**SIGNALS:** `game_saved(slot_name)`, `game_loaded(slot_name)`,
`save_failed(reason)`, `load_failed(reason)`

## Grid restore support added to the mowing system

```gdscript
# Custom_Gridmap
mowed_item_names() -> PackedStringArray
restore_mowed_items(names: PackedStringArray) -> int   # returns how many applied

# Multi_Mesh_Chunk
mowed_item_names() -> PackedStringArray
mow_item_silent(item_name, coord) -> bool   # no multimesh rebuild
rebuild_multimeshes() -> void
```

`restore_mowed_items()` groups by chunk and rebuilds each affected chunk's
MultiMesh **once**, instead of once per blade. Replaying 36,864 individual
`mow_item()` calls would rebuild the meshes 36,864 times.

## Version policy

`save_format_version` is checked on load. Version 1 is the only version, so there
is no migration code and none should be written speculatively. When the schema
changes:

- Additive change (new optional field): keep version 1, default it on read.
- Breaking change: bump the version and add one explicit upgrade step.

Missing fields already fall back to defaults everywhere via `data.get(key, default)`.

### The economy and upgrades sections are the worked example

Both were added in session 7 **without bumping the version**, because both are
additive. `load_game()` requires only `world`, `jobs` and `session`; everything
else is read with a default.

A save written before they existed therefore loads, and:

- `Economy.initialise_for_legacy_save(day)` starts a fresh market anchored to
  **that save's own day**, rather than one that has been running since the epoch;
- `MowerUpgrades.from_save_dict({})` leaves every machine stock.

`Economy Test` writes a legacy save with neither section and asserts it loads
and produces a working market.

Two rules that made this safe:

1. **Derived values are never saved.** Prices and indices are recomputed from
   the condition, event and drift, so a save cannot contain a price that
   disagrees with the state that produced it.
2. **Loading never advances the market.** `from_save_dict()` restores and stops;
   `WorldClock.day_changed` moves it when the world next moves. Combined with
   day-derived seeding, loading a save cannot reroll the economy — `Economy Test`
   asserts the restored fuel price matches to four decimal places.

Unknown mower ids and unknown upgrade categories are **dropped** on load rather
than kept, so a level for something this build no longer has cannot sit in the
file forever and reappear if the name is reused.

## Where the player reaches it

| Action | Where |
|---|---|
| Save | Pause menu -> **SAVE GAME** (during a job), or **F5** anywhere in a live session |
| Load | Main menu -> **LOAD GAME** (slot picker), **CONTINUE** (most recent), or **F9** |
| Delete | Main menu -> LOAD GAME -> DELETE on a row |

F5/F9 are handled in `GameSession._unhandled_input()` rather than in a screen,
because the Town has no pause menu of its own and quick-save is an
application-level concern.

`UI/Load Game/load_game.gd` (`LoadGameScreen`) is built from script rather than
authored as a scene, so it always matches `UITheme` and there is no `.tscn`
palette to re-point. It is presentation only: the host supplies
`SaveService.list_saves()` and acts on `load_requested` / `delete_requested` /
`back_requested`.

## KNOWN LIMITATIONS

- **Saving always writes the same slot** (`slot1`) from the in-game controls. The
  service supports arbitrary slot names and the picker lists every slot it finds,
  but there is no "save as" UI, so multiple slots only appear if something else
  creates them (the test harness does).
- **No autosave.** Saving is explicit.
- Saving from the Town is only available via F5 — the town has no pause menu.
- `Custom_Gridmap.save_object()` / `load_object()` are now dead weight next to the
  lighter mowed-set approach. Left in place because removing working serialization
  code was out of scope for this pass.
- `Data Structures/Game Profile.gd` (`class_name Game_Profile`) is **not used** by
  this system. It predates it and stores a version triple plus a copy of the
  model. Kept for review; the schema above supersedes it.

## Settings keys (2026-08-19)

`settings.json` is written from `GameSettings.values()`, so it picks up new keys
automatically. `invert_look_y` (bool, default `false`) was added in Milestone 5
and needs no save-format change — settings are versionless and merged over
`DEFAULTS`, so an older file simply falls back to the default.
