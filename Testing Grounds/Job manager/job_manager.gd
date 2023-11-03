extends Node3D
class_name Job_Manager
"""
Manages jobs. Loads the the job the users picks and loads the relevent.
This handles storing and loading either when the game starts up OR when screen are swtiched.
Should allow for multiple jobs to be started at once of different sizes

EXPECTS: to be added to scene tree
"""
var job_generator:Job_Generator

# Called when the node enters the scene tree for the first time.
func _ready():
	job_generator = $"Job Generator"
	
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func recieve_job_offer(offer:Job_Offer):
	"""
	Get a new job offer from the Job generator and display it.
	Also store it in an Dictionary for further processing
	"""
	pass
	
func delete_job_offer():
	pass
