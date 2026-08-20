# ACA Sky3D Environment

Reusable time-of-day and weather composition on top of a **vanilla** Sky3D
install. Profile-driven looks, layered precipitation, and quality levels that
switch real GPU mechanisms on and off.

Built for Godot **4.6**, tested against Sky3D **2.1-dev**.

---

## What it is

Sky3D gives you a beautiful sky and a sun that moves. It does not give you
*weather*, and it does not give you a way to say "evening, raining, on a laptop".
This package is that layer.

```
     your game state  (clock, save file, settings — none of it known here)
              |
       [ your integration layer ]
              |
       ACASky3DEnvironment
              |
   vanilla Sky3D  +  Godot Environment  +  ACAPrecipitationRig
```

**The adapter owns visual composition. Your game owns game state.** Nothing in
this package knows what a clock or a player is; it is told an hour and a weather
name and it makes the world look like that.

---

## Install

Order matters, because this package reads Sky3D's classes.

1. Install **vanilla Sky3D** into `res://addons/sky_3d/`
   (<https://github.com/TokisanGames/Sky3D>). Enable it in
   *Project ▸ Project Settings ▸ Plugins*.
2. Copy this folder to `res://addons/aca_sky3d_environment/`.
3. Restart the editor once, so the `class_name` globals register.

**Sky3D is never modified.** Everything here reads and writes its public
exported properties. If you find yourself wanting to edit a file under
`addons/sky_3d/`, the answer is a new key in `env_keys.gd` instead.

---

## Quick start

```gdscript
# A Sky3D node already in your scene, plus:
var rig := ACAPrecipitationRig.new()
add_child(rig)

var env := ACASky3DEnvironment.new()
add_child(env)
env.bind($Sky3D)                    # finds the Skydome child itself
env.set_precipitation_rig(rig)
env.set_tracking_target($Player/Camera3D)
env.set_quality(&"High")
env.apply_immediate(&"Clear", 12.0)

# then, from wherever your clock lives:
env.set_time_of_day(hour)           # 0.0 – 23.99; also moves the sun
env.set_weather(&"Rain")            # cross-fades
```

Run `demo/Environment Demo.tscn` for a working scene that loads none of your
game — it builds its own ground, camera and Sky3D at runtime.

---

## API

| Call | Does |
|---|---|
| `bind(sky, dome = null)` | Attach to a Sky3D node. Finds `Skydome` if omitted. |
| `set_time_of_day(hour)` | Present this hour. **Also writes `Sky3D.current_time`**, so the sun moves. |
| `set_weather(id)` | Cross-fade to a weather profile. Unknown ids warn and fall back. |
| `apply_immediate(id, hour)` | Set state *and* snap. For scene load and save restore. |
| `set_quality(id)` | `High` / `Medium` / `Low`. Switches mechanisms, not just numbers. |
| `set_tracking_target(node)` | What rain follows. Also infers `ground_reference`. |
| `set_ground_reference(y)` | Where ground level is. **See the warning below.** |
| `set_transition_speed(per_second)` | Exponential approach rate. |
| `set_presentation_override(layer)` | One extra `{scale:{}, set:{}}` layer for media tooling. |
| `clear_presentation_override()` | Remove it. |
| `compose(weather, hour)` | The composed key dictionary. Works unbound — no scene needed. |
| `current_visual_state()` | What is on screen right now, mid-transition included. |

### ⚠ `ground_reference`

`Environment.fog_height` is an **absolute world Y**. If your level is not built
near the origin, height fog measured from zero will saturate and your whole
screen will render flat white. That is not a fog that needs tuning down; it is a
fog measuring from the wrong place.

`set_tracking_target()` infers it from the target's height. Set it explicitly
whenever you know better.

---

## Profiles

The look is **data**, in `profiles/`:

| | |
|---|---|
| `profiles/time/` | `ACAEnvTimeProfile` — Morning, Day, Evening, Night |
| `profiles/weather/` | `ACAEnvWeatherProfile` — Clear, Foggy, Rain |
| `profiles/quality/` | `ACAEnvQualityProfile` — High, Medium, Low |

Edit them in the inspector. Add your own and they are picked up automatically —
the directories are scanned, not hard-coded. `tools/build_default_profiles.gd`
regenerates the shipped set if you need to get back to a known state (it
**overwrites**).

`anchors` on the adapter maps hours to time profiles. Those belong to *your*
world: measure them against your own Skydome's sun rather than copying ours.

### How composition works

Weather is applied to a time profile with three different operations, chosen per
property by what that property means:

- **Multiply** — energies and exposures. "A third less sun" is true at any hour.
- **Bias** — colours, as `lerp(hour_value, target, weight)`.
- **Set** — things the weather simply owns: cloud cover, fog range, rain.

The bias step is the important one. An earlier design multiplied *everything*,
which is elegant and wrong: multiplying a `Color` can only make it darker, never
bluer, so a storm at golden hour came out as a dim golden hour. With a bias
weight of 0.5, half the hour's hue survives — evening rain stays recognisably an
evening *and* genuinely reads blue-grey.

---

## Fog

Two independent mechanisms, deliberately doing different jobs.

| | Carries | Notes |
|---|---|---|
| **Godot Environment fog** (`env:`) | **Range** | `fog_depth_begin/end/curve` for near-sharp → far-gone, `fog_sky_affect` to keep the sky, height fog so silhouettes stand in it |
| **Sky3D aerial** (`dome:fog_*`) | **Colour** | Tinted by the same scattering model as the sky, so distance always agrees with it |
| **Volumetric** (`env:volumetric_fog_*`) | Real scattering | High only. Genuinely expensive. |

Sky3D's fog is a screen-space quad, and the line that would exclude the sky is
**commented out in the shipped `AtmFog.gdshader`**. Density high enough to hide a
treeline therefore also washes the sky — that is the "white wall" everyone hits.
Since Sky3D is read-only, the answer is to keep that quad *subtle* and let
Environment fog, which has `fog_sky_affect`, carry the range.

Fog colour is **derived**, not authored twice: the composed atmosphere tints are
mixed into the profile's `fog_tint`, so a fogged evening is warm and a fogged
night is blue for free, and both follow any change made to the sky above them.

---

## Precipitation

`ACAPrecipitationRig` builds three GPUParticles3D layers in code — no particle
scene, no texture, nothing to copy.

Distance is expressed in **alpha and count, never in size alone**. Scaling a near
emitter up for distance is exactly how rain ends up looking like scratches on a
film print. Every layer uses
`TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY`, so a streak always lies along the
direction it is travelling and wind tilts the rain for free.

`local_coords` is false on every layer, so moving the rig moves the *spawn
volume* and leaves airborne drops where they are; the volume is also pushed ahead
of the target by its own measured velocity, because a target at 30 u/s outruns
rain spawned directly overhead.

### No audio is included

This package bundles **no sound files**. Hand it a player you own:

```gdscript
rig.set_audio_player(my_rain_player)   # faded with intensity; you own the asset
```

Give it nothing and it stays silent.

---

## Quality

A level here **removes work**. It does not scale a number and hope.

| | High | Medium | Low |
|---|---|---|---|
| Depth + height fog | ✔ | ✔ | ✔ (no height term) |
| Sky3D aerial quad | ✔ | ✔ | ✖ |
| Volumetric fog | ✔ | ✖ | ✖ |
| Rain emitters | 3 + splash | 2 | 1 |
| Recomposition | 20 Hz | 16 Hz | 10 Hz |

If two levels ever measure the same on your hardware, one of them is a lie and
should be deleted rather than shipped.

---

## Licence

The package's own code and profiles follow the host project's licence. Sky3D is
separate and stays under its own — install it yourself; it is deliberately not
vendored here.
