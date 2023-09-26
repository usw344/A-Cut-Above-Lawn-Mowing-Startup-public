extends Node3D

@onready var gridmap:GridMap = $"Mowing Area/Grass Grid"

var width_and_length:int = 32
var total_grid_width_length:int # calcuated in ready function

# Called when the node enters the scene tree for the first time.
func _ready():
	
	
	set_inital_positions_and_sizes()

	make_inital_gridmap()
	
	#connect signal for collision
	$"Small Gas Mower".collided.connect(handle_collision)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	$"Small Gas Mower".position.y = 0
#	print($"Small Gas Mower".position)

func make_inital_gridmap():
	"""
	Based on the given grid location
	make the inital gridmap.
	""" 
	# for gridmap cell 2, the reference is 2m-> 1 grass
	# 800m -> 400 distance
	
	for x in range(-total_grid_width_length, total_grid_width_length, 1):
		for z in range(-total_grid_width_length, total_grid_width_length, 1):
			gridmap.set_cell_item(Vector3i(x, 0, z), 3)
	
func update_gridmap():
	"""
	Based on the current gridmap update any cells that need to be updated
	"""

	pass

func set_inital_positions_and_sizes():
	"""
	Set the position of the mower in the level and set the position of the start zone based on level 
	width and height
	this function can be used with a saved mower position or the default
	"""
	# set the width and length of the mowing area
	var multiply_width_length_by_2 = width_and_length*2 # since in code it does not auto scale to twice the value
	$"Mowing Area/MeshInstance3D".mesh.size = Vector2(multiply_width_length_by_2,multiply_width_length_by_2)
	$"Mowing Area/CollisionShape3D".shape.size = Vector3(multiply_width_length_by_2,1,multiply_width_length_by_2)

	# calculate how much grass is needed
	total_grid_width_length = int(width_and_length/2)
	
	# set the start position area
	var pos:Vector3 = Vector3()
	pos.x += width_and_length + ($"Start Area/MeshInstance3D".mesh.size.x/2)
	pos.y = 0
	$"Start Area".position = pos
	
	# set the mower to the start position
	$"Small Gas Mower".position = $"Start Area".position

func handle_collision(collision_array:Array):
	for collision in collision_array:
		if collision.get_collider().name != "Grass Grid":
			continue

		var position_of_collision:Vector3 = collision.get_position()
		
		var grid_position_of_collision:Vector3i = Vector3i(position_of_collision.x,0,position_of_collision.z)   

		grid_position_of_collision = $"Mowing Area".to_local(grid_position_of_collision)


		gridmap.set_cell_item(grid_position_of_collision,-1)

