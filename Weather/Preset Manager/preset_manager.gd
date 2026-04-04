extends Node3D
class_name preset_manager

@export var custom_gridmap_path: NodePath
@export var time_preset_transition_duration: float = 2.5

var current_time_of_day: float = 0.5
var current_time_preset: String = "Day"
var current_weather_preset: String = "Clear"
var current_quality_preset: String = "LOW" ## Low Poly or High Poly

var time_of_day_tween: Tween = null



@onready var custom_gridmap = get_node_or_null(custom_gridmap_path)
@onready var sky3d = $Sky3D
@onready var skydome:Skydome = $Sky3D/Skydome
@onready var time_of_day_node = $Sky3D/TimeOfDay
@onready var rain_handler:Rain_Handler = $"Rain Handler"

func _ready() -> void:
	# by default no rain unless called for
	rain_handler.stop_rain_instant()

func set_audio_player(player:AudioStreamPlayer):
	rain_handler.set_ambience_sound_player(player)

func _____TIME____():
	pass
func set_time_of_day_normalized(value: float) -> void:
	## note this function expects a value range 0-23.99 passed in
	## UNTIL THIS NOTE IS CHANGED: this mapping of slider to 0-23.99 range
	## happens in the MVP_HUD
	current_time_of_day = clampf(value, 0.0, 23.99)
	sky3d.current_time = current_time_of_day

func smooth_set_time_of_day(target_time: float, duration: float = -1.0) -> void:
	target_time = clampf(target_time, 0.0, 23.99)

	if duration < 0.0:
		duration = time_preset_transition_duration

	if time_of_day_tween:
		time_of_day_tween.kill()
		time_of_day_tween = null

	if is_equal_approx(current_time_of_day, target_time):
		set_time_of_day_normalized(target_time)
		return

	time_of_day_tween = create_tween()
	time_of_day_tween.set_trans(Tween.TRANS_SINE)
	time_of_day_tween.set_ease(Tween.EASE_IN_OUT)
	time_of_day_tween.tween_method(set_time_of_day_normalized, current_time_of_day, target_time, duration)
	time_of_day_tween.finished.connect(_on_time_of_day_tween_finished)

func _on_time_of_day_tween_finished() -> void:
	time_of_day_tween = null

func map_0_100_to_time(value: float) -> float:
	return (value / 100.0) * 23.99

func apply_time_of_day_preset(preset_name: String) -> void:
	current_time_preset = preset_name

	match preset_name:
		"Day":
			smooth_set_time_of_day(12.00)
		"Night":
			smooth_set_time_of_day(22.00)
		"Evening":
			smooth_set_time_of_day(17.5)

func _____WEATHER_____():
	pass

func apply_weather_preset(preset_name: String) -> void:
	current_weather_preset = preset_name

	match preset_name:
		"Clear":
			rain_handler.stop_rain()
			apply_clear_sky_preset()
		"Foggy":
			apply_foggy_sky_preset()
			rain_handler.stop_rain()
		"Rain":
			rain_handler.start_rain()
			apply_rain_sky_preset()


var weather_sky_tween: Tween = null


func _kill_weather_sky_tween() -> void:
	if weather_sky_tween:
		weather_sky_tween.kill()
		weather_sky_tween = null


func _begin_weather_sky_tween(duration: float) -> Tween:
	_kill_weather_sky_tween()
	weather_sky_tween = create_tween()
	weather_sky_tween.set_parallel(true)
	weather_sky_tween.set_trans(Tween.TRANS_SINE)
	weather_sky_tween.set_ease(Tween.EASE_IN_OUT)
	return weather_sky_tween


