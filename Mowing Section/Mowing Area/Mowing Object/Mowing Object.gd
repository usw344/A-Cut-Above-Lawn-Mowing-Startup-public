extends Node3D

"""
Object to hold the actual mowing game. This contains the Custom_Gridmap and also
the mowing UI. This will also store all necessary data to save/load a job 

This object has a save_object() and load_object() method

"""
## Job object with the information of this given job (size etc.)
var job:Job 

var custom_gridmap:Custom_Gridmap

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func initialize_game():
	"""
	Function to start the job intially. Note this function should only be called ONCE per job. 
	After this is called, calling it again will wipe the mowing progress made and reset to an 
	default mowing job based on the params set in the Job object.
	
	If the objective is to load a saved game this can be done using the save/load functions. Those functions
	will also load the Job object into the job array
	
	If the objective is to start a game again (say the user left to another job or went back to another scene)
	This can be done with load_from_model() which will only load the object.
	"""
	pass


func save_object():
	pass
func load_object():
	pass
