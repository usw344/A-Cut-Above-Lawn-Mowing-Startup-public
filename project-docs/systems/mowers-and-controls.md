# Mowers and Player Controls

Status: Current playable runtime  
Canonical location: `Assets/Vehicles and Mowers/Mowers/`

## Canonical mower variants

| Runtime key | Scene                  | Controller           | Visual source                              | Audio             |
| ----------- | ---------------------- | -------------------- | ------------------------------------------ | ----------------- |
| `rider`     | `Mower Rider.tscn`     | `mower_rider.gd`     | `Mower Scenes/Rider Mower (In Parts).tscn` | Powered mower SFX |
| `powered`   | `Non Rider Mower.tscn` | `non_rider_mower.gd` | `Non Rider Mower Mesh.tscn`                | Powered mower SFX |
| `push`      | `Push Mower.tscn`      | `push_mower.gd`      | `Push Mower Mesh.tscn`                     | Push mower SFX    |

The rider mower is authored into `Minimum Viable Game.tscn` and is the initial active mower. The HUD can replace it with either alternative.

## Common scene contract

Each canonical wrapper scene is a `CharacterBody3D` containing:

- A mower visual scene.
- A collision shape.
- A camera.
- A development label CanvasLayer.
- A 3D audio player.
- A controller script.

Each controller declares:

```gdscript
signal collided
signal fuel_empty
```

The MVP depends on the `collided` signal when connecting a newly selected mower to the custom mowing grid.

## Movement

Canonical movement follows the same broad sequence:

1. Read project gravity.
2. Apply gravity to vertical velocity.
3. Record the mower position in `model`.
4. Read `move_forward` and `move_back`.
5. Multiply direction by `model.get_speed() * 3`.
6. Call `move_and_slide()`.

W and S are the default actions. A/D and jump exist in the project input map but are not used by these controllers.

Turning is mouse-driven rather than action-driven.

## Camera and mouse control

### Rider mower

The rider implementation keeps target yaw and pitch values and smooths them with exponential interpolation:

- Mouse horizontal motion changes target body yaw.
- Mouse vertical motion changes target camera pitch.
- Pitch is clamped between exported minimum and maximum degrees.
- P toggles a mode that disables vertical camera movement while retaining horizontal turning.

Applied yaw is forwarded to the multipart mower visual so its steering wheel can react.

### Powered and push mowers

These controllers directly rotate the body around Y from horizontal mouse motion and rotate the camera around X from vertical mouse motion.

All mower `_ready()` methods capture the mouse.

## Rider visual animation

`Mower Scenes/rider_mower_(in_parts).gd` extends `MeshInstance3D` and owns:

- Four wheel mesh references.
- Steering wheel reference.
- Wheel rotation from mower speed.
- Smoothed steering-wheel deflection and return.
- A small scale pulsation intended to simulate engine vibration.

The rider controller calls:

- `send_speed_data(velocity, delta)`
- `send_rotation_data(applied_rotation)`

This separation makes the wrapper responsible for physics and the multipart scene responsible for visual part animation.

## Fuel

All canonical controllers currently share the same global fuel state.

Per physics frame:

- A small idle amount is added to `mower_fuel_idle_counter`.
- Forward or backward input adds a larger amount.
- When the counter reaches `idle_fuel_use`, one fuel unit is removed and the counter resets.
- If fuel reaches zero, `fuel_empty` is emitted.

Current testing behavior immediately resets fuel to 100 after an empty-fuel event. Fuel exhaustion therefore does not yet stop gameplay.

Because the state is in `model`, fuel and speed carry across mower switches.

## Collision contract

After `move_and_slide()`, each controller:

1. Iterates `get_slide_collision_count()`.
2. Collects each `KinematicCollision3D`.
3. Emits the collection through `collided`.

The custom grid checks collider names and treats grass collider names as encoded chunk coordinates.

This signal is emitted every mower physics frame, even when the collision array is empty.

## Audio

### Rider and powered mower

Engine volume and pitch interpolate between idle and moving values based on horizontal-speed ratio. A small pitch increase is added during acceleration.

### Push mower

Audio interpolates from effectively silent while stopped to a louder moving value. It does not use the same powered-idle profile.

All mower audio players start in `_ready()`.

## Mower selection

`MVP.gd` preloads all three scenes and maps:

```text
push
powered
rider
```

The HUD popup IDs 0, 1, and 2 map to those keys. Selection preserves the current transform and mouse mode, then instantiates a fresh mower and reconnects mowing collisions.

## Canonical future direction

Future mower selection, ownership, upgrades, and persistence should extend this canonical scene set.

Expected model responsibilities include:

- Stable selected-mower identifier.
- Owned mower list.
- Persistent per-mower statistics or upgrades.
- Fuel and storage state ownership rules.
- Separation of base mower data from transient runtime node state.

Those schemas are not yet implemented.

## Legacy mower architecture

`Mowing Section/Mower/Mower_Normal/Mower_Normal.tscn` and `Mowing Section/Mower/Mower.gd` are retained for compatibility and historical reference.

Evidence that they are noncanonical:

- The MVP does not instantiate them.
- The MVP has its own three-scene lookup.
- Their movement basis, visual node assumptions, and speed multiplier differ.
- `Model.mower_scene_references` points to this older scene rather than the active scene set.

They should not be described as a fourth current mower type.
