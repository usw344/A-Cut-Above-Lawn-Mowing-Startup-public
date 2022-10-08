extends GridMap


var noise = OpenSimplexNoise.new()

##var to hold the 
var noise_grid = {}


# Called when the node enters the scene tree for the first time.
func _ready():
	
	
	var val = 100
	for x in range (val):
		for y in range (15,val,1):
			for z in range (val):
				if y < noise.get_noise_2d(x,z) * 8 + 5:
					set_cell_item(x,y,z,2)
				elif y < noise.get_noise_2d(x,z) * 10 + 15:
					set_cell_item(x,y,z,1)


"""
	Function to generate a noise grid.
	param grid: The dictionary to contain the noise values. Key: Vector2 (x,z), Value: the noise value for that place 
"""
func get_noise(grid,x_constraint,y_constraint,z_constraint):
	for x in x_constraint:
		for y in y_constraint:
			for z in z_constraint:
				var noise = noise.get_noise_2d(x,z)
				grid[Vector2(x,z)] = noise
				
