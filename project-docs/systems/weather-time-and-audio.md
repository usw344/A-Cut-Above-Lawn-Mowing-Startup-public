# Weather, Time of Day, and Audio

Status: **Current.** Time and weather are now persistent application state and
survive every scene change. Verified by the Flow Test.

## Ownership

```
WorldClock  (autoload — game minutes, season, current weather preset)
    │
    ├──▶ ACAWorldClockTimeProvider ──▶ ACAJobManager   (offer arrival + expiry)
    │
    ├──▶ preset_manager ──▶ ACAWeatherVisualAdapter ──▶ Sky3D / Skydome   (mowing)
    │                   └──▶ Rain_Handler            ──▶ particles + audio
    │
    └──▶ town_screen.gd ──▶ ACATownLightAdapter ──▶ the town's own lights (town)
```

**`res://addons/sky_3d/` is READ-ONLY.** Every visual decision lives in
project-owned code under `Weather/Visual/`. Verified by hash against Backup 04:
44 addon files, none changed.

`WorldClock` owns **state**. `preset_manager` remains the project-facing
**adapter** over Sky3D and the Rain Handler and was not replaced. Scenes adapt to
the clock; they never own one.

## WorldClock — `Game/World/world_clock.gd`

See [application layer](../application-layer.md) for the full API.

- **One tuning value:** `game_minutes_per_real_second = 6.0`. Nothing else in the
  project may hard-code a time conversion.
- New world starts at **08:00, Spring, Clear**.
- `hour_of_day()` returns 0..23.99 — exactly the form Sky3D's `current_time` wants.
- `WEATHER_PRESETS = ["Clear", "Foggy", "Rain"]`. Adding one here requires adding
  it to `preset_manager.apply_weather_preset()`.
- `process_mode = PAUSABLE`, so pausing the tree stops game time deliberately.

## Preset Manager — `Weather/Preset Manager/preset_manager.gd`

Scene: `Weather/Preset Manager/Preset Manager.tscn`, containing `Sky3D`
(`Skydome`, `TimeOfDay`) and the `Rain Handler`. Instanced in the mowing scene as
`PresetManager (Sky3D)`.

**PUBLIC API**
```
set_time_of_day_normalized(hours 0..23.99)
smooth_set_time_of_day(target_hours, duration = -1)
apply_time_of_day_preset("Day" | "Evening" | "Night")   # 12.00 / 17.5 / 22.00
apply_weather_preset("Clear" | "Foggy" | "Rain")
set_audio_player(AudioStreamPlayer)      # for rain ducking
get_and_set_mower_global_position(pos)   # rain emitter follows the mower
```
State it exposes: `current_time_of_day`, `current_time_preset`,
`current_weather_preset`, `current_quality_preset`.

**Reworked 2026-08-19 (Milestone 7).** The preset manager no longer holds the
look. It routes: rain on/off, the clock, and the scene wiring. The look lives in
`ACAWeatherVisualAdapter`, which it creates as a child in `_ready()`.

New/changed API:
```
apply_world_state_immediate(weather, hour)   # scene load + save restore, no ease
follow_world_clock: bool = true              # export; pushes WorldClock into Sky3D
TIME_PRESET_HOURS = {Morning 7.0, Day 12.0, Evening 16.3, Night 22.0}
visual: ACAWeatherVisualAdapter               # the look adapter
```

`follow_world_clock` also sets `sky3d.enable_game_time = false`. **Sky3D ships
its own clock** (`minutes_per_day = 15`, a full day every 15 real minutes) which
drifted against WorldClock's four-minute day, so the sky and the HUD readout
disagreed. One clock only.

## ACAWeatherVisualAdapter — `Weather/Visual/weather_visual_adapter.gd`

**STATUS:** Authoritative for the mowing look. Added 2026-08-19.

**PUBLIC API**
```
bind(sky3d_node, skydome_node)      is_bound() -> bool
set_state(weather, hour)            # eases towards it
apply_immediate(weather, hour)      # snaps - scene load / save restore
compose(weather, hour) -> Dictionary        # inspectable without a scene
time_values(hour) -> Dictionary             # the pure time look
current_weather() / current_hour() / time_profile_at(hour)
blend_speed = 1.2   update_interval = 0.05   (both @export)
```

