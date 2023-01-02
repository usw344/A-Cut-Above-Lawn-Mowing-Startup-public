extends Spatial
"""
This script keeps track of all the relevent data for the current level. 
(including how full the storage on the mower is. Money amount. Gas/Electricity amount and any other
job specic choices )



"""

## Variable refernce to nodes

onready var mowing_area = $"Mowing Area"
onready var player_hud = $Player_HUD
onready var storage_truck = $Storage_Depot

####mower variables for fuel
var fuel = 100 
var fuel_used_per_block_removed = 2
var fuel_used_idling_multiplier = 2

####mover variables for grass
var value_of_mowed_grass_in_storage = 2
var value_per_unit  = 0.05

##counter variable used in fuel loss computation due to idleling
var mower_on = 0

##internal script methods functions
var fuel_whole_number_counter = 0 ##variable used in fuel loss computation due to idleling
var storage_is_full_notification_limiter = false
var fuel_is_empty_notification_limiter = false

#################### Variables for fuel and grass screens in game
var show_grass_deposit_screen_if_clicked = false
var show_fuel_screen_if_clicked          = false
var timer_for_button_click_to_display_screen = Timer.new()


#################### Signals
signal send_notification
signal show_grass_deposit_screen
signal add_grass
signal exit(fuel)
signal done

func _ready():
	
#	
	timer_for_button_click_to_display_screen.connect("timeout",self,"remove_press_key")
	add_child(timer_for_button_click_to_display_screen)
	
	player_hud.connect("Return",self,"return_to_managment_screen")
	
	##testing save feature
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	###same for save and laod
	var file = File.new()
	var save_file = "res://Saves/testing_save.save"
	
	##to load
	file.open(save_file,File.READ)
	var save_data = file.get_var(true)
	
	load_data(save_data)
	var a_fuel_object = {"fuel_val":100,"fuel_per_idle":2,"fuel_used_per_block":2}
	set_fuel_vars(a_fuel_object)

#	to save
#	set_grid_vars({"width":10,"length":10,"tileset":1})
#	set_current_job_label("This is a save file testing")
#	file.open(save_file,File.WRITE)
#	file.store_var(save_data(),true)
#
#
#	file.close()

func save_testing():
	if Input.is_action_just_released("save"):
		var file = File.new()
		var save_file = "res://Saves/testing_save.save"
		
		file.open(save_file,File.WRITE)
		file.store_var(save_data(),true)


		file.close()
		print("saved")

"""
	Function to update the fuel and storage
	Signal Receive: from Mowing_Area node, recives how much to update the money and gas
	in format of of a dictionary
"""
func receive_update(update):
	##make releated updates to other areas
	$Player_HUD.add_to_storage(update["storage"])
	$Player_HUD.set_current_fuel_value(get_current_fuel_value()-update["fuel"])

func handle_mower_collision(collision):
	
	##CHECK which thing the collision occured with in game
	var current_name = collision.collider.name
	if current_name == "Storage_Truck":
		add_grass_to_storage()
		empty_storage()
		
		##display screen for 
		player_hud.display_deposit_grass_key_label("K to open grass deposit screen")
		show_grass_deposit_screen_if_clicked = true
		timer_for_button_click_to_display_screen.wait_time = 3.0
		timer_for_button_click_to_display_screen.start()
		
	
	if current_name == "Fuel_Truck":
		pay_for_fuel()

	##if storage is not full and collision is with a block
	if get_storage_value() != 100 and get_current_fuel_value() > 0:
		
		#get location of the block that was collided with
		var grid_position = mowing_area.get_cell_position_at_collision(collision)
		#var grid_pos = $"Mowing Area/GridMap".world_to_map(collision.position-collision.normal)
		
		var cell_item_ident = mowing_area.get_cell_item(grid_position)
		
		#print("grid_position: " + str(grid_pos) + " cell ident " + str(cell_item_ident))
		if(cell_item_ident != 4 and cell_item_ident != -1):
			##return true if that was last cell in current gridmap
			if mowing_area.remove_cell(grid_position): 
				receive_update({"fuel":compute_fuel_loss(true),"storage":value_of_mowed_grass_in_storage})
				emit_signal("done")
			
			##update mower storage and fuel. for now just use a raw value of -1 -1. 
			receive_update({"fuel":compute_fuel_loss(true),"storage":value_of_mowed_grass_in_storage})
		
	##the storage is full and the collision is not with a truck either
	else: 
		# in case where storage is full
		if not storage_is_full_notification_limiter and get_current_fuel_value() > 0: 
			storage_is_full_notification_limiter = true ##stops the notification storage is full from being sent after first collision
			prepare_and_send_notification("Storage Is Full")
			

		##in case it is the fuel that is run out but storage is there
		elif get_current_fuel_value() <= 0 and not fuel_is_empty_notification_limiter: #TO DO REPLACE THIS WITH NOTIFCATION SYSTEM call
			fuel_is_empty_notification_limiter = true
			prepare_and_send_notification("Fuel Empty")
			
"""
	Function to prepare and send a notification
	In this case sends a notification and roughly the time of sending it
"""
func prepare_and_send_notification(wording):
	var time = OS.get_time()
	var string_format = String(time.hour) +":"+String(time.minute)+":"+String(time.second)
	emit_signal("send_notification",String(string_format+ ": "+wording))

