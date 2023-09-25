extends Node3D

var width_and_length:int = 200
var total_grid_width_length:int # calcuated in ready function

# Called when the node enters the scene tree for the first time.
func _ready():
	set_inital_positions_and_sizes()
	
	# test the gridmap 
	test_custom_gridmap()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func test_custom_gridmap():
	# setup the meshlibrary
	var grid_size:int = 16
	set_grid_paramters(grid_size,grid_size,Mesh_List.new())
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
func set_grid_paramters(width:int, length:int, a_mesh_list:Mesh_List,batching:int = 16):
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
func set_gridspace_item(item:Grass_Grid_Item):
	"""
	Set a item into gridmap. Provide a grass grid item with at least the position and mesh_id set
	
	CONDITION: mesh_id that is set should match what is the library_object
	"""
	var position_vector:Vector3i = item.get_grid_position()
	
	# check if this a valid point in the given grid
	grid_mapping[position_vector] = item
	pass

func make_grid():
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
#	saveArrayAsCSV(array_of_coordinates, path) # for testing
	
	# partition this into chunks
	var chunk_size_x:int = int(sqrt(batching_size)) #batch 16 = 4x4 which is sqrt(16)
	var chunks_size_y:int = chunk_size_x
	var array_of_partitioned_chunks:Array = partition_grid_into_chunks(array_of_coordinates, chunk_size_x, chunk_size_x)
	
	# now fill those dictionaries
	fill_dictionaries(array_of_partitioned_chunks)
	
	# at this point we have the base grid information ready. Now begin rendering 
	# make the grid of multimesh chunks 
	fill_multimesh_grid()

func fill_multimesh_grid():
	pass
	
func fill_dictionaries(grid_partitioned_in_grid:Array) ->void:
	"""
	Fill out dicts of chunk id to coord and coord to chunk id maping 
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
	# assuming a grid of 32x32
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

# test this function with the following data
var path = "C:/Users/usw87/Desktop/Godot outside of project store/output_grid.csv"
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

func test_it():
	var chunk_sizex = 2
	var chunk_sizey = 2
	var gridChunks = partition_grid_into_chunks(grid, chunk_sizex, chunk_sizey)
	for chunk in gridChunks:
		print(chunk)
