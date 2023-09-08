extends Node3D

@onready var gridmap:GridMap = $StaticBody3D/GridMap 

var width_and_length:int = 500
var total_grid_width_length:int = 500

# Called when the node enters the scene tree for the first time.
func _ready():
	make_inital_gridmap()
	
	# set the width and length of the area
	var multiply_width_length_by_2 = width_and_length*2
	$StaticBody3D/MeshInstance3D.mesh.size = Vector2(multiply_width_length_by_2,multiply_width_length_by_2)
	$StaticBody3D/CollisionShape3D.shape.size = Vector3(multiply_width_length_by_2,1,multiply_width_length_by_2)

	# calculate how much grass is needed
	total_grid_width_length = int(width_and_length/2)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func make_inital_gridmap():
	"""
	Based on the given grid location
	make the inital gridmap.
	""" 
	# for gridmap cell 2, the reference is 2m-> 1 grass
	# 800m -> 400 distance
	
	for x in range(-total_grid_width_length, total_grid_width_length, 1):
		for z in range(-total_grid_width_length, total_grid_width_length, 1):
			gridmap.set_cell_item(Vector3i(x, 0, z), 2)
	
func update_gridmap():
	"""
	Based on the current gridmap update any cells that need to be updated
	"""
	pass
