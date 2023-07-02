extends Node3D

var data:Job_Data_Container = null

# use three dictionaries to store
# 1. to store empty slots
# 2. to store low LOD grass
# 3. to store nearby grass 

var mowed_high_lod:Dictionary
var mowed_low_lod:Dictionary

var unmowed_high_lod:Dictionary
var unmowed_low_lod:Dictionary

var grass_container_scene = load("res://Mowing Section/Mowing_Area/Grass Cell/Grass Cell.tscn")

var grass_grid: Dictionary = {} # store all current grass key = location value = Dictionary ( key = typeLOD, value child)
var grass_grid_for_collision:Dictionary = {} # key = name value = vector location
# store scenes to different types of grass
var grass_mowed_low_LOD_scene = load("res://Assets/Grass with LOD/Mowed Grass Low LOD.tscn")

var grass_mowed_high_LOD_scene = load("res://Assets/Grass with LOD/Mowed Grass High LOD.tscn")

var grass_unmowed_low_LOD_scene = load("res://Assets/Grass with LOD/Unmowed Grass Low LOD.tscn")

var grass_unmowed_high_LOD_scene = load("res://Assets/Grass with LOD/Unmowed Grass High LOD.tscn")

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



## TESTING
var run = true
var mower_position_tracker:Vector3 = Vector3(0,10000,-1000) # to prevent needless checking and removing
# Called when the node enters the scene tree for the first time.
func _ready():
	var grass_container_scene = preload("res://Mowing Section/Mowing_Area/Grass Container/Grass Container.tscn")


func _process(delta):
	pass


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
	
	# TESTING. WHEN proper 3d models are added then this won't be needed as much
	level.scale = data.get_house_scale()
	
	# set reference to mowing area
	mowing_area = _level.get_node("StaticBody3D/Mowing Area")


	# if this is a new unstarted job do this calcuation for width and height
	if data.get_is_width_height_set() != true:
		var scaling = level.get_node(".").scale
		data.set_width(mowing_area.mesh.size.x * scaling.x)
		data.set_length(mowing_area.mesh.size.y * scaling.z)
		
	

	
#	# get the truck zone area and connect the Area3D signal
#	truck_zone = level.get_node("Truck Zone")
#	truck_zone.connect("body_entered",handle_truck_zone) 

	# set the size of the different set of grasses in job container
	var grass_instance = grass_unmowed_high_LOD_scene.instantiate()
#	print(grass_instance.get_node("Mesh grass").mesh.get_aabb().size)
#	print(scaling*grass_instance.scale * grass_instance.get_node("Mesh grass").mesh.get_aabb().size)
	



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
				
				# this is needed otherwise. example global 4xx might become 7.xx local
				current_position = level.to_local(current_position)

				mowing_area.add_child(a_scene)
				a_scene.setup_cell(current_position,data)
	
	else: # MAIN LOOP of this function 
		pass

func get_n_nearest_grass(pos:Vector3,n:int) -> Array:
	"""
		Takes in a vector3 containg GRID COORD and finds n nearest grass grid places from list
		Returns an array of all of them
		
		TODO: to optimize return only the grass grid cells that need to be changed
	"""

	if pos == mower_position_tracker:
		return [] # no checking needed

	mower_position_tracker = pos
	var mower_position:Vector2 = Vector2(pos.x,pos.z)
	
	var return_array:Array = []

	var mower_x: = pos.x
	var mower_z: = pos.z
	
	# this is still pretty quick
	for x in range(mower_x-n,mower_x+n,1):
		for z in range(mower_z-n, mower_z+n, 1):
			if grass_grid.has(Vector3(x,0,z)):
				return_array.append(Vector3(x,0,z))

		
	return return_array

#OUT DATED. This func
func handle_collision(collisions):
	for collision in collisions:
		var collision_name = collision.get_collider().name
		if collision_name == "StaticBody3D":
			return
		if collision_name in grass_grid_for_collision:
			# take high lod grass and swtich it to lod LOD
			var grass_coord:Vector3 = grass_grid_for_collision[collision_name]
			
			var grass_grid_cell = grass_grid.get(grass_coord)
			grass_grid_cell["unmowed high LOD"].hide()
			grass_grid_cell["unmowed high LOD"].get_node("CollisionShape3D").disabled = true
			grass_grid_cell["mowed high LOD"].show()
			
			# remove form the relevant dictionaries
			unmowed_high_lod.erase(grass_coord)
			mowed_low_lod[grass_coord] = grass_grid_cell["mowed high LOD"]


# helper functions for the calculate_grass_loading function
func get_grid_edges() -> Vector4:
	"""
		Returns the edges of the grid. top left and bottom right
		This can then be used in a for loop to generate a grid
		
		return a Vector 4 with x = topx, y = topy, w = bottomx, z = bottom z (in  global coords)
	"""

	# find the top right of the grid (0,0,0) is the centre of the mowing area
	var top_x = data.get_width()/2
	var top_z = data.get_length()/2
	
	
	var bottom_x = -data.get_width()/2
	var bottom_z = -data.get_length()/2

	#x,y,z,w
	return round(Vector4(top_x,top_z,bottom_x,bottom_z))

func to_grid_coord(pos:Vector3,grid_cell_size:int):
	return round(pos/grid_cell_size)

	
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
