# Weather, Time of Day, and Audio

Status: **Current** — source-verified 2026-08-20 (session 7, Milestone A).
Canonical owner: `WorldClock` (state) → `preset_manager` (API) →
`ACASky3DEnvironment` (look).
Important paths:

- `Game/World/world_clock.gd`
- `Weather/Preset Manager/preset_manager.gd`
- `Weather/Visual/weather_visual_adapter.gd`
- `Weather/Handlers/rain_handler.gd`
- `addons/aca_sky3d_environment/`
- `addons/sky_3d/` — **third party, read-only**

## Purpose

One clock and one weather state for the whole application, and a look composed
from them that is attractive at any hour, in any weather, on modest hardware.

## Ownership

```
WorldClock            authoritative time, season, weather STATE (a name)
      |
preset_manager        the project-facing API scenes already call
      |
ACAWeatherVisualAdapter   A Cut Above integration. Thin: anchors, binding,
      |                   quality mapping, ground reference
ACASky3DEnvironment       REUSABLE PACKAGE. Composition and writing
      |
vanilla Sky3D  +  Godot Environment  +  ACAPrecipitationRig
```

| Concern | Owner |
|---|---|
| What time it is, what the weather IS | `WorldClock` |
| Which hour maps to which time profile | `ACAWeatherVisualAdapter.TIME_ANCHORS` |
| What a look CONTAINS | profile resources under `addons/aca_sky3d_environment/profiles/` |
| How a look is COMPOSED and written | `ACASky3DEnvironment` |
| Rain particles | `ACAPrecipitationRig` (built in code) |
| Rain audio and the ambience duck | `Rain_Handler` — **project-owned, not in the addon** |
| The Town's lighting | `ACATownLightAdapter` (a separate, simpler adapter) |

## The reusable package

`addons/aca_sky3d_environment/` knows nothing about A Cut Above. It could be
copied into any Godot 4.6 project that has a vanilla Sky3D. `Environment Test`
enforces that mechanically: it greps the package for this project's paths and
class names and fails if any appear.

Its own documentation is `addons/aca_sky3d_environment/README.md`.

### Composition

Weather is applied to a time profile with three operations, chosen per property:

| Operation | Used for | Why |
|---|---|---|
| **Multiply** | energies, exposures | "a third less sun" is true at any hour |
| **Bias** (`lerp` toward a target, with a weight) | colours | multiplying a `Color` can only darken it, never make it bluer |
| **Set** | cloud cover, fog range, rain | the weather owns these outright; they are not properties of four o'clock |

The bias step resolves **R-020**. The previous rule multiplied everything, so a
storm at golden hour came out as a dim golden hour. At a bias weight of 0.5 half
the hour's hue survives — evening rain stays recognisably an evening *and* reads
blue-grey. `Weather Test` asserts both halves at four hours.

### Fog — two mechanisms, deliberately

| | Carries | Notes |
|---|---|---|
| Godot `Environment` fog (`env:`) | **range** | `fog_depth_begin/end/curve`, `fog_sky_affect`, height fog |
| Sky3D aerial (`dome:fog_*`) | **colour** | tinted by the same scattering model as the sky |
| Volumetric (`env:volumetric_fog_*`) | real scattering | High quality only. Expensive |

Sky3D's fog is a screen-space quad, and the line that would exclude the sky is
**commented out in the shipped `AtmFog.gdshader`**. Density high enough to hide a
treeline therefore also washes the sky — that is the white wall. Sky3D is
read-only, so the quad is kept subtle and Environment fog, which has
`fog_sky_affect`, carries the range.

Fog colour is **derived**, not authored twice: the composed atmosphere tints are
mixed into the profile's `fog_tint`, so a fogged evening is warm and a fogged
night is blue for free.

!!! warning "`fog_height` is an absolute world Y"
    The mowing lawn is authored at about **y = -508**. With the fog layer
    measured from the origin, every surface in that scene is five hundred units
    "below" it, the height term saturates, and the whole frame renders flat
    white. `ACASky3DEnvironment.ground_reference` fixes the measurement;
    `MVP._track_weather_to_camera()` sets it from the grid's own `Mowing Area`.

### Precipitation

Three `GPUParticles3D` layers built in code — no particle scene, no texture.

