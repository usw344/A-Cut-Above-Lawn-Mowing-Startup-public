extends Node3D
class_name Grass_Grid_Item

"""
A data structure to hold 
"""

var grid_position:Vector3i # store the gridmap cell location
var type:String ## is this grass, rock, tree etc

var lod:int ## from lod 0-3 0 heighest 3 = lowest. -1 being empty



# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func _init(lod_val:int, type_val:String, grid_position_val:Vector3i):
	set_lod(lod_val)
	set_type(type_val)
	set_grid_position(grid_position_val)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func set_lod(l:int) ->void:
	lod = l
func get_lod()->int:
	return lod

func set_grid_position(pos:Vector3i) ->void:
	grid_position = pos
func get_grid_position() ->Vector3i:
	return grid_position
	
func set_type(s:String) ->void:
	type = s
func get_type() ->String:
	return type

