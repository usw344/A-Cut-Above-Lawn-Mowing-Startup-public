extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready():
	make_gridmap()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func make_gridmap():
	var gridmap:GridMap = $StaticBody3D/GridMap
	var total_distance_half:int = 120
	for x in range(-total_distance_half, total_distance_half, 1):
		for z in range(-total_distance_half, total_distance_half, 1):
			gridmap.set_cell_item(Vector3i(x, 0, z), 2)
	
