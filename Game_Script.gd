extends Node

var level = preload("res://Level/Level.tscn")



onready var current_menu = $Main_Menu

var buttons = {}
var game_scene = null
func _ready():
	
	#setup buttons for main_menu
	buttons = current_menu.get_buttons()
	assign_button_key_press(buttons)

	
	##for main menu mouse mode should be visable
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	

"""
	TODO: Function to start a new game by brining up new game selection screen.
	**CURRENT** Currently swtiches to game scene
"""
func new_game():
	add_child(level.instance()) 
	current_menu.queue_free()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	
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
			
			next_menu = load("res://Menus/Settings/Settings.tscn").instance()
			add_child(next_menu)
			current_menu.queue_free()
			current_menu = next_menu
			
			assign_button_key_press(current_menu.get_buttons())
		"Saved Games":
			pass
		"Main_Menu":
						
			next_menu = load("res://Menus/Main_Menu/Main_Menu.tscn").instance()
			add_child(next_menu)
			current_menu.queue_free()
			current_menu = next_menu
			
			assign_button_key_press(current_menu.get_buttons())


func _input(event):
	if Input.is_action_just_released("pause"):
		pass

