@tool
class_name ACAEnvTimeProfile
extends Resource
## ONE TIME OF DAY, as an editable resource.
##
## A time profile is the world with NO weather on it: how bright it is, what
## colour the light is, how far you can see. Weather is composed on top by
## `ACAEnvWeatherProfile`, and the two together make the look.
##
## Every profile must carry EVERY field, because two neighbouring profiles are
## blended continuously — a missing value would pop. They are plain exports
## rather than a dictionary precisely so the editor enforces that.

## Stable identifier. `Morning`, `Day`, `Evening`, `Night` in the shipped set.
@export var id: StringName = &"Day"

@export_group("Exposure")
## Scales light BEFORE the tonemapper (softer highlights).
@export_range(0.0, 4.0, 0.005) var camera_exposure: float = 1.0
## Scales light AFTER the tonemapper (hotter highlights).
@export_range(0.0, 4.0, 0.005) var tonemap_exposure: float = 1.0
## Light energy coming out of the sky shader itself.
@export_range(0.0, 4.0, 0.005) var skydome_energy: float = 1.0

@export_group("Sun and moon")
@export var sun_light_color: Color = Color(1.0, 0.98, 0.94)
## What the sun fades TOWARDS as it approaches the horizon. Sky3D blends
## between this and `sun_light_color` by sun altitude, so this is the value
## that actually paints low-sun scenes — and the one that turns an evening
## sepia if it is pushed too far.
@export var sun_horizon_light_color: Color = Color(0.98, 0.60, 0.36)
@export_range(0.0, 8.0, 0.005) var moon_energy: float = 0.3
@export var moon_light_color: Color = Color(0.62, 0.76, 0.98)
@export_range(0.0, 100.0, 0.5) var sun_disk_intensity: float = 30.0

@export_group("Ambient")
@export_range(0.0, 4.0, 0.005) var ambient_energy: float = 1.0
@export_range(0.0, 1.0, 0.005) var sky_contribution: float = 1.0
## Sky3D drops `ambient_light_sky_contribution` to this after dark. LOWER means
## MORE neutral fill, i.e. a more readable night.
@export_range(0.0, 1.0, 0.005) var night_ambient_min: float = 0.7

@export_group("Atmosphere")
@export_range(0.0, 1.0, 0.005) var atm_darkness: float = 0.48
@export_range(0.0, 60.0, 0.1) var atm_sun_intensity: float = 18.0
@export var atm_day_tint: Color = Color(0.81, 0.91, 1.0)
@export var atm_horizon_light_tint: Color = Color(0.98, 0.68, 0.50)
@export var atm_night_tint: Color = Color(0.22, 0.28, 0.40)
@export_range(0.0, 1.0, 0.001) var atm_mie: float = 0.07
## The colour of the sky's own lower hemisphere.
@export var ground_color: Color = Color(0.24, 0.25, 0.23)

@export_group("Aerial perspective")
## Sky3D's screen-space scattering quad. Kept LOW at every hour: it cannot
## exclude the sky, so it tints distance rather than carrying range. See the
## FOG note in `env_keys.gd`.
@export_exp_easing() var aerial_density: float = 0.00075
@export_range(0.0, 5000.0, 1.0) var aerial_start: float = 0.0
@export_range(0.0, 5000.0, 1.0) var aerial_end: float = 1100.0
@export_exp_easing() var aerial_rayleigh_depth: float = 0.115
@export_exp_easing() var aerial_mie_depth: float = 0.00012
## How fast the quad fades as you look UP. Higher keeps more sky clean.
@export_range(0.0, 12.0, 0.05) var aerial_falloff: float = 3.0

@export_group("Cloud lighting")
## Only the LIGHTING of the clouds is a time-of-day matter. Their shape, cover
## and speed belong to the weather.
@export var cloud_day_color: Color = Color(0.86, 0.90, 1.00)
@export var cloud_horizon_color: Color = Color(0.98, 0.55, 0.28)
@export var cloud_night_color: Color = Color(0.17, 0.20, 0.28)

@export_group("Depth fog tint")
## The base colour distance fades towards at this hour, before weather biases
## it. Composition also mixes the atmosphere tints into this, so an evening fog
## is warm and a night fog is blue without either being authored twice.
@export var fog_tint: Color = Color(0.62, 0.68, 0.78)
## Energy of the depth fog's light. Lifts a night fog off black.
@export_range(0.0, 4.0, 0.005) var fog_light_energy: float = 1.0


## Flatten to the composed key space. Blending happens on these dictionaries,
## so every profile produces exactly the same keys.
func to_values() -> Dictionary:
	return {
		"sky:camera_exposure": camera_exposure,
		"sky:tonemap_exposure": tonemap_exposure,
		"sky:skydome_energy": skydome_energy,
		"sky:moon_energy": moon_energy,
		"sky:ambient_energy": ambient_energy,
		"sky:sky_contribution": sky_contribution,
		"sky:night_ambient_min": night_ambient_min,
		"dome:sun_light_color": sun_light_color,
		"dome:sun_horizon_light_color": sun_horizon_light_color,
		"dome:moon_light_color": moon_light_color,
		"dome:sun_disk_intensity": sun_disk_intensity,
		"dome:atm_darkness": atm_darkness,
		"dome:atm_sun_intensity": atm_sun_intensity,
		"dome:atm_day_tint": atm_day_tint,
		"dome:atm_horizon_light_tint": atm_horizon_light_tint,
		"dome:atm_night_tint": atm_night_tint,
		"dome:atm_mie": atm_mie,
		"dome:ground_color": ground_color,
		"dome:fog_density": aerial_density,
		"dome:fog_start": aerial_start,
		"dome:fog_end": aerial_end,
		"dome:fog_rayleigh_depth": aerial_rayleigh_depth,
		"dome:fog_mie_depth": aerial_mie_depth,
		"dome:fog_falloff": aerial_falloff,
		"dome:clouds_cumulus_day_color": cloud_day_color,
		"dome:clouds_cumulus_horizon_light_color": cloud_horizon_color,
		"dome:clouds_cumulus_night_color": cloud_night_color,
		"env:fog_light_color": fog_tint,
		"env:fog_light_energy": fog_light_energy,
	}
