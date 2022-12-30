extends Spatial

var noise = OpenSimplexNoise.new()
var noise_grid = {}

var block_list = {
	"dark_purple": 0,
	"green":       1,
	"blue":        2,
	"texture_grass": 5
}

func _ready():
	##For testing to see if code is working
	set_mowing_area(15,15,1)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	

############################################################### FUNCTION that can be
															  # used by other scripts

"""
	Function to draw the grid map (the blocks that are mowed)

"""
func set_mowing_area(width,length,tileset):
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
	$"Ground Area".transform.origin.y = 2
	
	##adding width and height since gridmap uses size 2 squares
	$"Ground Area".transform.origin.x += width
	$"Ground Area".transform.origin.z += length
	
	#set the size of shape
	collision_shape.shape.extents.x = width
	collision_shape.shape.extents.z = length
	
	mesh_instance.mesh.size.x = width*2
	mesh_instance.mesh.size.z = length*2
	
	##add space for trucks and start space
	var margin = width/6 + 5
	collision_shape.shape.extents.x += margin
	mesh_instance.mesh.size.x += margin*2
	
	$"Ground Area".transform.origin.x -= margin
	
	

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
	print("setting")
	var gridmap = $GridMap ###THIS COULD RESULT IN NULL DEPENDING ON IF THE GAME HAS ENTERED
	for x in width:
		for y in height:
			for z in length:
				var current_val_of_noise = noise_grid[Vector2(x,z)]
				if between(current_val_of_noise,0,0.3):
					gridmap.set_cell_item(x,1,z,block_list["dark_purple"])
				elif between(current_val_of_noise,0.3,0.8):
					gridmap.set_cell_item(x,1,z,block_list["texture_grass"])
				else:
					gridmap.set_cell_item(x,1,z,block_list["blue"])

func set_noise():
	randomize()
	noise.set_seed(randi())
	noise.set_octaves(6)

"""
	Function to check if a give value is between two bounds
	val: value to check
	lower: lower bound
	upper: upper bound
"""
func between(val, lower, upper):
	return lower <= val and val < upper
