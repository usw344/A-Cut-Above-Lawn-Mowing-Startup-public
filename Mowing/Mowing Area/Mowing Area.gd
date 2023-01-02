extends Spatial

var noise = OpenSimplexNoise.new()
var noise_grid = {}
var count_in_gridmap = 0

var grid_margin = 10
var grid_size = Vector3()
var block_list = {
	"dark_purple": 0,
	"green":       1,
	"blue":        2,
	"texture_grass": 5
}
#var f = RandomNumberGenerator.new()
func _ready():
	#For testing to see if code is working
#	set_mowing_area(10,10,1)
#	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
#
#	set_truck_location("right",$Fuel_Truck_Container)
#	set_truck_location("left",$Storage_Depot)
#	set_mower_position($Mower_Basic)
#	$Mower_Basic.max_speed = 70
#	$Mower_Basic.jump_strength = 30

	self.remove_child($Storage_Depot)
	self.remove_child($Fuel_Truck_Container)
	self.remove_child($Mower_Basic)
	
############################################################### FUNCTION that can be
															  # used by other scripts

"""
	Function to draw the grid map (the blocks that are mowed)

"""
func set_mowing_area(width,length,tileset):
	grid_size.x = width
	grid_size.z = length
	grid_size.y = 1
	set_noise()
	calc_grid(width,1,length)
	set_gridmap(width,1,length)
	
	set_ground_area(width,length)
	
	
"""
	Function to set the ground under the grid_map in this code
"""
func set_ground_area(width,length):
	var mesh_instance = $"Ground Area/MeshInstance"
	var collision_shape = $"Ground Area/CollisionShape"
	
	##move the ground to be in line with the grid map 
	$"Ground Area".transform.origin.y = 0
	
	##adding width and height since gridmap uses size 2 squares
	$"Ground Area".transform.origin.x += width
	$"Ground Area".transform.origin.z += length
	
	#set the size of shape
	collision_shape.shape.extents.x = width
	collision_shape.shape.extents.z = length
	
	mesh_instance.mesh.size.x = width*2
	mesh_instance.mesh.size.z = length*2
	
	##add space for trucks and start space
#	var margin = width/6 + 5 ##How much space for the trucks
	
	collision_shape.shape.extents.x += grid_margin
	mesh_instance.mesh.size.x += grid_margin*2
	
	$"Ground Area".transform.origin.x -= grid_margin


################################################################# FUNCTIONS

"""
	Function to calculate the noise values for the grid
"""
func calc_grid(width,height,length):
	for x in width:
		for y in height:
			for z in length:
				var current_noise = 2*(abs(noise.get_noise_2d(x ,z)))
				noise_grid[Vector2(x,z)] = current_noise

func set_gridmap(width,height,length):
	var gridmap = $GridMap ###THIS COULD RESULT IN NULL DEPENDING ON IF THE GAME HAS ENTERED
	for x in width:
		for y in height:
			for z in length:
				var current_val_of_noise = noise_grid[Vector2(x,z)]
				if current_val_of_noise != -1000:
					if between(current_val_of_noise,0,0.3):
						gridmap.set_cell_item(x,1,z,block_list["dark_purple"])
					elif between(current_val_of_noise,0.3,0.8):
						gridmap.set_cell_item(x,1,z,block_list["texture_grass"])
					else:
						gridmap.set_cell_item(x,1,z,block_list["blue"])
					count_in_gridmap += 1

func set_noise():
	randomize()
	noise.set_seed(randi())
	noise.set_octaves(6)

########################################################### FUNCTIONS for truck placement
"""
	Sets the truck position
"""
func set_truck_location(side,truck):
	if side == "left":
		truck.transform.origin.z+= 3
	else:
		var truck_distance = 20
		if grid_size.x <= 10:
			truck_distance = 13.5
		truck.transform.origin.z+= truck_distance ##minus 2 to account for the width of truck
	
	#setting height
	truck.transform.origin.y = 3
	
	#set to zero as a starting point
	truck.transform.origin.x = 0
	truck.transform.origin.x -=  grid_margin
	

func set_mower_position(mower_object):
	mower_object.transform.origin = Vector3(-grid_margin,3,9)
	
########################################################### FUNCTION relating to GRIDMAP
"""
	Function to remove a cell from the grid map
	
	return if the cell removed was the last one then this returns true
"""
func remove_cell(cell_location):
	var gridmap = $GridMap
	noise_grid[Vector2(cell_location.x,cell_location.z)] = -1000
	gridmap.set_cell_item(cell_location.x,cell_location.y,cell_location.z,-1)
	count_in_gridmap -= 1
	return completed()
	
func get_cell_item(in_grid_location):
	var gridmap = $GridMap
	return gridmap.get_cell_item(in_grid_location.x, in_grid_location.y,in_grid_location.z)

func get_cell_position_at_collision(collision):
	var gridmap = $GridMap
	return gridmap.world_to_map(collision.position-collision.normal)
	

func completed():
	if count_in_gridmap == 0:
		return true


"""
	Function to check if a give value is between two bounds
	val: value to check
	lower: lower bound
	upper: upper bound
"""
func between(val, lower, upper):
	return lower <= val and val < upper

##################### SET and GET functions for saving

func get_grid():
	return noise_grid

func set_grid(grid_data,grid_data_size):
	noise_grid = grid_data
	set_gridmap(grid_data_size.x,grid_data_size.y,grid_data_size.z)
	set_ground_area(grid_data_size.x,grid_data_size.z)

"""
	Function to return grid_size
	return Vector3 of grid size
"""
func get_grid_size():
	return grid_size
"""
	Function to set grid size
	size: Vector3 of grid size
"""
func set_grid_size(size):
	grid_size = size
