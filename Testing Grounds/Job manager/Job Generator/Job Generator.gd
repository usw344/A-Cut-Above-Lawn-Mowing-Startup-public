extends Node3D
class_name Job_Generator
"""

	Generate Job options and display them.
	Handles which difficulty the jobs should have 
	
	EXPECTS: to be added to scene (this uses the Model and process functions)

"""

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func if_new_job_is_to_be_added() ->bool:
	"""
	Abstraction function to see if a new job should be added
	The purpose of this function is to abstract away the calculation 
	that is used to control the flow of jobs. 
	
	Exmaple: this function can later use a complex equation that factors in 
	customer satisfaction, market state, Game difficulty setting etc.
	
	CURRENTLY: this just uses a timer which increaes with the number of unaccepted jobs
	So 0 or some jobs == faster timer etc. 
	
	Returns true if a new job should be added
	Returns false if a new job should not be added
	"""
	var timer:Timer = $"Add Job Timer"
	if timer.is_stopped():
		# reset the timer (calculate the new time to be used)
		return true
	return false

