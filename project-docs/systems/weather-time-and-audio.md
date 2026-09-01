# Weather, Time of Day, and Audio

Status: **Current** — source-verified 2026-08-29 (the regional-world and
Sky3D pass). Previous revision 2026-08-20.
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

## The eight skies

There used to be three: Clear, Foggy and Rain. Three is enough to have a
forecast and not enough to have WEATHER — a day was either perfect, in a
white-out, or being rained on, and there was nothing in between for the sky to
be on an ordinary afternoon.

| | | |
|---|---|---|
| **Clear** | the sun, and cloud masses rather than popcorn | `cumulus_size` 2.4 |
| **Partly Cloudy** | the everyday sky, and the most common one after Clear | |
| **Overcast** | soft and nearly shadowless, with the SKY doing the lighting. Structurally different from clear rather than merely darker: `sun_shadow_opacity` 0.20 against 0.90, ambient up by a third, contrast down | |
| **Mist** | the near field completely readable, the distance softened, ground-hugging height fog | begins at 78 units |
| **Foggy** | the same idea pushed to a silhouette-only distance, still playable at the machine | begins at 55 units |
| **Light Rain** | rain at 0.40 intensity. Wets the ground exactly as heavy rain does — it is lighter to LOOK at, not to stand in | |
| **Rain** | 1.0, with real cloud structure over it | |
| **Clearing** | the sky breaking up after rain, and the best-looking thing the weather does | |

**The three original names are unchanged**, so every save ever written by this
project still loads with a sky it recognises.

### Clearing is derived, not rolled

`Clearing` is not in `WEATHER_WEIGHTS`. It is what a bright block that
IMMEDIATELY FOLLOWS A WET ONE is called, and `_scheduled_preset()` derives it by
hashing the previous block as well as this one. That keeps the schedule pure — a
forecast is still the same function evaluated later — and costs one extra hash.
`Weather Test` walks four hundred blocks and asserts that every Clearing in them
followed rain.

### One question, asked in one place

`ACAWorldClock.is_rain(preset)` and `is_damp_air(preset)` are how everything
else asks. Before them, six files compared against the string `"Rain"`, and
adding a ninth sky would have meant finding all six.

### Quiet weather is the majority

Clear plus Partly Cloudy is more than half of every season. Variety in a
forecast comes from the occasional bad afternoon standing out, not from every
block being dramatic.

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
    `MVP._track_weather_to_camera()` sets it from the terrain's own height at
    the middle of the lawn, so it stays correct on ground that is not flat.

### Rain is the colour of the air it is falling through

Every streak is drawn UNSHADED, which means it ignores the scene's own light
entirely — so a bright base colour is the brightest thing on screen in exactly
the weather that is meant to be the darkest. That is the white-lines-glued-to-
the-camera look, and the first render of this rig had it.

Two things fixed it. The base colour is a dim blue-grey rather than white, and
`ACAPrecipitationRig.set_tint()` multiplies it by the composed
`env:fog_light_color` — the colour of distance at this hour in this weather,
which is exactly what water suspended in that air should be. An evening shower
is warm and a night one is blue, and neither is authored anywhere.

Per-drop opacity varies through `color_initial_ramp`, a gradient sampled once
per particle: every streak at exactly the same opacity is the second thing that
makes rain read as a texture rather than as weather.

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

**Morning moved from 07:00 to 08:12.** Seven o'clock is twenty-five minutes
after sunrise: the sun is barely off the horizon, Sky3D paints the whole dome
with its horizon tint, and the render came out as a pink scene in which the
grass could not be read. Eight-twelve is an hour and a half up, which is what
"morning" means — and it is when the player's working day starts. The 05:12 to
08:12 span is dawn, and it is a blend rather than a look.

## The place layer

`ACAEnvComposer` applies **two** host layers rather than one, and they have
different owners and different lifetimes:

| | Owner | Lifetime |
|---|---|---|
| `set_place_layer()` | the running game | set when a level loads, and it must survive a media capture |
| `set_presentation_override()` | media tooling | one shot, and asserted empty afterwards |

The place layer is how a region says how far you can see. It is scale-only, it
touches four fog keys and nothing else, and it is the mechanism behind
`ACARegionalContext.air_layer()`. **It is not a second weather system** — see
`project-docs/systems/territories-and-operations.md`.

## What the ground does about it

`ACAGroundWetness` (`Mowing Section/Property/aca_ground_wetness.gd`).

The mowing already behaved differently on wet ground: the catcher filled faster,
the dust stopped, the grip dropped. None of that was VISIBLE, which made a real
mechanic read as an invisible one.

It reads `ACAGroundConditions.current()` — the one authority, itself a pure
function of the one weather authority — and turns the answer into two shader
numbers. **No shader was edited and no uniform was added**: both lawn shaders
already carried `colour_bias` (wet grass is greener and cooler) and
`roughness_value` (water fills the micro-detail of a leaf, so wet grass catches
a sheen dry grass does not). Both are applied as a DELTA on the property's own
authored value, so a lawn the generator drew as parched still reads as parched
in the rain.

The authored roughness is remembered on the material the first time it is
touched, because reading the live value back and scaling it would compound — and
the sky can change eight times in a working day.

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
| `Weather Test` (106) | composition, the R-020 rule at four hours, fog is not a white wall, night is readable, the rig is layered and world-space, quality levels differ |
| `Environment Test` (28) | the package is portable, bundles no assets, composes unbound, ground reference, interruption safety |
| `Weather Matrix` | 32 rendered shots + fps per weather per hour |
| `Region Probe` | every region's hub, per condition, with a settled frame rate beside each |
| `Sky Probe` / `Sun Probe` | cloud-scale sweeps; measured sun altitude |

## Known limitations

1. `fx:wetness` is composed and still nothing consumes it. The wet-ground look
   is driven from `ACAGroundConditions` instead, which is the game's own
   authority and already carries the property's dryness; the package key is
   left as an advisory for a host that wants it.
2. The Town and the hubs have no rain PARTICLES. They do have a sun-elevation
   arc now — `sun_pitch_offset_degrees` per time profile, applied about the
   light's own right axis — because a hub at "evening" was otherwise a midday
   scene with warm light on it. Day's offset is zero, so the Business Town's
   authored daytime look is unchanged.
3. `addons/sky_3d/.../MoonRender.tscn` fails to load. Pre-existing, third-party,
   nothing loads it.
4. Snow is not implemented. `Weather/precipitation/snow*.tres` are dead files.
