@tool
class_name ACAEnvWeatherProfile
extends Resource
## ONE WEATHER, composed ON TOP of whatever time of day it is.
##
## ---------------------------------------------------------------------------
## THE COMPOSITION RULE, AND WHY IT IS NOT ONE OPERATION
## ---------------------------------------------------------------------------
##
## An earlier version of this system used a single rule — weather always
## MULTIPLIES the time value — because one rule is elegant. It produced warm
## sepia storms, and no amount of tuning fixed it, because multiplying a Color
## can only make it DARKER. It can never make it bluer. A storm at golden hour
## came out as a dim golden hour.
##
## So the operation is chosen PER PROPERTY, by what that property means:
##
##   MULTIPLY  energies and exposures — "a third less sun" is a real statement
##             about any hour, so `sun_energy_mul` composes correctly at all of
##             them.
##
##   BIAS      colours. `lerp(time_value, target, weight)`. Weight 0 keeps the
##             hour untouched, 1 replaces it, and everything between is a
##             partial pull. THIS is what lets rain drag an evening towards
##             blue-grey while still leaving it recognisably an evening.
##
##   SET       things the weather simply owns. Cloud cover is not a property of
##             four o'clock; it is a property of the weather. Fog range, cloud
##             shape and precipitation are all in this group.
##
## A profile therefore reads as three blocks, and which block a field is in is
## a deliberate statement about what that field means.

@export var id: StringName = &"Clear"
## Shown by a game's own UI if it wants one. Never used for logic.
@export var display_name: String = "Clear"

# =============================================================== MULTIPLIERS
@export_group("Multipliers")
@export_range(0.0, 3.0, 0.005) var camera_exposure_mul: float = 1.0
@export_range(0.0, 3.0, 0.005) var tonemap_exposure_mul: float = 1.0
@export_range(0.0, 3.0, 0.005) var skydome_energy_mul: float = 1.0
@export_range(0.0, 3.0, 0.005) var ambient_energy_mul: float = 1.0
@export_range(0.0, 3.0, 0.005) var moon_energy_mul: float = 1.0
@export_range(0.0, 3.0, 0.005) var night_ambient_min_mul: float = 1.0
@export_range(0.0, 3.0, 0.005) var atm_darkness_mul: float = 1.0
@export_range(0.0, 3.0, 0.005) var sun_disk_intensity_mul: float = 1.0
## Scales the time profile's aerial-perspective density. The RANGE of the
## depth fog is set outright below; this only tints.
@export_range(0.0, 8.0, 0.005) var aerial_density_mul: float = 1.0
@export_range(0.0, 3.0, 0.005) var aerial_end_mul: float = 1.0

# ==================================================================== BIASES
@export_group("Colour bias")
## Each pair is `lerp(hour_colour, bias, weight)`. Weight 0 = the hour is kept.
@export var sun_light_bias: Color = Color(0.75, 0.80, 0.90)
@export_range(0.0, 1.0, 0.005) var sun_light_bias_weight: float = 0.0
@export var sun_horizon_bias: Color = Color(0.72, 0.78, 0.88)
@export_range(0.0, 1.0, 0.005) var sun_horizon_bias_weight: float = 0.0
@export var atm_day_bias: Color = Color(0.55, 0.62, 0.72)
@export_range(0.0, 1.0, 0.005) var atm_day_bias_weight: float = 0.0
@export var atm_horizon_bias: Color = Color(0.58, 0.65, 0.75)
@export_range(0.0, 1.0, 0.005) var atm_horizon_bias_weight: float = 0.0
@export var cloud_day_bias: Color = Color(0.58, 0.63, 0.72)
@export_range(0.0, 1.0, 0.005) var cloud_day_bias_weight: float = 0.0
@export var cloud_horizon_bias: Color = Color(0.55, 0.61, 0.72)
@export_range(0.0, 1.0, 0.005) var cloud_horizon_bias_weight: float = 0.0
## Biases the DEPTH fog colour away from the sky-derived tint. Keep this low:
## fog that has stopped agreeing with the sky stops reading as distance.
@export var fog_tint_bias: Color = Color(0.60, 0.66, 0.74)
@export_range(0.0, 1.0, 0.005) var fog_tint_bias_weight: float = 0.0

# ====================================================================== SETS
@export_group("Sun")
@export_range(0.0, 4.0, 0.005) var sun_energy: float = 1.05
@export_range(0.0, 1.0, 0.005) var sun_shadow_opacity: float = 0.92

