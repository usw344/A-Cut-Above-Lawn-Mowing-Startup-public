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
	The offer comining is already removed from the model. That is done by the 
	the Job Generator class. The 
	"""
	# update the display
	job_offer_display.update_display()
	
	# TODO: in case later descision is taken to save rejected or time ran out then save as a rejected job offer
	
	# remove child node 
	remove_child(offer)
	print("testing connection of signal")
	
