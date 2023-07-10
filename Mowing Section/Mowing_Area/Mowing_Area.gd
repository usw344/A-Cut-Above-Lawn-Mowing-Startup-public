extends Node3D

var data:Job_Data_Container = null

# Grass Cell scene reference
var grass_container_scene = load("res://Mowing Section/Mowing_Area/Grass Cell/Grass Cell.tscn")

# store the Grass cells by location (key = Location, key = child)
var grass_grid: Dictionary = {}

# store all the mowed grass reference
var mowed_grass_grid:Dictionary = {} # key = name value = vector location

# store all the grass in high lod
var high_lod_grass:Dictionary = {}

# albedo for grass 42d99a

# testing purposes
var mesure = Mesurment.new("Mowing Area")

# store references of nodes from the level scene for easier access
var truck_zone:Area3D

var level = null # reference to the level object

var mowing_area = null

# to prevent heavy compuations generate an inital grid. 
# only check the cells nearest to the mower and leave the rest to what they were last time
var is_inital_grid_set:bool = false

# to prevent running the expensive n_nearest function unnecessarily track current grid pos
var mower_recorded_grid_position:Vector2 = Vector2()

# how close grass is before it is in high LOD
var lod_limit:int = 5

# to prevent needless checking and removing
var mower_position_tracker:Vector3 = Vector3()

# since the first time mower_position is not set, we use this to trigger a nearest check
var first_check:bool = true 

 
# Called when the node enters the scene tree for the first time.
func _ready():
	var grass_container_scene = preload("res://Mowing Section/Mowing_Area/Grass Container/Grass Container.tscn")


func _process(delta):
	if Input.is_action_just_pressed("Testing"):
		grass_grid[Vector3(-2,0,52)].position.y += 2
		print("Global position in grid coord" , round((grass_grid[Vector3(-2,0,52)].global_position)/22))

func setup(new_data:Job_Data_Container):
	"""
	Main function for this class. Pass in the Job_Data_Container object here. This function will setup the 
	mowing objects and ground
	"""
	data = new_data
	
	# pull out the type and variant information of this level
	var type = data.get_house_type()
	var variant = data.get_house_variant()
	
	#get the referene ( returns a load () ) of the level that is needed
	var level_reference = model.get_level(type,variant)

	# setup ground and house
	var _level = level_reference.instantiate()
	add_child(_level)
	
	level = _level #  store the copy to a global variable
	
	# Scale the level accordingly
	level.scale = data.get_house_scale()
	
	# set reference to mowing area (to add grass to it later)
	mowing_area = _level.get_node("StaticBody3D/Mowing Area")


	# if this is a new unstarted job do this calcuation for width and height
	if data.get_is_width_height_set() != true:
		var scaling = level.get_node(".").scale
		data.set_width(mowing_area.mesh.size.x * scaling.x)
		data.set_length(mowing_area.mesh.size.y * scaling.z)
		
	

	
#	# get the truck zone area and connect the Area3D signal
#	truck_zone = level.get_node("Truck Zone")
#	truck_zone.connect("body_entered",handle_truck_zone) 

	



func calculate_grass_loading(mower_current_position:Vector3):
	"""
		Calculate what grass should be currently rendered and at what LOD
		
		This function should be called from an outside node. This will give control over stopping
		the expensive calculations that occur here can be paused when not needed
	"""
	var grass_size = data.get_grass_size() # grass size is hard coded for each level size

	# inital grid generation is expensive. do it once
	if data.get_is_inital_grass_grid_set() == false:
		data.set_is_inital_grass_grid_set(true)
		var positions:Vector4 = get_grid_edges()
		var top_x = positions.x
		var top_z = positions.y
		var bottom_x = positions.z
		var bottom_z = positions.w
	
		
		for x_position in range(top_x,bottom_x,-grass_size):
			for z_position in range(top_z,bottom_z,-grass_size):
				var a_scene = grass_container_scene.instantiate()
				var current_position = Vector3(x_position,0,z_position)
				
