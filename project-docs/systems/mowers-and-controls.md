# Mowers and Player Controls

Status: Current playable runtime  
Canonical location: `Assets/Vehicles and Mowers/Mowers/`

## Canonical mower variants

| Runtime key | Scene                  | Controller           | Visual source                              | Audio             |
| ----------- | ---------------------- | -------------------- | ------------------------------------------ | ----------------- |
| `rider`     | `Mower Rider.tscn`     | `mower_rider.gd`     | `Mower Scenes/Rider Mower (In Parts).tscn` | Powered mower SFX |
| `powered`   | `Non Rider Mower.tscn` | `non_rider_mower.gd` | `Non Rider Mower Mesh.tscn`                | Powered mower SFX |
| `push`      | `Push Mower.tscn`      | `push_mower.gd`      | `Push Mower Mesh.tscn`                     | Push mower SFX    |

The rider mower is authored into `Minimum Viable Game.tscn` and is the initial active mower. The **development** HUD (F3) can replace it with either alternative.

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
signal fuel_empty      # POWERED mowers only - the Push Mower has neither the
                       # signal nor the state; see FUEL below
const POWERED := true  # false on push_mower.gd
func is_powered() -> bool
```

`MVP.gd` depends on the `collided` signal when connecting a newly selected mower to the custom mowing grid. **`collided` is also the blade contract**: a powered mower with an empty tank emits `fuel_empty` instead, so nothing is cut.

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

**Reworked 2026-08-19 (Milestone 5).** All three controllers now share one
convention. This is a GAMEPLAY camera — responsive, not cinematic. The trailer
has its own rig; do not slow these values down for video.

Every controller keeps `target_body_yaw` / `target_camera_pitch`, updated in
`_input` from mouse motion, and approaches them exponentially in
`_physics_process` (`1 - exp(-k * delta)`, so the feel is frame-rate independent).

| `@export` | Rider | Walk-behinds | Meaning |
|---|---|---|---|
| `mouse_yaw_smoothing` | 18.0 | 26.0 | body turn. The mower has mass, so some lag is wanted. |
| `mouse_pitch_smoothing` | 32.0 | 32.0 | camera pitch. Near-immediate; nothing physical is attached to it. |
| `min_camera_pitch_degrees` | -75 | -75 | clamp; the camera can never flip |
| `max_camera_pitch_degrees` | 45 | 45 | clamp |

Roughly: ~6-9 is cinematic drift (what the rider used to be, and why it floated),
~16-20 is responsive vehicle steering, ~30+ is effectively raw.

**Vertical direction is conventional:** mouse up looks up. `relative.y` is
positive downwards and camera pitch is positive upwards, so the controllers
**subtract**. `GameSettings.invert_look_y()` flips exactly that and nothing else;
it defaults to OFF and is never hard-coded.

Rider only: **P** toggles a mode that freezes pitch while keeping steering.
Applied yaw is forwarded to the multipart mower visual so its steering wheel
reacts (`send_rotation_data`).

Every mower `_ready()` declares `AppUI.set_mouse_context(Input.MOUSE_MODE_CAPTURED)`.
It does **not** write `Input.mouse_mode` — see the mouse capture section below.

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

See the **FUEL** section near the end of this page — it is the authoritative
description. In short: `MowerFuel` owns the rules, `model.mower_fuel` holds the
level, the two powered mowers burn it and the Push Mower does not.

## Collision contract

After `move_and_slide()`, each controller:

1. Iterates `get_slide_collision_count()`.
2. Collects each `KinematicCollision3D`.
3. Emits the collection through `collided`.

The custom grid checks collider names and treats grass collider names as encoded chunk coordinates.

This signal is emitted every mower physics frame, even when the collision array is empty.

## Audio

Every mower's `AudioStreamPlayer3D` plays on the **`Mower`** bus. The balance
against ambience and rain is a bus trim, not a value in a controller — see
[weather, time and audio](weather-time-and-audio.md#audio).

### Rider and powered mower

Engine volume and pitch interpolate between idle and moving values based on horizontal-speed ratio. A small pitch increase is added during acceleration.

**Empty tank:** the target becomes `engine_off_volume_db` (-60) with the pitch
dropped to `idle_pitch * 0.8`, so it audibly dies rather than being muted, and
the player is `stop()`ped once it gets there. A refuel `play()`s it again from
silence. With Auto Refuel on the tank refills inside the same `consume()` call,
so the engine never actually stops and nothing pops.

### Push mower

Audio interpolates from effectively silent while stopped to a louder moving value. It does not use the same powered-idle profile — it is a reel mower, driven by its own wheels, which is the same fact that makes it burn no fuel.

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

- The mowing scene does not instantiate them.
- `MVP.gd` has its own three-scene lookup.
- Their movement basis, visual node assumptions, and speed multiplier differ.
- `Model.mower_scene_references` points to this older scene rather than the active scene set.

They should not be described as a fourth current mower type.

## Look settings — read the accessors, never the raw values

`GameSettings.invert_look_y()` — vertical inversion, default OFF. Any new look
code must go through it and through `look_sensitivity()` below.

## Mouse sensitivity — read `look_sensitivity()`

**Changed 2026-08-19.** All three canonical mower controllers now expose:

```gdscript
var mouse_sensitivity: float = 0.002     # authored base - do NOT read directly
func look_sensitivity() -> float:
    return mouse_sensitivity * GameSettings.mouse_sensitivity_scale()
