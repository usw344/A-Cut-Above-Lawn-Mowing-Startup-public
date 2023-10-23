extends Node3D
class_name Multi_Mesh_Chunk
## handle the multi_mesh for this region
## auto loads the both the correct type and correct LOD of grass as mower moves

var chunk_coord:Vector2 = Vector2() # global position (x, 0 ,z)
var chunk_size:int = 100 # this is a base estimate

var chunk_grid_coord:Vector2 # grid version of global position


var global_item_position_to_instance_position:Dictionary = {}

# what is the current mesh that this chunk is using
var mesh:Mesh
var multimesh_instance_mowed:MultiMeshInstance3D = MultiMeshInstance3D.new()
var multimesh_instance_unmowed:MultiMeshInstance3D = MultiMeshInstance3D.new()


var multimesh_instances_coords_mowed:Array = []
var multimesh_instances_coords_unmowed:Array = []


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

# TODO move this to the model
var grass_collision_shape:Resource = load("res://Assets/MultiMesh_Grass/Extracted Meshes/Unmowed/Unmowed Grass Collision Shape polygon.tres")
var mowed_grass_mesh:Mesh=  load("res://Assets/MultiMesh_Grass/Resized Meshes/Mowed_Grass_OBJ.obj")
var unmowed_grass_mesh:Mesh = load("res://Assets/MultiMesh_Grass/Resized Meshes/Unmowed_Grass_OBJ.obj")


var rendered:bool = false
var collisions_static_bodies:Dictionary # key = name # value = staticbody
var collision_global_to_local_coord_reference:Dictionary # key = global, # value = local
var chunk_id:int

func generate_collision():
	"""
	Make individual collison shapes for each item instance
	Precondition 1 : the multimesh must be inside the scene
	Precondition 2 : the setup_chunk function must have been called
	"""
	for coordinate in multimesh_instances_coords_unmowed:
		var static_body:StaticBody3D = StaticBody3D.new()
		var collision_body:CollisionShape3D = CollisionShape3D.new()
		multimesh_instance_unmowed.add_child(static_body)
		
		static_body.add_child(collision_body)
		collision_body.shape = grass_collision_shape
		var coord:Vector3i = coordinate
#		var global_coordinate:Vector3i = Vector3i(-8,0,8)
		
		static_body.position = coord
		static_body.scale*= 3
		
		var str:String = get_str_represenation_of_collision_data(coord)
		static_body.name = str
		
		collisions_static_bodies[str] = static_body

func str_to_vector4i(str) -> Vector4i:
	""" Take in a string in format ' (x,y,z,w)  ' and return that as a Vector4i """
	var vector4i:Vector4i = Vector4i()
#	var vec_str:String = str.substr(1, str.length() - 2)
	var vec_arr = str.split(",")
	vector4i.x = vec_arr[0].to_int()
	vector4i.y = vec_arr[1].to_int()
	vector4i.z = vec_arr[2].to_int()
	vector4i.w = vec_arr[3].to_int()

	return vector4i

func get_str_represenation_of_collision_data(pos:Vector3i) ->String:
	"""
	Return a string in format (chunk_id, x ,y ,z)
	"""
	var retr_str:String = ""
	retr_str += (str(chunk_id)) + ","
	retr_str += str(pos.x) + ","
	retr_str += str(pos.y) + ","
	retr_str += str(pos.z) + ","

	
	return retr_str

func setup_chunk(coord:Vector2, size:int,coords_of_items:Array,id:int):
	"""
	Function used to setup the chunk initally. NOTE this function should not be used
	if thsi chunk is being made from a load file.
	"""
	chunk_coord = coord*size ## bring them into screen space rather than grid

	chunk_size = size
	chunk_grid_coord = coord

#	mesh = mod.get_grass_mesh_for_lod(lod,false) # use mod not MODEL since model since model is not there
	fill_dictionaries(coords_of_items)
	
	# currently testing
	chunk_id = id
	
	# assume all are unmowed
	multimesh_instance_unmowed.multimesh = make_multimesh(multimesh_instances_coords_unmowed)
	multimesh_instance_mowed.multimesh = make_multimesh(multimesh_instances_coords_mowed)

func fill_dictionaries(global_coords_of_items:Array):
	# make the relevant references dictionaries to allow efficent access to individal meshes
	# map global coordinates to instance coordinates
	var i:int = 0
	# this is in local position so go from 0 to chunk_size (width and length). multiply by 2 to space them out more. Still same number of instances
	for x in range(0,chunk_size*2, 2): # remeber that indivial instances are in LOCAL space with relation to multimeshInstance3D
		for z in range(0,chunk_size*2 , 2): # so it is 0-size for each mm_instance and then each mm_instance3D is moved
			multimesh_instances_coords_unmowed.append(Vector3i(x, 0, z))
			global_item_position_to_instance_position[global_coords_of_items[i]] = Vector3i(x, 0, z)
			i+=1


