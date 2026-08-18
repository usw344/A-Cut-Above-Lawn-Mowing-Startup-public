@tool
class_name VegetationWindInstance
extends Node3D

## Non-destructively applies a saved wind material to every mesh below this
## wrapper. The imported GLTF/GLB remains untouched and can be reimported safely.

@export var wind_material: ShaderMaterial:
	set(value):
		wind_material = value
		_queue_apply_material()

@export_range(0.0, 2.0, 0.01, "or_greater") var wind_cull_margin := 0.35:
	set(value):
		wind_cull_margin = maxf(value, 0.0)
		_queue_apply_material()


func _ready() -> void:
	_apply_material(self)


func _queue_apply_material() -> void:
	if is_inside_tree():
		_apply_material.call_deferred(self)


func _apply_material(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_override = wind_material
		mesh_instance.extra_cull_margin = wind_cull_margin
	for child in node.get_children():
		_apply_material(child)