#				for some reason this works with level.to_local but not with mowing_area.to_local
				current_position = level.to_local(current_position)
				
				# add to mowing_area (even though we used level.to_local)
				mowing_area.add_child(a_scene)
				# similar to init() setup_cell sets up the object
				a_scene.setup_cell(current_position,data)
				

				# calcuate correct global grid location [See NOTE 1 above why] 
				var global_grid_position:Vector3 = round(a_scene.get_this_global_position()/grass_size)
				
				# it is not zeroed for some reason
				global_grid_position.y = 0
	
				# add to dictionary of objects
				grass_grid[global_grid_position] = a_scene
				

				
	else: # MAIN LOOP of this function 
		var nearest_grass:Array = get_n_nearest_grass(mower_current_position,lod_limit)
		if nearest_grass.is_empty(): # no change in mower position
			return
		# run main 

		for grass_coord in nearest_grass:
			if grass_coord in high_lod_grass:
				continue
			# if not then flip this into high LOD
			grass_grid[grass_coord].flip_to_high_lod()
			high_lod_grass[grass_coord] = true


func test1():
#	print("*****")
	pass
#	var grass_keys = grass_grid.keys()
#	grass_keys.sort_custom(func(a, b): return a[0] > b[0])
#
#	if Vector3(-4,0,24) in grass_keys:
#		print("-4,0,24 is in there but not being found for some reason")
	
#	print(grass_keys)
#	print("*****")
		

func get_n_nearest_grass(pos:Vector3,n:int) -> Array:
	"""
		Takes in a vector3 containg  and finds n nearest grass grid places from list
		Returns an array of all of them
		
	"""

	if pos == mower_position_tracker and first_check == false:
		return [] # no checking needed
		
	first_check = false # since power position is now set
	mower_position_tracker = pos
	
	var return_array:Array = []
	
	# convert mower position into grid coord
	var mower_pos_grid_coord = to_grid_coord(pos)
	
	# find the loop variables
	var start_x = mower_pos_grid_coord.x - n
	var end_x = mower_pos_grid_coord.x + n
	
	var start_z = mower_pos_grid_coord.z - n
	var end_z = mower_pos_grid_coord.z + n
	
#	print("****  ",start_x,"  ",end_x)
	for x in range(start_x, end_x , 1):
		for z in range(start_z, end_z, 1):
			var coord:Vector3 = Vector3(start_x, 0, start_z)
			
			if grass_grid.has(coord) and coord not in return_array:
				return_array.append(coord)
	

		
	return return_array


func handle_collision(collisions):
	$Debug.text = ""
	for collision in collisions:
		var grid_pos = to_grid_coord(collision.get_position())
		if grass_grid.has(grid_pos):
#			print("found case")
			
			$Debug.text += "Collision grid location" + str(collision.get_position())


# helper functions for the calculate_grass_loading function
func get_grid_edges() -> Vector4:
	"""
		Returns the edges of the grid. top left and bottom right
		This can then be used in a for loop to generate a grid
		NOTE: this function return the LOCAL grid edges for a plane with centre being (0,0,0)
		
		return a Vector 4 with x = topx, y = topy, w = bottomx, z = bottom z (in  global coords)
	"""

	# find the top right of the grid (0,0,0) is the centre of the mowing area
	var top_x = data.get_width()/2
	var top_z = data.get_length()
	
	
	var bottom_x = -data.get_width()/2
	var bottom_z = -data.get_length()/2

#	$MeshInstance3D2.position = mowing_area.to_global(Vector3(0,0,0))

	#x,y,z,w
	return round(Vector4(top_x,top_z,bottom_x,bottom_z))

func to_grid_coord(pos:Vector3):
	"""
		As per NOTE 1 above, this function corrects the given position to be a
		global grid coordinate (as the mowing area uses a local system so its x,y,z
		can't be used for grid coordinate system)
	"""
	
	# grid coord are technically 2d (so zero the y), but to make the process easier Vector3 is used
	pos.y = 0
	
	# translate the z over
#	pos.z += (data.get_length()/2)
	
	return round(pos/data.get_grass_size())

	
func return_truck_zero_position() ->Vector3:
	var road_size = 8.5 # this is from the 3D model
	var road_size_scaled = road_size * data.get_house_scale().x # this m
	
	var centre_x = (data.get_width())/65 # for some reason this centres it
	var centre_z = road_size_scaled/2.5 # calculate road width and then some buffer

	var pos:Vector3 = Vector3(centre_x,25,centre_z)
	
	return pos
	

func handle_truck_zone(node):
	"""
		Handle collision with truck zone. (this should open the refuel and cuttings deposit menu)
	"""
	print(node.name)


func set_data(d:Job_Data_Container):
	data = d