@export_group("Atmosphere")
@export_exp_easing() var atm_turbidity: float = 0.001
@export_range(0.0, 4.0, 0.005) var atm_thickness: float = 0.70

@export_group("Clouds")
@export var clouds_visible: bool = true
@export_range(0.0, 1.0, 0.005) var clouds_coverage: float = 0.42
@export_range(0.0, 8.0, 0.01) var clouds_absorption: float = 2.0
@export_range(0.0, 1.0, 0.005) var clouds_sky_tint_fade: float = 0.45
@export_range(0.0, 30.0, 0.05) var clouds_intensity: float = 10.0
@export_range(0.0, 1.0, 0.001) var clouds_speed: float = 0.055
@export var cumulus_visible: bool = true
@export_range(0.0, 1.0, 0.005) var cumulus_coverage: float = 0.44
@export_range(0.0, 8.0, 0.01) var cumulus_absorption: float = 1.9
@export_range(0.0, 0.2, 0.001) var cumulus_thickness: float = 0.026
@export_range(0.0, 8.0, 0.01) var cumulus_noise_freq: float = 2.7
@export_range(0.0, 4.0, 0.005) var cumulus_intensity: float = 0.62
@export_range(0.0, 4.0, 0.005) var cumulus_mie_intensity: float = 1.0
@export_range(0.0, 1.0, 0.001) var cumulus_speed: float = 0.045
## THE key that decides whether there are clouds or a featureless wash. Sky3D
## samples its cumulus noise at `point * size * 0.0212`; LOW is big masses,
## HIGH is fine stipple. The shipped default of 0.5 is a smooth gradient with
## no cloud in it.
@export_range(0.1, 30.0, 0.1) var cumulus_size: float = 5.0

@export_group("Depth fog")
## Godot Environment fog — the mechanism that carries RANGE. See `env_keys.gd`.
@export var fog_enabled: bool = false
## 0 exponential, 1 depth. Depth is used throughout: it is the only one with an
## explicit near-clear distance.
@export_enum("Exponential:0", "Depth:1") var fog_mode: int = 1
@export_exp_easing() var fog_density: float = 0.0
## Nothing nearer than this is fogged AT ALL. This is the single control that
## keeps the near field sharp, and it is why fog is depth rather than
## exponential.
@export_range(0.0, 4000.0, 1.0) var fog_depth_begin: float = 24.0
@export_range(0.0, 4000.0, 1.0) var fog_depth_end: float = 420.0
## Shapes the ramp between them. Below 1 loses contrast early, above 1 holds
## the mid-distance and then falls away.
@export_range(0.05, 8.0, 0.01) var fog_depth_curve: float = 1.0
## How much of the fog lands on the SKY. This is the white-wall control: at 0
## the sky is untouched however thick the ground fog is.
@export_range(0.0, 1.0, 0.005) var fog_sky_affect: float = 0.15
## Blends the fog colour towards the sun's own colour along the view ray.
@export_range(0.0, 1.0, 0.005) var fog_aerial_perspective: float = 0.2
@export_range(0.0, 1.0, 0.005) var fog_sun_scatter: float = 0.0
## World height the height-fog sits at, and how fast it thickens below it.
## Ground-hugging fog is what leaves silhouettes standing in it.
@export var fog_height: float = 0.0
@export_range(0.0, 1.0, 0.0001) var fog_height_density: float = 0.0

@export_group("Volumetric fog")
## HIGH quality only. Real scattering; genuinely expensive.
@export_exp_easing() var volumetric_density: float = 0.0
@export_range(-0.9, 0.9, 0.005) var volumetric_anisotropy: float = 0.2
@export var volumetric_albedo: Color = Color(1, 1, 1)
@export_range(0.0, 1.0, 0.005) var volumetric_sky_affect: float = 0.0
@export_range(0.0, 1.0, 0.005) var volumetric_ambient_inject: float = 0.0

@export_group("Grade")
## A restrained global saturation trim. Overcast really does desaturate a
## scene; this is the cheapest honest way to say so.
@export_range(0.0, 2.0, 0.005) var saturation: float = 1.0
@export_range(0.0, 2.0, 0.005) var contrast: float = 1.0

