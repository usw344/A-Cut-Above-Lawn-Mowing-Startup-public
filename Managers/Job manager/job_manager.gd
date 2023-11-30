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
@onready var job_offer_display:Job_Offer_Display =$"Display/Job Offer Display"

var is_job_offer_display_visible:bool = false


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
	
	Notify the job_offer_display to update display (if the job offer display is 
	currently displayed )
	
	The reason this signal is not directly sent to the job offer display is
	since that job_offer_display can sometimes be OUT of the scene tree and inactive
	when the user is on other parts of the game.
	
	Similary add job offer to scene here and not in the display scene since the job_offer_display 
	can sometimes be outside of the scene
	
	NOTE: by this time the offer has already been added to the model
	"""
#	var job_offer_display:Job_Offer_Display = $"Display/Job Offer Display"
	add_child(offer)
	offer.connect("remove_offer",remove_job_offer)
	job_offer_display.update_display() # this will pull from the model


func remove_job_offer(offer:Job_Offer) -> void:
	"""
	currently handles removing a job offer (either that is timed out or declined)
	NOTE: I also think it could be easier to simply do the following
	
	To handle this only in the Job Offer display. Meaning, since that is where the
	both the progress bar time out and decline button methods of removing or rejecting a job 
	offer come from. 
	
	However, the Job_Offer display may not always be in the scene. Instead
	by having this serve as an abstraction, we can continue handling this in the background 
	even if the Job_Offer_display is not in the scene
	
	So currently:
		1. Job_Offer_Display calls function from Job_Generator. 
			a. or the timeout is triggered in the Job_offer object. Which in turn is attached to this function
		2. Job_Generator. Then emits signal
		3. Signal is recived by this function. (from either job generator or from job_offer)
			a. Either update the Job Display offer 
			b. in case something else is needed. Do that.
		4. Remove the Job Offer child from this object.
	
	"""
	## remove from the model
	model.remove_job_offer(offer)
	
	# update the display
	job_offer_display.update_display()
	
	# TODO: in case later descision is taken to save rejected or time ran out then save as a rejected job offer
	
	# remove child node 
	remove_child(offer)
	
	print("Removing the job offer with ID: " + str(offer.get_id()))

	
	
