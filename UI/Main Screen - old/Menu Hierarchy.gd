extends Control


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func handle_button_press(action:String) -> void:
	"""
	Manager function to handle all signal matters. Expects to recieve a String which contains 
	the action keyword for the button that was clicked
	"""
	if action == "New Game":
		pass
	elif action == "Load Game":
		pass
	elif action == "Options":
		pass
	pass
