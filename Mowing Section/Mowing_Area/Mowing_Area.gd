extends Node3D

var data:Job_Data_Container = null

# use three dictionaries to store
# 1. to store empty slots
# 2. to store low LOD grass
# 3. to store nearby grass 
var grass_empty:Dictionary = {} # mowed grass locations
var grass_low_LOD: Dictionary = {} # far away grass (less faces and no collision). this can hold both mowed and unmowed
var grass_high_LOD: Dictionary = {} # close by grass (high level of LOD and collision )
var grass_grid: Dictionary = {} # store all current grass
var grass_grid_keys:Array = []
# store scenes to different types of grass

var grass_mowed_low_LOD = load("res://Assets/Grass with LOD/objects/mowed_grass_low_LOD.glb")

var grass_mowed_high_LOD = load("res://Assets/Grass with LOD/Mowed Grass High LOD.tscn")

var grass_unmowed_low_LOD = load("res://Assets/Grass with LOD/objects/unmowed_grass_low_LOD.glb")

var grass_unmowed_high_LOD = load("res://Assets/Grass with LOD/Unmowed Grass High LOD.tscn")


# testing purposes
var mesure = Mesurment.new("Mowing Area")

# store references of nodes from the level scene for easier access
var truck_zone:Area3D

var level = null # reference to the level object

var mowing_area = null

# to prevent heavy compuations generate an inital grid. 
# only check the cells nearest to the mower and leave the rest to what they were last time
var is_inital_grid_set:bool = false

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
	var grass_instance = grass_unmowed_high_LOD.instantiate()
#	print(grass_instance.get_node("Mesh grass").mesh.get_aabb().size)
#	print(scaling*grass_instance.scale * grass_instance.get_node("Mesh grass").mesh.get_aabb().size)
	



func calculate_grass_loading(mower_current_position:Vector3):
	"""
		Calculate what grass should be currently rendered and at what LOD
		
		This function should be called from an outside node. This will give control over stopping
		the expensive calculations that occur here can be paused when not needed
	"""
	var grass_size = 16
	if data.get_is_inital_grass_grid_set() == false:
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
		# setup inital grid
		var grass_counter: int = 0
#		print(top_x," top z is:" + str(top_z),"grass size" + str(grass_size))
		for x in range(top_x,bottom_x,-grass_size):
			for z in range(top_z,bottom_z,-grass_size):
				
				# calculate position
				var position_ = Vector3(x,7,z) #FIX Y ISSUE (y is not always on ground)
				
				#find distance between current grass and mower position
				var grass_position:Vector2 = Vector2(position_.x,position_.z)
				var mower_postion:Vector2 = Vector2(mower_current_position.x,mower_current_position.z)
				
				var distance_between_them = get_distance_from_player(grass_position,mower_postion,grass_size)
				
				# due to branching, it throws an error if child_ is not declared before branching
				var child_
				var y_test = 75 # FOR TESTING REMOVE THIS LATER THIS IS TO SEE LOD
				if distance_between_them < 120: # HIGH LOD TINKER AS NEEDED
					y_test = 7 # FOR TESTING
					position_.y = y_test
					child_ = grass_mowed_high_LOD.instantiate()
					
					grass_high_LOD[position_] = child_ # store in LOD
					grass_grid[position_] = child_ # store in grass grid
				
				else: #LOW LOD
					child_ = grass_mowed_high_LOD.instantiate()
					grass_grid[position_] = child_ # store in grass grid

				# add it to scene
				mowing_area.add_child(child_)
				
				position_.y = y_test
				child_.position = mowing_area.to_local(position_)
		
				# since later we will be doing a lot of looping though this.
				# convert and do a one order of the a list of the keys (vector3) positions
				grass_grid_keys = grass_grid.keys()
		print(len(grass_grid))
	else: # inital grid is setup already
		
		# convert mower coord into grid coord
		mower_current_position /= grass_size 
		for x in range(20):
			for z in range(20):
				pass
		
		pass
#	print(len(grass_grid))

#
#	var position_ = Vector3(top_x,7,top_z)
#
#	var child_ = grass_unmowed_high_LOD.instantiate()
#
#	mowing_area.add_child(child_)
#
#	child_.position = mowing_area.to_local(position_)
#
#	## testing move the grass over one size
#
#	# calcuate the starting position of x (origin - width/2)
#	top_x -=  level.get_node(".").scale.x * 1.75 # move right this spaces them out
#	print(level.get_node(".").scale.x * 1.75)
#	child_ = grass_unmowed_high_LOD.instantiate()
#
#	mowing_area.add_child(child_)
#	position_ = Vector3(top_x,7,top_z)
#
#
#	child_.position = mowing_area.to_local(position_)

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