func apply_rain_sky_preset(duration: float = 2.0) -> void:
	sky3d.sky_enabled = true
	sky3d.lights_enabled = true
	sky3d.clouds_enabled = true
	sky3d.fog_enabled = true

	var t := _begin_weather_sky_tween(duration)

	# Sky3D lighting wrapper values
	t.tween_property(sky3d, "camera_exposure", 0.82, duration)
	t.tween_property(sky3d, "tonemap_exposure", 0.90, duration)
	t.tween_property(sky3d, "skydome_energy", 0.72, duration)
	t.tween_property(sky3d, "cloud_intensity", 0.32, duration)
	t.tween_property(sky3d, "sun_energy", 0.30, duration)
	t.tween_property(sky3d, "sky_contribution", 0.72, duration)
	t.tween_property(sky3d, "ambient_energy", 0.88, duration)
	t.tween_property(sky3d, "moon_energy", 0.22, duration)

	# Atmosphere
	t.tween_property(skydome, "atm_darkness", 0.72, duration)
	t.tween_property(skydome, "atm_sun_intensity", 10.5, duration)
	t.tween_property(skydome, "atm_day_tint", Color(0.63, 0.70, 0.78, 1.0), duration)
	t.tween_property(skydome, "atm_horizon_light_tint", Color(0.62, 0.66, 0.72, 1.0), duration)
	t.tween_property(skydome, "atm_mie", 0.11, duration)
	t.tween_property(skydome, "atm_turbidity", 0.0035, duration)

	# Screen-space fog
	t.tween_property(skydome, "fog_density", 0.0032, duration)
	t.tween_property(skydome, "fog_start", 0.0, duration)
	t.tween_property(skydome, "fog_end", 340.0, duration)
	t.tween_property(skydome, "fog_rayleigh_depth", 0.18, duration)
	t.tween_property(skydome, "fog_mie_depth", 0.0007, duration)
	t.tween_property(skydome, "fog_falloff", 1.8, duration)

	# Flat cloud layer
	t.tween_property(skydome, "clouds_visible", true, duration)
	t.tween_property(skydome, "clouds_coverage", 0.82, duration)
	t.tween_property(skydome, "clouds_absorption", 2.8, duration)
	t.tween_property(skydome, "clouds_sky_tint_fade", 0.82, duration)
	t.tween_property(skydome, "clouds_intensity", 0.42, duration)
	t.tween_property(skydome, "clouds_speed", 0.11, duration)

	# Cumulus storm layer
	t.tween_property(skydome, "clouds_cumulus_visible", true, duration)
	t.tween_property(skydome, "clouds_cumulus_coverage", 0.93, duration)
	t.tween_property(skydome, "clouds_cumulus_absorption", 3.4, duration)
	t.tween_property(skydome, "clouds_cumulus_thickness", 0.05, duration)
	t.tween_property(skydome, "clouds_cumulus_noise_freq", 2.1, duration)
	t.tween_property(skydome, "clouds_cumulus_intensity", 0.30, duration)
	t.tween_property(skydome, "clouds_cumulus_mie_intensity", 0.55, duration)
	t.tween_property(skydome, "clouds_cumulus_speed", 0.08, duration)

	# Darker cloud colors
	t.tween_property(skydome, "clouds_cumulus_day_color", Color(0.68, 0.73, 0.79, 1.0), duration)
	t.tween_property(skydome, "clouds_cumulus_horizon_light_color", Color(0.56, 0.60, 0.66, 1.0), duration)
	t.tween_property(skydome, "clouds_cumulus_night_color", Color(0.08, 0.09, 0.12, 1.0), duration)


func apply_clear_sky_preset(duration: float = 2.0) -> void:
	sky3d.sky_enabled = true
	sky3d.lights_enabled = true
	sky3d.clouds_enabled = true
	sky3d.fog_enabled = true

	var t := _begin_weather_sky_tween(duration)

	# Sky3D defaults / near-defaults
	t.tween_property(sky3d, "camera_exposure", 1.0, duration)
	t.tween_property(sky3d, "tonemap_exposure", 1.0, duration)
	t.tween_property(sky3d, "skydome_energy", 1.0, duration)
	t.tween_property(sky3d, "cloud_intensity", 0.6, duration)
	t.tween_property(sky3d, "sun_energy", 1.0, duration)
	t.tween_property(sky3d, "sky_contribution", 1.0, duration)
	t.tween_property(sky3d, "ambient_energy", 1.0, duration)
	t.tween_property(sky3d, "moon_energy", 0.3, duration)

	# Atmosphere defaults
	t.tween_property(skydome, "atm_darkness", 0.5, duration)
	t.tween_property(skydome, "atm_sun_intensity", 18.0, duration)
	t.tween_property(skydome, "atm_day_tint", Color(0.807843, 0.909804, 1.0, 1.0), duration)
	t.tween_property(skydome, "atm_horizon_light_tint", Color(0.980392, 0.635294, 0.462745, 1.0), duration)
	t.tween_property(skydome, "atm_mie", 0.07, duration)
	t.tween_property(skydome, "atm_turbidity", 0.001, duration)

	# Fog defaults
	t.tween_property(skydome, "fog_density", 0.0007, duration)
	t.tween_property(skydome, "fog_start", 0.0, duration)
	t.tween_property(skydome, "fog_end", 1000.0, duration)
	t.tween_property(skydome, "fog_rayleigh_depth", 0.115, duration)
	t.tween_property(skydome, "fog_mie_depth", 0.0001, duration)
	t.tween_property(skydome, "fog_falloff", 3.0, duration)

	# Flat cloud defaults
	t.tween_property(skydome, "clouds_visible", true, duration)
	t.tween_property(skydome, "clouds_coverage", 0.5, duration)
	t.tween_property(skydome, "clouds_absorption", 2.0, duration)
	t.tween_property(skydome, "clouds_sky_tint_fade", 0.5, duration)
	t.tween_property(skydome, "clouds_intensity", 10.0, duration)
	t.tween_property(skydome, "clouds_speed", 0.07, duration)

	# Cumulus defaults
	t.tween_property(skydome, "clouds_cumulus_visible", true, duration)
	t.tween_property(skydome, "clouds_cumulus_coverage", 0.55, duration)
	t.tween_property(skydome, "clouds_cumulus_absorption", 2.0, duration)
	t.tween_property(skydome, "clouds_cumulus_thickness", 0.0243, duration)
	t.tween_property(skydome, "clouds_cumulus_noise_freq", 2.7, duration)
	t.tween_property(skydome, "clouds_cumulus_intensity", 0.6, duration)
	t.tween_property(skydome, "clouds_cumulus_mie_intensity", 1.0, duration)
	t.tween_property(skydome, "clouds_cumulus_speed", 0.05, duration)

	# Cumulus colors defaults
	t.tween_property(skydome, "clouds_cumulus_day_color", Color(0.823529, 0.87451, 1.0, 1.0), duration)
	t.tween_property(skydome, "clouds_cumulus_horizon_light_color", Color(0.98, 0.43, 0.15, 1.0), duration)
	t.tween_property(skydome, "clouds_cumulus_night_color", Color(0.090196, 0.094118, 0.129412, 1.0), duration)


