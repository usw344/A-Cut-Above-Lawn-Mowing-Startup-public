extends SceneTree
## BOOTSTRAP. Writes the shipped default profiles to `profiles/`.
##
##   godot --headless --path <project> \
##     --script "res://addons/aca_sky3d_environment/tools/build_default_profiles.gd"
##
## The `.tres` files it produces are the SOURCE OF TRUTH from then on: edit them
## in the inspector, not here. This exists so a fresh install has a working set,
## and so the defaults can be restored after an experiment.
##
## Running it OVERWRITES the shipped profiles. It will not touch a directory
## that is not this package's own.

const ROOT := "res://addons/aca_sky3d_environment/profiles"


func _initialize() -> void:
	for sub in ["time", "weather", "quality"]:
		DirAccess.make_dir_recursive_absolute(ROOT + "/" + sub)
	_time_profiles()
	_weather_profiles()
	_quality_profiles()
	print("[PROFILES] wrote defaults to ", ROOT)
	quit(0)


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		printerr("[PROFILES] failed to write %s (%d)" % [path, err])
	else:
		print("[PROFILES] ", path)


# ============================================================== time profiles

func _time_profiles() -> void:
	# ---------------------------------------------------------------- DAY
	# The reference neutral look. Everything else is a departure from this,
	# and nothing here is graded: a clear noon should look like a clear noon.
	var day := ACAEnvTimeProfile.new()
	day.id = &"Day"
	day.camera_exposure = 1.00
	day.tonemap_exposure = 1.00
	day.skydome_energy = 1.00
	day.sun_light_color = Color(1.00, 0.98, 0.94)
	day.sun_horizon_light_color = Color(0.98, 0.66, 0.44)
	day.moon_energy = 0.30
	day.moon_light_color = Color(0.62, 0.76, 0.98)
	day.sun_disk_intensity = 30.0
	day.ambient_energy = 1.00
	day.sky_contribution = 1.00
	day.night_ambient_min = 0.70
	day.atm_darkness = 0.48
	day.atm_sun_intensity = 18.0
	day.atm_day_tint = Color(0.81, 0.91, 1.00)
	day.atm_horizon_light_tint = Color(0.96, 0.72, 0.56)
	day.atm_night_tint = Color(0.22, 0.28, 0.40)
	day.atm_mie = 0.070
	day.ground_color = Color(0.24, 0.25, 0.23)
	day.aerial_density = 0.00062
	day.aerial_start = 0.0
	day.aerial_end = 1200.0
	day.aerial_rayleigh_depth = 0.115
	day.aerial_mie_depth = 0.00012
	day.aerial_falloff = 3.2
	day.cloud_day_color = Color(0.88, 0.92, 1.00)
	day.cloud_horizon_color = Color(0.98, 0.62, 0.38)
	day.cloud_night_color = Color(0.17, 0.20, 0.28)
	day.fog_tint = Color(0.66, 0.74, 0.84)
	day.fog_light_energy = 1.00
	_save(day, ROOT + "/time/day.tres")

	# ------------------------------------------------------------ MORNING
	# Not "day but darker": a cooler sky, a warm low sun, and haze day has not
	# got. The warmth belongs to the HORIZON, not to the whole dome.
	var morning := ACAEnvTimeProfile.new()
	morning.id = &"Morning"
	morning.camera_exposure = 1.05
	morning.tonemap_exposure = 1.01
	morning.skydome_energy = 1.00
	morning.sun_light_color = Color(1.00, 0.95, 0.88)
	morning.sun_horizon_light_color = Color(1.00, 0.78, 0.58)
	morning.moon_energy = 0.35
	morning.moon_light_color = Color(0.62, 0.76, 0.98)
	morning.sun_disk_intensity = 30.0
	morning.ambient_energy = 1.05
	morning.sky_contribution = 0.95
	morning.night_ambient_min = 0.60
	morning.atm_darkness = 0.42
	morning.atm_sun_intensity = 16.0
	morning.atm_day_tint = Color(0.82, 0.89, 1.00)
	morning.atm_horizon_light_tint = Color(1.00, 0.78, 0.60)
	morning.atm_night_tint = Color(0.22, 0.28, 0.40)
	morning.atm_mie = 0.082
	morning.ground_color = Color(0.17, 0.18, 0.17)
	morning.aerial_density = 0.0014
	morning.aerial_start = 0.0
	morning.aerial_end = 700.0
	morning.aerial_rayleigh_depth = 0.135
	morning.aerial_mie_depth = 0.00026
	morning.aerial_falloff = 2.7
	morning.cloud_day_color = Color(0.95, 0.95, 1.00)
	morning.cloud_horizon_color = Color(1.00, 0.70, 0.48)
	morning.cloud_night_color = Color(0.17, 0.20, 0.28)
	morning.fog_tint = Color(0.74, 0.78, 0.84)
	morning.fog_light_energy = 1.00
	_save(morning, ROOT + "/time/morning.tres")

	# ------------------------------------------------------------ EVENING
	#
	# THE SEPIA FIX.
	#
	# The previous evening put warm values on EVERY term at once: a salmon
	# `atm_day_tint` over the whole dome, a heavily saturated
	# `sun_horizon_light_color` on every object, and a warm `ground_color`
	# under it. Rendered, that is not golden hour — it is a sepia filter, with
	# orange tree trunks standing in red-brown dirt.
	#
	# Real evening light is NARROW. The warm band sits at the horizon; the
	# upper sky stays blue and goes bluer as the sun drops. So the warmth is
	# concentrated in `atm_horizon_light_tint` and `sun_light_color`, while
	# `atm_day_tint` is COOL and `ground_color` is neutral. The key light is
	# still golden; the world is no longer painted in it.
	var evening := ACAEnvTimeProfile.new()
	evening.id = &"Evening"
	evening.camera_exposure = 1.08
	evening.tonemap_exposure = 1.01
	evening.skydome_energy = 1.02
	evening.sun_light_color = Color(1.00, 0.90, 0.78)
	evening.sun_horizon_light_color = Color(1.00, 0.87, 0.76)
	evening.moon_energy = 0.40
	evening.moon_light_color = Color(0.62, 0.76, 0.98)
	evening.sun_disk_intensity = 34.0
	evening.ambient_energy = 1.12
	evening.sky_contribution = 0.95
	evening.night_ambient_min = 0.52
	evening.atm_darkness = 0.42
	evening.atm_sun_intensity = 17.0
	evening.atm_day_tint = Color(0.84, 0.86, 0.96)
	evening.atm_horizon_light_tint = Color(0.99, 0.76, 0.62)
	evening.atm_night_tint = Color(0.22, 0.28, 0.40)
	evening.atm_mie = 0.088
	evening.ground_color = Color(0.20, 0.20, 0.20)
	evening.aerial_density = 0.0013
	evening.aerial_start = 0.0
	evening.aerial_end = 780.0
	evening.aerial_rayleigh_depth = 0.130
	evening.aerial_mie_depth = 0.00024
	evening.aerial_falloff = 2.7
	evening.cloud_day_color = Color(0.98, 0.94, 0.94)
	evening.cloud_horizon_color = Color(1.00, 0.74, 0.58)
	evening.cloud_night_color = Color(0.17, 0.20, 0.28)
	evening.fog_tint = Color(0.74, 0.72, 0.76)
	evening.fog_light_energy = 1.00
	_save(evening, ROOT + "/time/evening.tres")

	# -------------------------------------------------------------- NIGHT
	# Lifted on purpose. `night_ambient_min` is the important one: Sky3D drops
	# `ambient_light_sky_contribution` to it after dark, and a LOWER value
	# means more neutral fill, i.e. a night you can still drive in.
	var night := ACAEnvTimeProfile.new()
	night.id = &"Night"
	night.camera_exposure = 1.28
	night.tonemap_exposure = 1.08
	night.skydome_energy = 1.00
	night.sun_light_color = Color(0.75, 0.82, 1.00)
	night.sun_horizon_light_color = Color(0.60, 0.62, 0.80)
	night.moon_energy = 0.85
	night.moon_light_color = Color(0.64, 0.78, 1.00)
	night.sun_disk_intensity = 22.0
	night.ambient_energy = 1.25
	night.sky_contribution = 0.95
	night.night_ambient_min = 0.42
	night.atm_darkness = 0.30
	night.atm_sun_intensity = 14.0
	night.atm_day_tint = Color(0.55, 0.66, 0.85)
	night.atm_horizon_light_tint = Color(0.44, 0.54, 0.74)
	night.atm_night_tint = Color(0.22, 0.28, 0.40)
	night.atm_mie = 0.070
	night.ground_color = Color(0.055, 0.065, 0.085)
	night.aerial_density = 0.0010
	night.aerial_start = 0.0
	night.aerial_end = 820.0
	night.aerial_rayleigh_depth = 0.130
	night.aerial_mie_depth = 0.00016
	night.aerial_falloff = 2.8
	night.cloud_day_color = Color(0.44, 0.50, 0.62)
	night.cloud_horizon_color = Color(0.36, 0.42, 0.56)
	night.cloud_night_color = Color(0.17, 0.20, 0.28)
	night.fog_tint = Color(0.13, 0.18, 0.28)
	night.fog_light_energy = 0.72
	_save(night, ROOT + "/time/night.tres")


