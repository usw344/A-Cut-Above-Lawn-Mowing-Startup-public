extends Node

var level = preload("res://Mowing/Current_Job/Current_Job.tscn")
var game_screen = preload("res://UI/Main Game Screen/Game Screen.tscn")

onready var notification_system = $Notification_System
onready var current_menu = $Main_Menu

var buttons = {}
var game_scene = null

var noise = OpenSimplexNoise.new()

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
	#add_child(game_screen.instance())
	#current_menu.queue_free()
	
	##old
	var new_game = level.instance()
	add_child(new_game) 
	current_menu.queue_free()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	new_game.connect("send_notification", notification_system, "add_notification")
	
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


func _input(_event):
	if Input.is_action_just_released("pause"):
		var current_mouse_mode = Input.mouse_mode
		if current_mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

#var testingVector = Vector2()
#var counter = 10
#func _process(delta):
#	counter += delta * 15
#	testingVector = Vector2(counter, 800+noise.get_noise_2d(counter+10,counter/2)*500)
#	line.add_point(testingVector)
#	line2.add_point( Vector2(counter, 800+noise.get_noise_1d(counter+10)*500)  )
