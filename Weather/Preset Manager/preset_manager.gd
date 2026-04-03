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
@onready var time_of_day_node = $Sky3D/TimeOfDay

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
			pass
		"Foggy":
			pass
		"Rain":
			pass