# =========================================================== weather profiles

func _weather_profiles() -> void:
	# -------------------------------------------------------------- CLEAR
	# The reference. No bias, no grade, no multipliers — Clear IS the time
	# profile. The only thing it adds is a little honest distance haze, so the
	# treeline sits behind air rather than being pasted on.
	var clear := ACAEnvWeatherProfile.new()
	clear.id = &"Clear"
	clear.display_name = "Clear"
	clear.sun_energy = 1.05
	clear.sun_shadow_opacity = 0.92
	clear.atm_turbidity = 0.0010
	clear.atm_thickness = 0.70
	clear.clouds_visible = true
	clear.clouds_coverage = 0.42
	clear.clouds_absorption = 2.0
	clear.clouds_sky_tint_fade = 0.45
	clear.clouds_intensity = 10.0
	clear.clouds_speed = 0.055
	clear.cumulus_visible = true
	clear.cumulus_coverage = 0.44
	clear.cumulus_absorption = 1.9
	clear.cumulus_thickness = 0.026
	clear.cumulus_noise_freq = 2.7
	clear.cumulus_intensity = 0.62
	clear.cumulus_mie_intensity = 1.00
	clear.cumulus_speed = 0.045
	clear.cumulus_size = 5.0
	clear.fog_enabled = true
	clear.fog_mode = 1
	clear.fog_density = 0.30
	clear.fog_depth_begin = 110.0
	clear.fog_depth_end = 1000.0
	clear.fog_depth_curve = 1.7
	clear.fog_sky_affect = 0.0
	clear.fog_aerial_perspective = 0.25
	clear.fog_sun_scatter = 0.05
	clear.fog_height = 0.0
	clear.fog_height_density = 0.0
	clear.volumetric_density = 0.0
	clear.saturation = 1.0
	clear.contrast = 1.0
	clear.rain_intensity = 0.0
	clear.wind = Vector2(0.6, 0.3)
	clear.wetness = 0.0
	_save(clear, ROOT + "/weather/clear.tres")

	# -------------------------------------------------------------- FOGGY
	#
	# THE FOG REDESIGN.
	#
	# The old Foggy pushed Sky3D's screen-space quad to `fog_density` 0.0042,
	# and that is where the white wall came from: the shipped `AtmFog.gdshader`
	# has its sky-exclusion line commented out, so density enough to hide a
	# treeline also washes the sky. Sky3D is read-only, so the answer is not to
	# push it harder — it is to STOP pushing it, and let a mechanism that CAN
	# exclude the sky carry the range.
	#
	# So the Sky3D quad stays gentle (2.2x a base of 0.00062, roughly a third
	# of what it used to be) and only tints, and Godot's Environment depth fog
	# does the work:
	#
	#   fog_depth_begin 18   nothing within 18 units is fogged at all, so the
	#                        mower and the grass in front of it stay SHARP
	#   fog_depth_curve 0.85 contrast is lost progressively, not at a wall
	#   fog_sky_affect 0.22  the sky is mostly left alone — no white wall
	#   height fog           sits on the ground, so the treeline is a row of
	#                        silhouettes standing in it rather than a smear
	var foggy := ACAEnvWeatherProfile.new()
	foggy.id = &"Foggy"
	foggy.display_name = "Fog"
	foggy.camera_exposure_mul = 1.06
	foggy.skydome_energy_mul = 0.96
	foggy.ambient_energy_mul = 1.16
	foggy.moon_energy_mul = 1.10
	foggy.atm_darkness_mul = 1.12
	foggy.sun_disk_intensity_mul = 0.60
	foggy.aerial_density_mul = 1.8
	foggy.aerial_end_mul = 0.55
	foggy.sun_light_bias = Color(0.86, 0.88, 0.92)
	foggy.sun_light_bias_weight = 0.30
	foggy.atm_day_bias = Color(0.72, 0.76, 0.82)
	foggy.atm_day_bias_weight = 0.30
	foggy.cloud_day_bias = Color(0.80, 0.83, 0.88)
	foggy.cloud_day_bias_weight = 0.35
	foggy.fog_tint_bias = Color(0.72, 0.76, 0.80)
	foggy.fog_tint_bias_weight = 0.35
	foggy.sun_energy = 0.70
	foggy.sun_shadow_opacity = 0.30
	foggy.atm_turbidity = 0.0022
	foggy.atm_thickness = 0.86
	foggy.clouds_visible = true
	foggy.clouds_coverage = 0.62
	foggy.clouds_absorption = 2.3
	foggy.clouds_sky_tint_fade = 0.66
	foggy.clouds_intensity = 6.0
	foggy.clouds_speed = 0.050
	foggy.cumulus_visible = true
	foggy.cumulus_coverage = 0.70
	foggy.cumulus_absorption = 2.3
	foggy.cumulus_thickness = 0.034
	foggy.cumulus_noise_freq = 2.5
	foggy.cumulus_intensity = 0.52
	foggy.cumulus_mie_intensity = 0.85
	foggy.cumulus_speed = 0.040
	foggy.cumulus_size = 9.0
	foggy.fog_enabled = true
	foggy.fog_mode = 1
	foggy.fog_density = 0.85
	foggy.fog_depth_begin = 18.0
	foggy.fog_depth_end = 210.0
	foggy.fog_depth_curve = 0.85
	foggy.fog_sky_affect = 0.13
	foggy.fog_aerial_perspective = 0.35
	foggy.fog_sun_scatter = 0.10
	foggy.fog_height = 3.0
	foggy.fog_height_density = 0.040
	foggy.volumetric_density = 0.028
	foggy.volumetric_anisotropy = 0.15
	foggy.volumetric_albedo = Color(0.90, 0.93, 0.97)
	foggy.volumetric_sky_affect = 0.0
	foggy.volumetric_ambient_inject = 0.25
	foggy.saturation = 0.94
	foggy.contrast = 1.0
	foggy.rain_intensity = 0.0
	foggy.wind = Vector2(1.0, 0.5)
	foggy.wetness = 0.15
	_save(foggy, ROOT + "/weather/foggy.tres")

	# --------------------------------------------------------------- RAIN
	#
	# The blue-grey storm, IN THE GAME rather than only in a trailer override.
	#
	# The old layer could only multiply, and multiplying a Color makes it
	# darker but never bluer — so a storm at golden hour came out as a dim
	# golden hour, which is R-020. The bias weights below are the fix: at 0.5,
	# HALF the hour's hue survives, so evening rain is still recognisably an
	# evening while genuinely reading blue-grey.
	var rain := ACAEnvWeatherProfile.new()
	rain.id = &"Rain"
	rain.display_name = "Rain"
	rain.camera_exposure_mul = 1.04
	rain.skydome_energy_mul = 0.86
	rain.ambient_energy_mul = 1.22
	rain.moon_energy_mul = 1.30
	rain.night_ambient_min_mul = 0.88
	rain.atm_darkness_mul = 1.14
	rain.sun_disk_intensity_mul = 0.25
	rain.aerial_density_mul = 1.8
	rain.aerial_end_mul = 0.62
	rain.sun_light_bias = Color(0.72, 0.78, 0.90)
	rain.sun_light_bias_weight = 0.45
	rain.sun_horizon_bias = Color(0.66, 0.72, 0.84)
	rain.sun_horizon_bias_weight = 0.45
	rain.atm_day_bias = Color(0.50, 0.57, 0.68)
	rain.atm_day_bias_weight = 0.55
	rain.atm_horizon_bias = Color(0.54, 0.60, 0.70)
	rain.atm_horizon_bias_weight = 0.50
	rain.cloud_day_bias = Color(0.58, 0.63, 0.73)
	rain.cloud_day_bias_weight = 0.55
	rain.cloud_horizon_bias = Color(0.52, 0.58, 0.70)
	rain.cloud_horizon_bias_weight = 0.50
	rain.fog_tint_bias = Color(0.58, 0.63, 0.70)
	rain.fog_tint_bias_weight = 0.45
	rain.sun_energy = 0.44
	rain.sun_shadow_opacity = 0.18
	rain.atm_turbidity = 0.0032
	rain.atm_thickness = 0.86
	rain.clouds_visible = true
	rain.clouds_coverage = 0.78
	rain.clouds_absorption = 2.7
	rain.clouds_sky_tint_fade = 0.55
	rain.clouds_intensity = 4.0
	rain.clouds_speed = 0.130
	rain.cumulus_visible = true
	rain.cumulus_coverage = 0.62
	rain.cumulus_absorption = 4.0
	rain.cumulus_thickness = 0.046
	rain.cumulus_noise_freq = 2.8
	rain.cumulus_intensity = 0.45
	rain.cumulus_mie_intensity = 0.35
	rain.cumulus_speed = 0.100
	rain.cumulus_size = 2.0
	rain.fog_enabled = true
	rain.fog_mode = 1
	rain.fog_density = 0.62
	rain.fog_depth_begin = 26.0
	rain.fog_depth_end = 340.0
	rain.fog_depth_curve = 1.05
	rain.fog_sky_affect = 0.07
	rain.fog_aerial_perspective = 0.30
	rain.fog_sun_scatter = 0.05
	rain.fog_height = 6.0
	rain.fog_height_density = 0.018
	rain.volumetric_density = 0.020
	rain.volumetric_anisotropy = 0.25
	rain.volumetric_albedo = Color(0.86, 0.90, 0.96)
	rain.volumetric_sky_affect = 0.0
	rain.volumetric_ambient_inject = 0.20
	rain.saturation = 0.90
	rain.contrast = 1.02
	rain.rain_intensity = 1.0
	rain.wind = Vector2(2.2, 1.1)
	rain.wetness = 0.65
	_save(rain, ROOT + "/weather/rain.tres")


