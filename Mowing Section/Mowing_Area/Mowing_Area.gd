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
	pass


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
	grass_size = 20
	# inital grid generation is expensive. do it once
	if data.get_is_inital_grass_grid_set() == false:

		data.set_is_inital_grass_grid_set(true)
		var positions:Vector4 = get_grid_edges()

		var top_x = positions.x
		var top_z = positions.y
		
		var bottom_x = positions.z
		var bottom_z = positions.w
		
		var LODS:Array = [grass_unmowed_high_LOD_scene,grass_mowed_low_LOD_scene,grass_mowed_high_LOD_scene] # grass_mowed_low_LOD_scene,grass_mowed_high_LOD_scene
		var LODS_keys:Array = ["unmowed high LOD","mowed low LOD","mowed high LOD"] # ""

		for x in range(top_x,bottom_x,-grass_size):
			for z in range(top_z,bottom_z,-grass_size):
				# calculate position
				var position_ = Vector3(x,0,z) 
				var child_ = grass_unmowed_low_LOD_scene.instantiate()
				# store in grass grid ( so divide by grass size and round)
				var grid_coord_for_this_grass = to_grid_coord(position_,grass_size)
				
				var cell_dictionary:Dictionary = {"unmowed low LOD":child_}
				
				grass_grid[grid_coord_for_this_grass] = cell_dictionary 
				
				# for default grid all grass is considered to be unmmowed low LOD
				unmowed_low_lod[grid_coord_for_this_grass] = child_

				# add it to scene
				add_child(child_)
				
				# conver the position to local coord of the mowing area mesh
#				child_.position = mowing_area.to_local(position_)

				# to make sure grass is on the ground
				child_.position.y = 20 
				
				# since the grass is a child of the level scene now. The scaling sets accordingly
				# this can lead to scaling issues so adjust the scaling (these hard coded values)
				# are stored in the model and are gotten from there by type of level (small, medium etc)
				child_.scale = data.get_grass_scale()
				child_.scale = Vector3(12,12,12)
				return
				# now copy the position and scale over and add child for each LOD
				for i in range(len(LODS)):
					var new_child = LODS[i].instantiate()
					# if this is the 3 (mowed grass high lod) then turn off collision for now
					mowing_area.add_child(new_child)
					new_child.hide()
					
					# if this is the 1 (mowed grass high lod) then turn off collision for now
					if i == 0: # 2 since 0,1,2 
						new_child.get_node("CollisionShape3D").disabled = true
					
					# set the position and scale
					new_child.position = child_.position
					new_child.scale = child_.scale
					if i == 1 or i == 2: # for mowed grass make it smaller
						new_child.scale.y /=2
					var grass_grid_cell:Dictionary = grass_grid.get(grid_coord_for_this_grass)
					grass_grid_cell[LODS_keys[i]] = new_child
					grass_grid_for_collision[new_child.name] = grid_coord_for_this_grass
				
				# to aid with collision store the key and child.name
				grass_grid_for_collision[child_.name] = grid_coord_for_this_grass
				
	
	else: # inital grid is setup already (meaning this a load from save) and the grid is loaded
		# convert mower coord into grid coord
		return ##FOR TESTING REMOVE ONCE DONE
		mower_current_position = to_grid_coord(mower_current_position,grass_size)
		
		# set the y to 0 since in grid coord the y = 0 for grass
		mower_current_position.y = 0
		
		var n_dist:int = 7
		var closest_grass_grid_cells:Array = []
		
		# this is needed to run at least once, so that mower trakcer position is not "set" and thus n_nearest works
		if run == true: 
			closest_grass_grid_cells = get_n_nearest_grass(mower_current_position,n_dist)
			mower_position_tracker = mower_current_position
			run = false
		
		else: # this else prevents the previous call to get_n_nearest from being overrided
			closest_grass_grid_cells = get_n_nearest_grass(mower_current_position,n_dist)

		# since we can get an empty array back no need to do the rest
		if len(closest_grass_grid_cells) == 0:
			return

		# check if this grass should be mowed or unmowed LOD
		# keep track of which grass to un flip the LOD as well
		for grass in closest_grass_grid_cells:
			var grass_grid_cell = grass_grid.get(grass)
			if grass in mowed_high_lod or grass in unmowed_high_lod: # already high LOD
				continue
			elif grass in mowed_low_lod: # change it to high mowed LOD
				grass_grid_cell["mowed low LOD"].hide()
				grass_grid_cell["mowed high LOD"].show()
				mowed_high_lod[grass] = grass_grid_cell["mowed high LOD"]
				
			elif grass in unmowed_low_lod: # change it to high unmowed LOD
				grass_grid_cell["unmowed low LOD"].hide()
				grass_grid_cell["unmowed high LOD"].show()
				
				# handle collision disabling
				var this_grass = grass_grid_cell["unmowed high LOD"]
				this_grass.get_node("CollisionShape3D").disabled = false
				
				# remove from the relevant dictionaries and add to correct one
				unmowed_low_lod.erase(grass)
				unmowed_high_lod[grass] = grass_grid_cell["unmowed high LOD"]

		# remove this from the high lod level.
		# to do this compare the current n_closest and remove
		# from high LOD levels any grass that is not in the n_closest
		var remove_from_high_LOD = [] # to store what needs to be erased. Erasing in loop can cause problems

		for high_mowed in mowed_high_lod:
			if high_mowed not in closest_grass_grid_cells:
				var grass_grid_cell = grass_grid.get(high_mowed)
				grass_grid_cell["mowed high LOD"].hide()
				
				grass_grid_cell["mowed low LOD"].show()
				
				# swap dictionaries entries around
				remove_from_high_LOD.append(high_mowed)
				mowed_low_lod[high_mowed] = grass_grid_cell["mowed low LOD"]


		for high_unmowed in unmowed_high_lod:
			if high_unmowed in closest_grass_grid_cells:
				continue
			else:
				var grass_grid_cell = grass_grid.get(high_unmowed)
				grass_grid_cell["unmowed high LOD"].hide()
				grass_grid_cell["unmowed low LOD"].show()
				
				# swap dictionaries entries around
				remove_from_high_LOD.append(high_unmowed)
				unmowed_low_lod[high_unmowed] = grass_grid_cell["unmowed low LOD"]
				
		# now that looping is done remove the grass from the respective dictionaries
		for remove_this in remove_from_high_LOD:
			if mowed_high_lod.has(remove_this):
				mowed_high_lod.erase(remove_this)
			if unmowed_high_lod.has(remove_this):
				unmowed_high_lod.erase(remove_this)
	
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
	# we can use the truck zero function to get the centre of start gate of mowing area
	var centre_start_ref = return_truck_zero_position()
	
	# since the centre point is halfway on left-right then move it over by half of length
	
	# find the top right of the grid
	var top_x = centre_start_ref.x + (data.get_width()/2)
	var top_z = centre_start_ref.z + (data.get_length()) # length is 1 distance
	
	
	var bottom_x = centre_start_ref.x - (data.get_width()/2)
	var bottom_z = centre_start_ref.z
		

	$MeshInstance3D.position = Vector3(top_x,25,top_z)
	$MeshInstance3D2.position = Vector3(bottom_x,50,bottom_z)
	
#	print(" ** ")
#	print(Vector3(top_x,25,top_z))
#	print(Vector3(bottom_x,50,bottom_z))
	
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
