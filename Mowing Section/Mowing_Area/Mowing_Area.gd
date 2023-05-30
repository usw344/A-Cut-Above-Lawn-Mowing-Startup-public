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

# store scenes to different types of grass
var grass_mowed_low_LOD_scene = load("res://Assets/Grass with LOD/Mowed Grass Low LOD.tscn")

var grass_mowed_high_LOD_scene = load("res://Assets/Grass with LOD/Mowed Grass High LOD.tscn")

var grass_unmowed_low_LOD_scene = load("res://Assets/Grass with LOD/Unmowed Grass Low LOD.tscn")

var grass_unmowed_high_LOD_scene = load("res://Assets/Grass with LOD/Unmowed Grass High LOD.tscn")


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
	
	
	# set reference to mowing area
	mowing_area = level.get_node("StaticBody3D/Mowing Area")

	# if this is a new unstarted job do this calcuation for width and height
	if data.get_is_width_height_set() != true:
		var scaling = level.get_node(".").scale
		data.set_width(mowing_area.mesh.size.x * scaling.x)
		data.set_length(mowing_area.mesh.size.y * scaling.z)
	
	
	
	# get the truck zone area and connect the Area3D signal
	truck_zone = level.get_node("Truck Zone")
	truck_zone.connect("body_entered",handle_truck_zone) 

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
	var grass_size = data.get_grass_size()
	
	if data.get_is_inital_grass_grid_set() == false:
		mesure.start_m("inital grid")
		data.set_is_inital_grass_grid_set(true)
		# find the top right of the grid
		var top_x = mowing_area.position.x - (data.get_width()/2)
		var top_z = mowing_area.position.z - (data.get_length()/2)
		
		var bottom_x = -data.get_width()/2
		var bottom_z = -data.get_length()/2
		
		# for some reason this points to the bottom right corner
		# to fix this negate them
		top_x = -top_x
		top_z = -top_z
		
		# on current design of level the fence cuts of part of the mowing area
		# to fix this add in a relative buffer. apply to both ends
		var x_buffer = data.get_width()/24
		var z_buffer = data.get_length()/24
		top_x -= x_buffer
		top_z -= z_buffer
		
		bottom_x += x_buffer
		bottom_z += z_buffer
		# setup inital grid ( to remove the need to add/remove children add a copy of each type)
		var LODS:Array = [grass_unmowed_high_LOD_scene] # grass_mowed_low_LOD_scene,grass_mowed_high_LOD_scene
		var LODS_keys:Array = ["unmowed high LOD"] # "mowed low LOD","mowed high LOD"
		for x in range(top_x,bottom_x,-grass_size):
			for z in range(top_z,bottom_z,-grass_size):
				
				# calculate position
				var position_ = Vector3(x,0,z) 

				var child_ = grass_unmowed_low_LOD_scene.instantiate()
				# store in grass grid ( so divide by grass size and round)
				var grid_coord_for_this_grass = round(position_/grass_size)
				
				var cell_dictionary:Dictionary = {"unmowed low LOD":child_}
				
				grass_grid[grid_coord_for_this_grass] = cell_dictionary 
				
				# for default grid all grass is considered to be unmmowed low LOD
				unmowed_low_lod[grid_coord_for_this_grass] = child_

				# add it to scene
				mowing_area.add_child(child_)
				
				# conver the position to local coord of the mowing area mesh
				child_.position = mowing_area.to_local(position_)
				
				# to make sure grass is on the ground
				child_.position.y = 0 
				
				# since the grass is a child of the level scene now. The scaling sets accordingly
				# this can lead to scaling issues so adjust the scaling (these hard coded values)
				# are stored in the model and are gotten from there by type of level (small, medium etc)
				child_.scale = data.get_grass_scale()
				
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
					var grass_grid_cell:Dictionary = grass_grid.get(grid_coord_for_this_grass)
					grass_grid_cell[LODS_keys[i]] = new_child
				
		mesure.stop_m()

	else: # inital grid is setup already (meaning this a load from save) and the grid is loaded
		# convert mower coord into grid coord
