extends GridMap

#the noise object
var noise = OpenSimplexNoise.new()

#Function to hold basic grid shapes
var grids = {}
export var grid_width = 50
export var grid_length = 50

var block_list = {
	"green":       1,
	"blue":        2,
	"dark_purple": 0,
	"ground_block": 4,
	"texture_grass": 5
}

func _ready():
	make_new_grid("Testing",grid_width,1,grid_length)
	
	display_this_grid("Testing",1) #draw the things to be destroyed


	

"""
	Function to make a new level and display it
	@param Title: ID for the level
	@param width: the x size of the gridmap
	@param height: the y size of the gridmap
	@param length: the z size of the gridmap
	
	POST: the function adds a new seed based level into grids 
"""
func make_new_grid(title,width,height,length):
	var current_grid = {}
	
	for x in width:
		for y in height:
			for z in length:
				var current_noise = 2*(abs(noise.get_noise_2d(x ,z)))
				current_grid[Vector2(x,z)] = current_noise
	
	grids[title] = [current_grid,width,height,length]
"""
	Function to check if a give value is between two bounds
	@param val: value to check
	@param lower: lower bound
	@param upper: upper bound
"""
func between(val, lower, upper):
	return lower <= val and val < upper
"""
	Function to display a grid that already has a noise map
	@param grid_id: the grid_id in the grids{} dict
"""
func display_this_grid(grid_id,layer):
	var width = grids[grid_id][1]
	var height = grids[grid_id][2]
	var length = grids[grid_id][3]
	
	
	var current_grid = grids[grid_id][0]
	
	for x in width:
		for y in height:
			for z in length:
				var current_val_of_noise = current_grid[Vector2(x,z)]
				if between(current_val_of_noise,0,0.3):
					set_cell_item(x,layer,z,block_list["dark_purple"])
				elif between(current_val_of_noise,0.3,0.8):
					set_cell_item(x,layer,z,block_list["texture_grass"])
				else:
					set_cell_item(x,layer,z,block_list["blue"])
"""
	Function to generate a noise grid. [internal method. Should not be used by itself]
	@param grid: The dictionary to contain the noise values. Key: Vector2 (x,z), 
	Value: the noise value for that place 
	
	@param x_constraint: the width of the gridmap (x in 2d space_)
	@param z_constraint: the width in another direction of grid (y in 2d space)
	@param y_constraint: the height 
	
	POST: 
"""
func get_noise(grid,x_constraint,y_constraint,z_constraint):
	for x in x_constraint:
		for y in y_constraint:
			for z in z_constraint:
				var current_noise = noise.get_noise_2d(x,z)
				grid[Vector2(x,z)] = current_noise

"""
	Function to allow editing a grid
"""
func edit_grid(grid_ID,location,replacment_block_id):
	set_cell_item(location.x,location.y+1,location.z,replacment_block_id)