func mow_item_by_name(item_name:String,coord:Vector3i):
	"""
	Pass in a item_name in the given format 'chunk_id,x,y,z' and
	since the collision function that uses this function already does the split
	to prevent duplicate work, also pass in the local to multimesh coord in Vector3i format
	"""
	# remove the static body
	if collisions_static_bodies.has(item_name): # prevent any case where staticbody is not there
		var static_body:StaticBody3D = collisions_static_bodies[item_name]
		multimesh_instance_unmowed.remove_child(static_body) # since the collision is the child of the multimesh instance
		collisions_static_bodies.erase(item_name)
		
		# update the multimesh
		multimesh_instances_coords_unmowed.erase(coord)
		multimesh_instances_coords_mowed.append(coord)
	else:
		return
	

	# regenerate the meshes
	multimesh_instance_mowed.multimesh = make_multimesh(multimesh_instances_coords_mowed,1)
	multimesh_instance_unmowed.multimesh = make_multimesh(multimesh_instances_coords_unmowed)

func make_multimesh(instance_coords:Array,type:int=0) ->MultiMesh:
	"""
	Generate a multimesh based on the given local position coordinates and an 
	optinal paramter to control what mesh is generated.
	
	0: unmowed grass
	1: mowed grass
	"""
#	print("For coord: " + str(chunk_coord) + " LOD: " + str(lod))
	var multi_mesh:MultiMesh = MultiMesh.new()

	if type == 0: # unmowed grass
		mesh = unmowed_grass_mesh
	elif type == 1: # mowed grass
		mesh = mowed_grass_mesh


	multi_mesh.set_mesh(mesh)
	multi_mesh.set_transform_format(MultiMesh.TRANSFORM_3D)
#	multi_mesh.set_use_colors(true)
	multi_mesh.set_instance_count(len(instance_coords)) # make as many instances as there are points

#	var a_color = Color(randf(), randf(), randf())

	for i in range(multi_mesh.get_instance_count()):
#		var a_color = Color(randf(), randf(), randf())
		# get the point and translate it over to chunk space
		var point:Vector3 = instance_coords[i]
		
		# set the information of this instance
		var scale_factor:float = 3
		var basis_vector = Basis()*scale_factor # can tweak grass scaling
		
		# TODO implement rotation for grass. (need to rotate the collision shape as well)
#		basis_vector = basis_vector.rotated(Vector3(0,0,1),randf_range(12.5,90.0))
#		basis_vector = basis_vector.rotated(Vector3(0,1,0),90)
		var transform_vector = Transform3D(basis_vector, point)
		
	
		multi_mesh.set_instance_transform(i, transform_vector)
#		multi_mesh.set_instance_color(i, a_color)
	
	return multi_mesh
	

func get_chunk_global_position() ->Vector3:
	return Vector3(chunk_coord.x, 0 , chunk_coord.y)


func get_for_rendering() -> Array:
	return [multimesh_instance_mowed,multimesh_instance_unmowed]

func save_object() ->Dictionary:
	"""
	Return information needed to reload this object using the multi_mesh_chunk.load_object()
	"""
	var data:Dictionary = {}
	var chunk_params:Dictionary = {
		"chunk_coord":chunk_coord,
		"chunk_grid_coord":chunk_grid_coord,
		"chunk_id":chunk_id,
		"chunk_size":chunk_size
	}
	
	
	# fill the dta object
	data["chunk_params"] = chunk_params
	data["mowed_coordinates"] = multimesh_instances_coords_mowed
	data["unmowed_coordinates"] = multimesh_instances_coords_unmowed
	
	data["global_to_instance_reference"] = global_item_position_to_instance_position
	
	return data
func load_object(data:Dictionary) -> void:
	"""
	Load the empty object using the data stored using the save_object() function>
	Note design decision made to NOT add collision using this function. That has to be done outside of this 
	class
	"""
	var chunk_param:Dictionary = data["chunk_params"]
	chunk_coord = chunk_param["chunk_coord"]
	chunk_grid_coord = chunk_param["chunk_grid_coord"]
	chunk_id = chunk_param["chunk_id"]
	chunk_size = chunk_param['chunk_size']
	
	multimesh_instances_coords_mowed = data["mowed_coordinates"]
	multimesh_instances_coords_unmowed = data["unmowed_coordinates"]

	global_item_position_to_instance_position = data["global_to_instance_reference"]
	
	# now load the multimeshes
	multimesh_instance_mowed.multimesh = make_multimesh(multimesh_instances_coords_mowed,1)
	multimesh_instance_unmowed.multimesh = make_multimesh(multimesh_instances_coords_unmowed)
