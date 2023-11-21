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
	will also load the Job object. 
	
	If the objective is to start a game again (say the user left to another job or went back to another scene)
	This can be done with load_from_model() which will only load the object.
	
	CONDITION: this function should only be called when it is in the scene tree. 
	ELSE: null errors will most likey occur.
	"""
	# to set the custom gridparam first get the data from the Job Object
	if self.is_inside_tree() == false:
		print(" ERROR initialize_game in Mowing Object. Not in scene tree")
		return
	var width:int = job.get_job_size().x
	var length:int = job.get_job_size().y
	
	# set the custom gridmap
	custom_gridmap.set_grid_paramters(width,length)
	
	
	
	pass


func save_object():
	"""
	Return a save state of this object. This action can be reversed using the data from this 
	function passed into the load_object.  
	
	The idea is that the the Job Manager will be responsible for the final save (to file)
	"""
	pass
func load_object():
	"""
	Provided data (in form of the return from save_object()) this function will load an empty 
	Mowing Object function
	"""
	pass
