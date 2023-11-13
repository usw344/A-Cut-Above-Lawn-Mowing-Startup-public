extends Node3D

var width_and_length:int = 1000 # remember this gets multiplied by 2
var total_grid_width_length:int # calcuated in ready function

var load_save_test_mode:int = -1 # save mode (save a game before testing loading)
func _ready():
	set_inital_positions_and_sizes()
	
	# test the gridmap 
	test_custom_gridmap()
#	test_save_loading()

func _process(delta):
#	test_save_loading()
	pass

func test_custom_gridmap() ->void:
	# setup the meshlibrary
#	var grid_size:int = 22*16
	var grid_size:int = 32
	set_grid_paramters(grid_size,grid_size,16)
	make_grid()


## custom gridmap variables
var grid_length:int 
var grid_width:int

var batching_size:int # how many meshes togather in a multimesh

# for the given widthxlength make a grid with a key represendting global coord of that item
var grid_mapping:Dictionary = {} # key = 

# store the data of chunks and coordinates in different ways
var chunk_to_coordinates_dictionary:Dictionary = {}
var coordinates_to_chunk_dictionary:Dictionary = {}

var chunk_id_to_chunk_dictionary:Dictionary = {}

## custom gridmap api functions
func set_grid_paramters(width:int, length:int,batching:int = 16) ->void:
	"""
	Setup the grid outline. This function replaces the _init() function.
	Call this function before using make_grid_function()
	
	width: width of the total grid
	length: length of total grid
	
	mesh_list: Mesh_List object containing somes meshes
	batching: how many meshes each multimesh instance will have
	"""
	grid_length = length
	grid_width = width
	batching_size = batching # default is 16 (so 4x4 mesh instances)

func set_gridspace_item(item:Grass_Grid_Item) ->void:
	"""
	Set a item into gridmap. Provide a grass grid item with at least the position and mesh_id set
	
	CONDITION: mesh_id that is set should match what is the library_object
	"""
	var position_vector:Vector3i = item.get_grid_position()
	
	# check if this a valid point in the given grid
	grid_mapping[position_vector] = item

var global_array_of_coordinates:Array = []
func make_grid() ->void:
	"""
	Based on all set values render the multimesh instances to their location based on 
	INITAL grid items values and placements.
	
	Note this function remakes the whole grid. If changes are to only a section
	call calling update_grid() instead as this function will revert to the orignal grid
	
	NOTE 1: this functin has the possibility of being a heavy computation.
	So, use only when needed
	
	Note 2: If this function is used before any gridspace item is set
	nothing will be rendered.
	
	Note 3: if width and height values are not set. This function will print error message
	and output to error log (todo this)
	"""
	# get all possibile coordinates first
	var array_of_coordinates:Array = make_an_array_of_arrays_of_coordinates()
	global_array_of_coordinates = array_of_coordinates
	# partition this into chunks
	var chunk_size_x:int = int(sqrt(batching_size)) #example batch 16 = 4x4 which is sqrt(16)
	var chunks_size_y:int = chunk_size_x
	var array_of_partitioned_chunks:Array = partition_grid_into_chunks(array_of_coordinates, chunk_size_x, chunks_size_y)

	# now fill those dictionaries (both mapping chunks to coords and coords to chunk)
	fill_dictionaries(array_of_partitioned_chunks)
	
	# at this point we have the base grid information ready. Now begin rendering 
	# make the grid of multimesh chunks 
	fill_multimesh_grid()

func fill_multimesh_grid() ->void:
	# find the grid coords of the multimesh chunks
	var grid_coords_of_chunks:Array
	var chunk_size_x: int = sqrt(batching_size) *2 #example batch 16 = 4x4 which is sqrt(16)
	var chunk_size_z: int = sqrt(batching_size) *2 # and we do *2 since in the loop we go from negative to positive. so either do *2 now or /2 later

	for z_coord in range(int(-grid_length/chunk_size_x ), int(grid_length/ chunk_size_z ) , 1  ):
		for x_coord in range(int(-grid_width/ chunk_size_x ) , int(grid_width/ chunk_size_z ), 1):
			grid_coords_of_chunks.append( Vector2i(x_coord, z_coord))

	# get the grid ids in a list (this will be passed into add_mm and used to get the cords)
	var grid_chunk_ids:Array = chunk_to_coordinates_dictionary.keys()
	# order them from largest to smallest. Since the for loop will pop off the end
	# this will in effect mean the list is process 0 -> n instead of n -> 
	# but poping at end is less intenstive operation wise
	grid_chunk_ids.sort_custom(func(a, b): return a > b) # decending order 
	grid_coords_of_chunks.reverse()

	for coord in grid_coords_of_chunks:
		var id:int = grid_chunk_ids.pop_back()
		chunk_id_to_chunk_dictionary[id] = add_multimesh_chunk(coord,sqrt(batching_size),id)
		chunk_id_to_chunk_dictionary[id].generate_collision()


