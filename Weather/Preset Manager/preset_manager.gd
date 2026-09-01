extends Node3D
class_name preset_manager
## THE project-facing weather/sky API. Scenes talk to this; nothing outside
## `Weather/` writes a Sky3D property directly.
##
##     WorldClock -> preset_manager -> ACAWeatherVisualAdapter -> Sky3D / Skydome
##                                  -> Rain_Handler             -> particles + audio
##
## This class routes and owns the scene wiring. The LOOK itself lives in
## `Weather/Visual/weather_visual_adapter.gd`, which composes a time-of-day
## profile with a weather layer. Change how something looks THERE, not here.
##
## `res://addons/sky_3d/` is read-only for this project. Everything below only
## reads and writes its public properties.

@export var custom_gridmap_path: NodePath
@export var time_preset_transition_duration: float = 2.5

## Follow WorldClock continuously instead of being set once per scene load.
## Sky3D ships with its own clock (a full day every 15 real minutes); with this
## on, that clock is switched off and WorldClock stays authoritative, so the sky
## and the HUD readout can never disagree.
@export var follow_world_clock: bool = true

var current_time_of_day: float = 0.5
var current_time_preset: String = "Day"
var current_weather_preset: String = "Clear"
var current_quality_preset: String = "LOW" ## Low Poly or High Poly

var time_of_day_tween: Tween = null

@onready var custom_gridmap = get_node_or_null(custom_gridmap_path)
@onready var sky3d = $Sky3D
@onready var skydome: Skydome = $Sky3D/Skydome
@onready var time_of_day_node = $Sky3D/TimeOfDay
@onready var rain_handler: Rain_Handler = $"Rain Handler"

## Project-owned look adapter. Created here rather than authored into the scene
## so the scene file stays a plain Sky3D + Rain Handler composition.
var visual: ACAWeatherVisualAdapter = null


func _ready() -> void:
	# by default no rain unless called for
	rain_handler.stop_rain_instant()

	visual = ACAWeatherVisualAdapter.new()
	visual.name = "Weather Visual Adapter"
	add_child(visual)
	visual.bind(sky3d, skydome)
	# The rain rig belongs to the Rain Handler (which owns the audio); the
	# environment adapter DRIVES it, because rain intensity is part of the
	# composed weather rather than a separate switch.
	visual.set_precipitation_rig(rain_handler.rig)
	visual.apply_quality_setting(_graphics_quality())

	sky3d.sky_enabled = true
	sky3d.lights_enabled = true
	sky3d.clouds_enabled = true
	sky3d.fog_enabled = true

	if follow_world_clock:
		# Sky3D's own time would drift against WorldClock. One clock only.
		sky3d.enable_game_time = false

	visual.apply_immediate(current_weather_preset, current_time_of_day)


## The player's graphics setting. Defensive: the environment package ships its
## own default level, and a missing autoload must not stop the sky binding.
func _graphics_quality() -> String:
	var settings := get_node_or_null(^"/root/GameSettings")
	if settings == null or not settings.has_method(&"graphics_quality"):
		return ""
	if not settings.is_connected(&"applied", _on_settings_applied):
		settings.connect(&"applied", _on_settings_applied)
	return String(settings.call(&"graphics_quality"))


## Quality follows the player changing it, rather than only the scene loading.
func _on_settings_applied(_values: Dictionary) -> void:
	if visual != null:
		visual.apply_quality_setting(_graphics_quality())
		rain_handler.set_quality(visual.environment().quality_profile(
			visual.current_quality()))


## Where the rain should sit. The mowing scene passes its camera.
func set_weather_tracking_target(node: Node3D) -> void:
	rain_handler.set_tracking_target(node)
	if visual != null:
		visual.set_tracking_target(node)


## WHICH REGION THIS SCENE IS IN. Presentation only: it scales how far the
## player can see and nothing else. See `ACARegionalContext.air_layer()`.
func set_weather_region(region: int) -> void:
	if visual != null:
		visual.set_region(region)


## Tell the environment where ground level is, for height fog. See the note on
## `ACASky3DEnvironment.ground_reference`.
func set_weather_ground_reference(world_y: float) -> void:
	if visual != null:
		visual.set_ground_reference(world_y)
	if rain_handler != null and rain_handler.rig != null:
		rain_handler.rig.ground_offset = world_y - rain_handler.global_position.y


func _process(_delta: float) -> void:
	if not follow_world_clock:
		return
	var clock := get_node_or_null(^"/root/WorldClock")
	if clock == null:
		return
	# A dev time-of-day tween is a deliberate override; leave it alone while it
	# is running.
	if time_of_day_tween != null and time_of_day_tween.is_valid():
		return
	set_time_of_day_normalized(clock.call(&"hour_of_day"))


func set_audio_player(player: AudioStreamPlayer):
	rain_handler.set_ambience_sound_player(player)


func _____TIME____():
	pass


func set_time_of_day_normalized(value: float) -> void:
	## note this function expects a value range 0-23.99 passed in
	##
	## `sky3d.current_time` is NOT written here. The environment adapter owns
	## it — `set_time_of_day()` forwards the hour to Sky3D itself, so the sun
	## position and the composed look can never come from two different places.
	current_time_of_day = clampf(value, 0.0, 23.99)
	if visual != null:
		visual.set_state(current_weather_preset, current_time_of_day)
	else:
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


## Named time-of-day targets. `Morning` was added with the visual adapter.
## Hours chosen against the MEASURED sun curve for this Skydome (up from about
## 06:35 to 17:05) - see the anchor note in weather_visual_adapter.gd.
const TIME_PRESET_HOURS := {
	"Morning": 8.2,
	"Day": 12.0,
	"Evening": 16.3,
	"Night": 22.0,
}


func apply_time_of_day_preset(preset_name: String) -> void:
	if not TIME_PRESET_HOURS.has(preset_name):
		push_warning("preset_manager: unknown time preset %s" % preset_name)
		return
	current_time_preset = preset_name
	smooth_set_time_of_day(TIME_PRESET_HOURS[preset_name])


func _____WEATHER_____():
	pass


## WHETHER THE RAIN RIG RUNS IS ONE QUESTION, asked of `ACAWorldClock`, so
## adding a sky never means editing a `match` in here again. HOW HARD it rains
## is composed by the environment adapter from the weather profile's
## `rain_intensity`, which is where a look belongs.
func apply_weather_preset(preset_name: String) -> void:
	if not ACAWorldClock.WEATHER_PRESETS.has(preset_name):
		push_warning("preset_manager: unknown weather preset %s" % preset_name)
		preset_name = "Clear"
	current_weather_preset = preset_name

	if ACAWorldClock.is_rain(preset_name):
		rain_handler.start_rain()
	else:
		rain_handler.stop_rain()

	if visual != null:
		visual.set_state(current_weather_preset, current_time_of_day)


## Scene load and save restore: put the world on screen with no transition, so
## the first frame is already correct instead of easing in from the last scene.
func apply_world_state_immediate(weather_preset_name: String, hour: float) -> void:
	current_weather_preset = weather_preset_name
	current_time_of_day = clampf(hour, 0.0, 23.99)
	if visual == null:
		sky3d.current_time = current_time_of_day

	if ACAWorldClock.is_rain(weather_preset_name):
		rain_handler.start_rain()
	else:
		rain_handler.stop_rain_instant()

	if visual != null:
		visual.apply_immediate(current_weather_preset, current_time_of_day)


func get_and_set_mower_global_position(mower_global_position: Vector3):
	rain_handler.set_mower_global_position(mower_global_position)
