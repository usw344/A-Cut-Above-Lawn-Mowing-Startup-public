extends Node2D

onready var text_rect = $TextureRect
onready var menu_label = $CanvasLayer/MarginContainer/VBoxContainer/Settings_Menu_Label


func _ready():
	pass


"""
	Internal method to handel background screen image size resizing upon screen being resized
"""
func screen_resized():
	pass


"""
	Return a dictionary of buttons in format button_name:reference_to_button (key:value)
	
	@returns  a dictionary in format button_name:reference_to_button.
"""
func get_buttons():
	return {
		"Main_Menu":$CanvasLayer/MarginContainer/VBoxContainer/Main_Menu
	}

"""
	Return the menu label
"""
func get_label():
	return menu_label


"""
	Set the text for the label
	@param new_text: the new text for the label
"""
func set_label_text(new_text):
	menu_label.text = new_text
