extends Node3D

var width_and_length:int = 200
var total_grid_width_length:int # calcuated in ready function

var grass_collision_shape:Resource = load("res://Assets/MultiMesh_Grass/Extracted Meshes/Unmowed/Unmowed Grass Collision Shape polygon.tres")
# Called when the node enters the scene tree for the first time.
func _ready():
	set_inital_positions_and_sizes()
	
	# test the gridmap 
	test_custom_gridmap()
	test_collision_placement()
	# test vs built in gridmap
#	test_built_in_gridmap(true)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

var collision_name_to_object_dictionary:Dictionary = {}
func test_collision_placement() ->void:
	for row in global_array_of_coordinates:
		for coord in row:
			var static_body:StaticBody3D = StaticBody3D.new()
			var collision_body:CollisionShape3D = CollisionShape3D.new()
			
			add_child(static_body)
			static_body.add_child(collision_body)
			collision_body.shape = grass_collision_shape
			
			coord.z -= 1 # for some reason there needs to a correction 1 over to line up collision with grid
			static_body.global_position = coord
			static_body.scale*= 3
			
			# test to see which one is the name that is returned via collision
			# untranslate coord 
			coord.z += 1
			var name_var = str(coord)
			static_body.name = name_var
			collision_body.name = name_var
			
			collision_name_to_object_dictionary[name_var] = static_body
#	$Collision_Test.global_position = Vector3(-8,1,7)
#	$Collision_Test.scale *= 3

func test_custom_gridmap() ->void:
	# setup the meshlibrary
	var grid_size:int = 16
	set_grid_paramters(grid_size,grid_size,Mesh_List.new(),16)
	make_grid()
	
#	test_it() # test grid paritions
	
	# test saving as csv 
#	saveArrayAsCSV(data, path) #this function works

## custom gridmap variables
var grid_length:int 
var grid_width:int

var batching_size:int # how many meshes togather in a multimesh
var mesh_list: Mesh_List # a container of mesh references

# for the given widthxlength make a grid with a key represendting global coord of that item
var grid_mapping:Dictionary = {} # key = 

# store the data of chunks and coordinates in different ways
var chunk_to_coordinates_dictionary:Dictionary = {}
var coordinates_to_chunk_dictionary:Dictionary = {}

## custom gridmap api functions
func set_grid_paramters(width:int, length:int, a_mesh_list:Mesh_List,batching:int = 16) ->void:
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

	mesh_list = a_mesh_list
func set_gridspace_item(item:Grass_Grid_Item) ->void:
	"""
	Set a item into gridmap. Provide a grass grid item with at least the position and mesh_id set
	
	CONDITION: mesh_id that is set should match what is the library_object
	"""
	var position_vector:Vector3i = item.get_grid_position()
	
	# check if this a valid point in the given grid
	grid_mapping[position_vector] = item
	pass
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
#	print(len(array_of_coordinates))
#	saveArrayAsCSV(array_of_coordinates, path) # for testing
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

	for z_coord in range(-int(grid_length/chunk_size_x ), int(grid_length/ chunk_size_z ) , 1  ):
		for x_coord in range(-int(grid_width/ chunk_size_x ) , int(grid_width/ chunk_size_z ), 1):
			grid_coords_of_chunks.append( Vector2i(x_coord, z_coord))
	
	var chunks:Array  = []
#	print("Making these many instances: " + str( len(grid_coords_of_chunks) *12 ))

	# get the grid ids in a list (this will be passed into add_mm and used to get the cords)
	var grid_chunk_ids:Array = chunk_to_coordinates_dictionary.keys()
	# order them from largest to smallest. Since the for loop will pop off the end
	# this will in effect mean the list is process 0 -> n instead of n -> 
	# but poping at end is less intenstive operation wise
	grid_chunk_ids.sort_custom(func(a, b): return a > b) # decending order 

#	print("testing grid ids" + str(grid_chunk_ids))