- Distance is expressed in **alpha and count, never size alone**. The old
  `Far Rain` was the near emitter scaled by **24**, over a `RibbonTrailMesh`
  0.2 units wide: a 4.8-unit white ribbon per drop, which is the curtain of rods
  in the pre-session-7 frames.
- `TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY` points each streak down its own
  velocity, so wind tilts the rain for free.
- `local_coords = false`, so moving the rig moves the SPAWN VOLUME and leaves
  airborne drops where they are; the volume leads the target by its own measured
  velocity, because a mower at 30 u/s outruns rain spawned overhead.

### Quality

A level REMOVES WORK. If two levels measure the same, one is a lie.

| | High | Medium | Low |
|---|---|---|---|
| Depth + height fog | ✔ | ✔ | ✔ (no height term) |
| Sky3D aerial quad | ✔ | ✔ | ✖ |
| Volumetric fog | ✔ | ✖ | ✖ |
| Rain emitters | 3 + splash | 2 | 1 |
| Recomposition | 20 Hz | 16 Hz | 10 Hz |

Driven from `GameSettings.graphics_quality()` through
`ACAWeatherVisualAdapter.QUALITY_FOR_SETTING`, and re-applied live when the
player changes the setting.

## Public integration points

| Call | Effect |
|---|---|
| `WorldClock.set_weather(preset)` | changes the world's weather STATE |
| `WorldClock.advance_to_hour(h)` | forward-only clock jump |
| `preset_manager.apply_weather_preset(name)` | the project-facing weather API |
| `preset_manager.apply_world_state_immediate(w, h)` | scene load / save restore, no transition |
| `preset_manager.set_weather_tracking_target(node)` | what rain follows |
| `preset_manager.set_weather_ground_reference(y)` | where ground level is, for height fog |
| `visual.set_presentation_override(layer)` | media tooling only; empty in gameplay |

## No tweens

Every value eases through ONE per-tick exponential approach. There is
deliberately no `Tween` in the adapter:

- time drifts continuously, so a fixed-duration tween would restart forever;
- overlapping weather changes cannot strand a stale tween writing old values;
- convergence is guaranteed from any state, including a mid-transition load.

`apply_immediate()` snaps instead.

## Time anchors

`ACAWeatherVisualAdapter.TIME_ANCHORS` maps hours to profiles. **Measured, not
guessed**: `Dev tools/Validation/Sun Probe.tscn` prints Sky3D's sun altitude per
half hour for this Skydome (realistic mode, latitude 16) — the sun is up from
about 06:35 to 17:05. Anchors outside that window put "Evening" after dark. If
the Skydome's latitude, date or celestial mode change, re-run the probe (R-017).

`ACATownLightAdapter` reads the same constant, so the two screens can never
disagree about when it is morning.

## Audio

The rain stream plays on the **Weather** bus, ambience on **Ambience** (see
`Game/App/audio_mix.gd`). Balance is a BUS TRIM, not a value in the rain handler.
The ambience duck is **relative** to the level the player was authored at,
captured once on hand-over.

**The addon bundles no audio.** `Assets/Sounds/*.wav` have unresolved
attribution (R-016) and must not be shipped inside anything redistributable.
`ACAPrecipitationRig.set_audio_player()` accepts a player the host owns.

## Persistence

`WorldClock.to_save_dict()` — minutes, season, weather name, running, time
scale. The look is **not** saved: it is recomposed from state, so it can never
disagree with the clock. On load, `apply_world_state_immediate()` snaps.

## Validation

| Suite | Guarantees |
|---|---|
| `Weather Test` (75) | composition, the R-020 rule at four hours, fog is not a white wall, night is readable, the rig is layered and world-space, quality levels differ |
| `Environment Test` (28) | the package is portable, bundles no assets, composes unbound, ground reference, interruption safety |
| `Weather Matrix` | 12 rendered shots + fps per weather per hour |
| `Sky Probe` / `Sun Probe` | cloud-scale sweeps; measured sun altitude |

## Known limitations

1. `fx:wetness` is composed but nothing consumes it. A wet-ground look would
   need the terrain and grass materials to accept a global parameter (A15,
   deferred).
2. The Town has no rain particles and no sun-elevation arc — lighting only.
3. `addons/sky_3d/.../MoonRender.tscn` fails to load. Pre-existing, third-party,
   nothing loads it.
4. Snow is not implemented. `Weather/precipitation/snow*.tres` are dead files.
