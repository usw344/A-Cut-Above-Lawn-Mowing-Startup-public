# Save and Load

Status: Existing foundations, not a complete runtime system

## Current position

Several scripts define serializable dictionaries or save-related APIs, but no authoritative end-to-end save file exists.

The current MVP:

- Does not create or select a profile.
- Does not write gameplay state.
- Does not load gameplay state.
- Does not autosave.
- Does not expose return-to-menu flow.

## Existing components

| Component | Existing capability | Integration status |
|---|---|---|
| `Game_Profile` | Version, profile name, data dictionary | Class exists; not created by working model code |
| `New Game.gd` | Validates name and opens/creates `user://saves` | Stops before profile creation or scene load |
| `Model.gd` | Declares save/load/profile methods | Methods are empty or discard constructed data |
| `Job_Data_Container` | Saves key generated-job fields | Not connected to current gameplay |
| `Custom_Gridmap` | Saves grid parameters, lookup dictionaries, and chunks | Implemented dictionary round-trip; not written by app flow |
| `Multi_Mesh_Chunk` | Saves mowed/unmowed coordinates and chunk parameters | Used by grid save representation |
| `Mowing Object` | Intended save/load wrapper | Methods are empty |

## Intended storage location

`New Game.gd` uses:

```text
user://saves
```

It:

1. Attempts `DirAccess.open("user://saves")`.
2. Creates the directory when absent.
3. Returns an opened `DirAccess`.

This is the appropriate broad location for release save files.

## Game profile object

`Data Structures/Game Profile.gd` declares `class_name Game_Profile`.

Fields:

- `version` dictionary with Major, Minor, and Smallest values.
- `profile_name`.
- Generic `data` dictionary.

The constructor expects all version parts, a name, and the data dictionary.

No script currently constructs a valid profile because `model.get_game_profile_object()` is empty.

## Model save API

`Model.save_game_data(file_name)` currently constructs:

```text
{
  "speed": ...,
  "blade_length": ...,
  "mower_fuel": ...,
  "mower_fuel_idle_counter": ...,
  "idle_fuel_use": ...
}
```

It does not:

- Return the dictionary.
- Open a file.
- Store data.
- Use `file_name`.

`load_game_data()` and `get_game_profile_object()` are empty.

## Job data representation

`Job_Data_Container.save_object()` returns:

```text
{
  "id": ...,
  "width": ...,
  "length": ...,
  "grass_data": ...,
  "object_data": ...
}
```

Its `load_object()` restores those fields.

Other fields such as house metadata, scale data, and initialization flags are currently omitted from that save dictionary.

## Mowing-grid representation

The grid and chunk dictionary formats are documented in [Mowing grid and grass removal](mowing-grid.md).

They preserve:

- Grid dimensions and batching.
- Coordinate/chunk lookup dictionaries.
- Per-chunk position and identity.
- Mowed and unmowed coordinates.
- Global-to-local coordinate references.

Loading recreates MultiMeshes and can recreate grass collision bodies.

## Development save test

`Custom_Gridmap.test_save_loading()` uses:

```text
res://Saves/testing/load_save_testing.txt
```

and `FileAccess.store_var(..., true)`.

The test call is disabled in normal `_process()`. This is not a release save path and should not be described as the canonical storage format.

The script also contains a CSV writer with a hard-coded path outside the repository. That is development instrumentation, not game persistence.

## Missing orchestration

A complete system still needs:

- Profile creation and filename rules.
- Duplicate-name handling.
- Versioned top-level schema.
- Serialization and atomic write strategy.
- Error handling and backup policy.
- Load menu enumeration.
- Mapping from saved mower IDs to canonical mower scenes.
- Job offer versus accepted-job persistence rules.
- Economy/equipment state.
- Time/weather state.
- Grid-state size and performance validation.
- Scene transition into loaded gameplay.
- Migration strategy.

## Compatibility guidance

There is no released authoritative schema yet, but the first formal schema should:

- Store a clear format version.
- Use stable logical IDs rather than node names where possible.
- Separate profile state from current-scene transient state.
- Treat canonical mower IDs as data, not raw node references.
- Make omitted/default fields explicit.
- Support adding fields without invalidating older saves.
- Define whether job offers continue counting down while not loaded.
- Avoid writing release saves under `res://`.

## Authority

`Documentation.odt` must not be used to infer a save format. It is obsolete. The source files listed here and future approved schema decisions are the relevant authorities.
