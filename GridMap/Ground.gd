extends Spatial
"""
	WHAT IS THE USE OF THIS SCRIPT. SEE IF IT CAN BE ROLLED INTO THE D
"""

export var width  = 250
export var height = 250

onready var gridmap = $GridMap

func _ready():
	pass


func mower_collided_handle(collision):
	var grid_position = gridmap.world_to_map(collision.position-collision.normal)
	var cell_item_ident = gridmap.get_cell_item(grid_position.x, grid_position.y+1,grid_position.z)
	if(cell_item_ident != 4):
		gridmap.edit_grid("Testing",grid_position,-1)

#	
	