"""
	Internal function to move the mower from point to another (not to be confused with
	move_slide as this will do it without simulating movement)
	
	@param x,y,z: three different values relating to the position in area
"""
func go_to(obj,location):
	obj.transform.origin.x = location.x
	obj.transform.origin.z = location.z
	obj.transform.origin.y = location.y
###################################################
"""
	Function empties storage
"""
func add_grass_to_storage():
	emit_signal("add_grass",get_storage_value())
"""
	Set storage amount in mower to zero
"""
func empty_storage():
	player_hud.clear_storage_handler()
	storage_is_full_notification_limiter = false
	
"""
"""
func add_money_for_grass(value_to_add):
	#var add_money_value = compute_storage_value()
	player_hud.add_value_to_money_label(value_to_add)

#################################################### Functions relating to storage
"""
	Function to compute how much money to add based on current storage value
	
	return value of current storage
"""
func compute_storage_value():
	##REASON this function and add_money_for_grass are not merged is that the plan is to add market value calculations in it
	##right now it seems these two functions could be merged
	var storage_value = get_storage_value()
	return storage_value*value_per_unit ##CHANGE HARDCOODE VALUE TO BE RELATIVE TO MARKET VALUE LATER

"""
	Internal function to get current amount of items in mower storage 
	return int value of current mower storage value
"""
func get_storage_value():
	return int(player_hud.get_storage_value())

########################################### Functions relating to fuel 

"""
	Internal function to get current fuel amount in mower
"""
func get_current_fuel_value():
	return int(player_hud.get_current_fuel_value())

func compute_fuel_loss(is_block):
	if not is_block:
		return steps_to_fuel_loss() * fuel_used_idling_multiplier
	else:
		return fuel_used_per_block_removed
	return 0
	
"""
	Internal function that computes fuel loss due to simply running the mower in game
"""
func steps_to_fuel_loss(): ##NEEDS MORE COMMENTING EXPLAINING FUNCTION
	if fmod(mower_on, 5) == 0:
		mower_on = 0
		return 1
	else:
		return 0

"""
	Internal function that increased the fuel based on amount being purchased
	Also reduces money listed
"""
func pay_for_fuel(): ##INCOMPLETE FUNCTION since does not allow currently to fill fuel based on amount of cash spent
	player_hud.set_current_fuel_value(100)
	fuel_is_empty_notification_limiter = false


func set_fuel_vars(fuel_object):
	fuel = fuel_object["fuel_val"]
	fuel_used_idling_multiplier = fuel_object["fuel_per_idle"] 
	
	fuel_used_per_block_removed= fuel_object["fuel_used_per_block"]
	
	
	
	$Player_HUD.set_current_fuel_value(fuel)

##################################################### Other functions
func _physics_process(delta):
	###adds approx. amount of time the mower object has been running 
	mower_on += delta
	mower_on = stepify(mower_on,0.01) ##ROUNDs the value to 2 decimal places
	save_testing()
	receive_update({"fuel":compute_fuel_loss(false),"storage":0})

func _input(event):
	if show_grass_deposit_screen_if_clicked and Input.is_action_just_released("Open Grass Deposit Screen"):
		emit_signal("show_grass_deposit_screen")
	if Input.is_action_just_released("exit_to_managment_screen"):
		return_to_managment_screen()

"""
	Remove the text on screen displaying what to click for deposit screen
"""
func remove_press_key():
	show_grass_deposit_screen_if_clicked = false
	show_fuel_screen_if_clicked = false
	
	player_hud.clear_press_key_labels()
	
	

func display_done_label():
	$Done.show()
	$"Managment Screen".show()

########################################################## FUNCTIONS relating to the main tscn

func return_to_managment_screen():
	emit_signal("exit",get_current_fuel_value()) ###IN THIS SIGNAL ALSO RETURN ANY DATA THAT NEEDS TO BE STORED

func set_current_job_label(text):
	$Player_HUD.set_current_job_label(text)

"""
	Function to set the grid variables for this job
"""
func set_grid_vars(grid_var_object):
	var width = grid_var_object["width"]
	var length = grid_var_object["length"]
	var tileset = grid_var_object["tileset"]
	
	
	$"Mowing Area".set_mowing_area(width,length,tileset)

	##set location for start points
	$"Mowing Area".set_truck_location("right",$Storage_Depot)
	$"Mowing Area".set_truck_location("left",$Fuel_Truck)
	$"Mowing Area".set_mower_position($Mower)
	
"""
	Return data that is to be stored
"""
func save_data():
	var game = $"Mowing Area"
	var data_object = {
		"Game grid":game.get_grid(),
		"Game size type":null,
		"Grid Size":game.get_grid_size(),
		"Fuel truck location":$Fuel_Truck.transform.origin,
		"Storage depot location":$Storage_Depot.transform.origin,
		"Mower location":$Mower.transform.origin,
		"Job label":$Player_HUD.get_current_job_label(),
		"Job elapse":$Player_HUD.get_elapse()
	}
	
	return data_object
	
func load_data(data_object):
	set_current_job_label(data_object["Job label"])
	go_to($Mower,data_object["Mower location"])
	go_to($Storage_Depot,data_object["Storage depot location"])
	
	go_to($Fuel_Truck,data_object["Fuel truck location"])
	
	$"Mowing Area".set_grid_size(data_object["Grid Size"])
	$"Mowing Area".set_grid(data_object["Game grid"],data_object["Grid Size"])
	$Player_HUD.set_elapse(data_object["Job elapse"])
	print('loaded game')
	