**COMPOSITION — the whole design.** A look is a TIME profile composed with a
WEATHER layer:

1. The hour picks a point on `TIME_ANCHORS` and the two neighbouring profiles
   are smoothstep-blended. Four profiles: **Night / Morning / Day / Evening**.
2. The weather layer applies in two parts:
   - `scale` **multiplies** the time value → evening rain is still evening
   - `set` **replaces** it → clouds and fog are weather's job

Twelve combinations from seven small tables, not twelve hand-written presets.

Keys are `"sky:<property>"` (the Sky3D WorldEnvironment) or `"dome:<property>"`
(its Skydome child).

**CLOUD SHAPE IS A COMPOSED KEY — `dome:clouds_cumulus_size`.**
Added 2026-08-19 (Milestone 10), and the reason "evening rain has no clouds" was
a real bug rather than a camera angle. Sky3D samples its cumulus noise at
`intersection_point * clouds_cumulus_size * 0.0212`; at the addon's shipped 0.5
the dominant octave barely changes across the whole dome, so the layer renders
as a smooth featureless wash. Low values give big shapes, high values fine
stipple. Measured with `Dev tools/Validation/Sky Probe.tscn`:

| Weather | `clouds_cumulus_size` | Reads as |
|---|---:|---|
| Clear | 5.0 | scattered fair-weather cumulus |
| Foggy | 9.0 | dense mackerel overcast |
| Rain | 2.0 | broken storm masses with gaps of sky |

Rain's `clouds_cumulus_coverage` also came down from 0.90 (a gapless sheet) to
0.62, and its `atm_day_tint` / `atm_horizon_light_tint` scales from 0.80 / 0.85
to 0.66 / 0.72, because with the clouds finally visible a late-afternoon storm
was still reading as a warm sunset haze.

**TIME_ANCHORS ARE MEASURED, NOT GUESSED.**
`Dev tools/Validation/Sun Probe.tscn` prints Sky3D's sun altitude per half hour
for this Skydome (realistic mode, latitude 16): **the sun is up from about 06:35
to 17:05**, highest at 12:00. The first attempt put "Evening" at 18:40 and
rendered a black screen with stars. If the Skydome's latitude, date or celestial
mode ever change, re-run the probe and move the anchors.

**NO TWEENS, deliberately.** One per-tick exponential approach towards the
composed target drives every property. Time drifts continuously, so a
fixed-duration tween would restart forever; two overlapping weather changes
cannot leave a stale tween writing old values, because there is nothing to leave
behind; and convergence is guaranteed from any state, including a
mid-transition load.

**STEP KEYS.** `Sky3D.set_ambient_energy` / `set_sky_contribution` /
`set_night_ambient_min` each start their *own* internal Tween on the
Environment. Driving them per frame would spawn a tween per frame. They are
written only when the target has moved by more than `STEP_DEADBAND` (0.03).
Bools are stepped too. **Anything added to the key set that calls
`update_day_night()` must go in `STEP_KEYS`.**

Readability rules, asserted in `Weather Test` rather than trusted to taste:
night is never pitch black (exposure ≥ 1.0, moon ≥ 0.5), day never blows out
(exposure ≤ 1.2), every weather keeps ambient fill ≥ 0.9, and Foggy keeps
`fog_start > 0` so the near field stays clear instead of becoming a white wall.

### The presentation override — media tooling, empty in gameplay

**Added 2026-08-19 (Milestone 12).**

```gdscript
set_presentation_override(layer: Dictionary)   # same `scale` / `set` shape as WEATHER_LAYERS
clear_presentation_override()
presentation_override() -> Dictionary
has_presentation_override() -> bool
```

One extra layer, composed **last** in `compose()` — after the time profile and
after the weather layer. It is EMPTY in normal gameplay, it eases in and out
through the same per-tick approach as everything else, and `Trailer Test`
asserts both that it is empty by default and that clearing it restores the
shipped look exactly, key for key.

It exists for one shot. `ACATrailerWeatherAdapter` uses it to bias the storm
blue-grey for the trailer's weather hero beat, which is the R-020 argument
deliberately taken out of the shipped tables:

- **the colours have to be `set`, not `scale`.** Scaling a `Color` multiplies
  every channel by the same factor, so it can only make a tint DARKER, never
  bluer. The shipped Rain layer already scales those keys as far as scaling can
  take them, and the result is still a dim warm sky.
- **exposure and ambient go UP as the tint goes cold.** The first cut of that
  look read as night with the mower lost in it. Cold and dark is a different
  picture from cold and moody, and only one of them is usable.

Normal Rain is unchanged — confirmed against the Weather Matrix.

## ACATownLightAdapter — `Weather/Visual/town_light_adapter.gd`

**STATUS:** Current. Added 2026-08-19; **closes R-013.**

Bound by `town_screen.gd` (`light_from_world_clock`, default on). Same
composition rule and the same `TIME_ANCHORS` as the sky adapter, over a much
smaller key set.

It changes **light only**: the two directional lights' colour/energy, a yaw
rotation applied *around* the authored sun basis, the `ProceduralSkyMaterial`
gradient, ambient energy, tonemap exposure and distance fog. It does **not**
replace `BusinessTown.tscn`, put Sky3D in the town, or touch SSAO, colour
grading, geometry or the camera rig. Every resource it writes is `duplicate()`d
first, so the authored sub-resources in the scene file are never mutated.

**The `Day` profile is the town exactly as authored**, so Day looks identical to
how it looked before the adapter existed. The other three are departures from
that reference.

Town fog densities are **much** lower than the mowing scene's (0.0045 / 0.0022
vs 0.0042 / 0.0027) because the town camera sits ~60 units back — the first
attempt used the mowing values and rendered a solid white wall.

Set `light_from_world_clock = false` on the Town Screen to revert to authored
lighting with no other change.

## How scenes reconnect

`MVP._setup_job_runtime()` on load:

```gdscript
preset_manager_object.apply_world_state_immediate(
    WorldClock.weather_preset(), WorldClock.hour_of_day())
WorldClock.weather_changed.connect(_on_world_weather_changed)
```

Immediate, not eased: the first frame of a new scene must already look right
rather than fading in from whatever the previous scene looked like.

Weather hotkeys (`7`/`8`/`9`) and the legacy HUD's weather buttons now write to
`WorldClock`, **not** to the scene. That is what makes the choice survive the
next transition.

Time-of-day hotkeys are now **`1`/`2`/`3`/`4`** = morning / day / evening /
night, and they write to `WorldClock.advance_to_hour()` like the weather keys
do. Writing the scene only would be undone by the next world-clock tick and
would not survive a transition. `advance_to_hour()` is **forward only** — every
consumer relies on the clock never running backwards, so a time already passed
lands on tomorrow.

## Rain Handler — `Weather/Handlers/rain_handler.gd`

`class_name Rain_Handler`. Owns near/far GPU rain particles, follows the mower,
fades rain in/out, and ducks the ambience stream (relatively — see the audio
section). `preset_manager._ready()` calls
`stop_rain_instant()` so a scene never starts wet by accident.

Authored precipitation resources exist for snow and heavy rain
(`Weather/precipitation/*.tres`, `Weather/particles/snow_particles.tscn`). They
are **not yet reachable** from `apply_weather_preset()` — active design, not legacy.

`near_rain_max_ratio`, `far_rain_max_ratio` and the emitters' own scale are the
knobs `ACATrailerWeatherAdapter` turns up for a capture, because rain vanishes on
compressed video. It saves and restores every one of them. **`MVP._physics_process`
hands the mower's position to this handler every physics tick**, so the rain
column follows the mower and nothing needs to move it — what a parked camera
fifty units away needs instead is a WIDER column.

## Town lighting — RESOLVED 2026-08-19

Was R-013. `BusinessTown.tscn` still uses its own authored `WorldEnvironment` +
`Sun` + `FillLight` and still shows day/clock/weather as text — but it now also
**re-lights from `WorldClock`** through `ACATownLightAdapter` (above), so time of
day and weather are visible on both screens.

What the town still does not have: rain particles, and a moving sun elevation
(only a yaw sweep around the authored basis). Both were judged out of scope for
a lighting pass.