@export_group("Precipitation")
## 0 = dry. Drives `ACAPrecipitationRig`; means nothing without one.
@export_range(0.0, 1.0, 0.005) var rain_intensity: float = 0.0
## Horizontal drift, world units per second. Small values read as weather;
## large ones read as a bug.
@export var wind: Vector2 = Vector2.ZERO
## 0 = dry ground. Advisory: a host project may or may not consume it.
@export_range(0.0, 1.0, 0.005) var wetness: float = 0.0


## The `set` half of the layer — values the weather owns outright.
func to_set_values() -> Dictionary:
	return {
		"sky:sun_energy": sun_energy,
		"sky:sun_shadow_opacity": sun_shadow_opacity,
		"sky:cloud_intensity": cumulus_intensity,
		"dome:atm_turbidity": atm_turbidity,
		"dome:atm_thickness": atm_thickness,
		"dome:clouds_visible": clouds_visible,
		"dome:clouds_coverage": clouds_coverage,
		"dome:clouds_absorption": clouds_absorption,
		"dome:clouds_sky_tint_fade": clouds_sky_tint_fade,
		"dome:clouds_intensity": clouds_intensity,
		"dome:clouds_speed": clouds_speed,
		"dome:clouds_cumulus_visible": cumulus_visible,
		"dome:clouds_cumulus_coverage": cumulus_coverage,
		"dome:clouds_cumulus_absorption": cumulus_absorption,
		"dome:clouds_cumulus_thickness": cumulus_thickness,
		"dome:clouds_cumulus_noise_freq": cumulus_noise_freq,
		"dome:clouds_cumulus_intensity": cumulus_intensity,
		"dome:clouds_cumulus_mie_intensity": cumulus_mie_intensity,
		"dome:clouds_cumulus_speed": cumulus_speed,
		"dome:clouds_cumulus_size": cumulus_size,
		"env:fog_enabled": fog_enabled,
		"env:fog_mode": fog_mode,
		"env:fog_density": fog_density,
		"env:fog_depth_begin": fog_depth_begin,
		"env:fog_depth_end": fog_depth_end,
		"env:fog_depth_curve": fog_depth_curve,
		"env:fog_sky_affect": fog_sky_affect,
		"env:fog_aerial_perspective": fog_aerial_perspective,
		"env:fog_sun_scatter": fog_sun_scatter,
		"env:fog_height": fog_height,
		"env:fog_height_density": fog_height_density,
		"env:volumetric_fog_density": volumetric_density,
		"env:volumetric_fog_anisotropy": volumetric_anisotropy,
		"env:volumetric_fog_albedo": volumetric_albedo,
		"env:volumetric_fog_sky_affect": volumetric_sky_affect,
		"env:volumetric_fog_ambient_inject": volumetric_ambient_inject,
		"env:adjustment_saturation": saturation,
		"env:adjustment_contrast": contrast,
		"fx:rain_intensity": rain_intensity,
		"fx:wind_x": wind.x,
		"fx:wind_z": wind.y,
		"fx:wetness": wetness,
	}


## The `scale` half — multipliers applied to the composed time value.
func to_scale_values() -> Dictionary:
	return {
		"sky:camera_exposure": camera_exposure_mul,
		"sky:tonemap_exposure": tonemap_exposure_mul,
		"sky:skydome_energy": skydome_energy_mul,
		"sky:ambient_energy": ambient_energy_mul,
		"sky:moon_energy": moon_energy_mul,
		"sky:night_ambient_min": night_ambient_min_mul,
		"dome:atm_darkness": atm_darkness_mul,
		"dome:sun_disk_intensity": sun_disk_intensity_mul,
		"dome:fog_density": aerial_density_mul,
		"dome:fog_end": aerial_end_mul,
	}


## The `bias` half — `[key, target_colour, weight]` triples.
func to_bias_values() -> Array:
	return [
		["dome:sun_light_color", sun_light_bias, sun_light_bias_weight],
		["dome:sun_horizon_light_color", sun_horizon_bias, sun_horizon_bias_weight],
		["dome:atm_day_tint", atm_day_bias, atm_day_bias_weight],
		["dome:atm_horizon_light_tint", atm_horizon_bias, atm_horizon_bias_weight],
		["dome:clouds_cumulus_day_color", cloud_day_bias, cloud_day_bias_weight],
		["dome:clouds_cumulus_horizon_light_color", cloud_horizon_bias,
			cloud_horizon_bias_weight],
		["env:fog_light_color", fog_tint_bias, fog_tint_bias_weight],
	]
