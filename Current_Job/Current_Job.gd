extends Spatial
"""
This script keeps track of all the relevent data for the current level. 
(including how full the storage on the mower is. Money amount. Gas/Electricity amount and any other
job specic choices )



"""

var storage = 0
var storage_cap = 25


## Variable refernce to nodes
onready var mowing_area = $Mowing_Area/GridMap
onready var grid = $Mowing_Area/GridMap
onready var player_hud = $Player_HUD

##mower variables
var fuel = 100
var value_of_mowed_grass_in_storage = 5

func _ready():
	go_to($Storage_Depot,-5,1,20)


"""
	Function to update the fuel and storage
	Signal Receive: from Mowing_Area node, recives how much to update the money and gas
	in format of of a dictionary
"""
func receive_update(update):
	$Player_HUD.add_to_storage(update["storage"])
	$Player_HUD.set_current_fuel_value(update["fuel"])

func handle_mower_collision(collision):
	
	var currentName = collision.collider.name
	if currentName == "Truck":
		add_money_for_grass()
		empty_storage()

	if get_storage_value() != 100:
		
		#get location of the block that was collided with
		var grid_position = grid.world_to_map(collision.position-collision.normal)
		var cell_item_ident = grid.get_cell_item(grid_position.x, grid_position.y+1,grid_position.z)
		
		if(cell_item_ident != 4 and cell_item_ident != -1):
			grid.edit_grid("Testing",grid_position,-1)
			
			##update mower storage and fuel. for now just use a raw value of -1 -1. 
			receive_update({"fuel":75,"storage":value_of_mowed_grass_in_storage})
	else:
		print("storage_is_full") #TO DO REPLACE THIS WITH NOTIFCATION SYSTEM call
"""
	Internal function to move the mower from point to another (not to be confused with
	move_slide as this will do it without simulating movement)
	
	@param x,y,z: three different values relating to the position in area
"""
func go_to(obj,x, y, z):
	obj.transform.origin.x = x
	obj.transform.origin.z = z
	obj.transform.origin.y = y

func empty_storage():
	player_hud.clear_storage_handler()
"""
"""
func add_money_for_grass():
	var add_money_value = compute_storage_value()
	player_hud.add_value_to_money_label(add_money_value)


func compute_storage_value():
	var storage_value = get_storage_value()
	var value_per_unit = 5
	
	
	return storage_value*value_per_unit ##CHANGE HARDCOODE VALUE TO BE RELATIVE TO MARKET VALUE LATER


func get_storage_value():
	return int(player_hud.get_storage_value())