#	print(grid_coords_of_chunks)
	for coord in grid_coords_of_chunks:
		chunks.append(add_multimesh_chunk(coord,sqrt(batching_size),grid_chunk_ids.pop_back())) #for now chunks are assumed to be same length and width
		

func add_multimesh_chunk(coord:Vector2i,chunk_size,chunk_id:int) ->Multi_Mesh_Chunk:
	"""
	sub function to add a multimesh chunk. 
	
	CURRENTLY using multimesh chunk system.
	TODO: change to using rendering server directly
	"""
	var a_chunk:Multi_Mesh_Chunk = Multi_Mesh_Chunk.new()
#	print(chunk_to_coordinates_dictionary[chunk_id])
	a_chunk.setup_chunk(coord,chunk_size,chunk_to_coordinates_dictionary[chunk_id],true)
	
	var pos = a_chunk.get_chunk_global_position()
	var mm = a_chunk.get_for_rendering() # returns a multimesh instance and renders it, TODO change to Rendering server
	add_child(mm)
	mm.position = pos
	return a_chunk
	
func fill_dictionaries(grid_partitioned_in_grid:Array) ->void:
	"""
	Fill out dicts of chunk id to coord and coord to chunk id maping 
	# tested
	"""
	# now convert these into a dictionary key = chunk_number value=array of coordinates
	var i:int = 0
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
	
	# to get them in the correct order we need to invert the grid from the centre
	# this way the top left is the -x,-z, and bottom right is x,z
#	first_half.reverse()
#	second_half.reverse()
	
#	grid_positions = first_half + second_half
#	# test this out
#	for i in range(-int(grid_width/2), int(grid_width/2), 1):
#		print()
#		print(grid_positions[i])
#		print()
	
#	for i in range(len(grid_positions)):
#		print()
#		print(str(grid_positions[i]))
	return grid_positions

func update_grid(global_grid_position:Vector3, new_item:Grass_Grid_Item):
	"""
	Make an update to a gridspace in the grid. The orignal grid data is not modified
	and grid can revert to inital state by calling make_grid()
	
	Note: precondition is that set_grid_paramters() was used correctl
	"""
	pass

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

func test_built_in_gridmap(grounded:bool = false):
	var grid_size:int = 144
	set_grid_paramters(grid_size,grid_size,Mesh_List.new())
	var array_of_coordinates:Array = make_an_array_of_arrays_of_coordinates()
	print("array of coordinates size from built in " + str(len(array_of_coordinates)))
	global_array_of_coordinates = array_of_coordinates
	var gridmap = $"Testing Gridmap"
	var i = 0
	var y:int = 2 # to have gridmap on ground or raised (to compare to custom gridmap)
	if grounded:
		y = 0

	
	for list_of_coord in global_array_of_coordinates:
		for coord in list_of_coord:
			var coord_corrected = Vector3i(coord.x, y, coord.z)
			i+=1
			gridmap.set_cell_item(coord_corrected, 1)
	print(i)


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

### testing grounds
# Sample grid initialization
var grid := [
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)],
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(2, 1, 0), Vector3(3, 1, 0)],
	[Vector3(0, 2, 0), Vector3(1, 2, 0), Vector3(2, 2, 0), Vector3(3, 2, 0)],
	[Vector3(0, 3, 0), Vector3(1, 3, 0), Vector3(2, 3, 0), Vector3(3, 3, 0)]
]
func partition_grid_into_chunks(grid: Array, chunk_size_x: int, chunk_size_y: int) -> Array:
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

func custom_grid_map_collision_handler(collision_objects:Array):
	for collision in collision_objects:
		var name_of_collision_object  = collision.get_collider().name
		if name_of_collision_object == "Mowing Area" or name_of_collision_object == "Start Area":
			continue
		else:
			print(name_of_collision_object)

func test_it():
	"""
	Testing partition grid
	"""
	var chunk_sizex = 2
	var chunk_sizey = 2
	var gridChunks = partition_grid_into_chunks(grid, chunk_sizex, chunk_sizey)
	for chunk in gridChunks:
		print(chunk)
