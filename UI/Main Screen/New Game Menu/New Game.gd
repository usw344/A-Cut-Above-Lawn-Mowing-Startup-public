extends Control



func _ready():
	pass 

func _process(delta):
	pass

func start_new_game() ->void:
	'''
	Make a new Game Profile Object and save it to file
	to file. Also load an initial model object
	
	Condition Check 1: Some text is entered into the text entry
	
	Condition Check 2: No existing game profile exists with this name 
	'''
	if $"Text Entry Background/Game Name Entry".text == "":
		pass
	# now check if this profile object exists
	var dir = DirAccess.open("user://")
	
func check_and_open_save_directory():
	pass
