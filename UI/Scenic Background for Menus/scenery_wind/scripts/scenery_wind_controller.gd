@tool
class_name SceneryWindController
extends Node

## A deliberately small shared wind controller. It updates saved ShaderMaterial
## resources directly, avoiding project-wide shader globals or editor-only state.

@export_group("Shared Breeze")
@export var wind_direction := Vector2(1.0, 0.25):
	set(value):
		wind_direction = value
		_queue_apply_wind()

@export_range(0.0, 2.0, 0.01, "or_greater") var tree_wind_speed := 0.55:
	set(value):
		tree_wind_speed = maxf(value, 0.0)
		_queue_apply_wind()

@export_group("Trees")
@export_range(0.0, 0.25, 0.001, "or_greater") var tree_wind_strength := 0.055:
	set(value):
		tree_wind_strength = maxf(value, 0.0)
		_queue_apply_wind()

@export_range(0.0, 0.15, 0.001, "or_greater") var tree_gust_strength := 0.025:
	set(value):
		tree_gust_strength = maxf(value, 0.0)
		_queue_apply_wind()

@export_group("Grass")
@export_range(0.0, 0.4, 0.001, "or_greater") var grass_wind_strength := 0.11:
	set(value):
		grass_wind_strength = maxf(value, 0.0)
		_queue_apply_wind()

@export_range(0.0, 0.2, 0.001, "or_greater") var grass_gust_strength := 0.035:
	set(value):
		grass_gust_strength = maxf(value, 0.0)
		_queue_apply_wind()

@export_group("Saved Materials")
@export var tree_materials: Array[ShaderMaterial] = []:
	set(value):
		tree_materials = value
		_queue_apply_wind()

@export var grass_materials: Array[ShaderMaterial] = []:
	set(value):
		grass_materials = value
		_queue_apply_wind()


func _ready() -> void:
	_apply_wind()


func _queue_apply_wind() -> void:
	if is_inside_tree():
		_apply_wind.call_deferred()


func _apply_wind() -> void:
	var shared_direction := wind_direction
	if shared_direction.length_squared() < 0.0001:
		shared_direction = Vector2.RIGHT
	else:
		shared_direction = shared_direction.normalized()

	for material in tree_materials:
		_apply_common_parameters(material, shared_direction)
		if material != null:
			material.set_shader_parameter("wind_strength", tree_wind_strength)
			material.set_shader_parameter("gust_strength", tree_gust_strength)

	for material in grass_materials:
		_apply_common_parameters(material, shared_direction)
		if material != null:
			material.set_shader_parameter("wind_strength", grass_wind_strength)
			material.set_shader_parameter("gust_strength", grass_gust_strength)


func _apply_common_parameters(material: ShaderMaterial, direction: Vector2) -> void:
	if material == null:
		return
	material.set_shader_parameter("wind_direction", direction)
	material.set_shader_parameter("wind_speed", tree_wind_speed)