# =========================================================== quality profiles

func _quality_profiles() -> void:
	# Each level below removes a WHOLE MECHANISM. If two of them ever measure
	# the same in `Weather Matrix`, one of them is a lie.
	var high := ACAEnvQualityProfile.new()
	high.id = &"High"
	high.display_name = "High"
	high.use_depth_fog = true
	high.use_aerial = true
	high.use_volumetric_fog = true
	high.volumetric_density_scale = 1.0
	high.volumetric_length = 96.0
	high.volumetric_detail_spread = 2.0
	high.depth_fog_density_scale = 1.0
	high.height_fog_density_scale = 1.0
	high.rain_layers = 3
	high.rain_amount_scale = 1.0
	high.rain_splash = true
	high.update_interval = 0.05
	_save(high, ROOT + "/quality/high.tres")

	# Everything High has except the froxel volume, which is the expensive one.
	var medium := ACAEnvQualityProfile.new()
	medium.id = &"Medium"
	medium.display_name = "Medium"
	medium.use_depth_fog = true
	medium.use_aerial = true
	medium.use_volumetric_fog = false
	medium.volumetric_density_scale = 0.0
	medium.volumetric_length = 64.0
	medium.volumetric_detail_spread = 2.0
	medium.depth_fog_density_scale = 0.92
	medium.height_fog_density_scale = 0.80
	medium.rain_layers = 2
	medium.rain_amount_scale = 0.75
	medium.rain_splash = false
	medium.update_interval = 0.06
	_save(medium, ROOT + "/quality/medium.tres")

	# Depth fog only: one cheap full-screen mechanism, no screen-space
	# scattering quad, no height integration, one rain emitter.
	var low := ACAEnvQualityProfile.new()
	low.id = &"Low"
	low.display_name = "Low"
	low.use_depth_fog = true
	low.use_aerial = false
	low.use_volumetric_fog = false
	low.volumetric_density_scale = 0.0
	low.volumetric_length = 48.0
	low.volumetric_detail_spread = 3.0
	low.depth_fog_density_scale = 0.78
	low.height_fog_density_scale = 0.0
	low.rain_layers = 1
	low.rain_amount_scale = 0.55
	low.rain_splash = false
	low.update_interval = 0.10
	_save(low, ROOT + "/quality/low.tres")
