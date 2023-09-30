extends Node3D
class_name Multi_Mesh_Chunk
## handle the multi_mesh for this region
## auto loads the both the correct type and correct LOD of grass as mower moves

var chunk_coord:Vector2 = Vector2() # global position (x, 0 ,z)
var chunk_size:int = 100 # this is a base estimate

var chunk_grid_coord:Vector2 # grid version of global position

# by storing each instance to coord we can handle collision and instances
var instance_to_position_map:Dictionary
var mowed_grass_instance:Array = []

# what is the current mesh that this chunk is using
var mesh:Mesh
var multimesh_instance:MultiMeshInstance3D = MultiMeshInstance3D.new()







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
	
	mesh = load("res://Assets/MultiMesh_Grass/Extracted Meshes/Mowed/Mowed High LOD_050_2.mesh")
	# setup the LOD 
#	use_colours_bool = test_with_color
	

	
	multimesh_instance.multimesh = make_multimesh()
	

func set_and_check_lod():
	if model.get_multi_mesh_LOD(chunk_grid_coord) != lod:
		lod = model.get_multi_mesh_LOD(chunk_grid_coord) # update to new LOD level
		return true
	
	return false


func make_multimesh() ->MultiMesh:
#	print("For coord: " + str(chunk_coord) + " LOD: " + str(lod))
	var multi_mesh:MultiMesh = MultiMesh.new()
	var points:Array = []
	
	# from chunk coord to chunk_coord + size make a multi_mesh

	
	for x in range(0,chunk_size, 1): # remeber that indivial instances are in LOCAL space with relation to multimeshInstance3D
		for z in range(0,chunk_size , 1): # so it is 0-size for each mm_instance and then each mm_instance3D is moved
			points.append(Vector3(x, 0, z))

	multi_mesh.set_mesh(mesh)
	multi_mesh.set_transform_format(MultiMesh.TRANSFORM_3D)
#	multi_mesh.set_use_colors(use_colours_bool)
	multi_mesh.set_instance_count(len(points)) # make as many instances as there are points

#	var a_color = Color(randf(), randf(), randf())

	for i in range(multi_mesh.instance_count):
		# get the point and translate it over to chunk space
		var point:Vector3 = points[i]
#		point.x *= i+1.5
		
		# set the information of this instance
		var scale_factor:float = 3
		var basis_vector = Basis()*scale_factor # can tweak grass scaling
		
#		basis_vector = basis_vector.rotated(Vector3(0,0,1),randf_range(12.5,90.0))
#		basis_vector = basis_vector.rotated(Vector3(0,1,0),90)
		var transform_vector = Transform3D(basis_vector, point)
		
		
		
#		transform_vector = transform_vector.scaled(Vector3(scale_factor,scale_factor,scale_factor))
#		if use_colours_bool:
#			multi_mesh.set_instance_color(i,a_color)
		
		multi_mesh.set_instance_transform(i, transform_vector)
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
