extends Node3D


@onready var custom_gridmap_object:Custom_Gridmap = $"Custom Gridmap"


func _physics_process(delta: float) -> void:
	pass
	
func _ready() -> void:
	custom_gridmap_object.test_custom_gridmap(256)
