extends Node3D
class_name Job_Manager
"""
Manages jobs. Loads the the job the users picks and loads the relevent.
This handles storing and loading either when the game starts up OR when screen are swtiched.
Should allow for multiple jobs to be started at once of different sizes

This also make sures all jobs keep going even in the background mode

Swaps different UI items in and out

EXPECTS: to be added to scene tree
"""
var job_generator:Job_Generator
@onready var job_offer_display:Job_Offer_Display =$"Job Offer Display Overlay/Job Offer Display"

var is_job_offer_display_visible:bool = false

# Called when the node enters the scene tree for the first time.
func _ready():
	job_generator = $"Job Generator"
#	var control_rect:ColorRect = $"Job Display/Background shadow"
#	control_rect.size = Vector2(200,200)
	
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func recieve_job_offer(offer:Job_Offer):
	"""
	Get a new job offer from the Job generator and display it.
	Also store it in an Dictionary for further processing.
	Also store it in the model to allow for global access
	
	Also notify the job_offer_display to update display (if the job offer display is 
	currently displayed )
	"""
	model.push_job_offer(offer)