#		mower_current_position = mowing_area.to_local(mower_current_position)
		mower_current_position /= grass_size 
		mower_current_position = round(mower_current_position)
		
		
		var n_dist:int = 14
		
		# set the y to 0 since in grid coord the y = 0 for grass
		mower_current_position.y = 0
		if run == true: # this is needed to run at least once, so that mower trakcer position is not "set" and thus n_nearest works
			var closest_grass_grid_cells:Array = get_n_nearest_grass(mower_current_position,n_dist)
			mower_position_tracker = mower_current_position
			run = false
		var closest_grass_grid_cells:Array = get_n_nearest_grass(mower_current_position,n_dist)
		
		# since we can get an empty array back no need to do the rest
		if len(closest_grass_grid_cells) == 0:
			return
		
		# check if this grass should be mowed or unmowed LOD
		# keep track of which grass to un flip the LOD as well
		for grass in closest_grass_grid_cells:

			if grass in mowed_high_lod or grass in unmowed_high_lod:
				continue
			#BROKEN
			elif grass in mowed_low_lod: # change it to high mowed LOD
				var new_grass = grass_mowed_high_LOD_scene.instantiate()
				var current_grass = grass_grid.get(grass)
				new_grass.position = current_grass.position
				new_grass.scale = current_grass.scale
				
				mowing_area.add_child(new_grass)
				mowing_area.remove_child(current_grass)
				grass_grid[grass] = new_grass

				
			elif grass in unmowed_low_lod: # change it to high unmowed LOD
				var grass_grid_cell = grass_grid.get(grass)
				grass_grid_cell["unmowed low LOD"].hide()
				grass_grid_cell["unmowed high LOD"].show()
				
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
				
				# disable collision shape
				var current_grass_obj = grass_grid_cell.get("mowed high LOD")
				current_grass_obj.get_node("CollisionShape3D").disable = true
				
				grass_grid_cell["mowed low LOD"].show()
				
				# swap dictionaries entries around
				remove_from_high_LOD.append(high_mowed)
				mowed_low_lod[high_mowed] = grass_grid_cell["mowed high LOD"]
#		print("Unmowed keys" , unmowed_high_lod.keys())
#		print()
#		print("closest keys", closest_grass_grid_cells)

		for high_unmowed in unmowed_high_lod.keys():
			if high_unmowed in closest_grass_grid_cells:
				continue
			else:
				var grass_grid_cell = grass_grid.get(high_unmowed)
				grass_grid_cell["unmowed high LOD"].hide()
				grass_grid_cell["unmowed low LOD"].show()
				
				# swap dictionaries entries around
				remove_from_high_LOD.append(high_unmowed)
				unmowed_low_lod[high_unmowed] = grass_grid_cell["unmowed high LOD"]
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
	
#	mesure.start_m("Find n nearest")
	var mower_x: = pos.x
	var mower_z: = pos.z
	
	for x in range(mower_x-n,mower_x+n,1):
		for z in range(mower_z-n, mower_z+n, 1):
			if grass_grid.has(Vector3(x,0,z)):
				return_array.append(Vector3(x,0,z))

		
#	mesure.stop_m()
	return return_array


func sort_by_x(a:Vector3 , b:Vector3):
	# go largest to smallest in this case
	var dist_a = a.x

	var dist_b = b.x

	if dist_a > dist_b:
		return true

	return false


func get_distance_from_player(a_point:Vector2,player:Vector2,grid_cell_size:int):
	"""
		For a_point (in grid cord using grid_cell_size) and player position in 
		global coord and a given grid_cell_size find the distance and return it
	"""
	var x_pos: int = round(player.x/grid_cell_size)
	var z_pos: int = round(player.y/grid_cell_size)

	var a_pointx = abs(a_point.x - x_pos)
	var a_pointy = abs(a_point.y - z_pos)

	# a squared plus b squared = c (distance) squared
	var dist_a = sqrt( (a_pointx * a_pointx) + (a_pointy*a_pointy)  )

	return dist_a


#OUT DATED. This func
func handle_collision(collision:KinematicCollision3D):
	pass

func handle_truck_zone(node):
	print(node.name)

func set_data(d:Job_Data_Container):
	data = d
