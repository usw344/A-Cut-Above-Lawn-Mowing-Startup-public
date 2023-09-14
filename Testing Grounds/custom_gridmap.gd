extends Node3D

var width_and_length:int = 200
var total_grid_width_length:int # calcuated in ready function

# Called when the node enters the scene tree for the first time.
func _ready():
	set_inital_positions_and_sizes()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

## custom gridmap variables
var grid_length:int 
var grid_width:int

var batching_size:int # how many meshes togather in a multimesh

# for the given widthxlength make a grid with a key represendting global coord of that item
var grid_mapping:Dictionary = {} # key = 
## custom gridmap api functions
func set_grid_paramters(width:int, length:int, mesh_library:Mesh_Library,batching:int = 16):
	grid_length = length
	grid_width = width
	batching_size = batching # default is 16

func set_gridspace_item(item:Grass_Grid_Item):
	"""
	Set a item into gridmap. Provide a grass grid item with at least the position and mesh_id set
	
	CONDITION: mesh_id that is set should match what is the library_object
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
