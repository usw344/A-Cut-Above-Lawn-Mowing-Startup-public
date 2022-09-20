extends Spatial

export var width  = 250
export var height = 250

onready var gridmap = $GridMap
signal list_current_cell_ident

func _ready():
	pass


func _on_Mower_this_is_test(collision):
	var grid_position = gridmap.world_to_map(collision.position-collision.normal)
	
	
	var cell_item_ident = gridmap.get_cell_item(grid_position.x, grid_position.y+1,grid_position.z)
	
	if(cell_item_ident != 4):
		gridmap.edit_grid("Testing",grid_position,-1)
	
	if cell_item_ident != -1 and cell_item_ident != 4:
		emit_signal("list_current_cell_ident",cell_item_ident)
#	
	