func add_multimesh_chunk(coord:Vector2i,chunk_size,chunk_id:int,test=false) ->Multi_Mesh_Chunk:
	"""
	sub function to add a multimesh chunk. 
	
	CURRENTLY using multimesh chunk system.
	TODO: change to using rendering server directly
	"""
	var a_chunk:Multi_Mesh_Chunk = Multi_Mesh_Chunk.new()
	a_chunk.setup_chunk(coord,chunk_size,chunk_to_coordinates_dictionary[chunk_id],chunk_id)
	var pos = a_chunk.get_chunk_global_position()
	
	# since there can be many different multimeshes per chunk add them all
	var multimeshe_instances:Array = a_chunk.get_for_rendering()
	for mm_instance in multimeshe_instances:
		add_child(mm_instance)
		mm_instance.position = pos

	return a_chunk
	
func fill_dictionaries(grid_partitioned_in_grid:Array) ->void:
	"""
	Fill out dicts of chunk id to coord and coord to chunk id maping 
	# tested
	"""
	# now convert these into a dictionary key = chunk_number value=array of coordinates
	var i:int = 0 # this is the chunk id
	grid_partitioned_in_grid.reverse()
	for chunk_arr in grid_partitioned_in_grid:
		chunk_to_coordinates_dictionary[i] = chunk_arr
		
		# also store it as a dictionary key = coordinate value = chunk_number
		for coord in chunk_arr:
			coordinates_to_chunk_dictionary[coord] = i
		i += 1

func make_an_array_of_arrays_of_coordinates() ->Array:
	"""
	will return an array of array where each array contains Vector3i position coordintes for the whole grid
	[ (-1,0,1), (0,0,1),  (1,0,1)]
	[ (-1,0,0), (0,0,0,), (1,0,0)]
	[ (-1,0,-1), (0,0,-1), (1,0,-1)]
	"""
	# make an empty 2d array  [ x[yyy], x2[yyy]...   ]
	var left: int = -int(grid_width/2)
	var right: int = int(grid_width/2)
	
	var left_z: int = -int(grid_length/2)
	var right_z: int = int(grid_length/2)
	
	var grid:Array = []
	for z in range(left_z,right_z,1):
		var row:Array = []
		for x in range(left, right, 1):
			row.append( x )
		grid.append(row)
	# at this point we have 
	#[-16, -15 .... 15, 16]
	#[-16, -15 .... 15, 16]
	#[-16, -15 .... 15, 16]
	# assuming a grid of 16x16
	# now convert to Vector3i grid positions
	var grid_positions:Array = []
	# go from negative to position for ordering ( so that left side is negative)
	for z in range(int(grid_length/2), -int(grid_length/2), -1): 
		var row:Array = []
		for x in range(len(grid[z])):
			var pos = Vector3i(grid[z][x],0,z)
			row.append(pos)
		grid_positions.append(row)
	
	var first_half:Array = grid_positions.slice(0,len(grid_positions)/2)
	var second_half:Array = grid_positions.slice(len(grid_positions)/2, len(grid_positions))
	
	return grid_positions

func mow_item(item_name:String) ->void:
	"""
	Expect an name object in form 'chunk_id,x,y,z'
	"""
	var vector4i:Vector4i = str_to_vector4i(item_name) # break the item name into the vector4i format
	var chunk_id:int = vector4i.x # chunk_id extracted from the item name in Vector4i form
	var coord_local_to_multimesh:Vector3i = Vector3i(vector4i.y,vector4i.z,vector4i.w)

	var chunk_to_remove_item_from:Multi_Mesh_Chunk = chunk_id_to_chunk_dictionary.get(chunk_id)

	# remove item
	chunk_to_remove_item_from.mow_item_by_name(item_name,coord_local_to_multimesh)


func str_to_vector4i(str) -> Vector4i:
	""" Take in a string in format ' (x,y,z,w)  ' and return that as a Vector4i """
	var vector4i:Vector4i = Vector4i()
	var vec_arr = str.split(",")
	vector4i.x = vec_arr[0].to_int()
	vector4i.y = vec_arr[1].to_int()
	vector4i.z = vec_arr[2].to_int()
	vector4i.w = vec_arr[3].to_int()

	return vector4i

func partition_grid_into_chunks(grid: Array, chunk_size_x: int, chunk_size_y: int) -> Array:
	"""
	Take the grid of coordiante and partition it into chunks. 
	"""
	var chunks := []
	
	for y in range(0, grid.size(), chunk_size_y):
		for x in range(0, grid[0].size(), chunk_size_x):
			var chunk:Array = []
			for j in range(y, min(y + chunk_size_y, grid.size())):
				var row := []
				for i in range(x, min(x + chunk_size_x, grid[0].size())):
					row.append(grid[j][i])
				chunk.append(row)
			chunks.append(chunk)
	
	# since each chunk is currently represented in array of arrays 
	# we can combine them from  [ [x,x,x], [y,y,y] ] -> [x,x,x,y,y,y] where x,y are Vector3
	var output_chunks:Array = []
	for chunk in chunks:
		var combined_row:Array
		for arr in chunk:
			combined_row += arr
		output_chunks.append(combined_row)
	return output_chunks

