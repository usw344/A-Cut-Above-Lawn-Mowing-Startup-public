extends Node3D
class_name Multi_Mesh_Chunk
## handle the multi_mesh for this region
## auto loads the both the correct type and correct LOD of grass as mower moves

var chunk_coord:Vector2 = Vector2() # global position (x, 0 ,z)
var chunk_size:int = 100 # this is a base estimate

var chunk_grid_coord:Vector2 # grid version of global position

# by storing each instance to coord we can handle collision and instances
var global_position_to_instance_mowed:Dictionary ={}
var global_position_to_instance_unmowed:Dictionary ={}

var global_coords_of_items:Array = [] 

var global_item_position_to_instance_position:Dictionary = {}

# what is the current mesh that this chunk is using
var mesh:Mesh
var multimesh_instance:MultiMeshInstance3D = MultiMeshInstance3D.new()



var multi_mesh_instances_coords:Array = []



# for testing this will assign a new color to the grass for this chunk
var use_colours_bool:bool = false

# store the current lod level (0 is highest, 3 is lowest)
var lod:int = 0


func _init():
	pass

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	# if this returns true that means a change in LOD has occured
#	update_chunk() # will remake the multimesh if chunk LOD level changes
	pass

func setup_chunk(coord:Vector2, size:int,coords_of_items:Array,test_with_color:bool = false, lod_level:int = 0):
	"""
	Function used to setup the chunk initally
	"""
	chunk_coord = coord*size ## bring them into screen space rather than grid

	chunk_size = size
	chunk_grid_coord = coord

#	mesh = mod.get_grass_mesh_for_lod(lod,false) # use mod not MODEL since model since model is not there
	fill_dictionaries(coords_of_items)
	
	# currently testing
	mesh = load("res://Assets/MultiMesh_Grass/Resized Meshes/Unmowed_Grass_OBJ.obj")

	multimesh_instance.multimesh = make_multimesh()

func fill_dictionaries(global_coords_of_items:Array):
	# make the relevant references dictionaries to allow efficent access to individal meshes
	# map global coordinates to instance coordinates
	var i:int = 0
	# from chunk coord to chunk_coord + size make a multi_mesh
	for x in range(0,chunk_size, 1): # remeber that indivial instances are in LOCAL space with relation to multimeshInstance3D
		for z in range(0,chunk_size , 1): # so it is 0-size for each mm_instance and then each mm_instance3D is moved
			multi_mesh_instances_coords.append(Vector3(x, 0, z))
			global_item_position_to_instance_position[global_coords_of_items[i]] = Vector3(x, 0, z)
			i+=1
	

func mow_item_by_global_position(global_position_coord:Vector3i):
	# get the instance postition of this item
	print(global_item_position_to_instance_position)
	var instance_position:Vector3 = global_item_position_to_instance_position.get(global_position_coord)
#	print("Global Coordinate is: " + str(global_position_coord) + " Local: " + str(instance_position) )
#	multi_mesh_instances_coords.erase(instance_position)
#	instance_position.y = 4
#	multi_mesh_instances_coords.append(instance_position)
	var index_pos:int = multi_mesh_instances_coords.find(instance_position)
	multi_mesh_instances_coords[index_pos].y += 4
	print(instance_position)
	global_item_position_to_instance_position[global_position_coord] = multi_mesh_instances_coords[index_pos]

	# remake the multimesh
	multimesh_instance.multimesh = make_multimesh()


func make_multimesh() ->MultiMesh:
#	print("For coord: " + str(chunk_coord) + " LOD: " + str(lod))
	var multi_mesh:MultiMesh = MultiMesh.new()


	multi_mesh.set_mesh(mesh)
	multi_mesh.set_transform_format(MultiMesh.TRANSFORM_3D)
#	multi_mesh.set_use_colors(true)
	multi_mesh.set_instance_count(len(multi_mesh_instances_coords)) # make as many instances as there are points

#	var a_color = Color(randf(), randf(), randf())

	for i in range(multi_mesh.instance_count):
#		var a_color = Color(randf(), randf(), randf())
		# get the point and translate it over to chunk space
		var point:Vector3 = multi_mesh_instances_coords[i]
#		point.x *= i+1.5
#		if point.y == 4:
#			point = Vector3(-8,4,8)
		
		# set the information of this instance
		var scale_factor:float = 3
		var basis_vector = Basis()*scale_factor # can tweak grass scaling
		
#		basis_vector = basis_vector.rotated(Vector3(0,0,1),randf_range(12.5,90.0))
#		basis_vector = basis_vector.rotated(Vector3(0,1,0),90)
		var transform_vector = Transform3D(basis_vector, point)
		
	
		multi_mesh.set_instance_transform(i, transform_vector)
#		multi_mesh.set_instance_color(i, a_color)
	# testing if local cordinates are the same as inputed
#	var arri:Array = []
#
#	for z in range(multi_mesh.get_instance_count()):
#		var transform_var:Transform3D = multi_mesh.get_instance_transform(z)
#		arri.append(transform_var.origin)
#	print(arri)
	
	return multi_mesh
	

func get_chunk_global_position() ->Vector3:
	return Vector3(chunk_coord.x, 0 , chunk_coord.y)

func update_chunk(model_var): # since this does not get added to scene tree pass in model
	"""
	If an LOD update needs to happen
	"""
	if lod != model.get_multi_mesh_LOD(chunk_grid_coord):
		lod = model.get_multi_mesh_LOD(chunk_grid_coord)
		mesh = model.get_grass_mesh_for_lod(lod,false)
		multimesh_instance.multimesh = make_multimesh()

func get_for_rendering() -> MultiMeshInstance3D:
	return multimesh_instance
