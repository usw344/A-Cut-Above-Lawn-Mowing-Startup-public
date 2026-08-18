extends Control



func _ready():
	var go_button:Button = $Go
	go_button.pressed.connect(start_new_game)

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
		print("error no name entered")
	else:
		# now check if this profile object exists
		var save_directory:DirAccess = open_saves_directory()
		
		## grab the Game Profile object and save it. (note it will be empty init) 
		var game_profile = model.get_game_profile_object()
		
		# load the game scene now
	
	
func open_saves_directory() -> DirAccess:
	"""
	Check if the save directory exists:
		yes: then return a DirAccess.open() object
		no:  make the save directory in user:// and then return DirAccess.open() object
	"""
	## DirAcess.open returns null if directory does not exists
	var directory:DirAccess = DirAccess.open("user://saves")
	
	if directory != null: ## saves folder exists.
		return directory
	else: ## make saves folder
		DirAccess.make_dir_absolute("user://saves")
		return DirAccess.open("user://saves") # note directory var from above is null
