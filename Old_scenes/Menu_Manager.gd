extends Node

signal start_game

var current_screen = null
var menu_buttons = []
var lock = false

onready var screens = {
	"start_screen": $Start_Screen,
	"pause_screen": $Pause_Menu
}

func _ready():
	register_buttons()
	change_screen($Start_Screen)

"""
	Function to get buttons from the game menues
"""
func register_buttons():
	menu_buttons =$Start_Screen/MarginContainer/VBoxContainer/Buttons.get_buttons()+$Pause_Menu/MarginContainer/VBoxContainer/Buttons.get_buttons()
	for button in menu_buttons:
		button.connect("pressed",self,"_on_button_pressed",[button.name])
		
	

func _on_button_pressed(name):
	if lock:
		return
	match name:
		"New Game":
			
			change_screen(null)
			yield(get_tree().create_timer(0.01),"timeout")
			emit_signal("start_game")
		"Settings":
			change_screen(screens["pause_screen"])
		"Saved Games":
			pass
		"Resume_Game":
			pass
		"Save":
			pass
		"Main_Menu":
			pass

func change_screen(new_screen):
	if current_screen:
		current_screen.disappear()
		yield(current_screen.tween, "tween_completed")
	current_screen = new_screen
	if new_screen:
		current_screen.appear()
		yield(current_screen.tween, "tween_completed")

func block_this(val):
	lock = val

func show_pause_menu():
	change_screen(screens["pause_screen"])
