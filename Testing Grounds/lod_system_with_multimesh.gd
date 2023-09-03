extends Node3D


# testing
var measure:Mesurment = Mesurment.new("Lod system testing")

var width:int = 1500
var length:int = 1500

var grass_cell_size:int = 2

var mesh_scene = preload("res://Assets/Grass with LOD/objects/Mowed Grass High LOD.glb") # find the unmowed version
var mesh:Mesh

# there will be half the length and width
var grid_length_half_length:int = 8

# for now store the multimesh instance 
var chunk_instances:Array[Multi_Mesh_Chunk] = []

# to test 
var lod_look_up_table:Dictionary
var stored_mower_position:Vector3 = Vector3()

func _ready():
	var mesh_scene_instance = mesh_scene.instantiate()
	mesh = mesh_scene_instance.get_node("Mowed Grass High LOD2").mesh
	
	
	# check the performance
	measure.start_m("testing with instancing")
	
	lod_look_up_table = make_lod_lookup_table()
	measure.stop_m()
#	print(lod_look_up_table[Vector2(0,0)])
	
	model.set_lod_lookup(lod_look_up_table)
	
	# now setup the multimesh chunks 
	
	main()
	
#	testing_lod_grid_lookup(true)
	stored_mower_position = $"Small Gas Mower".global_position
	

var fps:Array = []
var fps_min_5:Array = []
var fps_min_10:Array = []
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
#	update_main()
	pass

func _input(event):
	if Input.is_action_just_pressed("ui_cancel"):
		get_fps_data()


func get_fps_data():
	"""
	Testing function 
	"""
	pass

func testing_lod_grid_lookup(pass_through:bool = false):
	var mower_global_position:Vector3 = $"Small Gas Mower".global_position

	# only call this function if the current and former mower_positions do not match
	if stored_mower_position == $"Small Gas Mower".global_position and pass_through == false:
		return

	stored_mower_position = $"Small Gas Mower".global_position # update 
	var mower_cord_test:Vector2 = Vector2(round(mower_global_position.x*1.2),round(mower_global_position.z*1.2 ))
	# for testing populate a bunch of boxmesh meshintances
	var boxmesh_grid:Dictionary = {}
	var coords:Array[Vector2] = make_2nx2n_a_grid(grid_length_half_length) 

	var multi_mesh:MultiMesh = MultiMesh.new()
	var new_boxmesh := BoxMesh.new()
	var shader_mat:StandardMaterial3D = StandardMaterial3D.new()
	shader_mat.albedo_color = Color(1,1,1)
	shader_mat.vertex_color_use_as_albedo = true
	new_boxmesh.surface_set_material(0, shader_mat)
	
	multi_mesh.set_mesh(new_boxmesh)
	multi_mesh.set_transform_format(MultiMesh.TRANSFORM_3D)
	multi_mesh.set_use_colors(true)
	multi_mesh.set_instance_count(len(coords))
	
		
	for i in range(multi_mesh.instance_count):
		var a_color = Color(randf(), randf(), randf())
		var point:Vector3 = Vector3(coords[i].x*1.2, 0, coords[i].y*1.2)
		
		if mower_cord_test == coords[i]:
			a_color = Color(0,0,0)
		else:
			if lod_look_up_table.has(mower_cord_test) and lod_look_up_table.get(mower_cord_test).has(coords[i]):
				var lod = lod_look_up_table[mower_cord_test][coords[i]]

				# set the color based on LOD value
				if lod == 0: # nearest to be mint green
					a_color = Color(255,0,0)
				elif lod == 1: # dark yellow sand color
					a_color = Color(0,255,0)
				elif lod == 2: 
					a_color = Color(0,0,255)
				elif lod == 3: # light pink color
					a_color = Color(1,1,1)
			else:
				continue

		
		
		
		var scale_factor:float = 1.0
		var basis_vector = Basis()*scale_factor
		var transform_vector = Transform3D(basis_vector, point)
		
		multi_mesh.set_instance_color(i,a_color)
		
		multi_mesh.set_instance_transform(i, transform_vector)

		boxmesh_grid[coords[i]] = i
	
	$MultiMeshInstance3D.multimesh = multi_mesh

