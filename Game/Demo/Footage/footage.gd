extends Node3D

"""

A demo scene designed to get the best possible footage for trailors and capsulate art. 

"""
@onready var custom_gridmap_object:Custom_Gridmap = $"Custom Gridmap"
@onready var mower = $"Small Gas Mower"
func _ready() -> void:
	custom_gridmap_object.test_custom_gridmap(256)
	
func _process(delta: float) -> void:
	pass
	
