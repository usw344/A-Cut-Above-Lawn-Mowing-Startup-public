extends Node3D


func _ready() -> void:
	$Camera3D.look_at_from_position(Vector3(12.0, 7.5, 14.0), Vector3(0.0, 2.6, 0.0))