func custom_grid_map_collision_handler(collision_objects:Array) -> void:
	for collision in collision_objects:
		var name_of_collision_object  = collision.get_collider().name
		if name_of_collision_object == "Mowing Area" or name_of_collision_object == "Start Area":
			continue
		else:
			mow_item(name_of_collision_object)



	
## testing ground functions
func set_inital_positions_and_sizes() ->void:
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
	## for testing
	$"Small Gas Mower".position = Vector3(-10,0,5)


# test this function with the following data
var path = "C:/Users/usw87/Desktop/Godot outside of project store/output_grid2.csv"
func saveArrayAsCSV(dataArray, filePath):

	var file = FileAccess.open(filePath, 2)
	# Open the file for writing
	if file!= null:
		for row in dataArray:
			var rowString = ""
			for item in row:
				# convert to format that can be handled in csv (, inside the 
				var str_compat_form:String = ""
				for char in str(item):
					if char == ",":
						str_compat_form += ":"
					else:
						str_compat_form += char
				rowString += str_compat_form + ","
#				rowString += """ " """ + str(item).c_escape() + """ " """ + ","
				
			rowString += "\n"

			file.store_string(rowString)
		file.close()
		print("CSV file saved to:", filePath)
	else:
		print("Failed to open the file for writing.")

#var chunk_to_coordinates_dictionary:Dictionary = {}
#var coordinates_to_chunk_dictionary:Dictionary = {}

func save_object() ->Dictionary:
	"""
	Save this instance of the custom gridmap data into a form that can be loaded later
	
	"""
	var save_dictionary:Dictionary = {} ## main save dictionary
	# first grab each multimeshinstance and save its state
	var chunk_save_objects:Dictionary = {}
	for id in chunk_id_to_chunk_dictionary.keys():
		chunk_save_objects[id] = chunk_id_to_chunk_dictionary[id].save_object()
	
	# also save the grid params
	var grid_params:Dictionary = {"grid_width":grid_width,"grid_length":grid_length,"batching_size":batching_size}

	# add all these save objects to the save_dictionary
	save_dictionary["chunk_save_objects"] = chunk_save_objects
	save_dictionary["grid_params"] = grid_params
	save_dictionary["chunk_to_coordinates_dictionary"] = chunk_to_coordinates_dictionary
	save_dictionary["coordinates_to_chunk_dictionary"] = coordinates_to_chunk_dictionary
	return save_dictionary
	
func load_object(data:Dictionary) ->void:
	"""
	Take a dictionary contaning a dictionary packed by custom_gridmap.save_object() and 
	loads current custom_gridmap object with the same data
	
	params:
	"""
	var grid_params:Dictionary = data["grid_params"]
	grid_width = grid_params["grid_width"]
	grid_length = grid_params["grid_length"]
	batching_size = grid_params["batching_size"]
	
	chunk_to_coordinates_dictionary = data["chunk_to_coordinates_dictionary"]
	coordinates_to_chunk_dictionary = data["coordinates_to_chunk_dictionary"]
	
	# now resetup the multimesh chunks
	var multimesh_chunk_saves:Dictionary = data["chunk_save_objects"]
	
	for mm_chunk_data_id in multimesh_chunk_saves:
		var mm_chunk_data = multimesh_chunk_saves[mm_chunk_data_id]
		var mm_chunk:Multi_Mesh_Chunk = Multi_Mesh_Chunk.new()
		mm_chunk.load_object(mm_chunk_data)
		
		# now render these
		var multimeshe_instances:Array = mm_chunk.get_for_rendering()
		var pos = mm_chunk.get_chunk_global_position()
		for mm_instance in multimeshe_instances: # render all multimeshes in it
			add_child(mm_instance)
			mm_instance.position = pos
		mm_chunk.generate_collision() # add collision shapes in 
		chunk_id_to_chunk_dictionary[mm_chunk_data_id] = mm_chunk

func test_save_loading():
	
	if load_save_test_mode == 0:
		if Input.is_action_just_pressed("Save"):
			var file = FileAccess.open("res://Saves/testing/load_save_testing.txt",FileAccess.WRITE)
			var data_to_save:Dictionary = save_object()
			print("saving game")			
			var data:Dictionary = save_object()

			file.store_var(data,true) # store the file
			file.close()
	else: # in load mode
		var file = FileAccess.open("res://Saves/testing/load_save_testing.txt",FileAccess.READ)
		load_save_test_mode = 0 # prevent reloading
		var data_loaded = file.get_var(true)
		load_object(data_loaded)
