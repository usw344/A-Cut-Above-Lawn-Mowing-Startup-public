extends Spatial

var grid

func _ready():
	pass
	

func new_grid(width,length,tile_num):
	grid = $GridMap
	grid.new_noise()
	grid.set_grid_width(width)
	grid.set_grid_length(length)
	grid.grid()