func main():

	# Make a grid -8 to 8 = 16x16
	var chunk_coords:Array = make_2nx2n_a_grid(grid_length_half_length)
	
	
#	var chunk:Multi_Mesh_Chunk = Multi_Mesh_Chunk.new()
#	chunk.setup_chunk(Vector2(0,0), 100 )
#	var mm_instance = chunk.get_for_rendering()
#	add_child(mm_instance)
#	print(chunk.get_chunk_global_position())
#	mm_instance.global_position += chunk.get_chunk_global_position()
#
#
#	var chunk2:Multi_Mesh_Chunk = Multi_Mesh_Chunk.new()
#	chunk2.setup_chunk(Vector2(0,1), 100,true )
#	mm_instance = chunk2.get_for_rendering()
#	add_child(mm_instance)
#	mm_instance.global_position += chunk2.get_chunk_global_position()
##	mm_instance.global_position += Vector3(0,0,0)
	
	# make the grid of multimesh objects
	for coord in chunk_coords:
		var chunk:Multi_Mesh_Chunk = Multi_Mesh_Chunk.new()
		chunk.setup_chunk(coord,50,true)
		var mm_instance = chunk.get_for_rendering()
		add_child(chunk.get_for_rendering())
		mm_instance.global_position += chunk.get_chunk_global_position()
		chunk_instances.append(chunk)
		

func update_main():
	for chunk in chunk_instances:
		chunk.update_chunk()


func make_lod_lookup_table() -> Dictionary:
	"""
	Precompute a table where for a given gridspace, the LOD level for each other gridspace can be looked up
	"""
	# make a general copy of all grid spaces coords with a lod (this copy can be used for each mower position)
	var grid_spaces_coord:Array[Vector2] = make_2nx2n_a_grid(grid_length_half_length)
	
	# init the dictionary to hold these values ( this can copied and used later)
	var grid:Dictionary = {} # key = position, value = LOD value
	for coord in grid_spaces_coord: 
		grid[coord] = 3 # default init value is lowest LOD value REMOVE HARD CODED VALUES
	
	var lookup_table:Dictionary = {} # key = mower grid coord, value = coords and lod of each chunk
	# for each grid space, make a new grid to store the LOD for the other gridspaces. 
	for mower_position_coord in grid_spaces_coord:
		# make a copy of a 2nx2n grid
		var current_grid:Dictionary = grid.duplicate()
		# find all the possible Vector2() that are in range (including those that DO NOT fit on the 2nx2n grid)
		var gridspaces_with_lod:Dictionary = calculate_LOD_gridspaces(mower_position_coord)
		
		# now update the current_grid lod values
		for coord in gridspaces_with_lod.keys(): # keys == coords
			if coord == mower_position_coord:
				current_grid[coord] == -1 # special case (current mesh that is being mowed)
				
			elif current_grid.has(coord): # filter out any Vector2() that does not fit on the 2nx2n grid
				current_grid[coord] = gridspaces_with_lod[coord] # update the LOD for the current grid
		
		# store the current grid for the current given "mower_coord"
		lookup_table[mower_position_coord] = current_grid
		
	return lookup_table

