extends Node3D
class_name preset_manager
@export var custom_gridmap_path: NodePath

var current_time_of_day: float = 0.5
var current_time_preset: String = "day"
var current_weather_preset: String = "clear"
var current_quality_preset: String = "high"

@onready var custom_gridmap = get_node_or_null(custom_gridmap_path)
@onready var sky3d = $Sky3D
@onready var time_of_day_node = $Sky3D/TimeOfDay

func set_time_of_day_normalized(value: float) -> void:
	current_time_of_day = clamp(value, 0.0, 1.0)

	# Replace this line with however Sky3D expects time to be set
	if time_of_day_node.has_method("set_time"):
		time_of_day_node.set_time(current_time_of_day)

func apply_time_preset(preset_name: String) -> void:
	current_time_preset = preset_name

	match preset_name:
		"day":
			set_time_of_day_normalized(0.35)
		"night":
			set_time_of_day_normalized(0.90)
		"sunrise":
			set_time_of_day_normalized(0.20)
		"sunset":
			set_time_of_day_normalized(0.75)

func apply_weather_preset(preset_name: String) -> void:
	current_weather_preset = preset_name

	match preset_name:
		"clear":
			pass
		"fog":
			pass
		"rain":
			pass

func apply_quality_preset(preset_name: String) -> void:
	current_quality_preset = preset_name

	if custom_gridmap and custom_gridmap.has_method("set_quality_preset"):
		custom_gridmap.call("set_quality_preset", preset_name)

	if custom_gridmap and custom_gridmap.has_method("regenerate_environment"):
		custom_gridmap.call_deferred("regenerate_environment")
