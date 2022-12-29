extends Node

var level = preload("res://Mowing/Current_Job/Current_Job.tscn")
var game_screen = preload("res://UI/Main Game Screen/Game Screen.tscn")

onready var grass_deposit_screen = load("res://Mowing/Grass Deposit and Sale/Grass Desposit and Sale.tscn").instance()

onready var notification_system = $Notification_System
onready var current_menu = $Main_Menu

onready var fuel_price = $"Fuel Price" ###THIS IS TO BE CHANGED TO THE CORRECT ONE LATER
onready var grass_price = $"Grass Price"

onready var game_management_screen = preload("res://UI/Main Game Screen/Game Screen.tscn")

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
	remove_mouse()

	game.connect("send_notification", notification_system, "add_notification")
	game.connect("show_grass_deposit_screen",self, "display_grass_deposit_screen")
	game.connect("add_grass",self,"add_grass_to_storage")
	game.connect("exit",self,"change_to_managment_screen")
	
	game.set_current_job_label(model.get_current_job()["Job Text"])
	
	management_screen.pause()
	remove_child(management_screen)
	
	add_child(game) 

func change_to_managment_screen():
	remove_child(game)
	display_mouse()
	add_child(management_screen)
	
	management_screen.unpause()
	
	model.remove_current_job()


"""
	TODO: Function to start a new game by brining up new game selection screen.
	**CURRENT** Currently swtiches to game scene
"""
func new_game():
	##old
	
	management_screen = game_management_screen.instance()
	add_child(management_screen)
	current_menu.queue_free()
	
	management_screen.set_model(model)
	
#	game = level.instance()
#	add_child(game) 
#	current_menu.queue_free()
#	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
#
#	game.connect("send_notification", notification_system, "add_notification")
#	game.connect("show_grass_deposit_screen",self, "display_grass_deposit_screen")
#	game.connect("add_grass",self,"add_grass_to_storage")
	

	
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
		
		#
		button.connect("pressed",self,"assign_button_action",[button.name])
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
			pass
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
