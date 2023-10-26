extends Node3D
"""
Manages jobs. Loads the the job the users picks and loads the relevent.
This handles storing and loading either when the game starts up OR when screen are swtiched.
Should allow for multiple jobs to be started at once of different sizes
"""
var job_generator:Job_Generator

# Called when the node enters the scene tree for the first time.
func _ready():
	job_generator = Job_Generator.new()
	# also add this to the scene tree
	add_child(job_generator)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