func apply_foggy_sky_preset(duration: float = 2.0) -> void:
	sky3d.sky_enabled = true
	sky3d.lights_enabled = true
	sky3d.clouds_enabled = true
	sky3d.fog_enabled = true

	var t := _begin_weather_sky_tween(duration)

	# Keep it brighter than rain, but flatter than clear
	t.tween_property(sky3d, "camera_exposure", 0.92, duration)
	t.tween_property(sky3d, "tonemap_exposure", 0.96, duration)
	t.tween_property(sky3d, "skydome_energy", 0.85, duration)
	t.tween_property(sky3d, "cloud_intensity", 0.48, duration)
	t.tween_property(sky3d, "sun_energy", 0.55, duration)
	t.tween_property(sky3d, "sky_contribution", 0.82, duration)
	t.tween_property(sky3d, "ambient_energy", 0.95, duration)
	t.tween_property(sky3d, "moon_energy", 0.25, duration)

	# Atmosphere
	t.tween_property(skydome, "atm_darkness", 0.60, duration)
	t.tween_property(skydome, "atm_sun_intensity", 13.0, duration)
	t.tween_property(skydome, "atm_day_tint", Color(0.74, 0.79, 0.84, 1.0), duration)
	t.tween_property(skydome, "atm_horizon_light_tint", Color(0.72, 0.74, 0.76, 1.0), duration)
	t.tween_property(skydome, "atm_mie", 0.09, duration)
	t.tween_property(skydome, "atm_turbidity", 0.0022, duration)

	# Fog is the star here
	t.tween_property(skydome, "fog_density", 0.0022, duration)
	t.tween_property(skydome, "fog_start", 0.0, duration)
	t.tween_property(skydome, "fog_end", 220.0, duration)
	t.tween_property(skydome, "fog_rayleigh_depth", 0.14, duration)
	t.tween_property(skydome, "fog_mie_depth", 0.00035, duration)
	t.tween_property(skydome, "fog_falloff", 2.1, duration)

	# Clouds
	t.tween_property(skydome, "clouds_visible", true, duration)
	t.tween_property(skydome, "clouds_coverage", 0.70, duration)
	t.tween_property(skydome, "clouds_absorption", 2.4, duration)
	t.tween_property(skydome, "clouds_sky_tint_fade", 0.72, duration)
	t.tween_property(skydome, "clouds_intensity", 0.60, duration)
	t.tween_property(skydome, "clouds_speed", 0.08, duration)

	t.tween_property(skydome, "clouds_cumulus_visible", true, duration)
	t.tween_property(skydome, "clouds_cumulus_coverage", 0.78, duration)
	t.tween_property(skydome, "clouds_cumulus_absorption", 2.6, duration)
	t.tween_property(skydome, "clouds_cumulus_thickness", 0.036, duration)
	t.tween_property(skydome, "clouds_cumulus_noise_freq", 2.4, duration)
	t.tween_property(skydome, "clouds_cumulus_intensity", 0.45, duration)
	t.tween_property(skydome, "clouds_cumulus_mie_intensity", 0.72, duration)
	t.tween_property(skydome, "clouds_cumulus_speed", 0.06, duration)

	t.tween_property(skydome, "clouds_cumulus_day_color", Color(0.75, 0.79, 0.84, 1.0), duration)
	t.tween_property(skydome, "clouds_cumulus_horizon_light_color", Color(0.70, 0.72, 0.75, 1.0), duration)
	t.tween_property(skydome, "clouds_cumulus_night_color", Color(0.09, 0.10, 0.12, 1.0), duration)





func get_and_set_mower_global_position(mower_global_position:Vector3):
	rain_handler.set_mower_global_position(mower_global_position)