func calculate_LOD_gridspaces(mower_grid_position:Vector2) ->Dictionary:
	"""
	Find all the possible grid position (this does NOT take into account grid size. so a given coord may
	not exist for a given grid but is still returned) find the LOD chunks coords (those coords which fall within any LOD range)
	
	Returns a dictionary with key = vector, value = lod value
	
	This is similar to doing:
			for x_cord in range(-x+mower_grid_position, x+mower_grid_position, 1): 
				for z_cord in range(-z+mower_grid_position, z+mower_grid_position, 1): 
					var pos = Vector2(x_cord,z_cord)
			then classifying those chunks to their LOD

	"""
	var current_lod_level:int = 0 #start at the inner value (note this value should have 1 added to it before using for addition or substraction)
	var current_lod_range:int = 1 #how far out this LOD chunk is
	var classifed_chunk_coords:Dictionary = {}
	while current_lod_level != 3: # replace 3 with maximum LOD level minus 1
		# find the maximum and minumum (do plus 1 since we start at LOD level 0
		var left_x:int = int(mower_grid_position.x - current_lod_range)
		var right_x:int = int(mower_grid_position.x + current_lod_range )
		
		var left_z:int = int(mower_grid_position.y - current_lod_range)
		var right_z:int = int(mower_grid_position.y + current_lod_range)
		
		
		for x in range(left_x, right_x+1, 1):
			for z in range(left_z, right_z+1, 1):
				if classifed_chunk_coords.has(Vector2(x, z)) == true: # a higher LOD chunk is there so pass
					continue
				else:
					classifed_chunk_coords[Vector2(x, z)] = current_lod_level
		
		current_lod_level += 1
		current_lod_range += 1
	
	
	return classifed_chunk_coords

func make_2nx2n_a_grid(n:int) ->Array[Vector2]:
	"""
	Return an array of Vector2 with an 2nx2n grid (ie n = 4 == 8x8 grid)
	"""
	var spaces:int = n
	var chunk_coords:Array[Vector2] = []
	for x in range(-spaces,spaces,1):
		for z in range(-spaces,spaces,1):
			chunk_coords.append(Vector2(x,z))

	return chunk_coords


func generate_multimesh():
	var multi_meshinstance:MultiMeshInstance3D = $MultiMeshInstance3D
	var multi_mesh:MultiMesh = MultiMesh.new()
	
	var points_to_render:Array = get_positions()
	points_to_render = points_to_render[0]
	
	multi_mesh.set_mesh(load("res://Testing Grounds/Mowed Grass High LOD.tres"))
	multi_mesh.set_transform_format(MultiMesh.TRANSFORM_3D)
	multi_mesh.set_instance_count(len(points_to_render))

	for i in range(multi_mesh.instance_count):
		# get the point and translate it over to chunk space
		var point:Vector3 = translate_to_local_space(points_to_render[i])
		
		# set the information of this instance
		var scale_factor:float = 2.0
		var basis_vector = Basis()*scale_factor
#		basis_vector = basis_vector.rotated(Vector3(0,0,1),randf_range(12.5,90.0))
#		basis_vector = basis_vector.rotated(Vector3(0,1,0),90)
		var transform_vector = Transform3D(basis_vector, point)
		
#		transform_vector = transform_vector.scaled(Vector3(scale_factor,scale_factor,scale_factor))
		
		
		multi_mesh.set_instance_transform(i, transform_vector)

	
	multi_meshinstance.multimesh = multi_mesh

func get_positions() ->Array:
	"""
	
	return Array with 2 Arrays [0] = multimesh points [1] = object point for grass
	"""
	var current_mower_position:Vector2 = Vector2(model.get_mower_position().x,model.get_mower_position().y)
	
	# return variables
	var grid_points:Array = []
	var object_points:Array = []
	
	# generate the grass grid points

	# generate the whole grid points
	var start_x: int = -int(width/2)
	var end_x:int = int(width/2)
	
	var start_z:int = -int(length/2)
	var end_z:int = int(length/2)
	
	
	
	for x in range(start_x, end_x, grass_cell_size):
		for z in range(start_z, end_z, grass_cell_size):
			grid_points.append(Vector2(x,z))
	
	return [grid_points,object_points]

func translate_to_local_space(coord:Vector2) ->Vector3:
	return Vector3(coord.x, 0, coord.y)
