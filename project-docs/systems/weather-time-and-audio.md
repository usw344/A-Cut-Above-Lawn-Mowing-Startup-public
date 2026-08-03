# Weather, Time of Day, and Audio

Status: Current playable runtime  
Canonical weather: Preset Manager plus Rain Handler  
Canonical sky: Sky3D

## Scene composition

`Weather/Preset Manager/Preset Manager.tscn` contains:

- `PresetManager` root with `preset_manager.gd`.
- `Sky3D` `WorldEnvironment`.
  - Sun light.
  - Moon light.
  - Skydome.
  - TimeOfDay.
- Instanced `Rain Handler`.

The scene is instantiated by `Minimum Viable Game.tscn`.

## Preset Manager

`preset_manager.gd` tracks:

- Current normalized time.
- Current time preset.
- Current weather preset.
- Current quality label.
- Time and weather tweens.

Its exported `custom_gridmap_path` is currently not required by the active behavior. Mower position is passed in explicitly through the MVP.

## Time of day

`set_time_of_day_normalized()` expects a value from 0.0 through 23.99 and assigns it to Sky3D’s `current_time`.

Preset targets:

| Preset | Target time |
|---|---:|
| Day | 12.00 |
| Evening | 17.5 |
| Night | 22.00 |

Preset changes use a sine eased tween. The default transition duration is 2.5 seconds.

The MVP applies Day during startup.

## Weather presets

### Clear

- Stops rain.
- Restores brighter exposure and sun energy.
- Uses light atmospheric haze.
- Restores longer fog distance.
- Uses moderate cloud coverage.

### Foggy

- Stops rain.
- Flattens and slightly darkens lighting.
- Increases fog density.
- Reduces fog end distance.
- Increases cloud coverage.

### Rain

- Starts rain.
- Darkens camera, sky, and direct sunlight.
- Increases atmosphere darkness and fog.
- Increases flat and cumulus cloud coverage.
- Uses darker cloud colours.
- Crossfades rain and ambience audio.

Sky changes use a parallel two-second tween by default. Starting a new weather transition kills the previous sky tween.

## Rain Handler

`Weather/Handlers/Rain Handler.tscn` contains:

- Near Rain particle scene.
- Far Rain particle scene.
- Rain AudioStreamPlayer.

`rain_handler.gd`:

- Starts with both emitters disabled.
- Uses global particle coordinates.
- Follows the active mower with a configurable offset.
- Tweens `amount_ratio` for smooth rain start/stop.
- Disables emitting after a stop transition completes.
- Supports immediate start/stop for initialization.

Near and far rain are scaled/configured differently to cover the player’s local and surrounding view.

## Mower following

Every MVP physics frame:

```text
MVP
  -> PresetManager.get_and_set_mower_global_position()
  -> RainHandler.set_mower_global_position()
```

The handler sets its global position to the mower position plus `rain_offset`.

When the MVP replaces the mower, its `current_mower` reference changes, so subsequent frames automatically track the selected mower.

## Audio

### Ambient sound

`Minimum Viable Game.tscn` owns an `AudioStreamPlayer` using:

```text
Assets/Sounds/Ambience Sound.wav
```

The MVP starts it and gives its node reference to the Preset Manager/Rain Handler.

### Rain sound

The Rain Handler owns:

```text
Assets/Sounds/rain-sound-188158.wav
```

Rain transitions tween:

- Rain audio toward a target rain volume.
- Base ambience toward a quieter rain volume.

Stopping rain reverses the crossfade.

### Mower sounds

Mower audio is owned by each canonical mower scene:

- Rider and powered mower use `Powered Lawn Mower SFX.wav`.
- Push mower uses `Push Lawn Mower SFX.wav`.

Mower controllers alter volume and pitch from horizontal speed.

No separate audio manager, music system, or custom audio-bus configuration was found.

## Sky3D

Sky3D 2.0 is installed, enabled, and directly used by the canonical weather scene. It supplies:

- World environment integration.
- Skydome material.
- Sun and moon lighting.
- Time-of-day behavior.
- Atmospheric fog.
- Flat and cumulus cloud properties.

The older proprietary GodotSky reference in the root README is historical and stale. GodotSky is neither active nor planned.

## Removed GodotWeatherSystem

The following resources are deprecated remnants:

- `Weather/precipitation/rain.tres`
- `Weather/precipitation/heavy_rain.tres`
- `Weather/precipitation/snow.tres`
- `Weather/precipitation/heavy_snow.tres`

They reference missing `addons/GodotWeatherSystem` particle paths and a missing C# `PrecipitationResource`.

The addon is not expected to return. These resources are cleanup debt, not part of the canonical weather system.

## Future direction

The current weather implementation was assembled quickly for the MVP. Future work should formalize and reorganize it without replacing its overall direction.

Areas to clarify during that work:

- Resource-based preset definitions versus hard-coded properties.
- Ownership of current weather/time in the global model or a dedicated manager.
- Save/load representation.
- Audio levels and bus structure.
- Quality presets.
- Snow support, if retained.
- Deterministic or simulated weather progression.