```

The authored value stays the base feel; the player's Settings value is a
multiplier clamped to 0.1 - 3.0. Any new look code must use `look_sensitivity()`.

## Mouse capture — owned by `AppUI`

**Changed 2026-08-19.** No mower, menu or HUD writes `Input.mouse_mode`. See
[application layer](../application-layer.md).

- A mower `_ready()` sets the **context** to `CAPTURED`.
- The pause stack takes a **hold** while it is open, which forces `VISIBLE`.
- Resume releases the hold, and the context decides what to go back to — which is
  why the same pause menu is correct in the town (`VISIBLE`) and in mowing.
- `Model._input()` still handles `ui_accept` (ENTER), but routes it to
  `AppUI.toggle_mouse_capture()`, which is inert while a hold exists. Without
  that, confirming a pause-menu button with ENTER grabbed the cursor back.
  Note `ui_accept` also covers Space, which is bound to `jump` — a known quirk.

## FUEL — reworked 2026-08-19 (Milestone 9)

### Owner

| | |
|---|---|
| **Rules** | `MowerFuel` (`Game/App/mower_fuel.gd`, autoload, `ACAMowerFuel`) |
| **Level** | `model.mower_fuel`, 0-100, a **float** |
| **Gauge** | `MVP.mower_fuel_fraction()` -> `MowerFuel.fraction()` |

`model` is storage only, because that is what SaveService already persists. No
controller, HUD or scene may implement a burn rate — D-009.

### Powered vs manual

| Mower | `POWERED` | Fuel |
|---|---|---|
| `rider` | true | burns, stops when empty |
| `powered` (walk-behind) | true | burns, stops when empty |
| `push` | **false** | **none.** Manual reel mower — no `consume()`, no `fuel_empty` signal, never stops cutting |

Every controller exposes `is_powered()`; `MVP.current_mower_is_powered()`
forwards it so the UI never has to check a scene name. D-010.

### Tuning — three numbers, all in `mower_fuel.gd`

```gdscript
CAPACITY                  = 100.0
FULL_TANK_DRIVING_SECONDS = 480.0   # 8 real minutes of held throttle
IDLE_BURN_FRACTION        = 0.45    # -> 17.8 minutes idling only
```

Chosen against the Job System's own estimates (`PLACEHOLDER_CELLS_PER_REAL_MINUTE`):
a Small lawn is 4.6 minutes and a Large lawn 18.4, so **one tank covers a small
contract and a large one genuinely needs a refuel**. Asserted in `Fuel Test`,
not left as a comment.

### TIME based, never tick based

`consume(delta, throttle)` multiplies by `delta`. The old model added a fixed
amount to a counter **every physics tick**, and this project runs
`physics/common/physics_ticks_per_second = 576` — a full tank emptied in about
**four seconds** while driving. Do not reintroduce a counter.

`fuel_changed` is rate-limited by `SIGNAL_DEADBAND`; the level itself is never
deadbanded. (An earlier attempt guarded the burn with `is_equal_approx`, whose
tolerance at 100.0 is larger than one tick's burn, so the tank never emptied.)

### Empty

One state governs everything, in `_physics_process`:

- `get_input()` returns `Vector3.ZERO` -> **no propulsion**
- `handle_collision("fuel_empty")` instead of `"collided"` -> the grid never
  gets a collision -> **no cutting**
- the engine loop fades to `engine_off_volume_db` with a falling pitch, then
  `stop()`s -> the engine dies rather than being turned down
- the HUD gauge reads 0% and captions **FUEL CRITICAL**
- one "Out of fuel" toast

It is a recoverable state, not a broken one: `MowerFuel.refuel_full()` restarts
the audio, the wheels and the blades on the next frame.

### Refuel interface

```gdscript
MowerFuel.refuel(amount) -> float      # returns how much fitted
MowerFuel.refuel_full()  -> float
MowerFuel.dev_drain()                  # development / validation only
```

There is no gas can, station or purchase yet — R-019. This is the one call
whatever supplies fuel will make.

### Auto Refuel — DEVELOPMENT ONLY

`MowerFuel.set_auto_refuel(bool)` / `toggle_auto_refuel()` / `auto_refuel()`.

- **OFF (default)** — real rules; the tank reaches zero and stays there.
- **ON** — a tank that reaches empty is refilled **once**, immediately. It is
  not a fuel lock: the gauge still drains between top-ups, which is the point.

Exposed on the **F3 development HUD** (`AUTO REFUEL: ON/OFF`, `Refuel (F7)`,
`Empty tank`, and a live `%` readout) and on **F8**. The production Gameplay HUD
never offers it. The Trailer Capture director turns it on for a run.

### Save / load

`mower_fuel` is in the `mower` block of the save and round trips exactly. An
**empty** save loads empty — it does not reset to 100, which the old forced
refill made impossible. `mower_fuel_idle_counter` and `idle_fuel_use` are still
written because they are fields of the current save format, but nothing reads
them.

### Notifications

`GameplayHUD` raises `low_fuel_entered` once per crossing of 20%; `MowerFuel`
raises `emptied` once per transition. `gameplay_ui.gd` suppresses both when the
active mower is manual or Auto Refuel is on, and suppresses "Fuel low" when the
tank is already empty.