## Reviewing the look — `Weather Matrix.tscn` and `Sky Probe.tscn`

`Sky Probe.tscn` renders **just the sky** — the Preset Manager, a camera tilted
up, one PNG per weather/hour, plus a sweep of any cloud parameter. Use it when
the question is "what does this value look like"; it answers in one run rather
than one full trailer per guess. It is what found the `clouds_cumulus_size` bug
above.


Weather is not tuned from numbers. `Dev tools/Validation/Weather Matrix.tscn`
renders the full **4 times x 3 weathers** matrix in the real mowing scene plus
six representative town shots, from a fixed camera pose so two runs are
comparable, and logs frame rate per combination. Look at the images.

Measured 2026-08-19 on the working machine: **115-131 fps across all twelve
combinations**, no weather-specific cost.

## Audio

**Reworked 2026-08-19 (Milestone 9). R-014 is closed.**

### The buses — `res://default_bus_layout.tres`

```
Master
  |- Mower       every mower's AudioStreamPlayer3D
  |- Ambience    the mowing scene's ambience bed
  |- Weather     rain, and any future precipitation audio
  +- UI          reserved; nothing plays on it yet
```

Routing is set on the `AudioStreamPlayer` nodes **in their own scenes**, not in
code. Adding a sound means picking its bus in the scene, never adding a volume
rule somewhere.

| Source | Node | Bus |
|---|---|---|
| Ambience | `AudioStreamPlayer` on the mowing scene root, `Ambience Sound.wav`, authored **-16.855 dB** | `Ambience` |
| Mower engine | `AudioStreamPlayer3D` on each mower, pitch/volume lerped with speed | `Mower` |
| Rain | `AudioStreamPlayer` on the Rain Handler | `Weather` |

### The mix — `Game/App/audio_mix.gd` (`ACAAudioMix`)

`AudioServer` has exactly ONE volume per bus and `GameSettings` writes it from
the player's slider, so the authored balance cannot live in the layout resource
— it would be wiped by the first apply. The layout ships every bus at 0 dB and
`ACAAudioMix.TRIM_DB` is applied **together with** the slider value.

```
Master 0.0    Mower +14.0    Ambience +5.0    Weather +10.0    UI 0.0
```

| Setting | Bus |
|---|---|
| `master_volume` | Master |
| `mower_volume` | Mower |
| `ambience_volume` | **Ambience AND Weather** |

No separate Weather slider: there is no case for turning the rain down but not
the birds. D-011.

### The trims were MEASURED, not chosen

`Dev tools/Validation/Audio Mix Probe.tscn` runs the real mowing scene, puts the
real rider through Clear / Foggy / Rain at idle and while mowing, and reports
the peak level each bus reaches. Measured 2026-08-19 at the default sliders:

| State | Mower | Ambience | Weather | Master |
|---|---|---|---|---|
| clear / idle | -20.2 | -16.8 | — | -16.8 |
| clear / mowing | **-11.3** | -19.5 | — | -12.3 |
| foggy / mowing | -12.5 | -22.4 | — | -13.7 |
| rain / idle | -19.2 | -29.4 | -16.5 | -15.3 |
| rain / mowing | **-12.1** | -27.3 | **-15.5** | -11.8 |

dBFS. The engine is the loudest element in every weather; heavy rain sits about
**3-4 dB under it**; the ambience bed is under both. Before the trims everything
peaked around -25 dBFS with nothing on top of anything.

**Re-run the probe after changing any source level or trim.** Do not tune these
numbers by eye.

### Rules

- Source levels are authored **once**. Nothing changes a mower's volume because
  of the weather, and nothing may start doing so.
- The Rain Handler's ambience duck is **relative**: `ambience_base_db` is
  captured when the player is handed over, and rain applies
  `ambience_rain_duck_db` (-7) on top of it. It used to write *absolute*
  decibels (`ambience_clear_db = 0.0`), so the first Rain -> Clear transition
  raised the -16.855 dB ambience by nearly 17 dB and left it there. The probe
  asserts the round trip returns to the authored level exactly.
- `stop_rain_instant()` also resets the ambience level, so a scene loading in
  Clear can never start ducked.
