extends Node

var level = preload("res://Mowing/Current_Job/Current_Job.tscn")
#var game_screen = preload("res://UI/Main Game Screen/Game Screen.tscn")
var new_game = preload("res://UI/Menus/New Game Menu/New Game Menu.tscn")
onready var grass_deposit_screen = load("res://Mowing/Grass Deposit and Sale/Grass Desposit and Sale.tscn").instance()

onready var notification_system = $Notification_System
onready var current_menu = $Main_Menu

onready var fuel_price = $"Fuel Price" ###THIS IS TO BE CHANGED TO THE CORRECT ONE LATER
onready var grass_price = $"Grass Price"

onready var game_management_screen = preload("res://UI/Main Game Screen/Game Screen.tscn")
onready var new_game_screen
var buttons = {}
var game_scene = null

##Variables for instances
var game
var management_screen

##to store game variables. These MIGHT be stored in save
onready var model = $Model


func _ready():
	
	#setup buttons for main_menu
	buttons = current_menu.get_buttons()
	assign_button_key_press(buttons)

	
	##for main menu mouse mode should be visable
	display_mouse()
	
	##if a current job is set change to it
	model.connect("set_current_scene_to_job",self,"change_to_game")


func change_to_game():
	game = model.get_current_job()["Game"]
	if model.started_game():
		### MAY NEED THIS 
		pass
	else:
		##set signals
		game.connect("send_notification", notification_system, "add_notification")
		game.connect("show_grass_deposit_screen",self, "display_grass_deposit_screen")
		game.connect("add_grass",self,"add_grass_to_storage")
		game.connect("exit",self,"change_to_managment_screen")
		game.connect("done",self,"current_job_selected_complete")
	
	
	remove_mouse()

	##Remove managment_screen
	management_screen.pause()
	remove_child(management_screen)
	
	game.set_fuel_vars(model.get_fuel_object())
	
	add_child(game) 

func change_to_managment_screen(fuel_value):
	remove_child(game)
	display_mouse()
	add_child(management_screen)
	
	management_screen.unpause()
	
	model.remove_current_job()
	model.set_fuel(fuel_value)

"""
	Function to start a new game by brining up new game selection screen.
"""
func new_game():
	new_game_screen = new_game.instance()
	add_child(new_game_screen)

	new_game_screen.connect("new_game",self,"first_switch_to_managment_screen")
	
	current_menu.queue_free()
	current_menu = new_game_screen

"""
	When new game is started this function is used to start the managment screen
"""
func first_switch_to_managment_screen(game_num,game_diff):
	management_screen = game_management_screen.instance()
	add_child(management_screen)
	
	management_screen.connect("save_current_game_data",self,"save_game")
	management_screen.set_model(model)
	
	model.set_game_number(game_num)
	model.set_game_difficulty(game_diff)

	##current menu
	current_menu.queue_free()

"""
	Load a game from information
"""
func load_a_game(game_location):
	### determine the location to load. This is done in the
	### set game function of the model res://Saves/game_location/
	model.set_game_number(game_location)
	
	##this functions loads the data into the current games, on offer labels etc
	model.load_information()
	
	###fill in the objects in the relevent nodes
	
	##setup the managment screen
	management_screen = game_management_screen.instance()
	add_child(management_screen)
	
	management_screen.connect("save_current_game_data",self,"save_game")
	management_screen.set_model(model)
	
	##enter the data for the mangament screen
	management_screen.load_data() ##handle all data loading needed from model
	
	##set the screen to be the loaded managment screen
	current_menu.queue_free()
"""
	Connects with signal from game object
"""
func current_job_selected_complete():
	model.add_to_past_jobs()
	$Timer.start()
	game.display_done_label()
	

	
"""
	Internal method to take a dictionary with buttons as value in key:value pair and
	assign them to the signal "pressed" and pass in button.name as argument
	
	@param button_dict: a dictionary with value in key:value pair being a reference to a button
	node
"""
func assign_button_key_press(button_dict):
	for key in button_dict:
		#get the button in question
		var button = button_dict[key]
		
		###NOTE button name refers to what is listed in the node list NOT the dict key
		##NOT the button text
		button.connect("pressed",self,"assign_button_action",[button.name])
		#button.connect("pressed",self,"assign_button_action",[key])
"""
	Internal function handle button clicks. Function uses other functions to handle
	what should happen when a specific button is clicked
"""
func assign_button_action(button_name):
	var next_menu = null
	match button_name:
		"Play":
			new_game()
		"Settings":
			#change the scene to the settings menu
			next_menu = load("res://UI/Menus/Settings_Menu/Settings.tscn").instance()
			add_child(next_menu)
			current_menu.queue_free()
			current_menu = next_menu
			
			assign_button_key_press(current_menu.get_buttons())
		"Saved Games":
			next_menu = load("res://UI/Menus/Load Menu/Load Game Menu.tscn").instance()
			add_child(next_menu)
			current_menu.queue_free()
			current_menu = next_menu
			
			current_menu.connect("load_game",self,"load_a_game")
			assign_button_key_press(current_menu.get_buttons())
			
		"Main_Menu":
			next_menu = load("res://UI/Menus/Main_Menu/Main_Menu.tscn").instance()
			add_child(next_menu)
			current_menu.queue_free()
			current_menu = next_menu
			
			assign_button_key_press(current_menu.get_buttons())


############################################ Functions relating to input and mouse modes
func _input(_event):
	if Input.is_action_just_released("pause"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			display_mouse()
		else:
			remove_mouse()
	if Input.is_action_just_pressed("save"):
		model.save_information()
func remove_mouse():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func display_mouse():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


############################################ Functions relating to grass deposit screen
"""
	Function to display the grass desposit screen when the signal is received
"""
func display_grass_deposit_screen():
	
	##remove current 
	remove_child(game)                
	notification_system.clear_all_displayed_notifications()
	
	##get the information from the model and add it to grass screen. Pass in grass price model
	grass_deposit_screen.set_grass_stored(model.get_grass())
	grass_deposit_screen.set_funds(model.get_funds())
	grass_deposit_screen.set_grass_price_model(grass_price)
	
	
	add_child(grass_deposit_screen)
	grass_deposit_screen.get_items_list()
	set_grass_deposit_screen_signals()
	
	display_mouse()

"""
	Connect the relevent signals from the grass desposit screen scnene to functions
"""
func set_grass_deposit_screen_signals():
	grass_deposit_screen.get_items_list()
	
	grass_deposit_screen.get_item("back_button").connect("pressed",self,"close_grass_deposit_screen")
	grass_deposit_screen.connect("update_model",self,"update_model")

"""
	Function that is used when signal to close grass desposit screen is received
"""
func close_grass_deposit_screen():
	remove_child(grass_deposit_screen)
	
	add_child(game)
	remove_mouse()

"""
	Function to use to add grass to model
"""
func add_grass_to_storage(value):
	model.set_grass(model.get_grass() + value)
	
func update_model():
	model.set_grass( grass_deposit_screen.get_grass_stored() )
	model.set_funds( grass_deposit_screen.get_funds()   )
	

func test_model_reference():
	print("This is current test_var value " + str(model.get_test_var()))


"""
	Save data
"""
func save_game():
	model.save_information()
