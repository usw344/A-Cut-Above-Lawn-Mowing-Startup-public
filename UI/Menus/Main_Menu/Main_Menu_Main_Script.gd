extends Control


onready var menu_label = $CanvasLayer/Main_Menu_Label


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
		"play":$CanvasLayer/Play,
		"settings":$CanvasLayer/Settings,
		"saved_game":$"CanvasLayer/Saved Games"
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
