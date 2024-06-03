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
#@onready var job_offer_display:Job_Offer_Display =$"Display/Job Offer Display"

var job_offer_display:Job_Offer_Display
var is_job_offer_display_visible:bool = false

@onready var job_offer_display_layer:CanvasLayer = $Job_Offer_Display_Layer

var job_offer_display_scene = load("res://Managers/Job manager/Job Display/Job_offer_display.tscn")

func _ready():
	job_generator = $"Job Generator"
	show_job_offer_display_menu()
	
	
#var control_rect:ColorRect = $"Job Display/Background shadow"
#	control_rect.size = Vector2(200,200)
	
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	$CanvasLayer/Label.text = str($"Job Generator".timer.get_wait_time())
	$CanvasLayer/Label.text += "Offers in model" + str(model.get_all_job_offers().size())

func recieve_job_offer(offer:Job_Offer):
	"""
	Get a new job offer from the Job generator and display it.
	
	Notify the job_offer_display to update display (if the job offer display is 
	currently displayed )
	
	The reason this signal is not directly sent to the job offer display is
	since that job_offer_display can sometimes be OUT of the scene tree and inactive
	when the user is on other parts of the game.
	
	Similary add the job offer to scene here and not in the display scene since the job_offer_display 
	can sometimes be outside of the scene
	
	NOTE: WE DO NOT add the job offer to the model before calling this function to check for the edge case
	listed in the TODO section below
	"""

	## TODO START
	# until TODO END this block of code is for an edge case where once all offers have been declined
	# for some reason the display does not update to show the new offers that come in after.
	# I think this is an issue inside the << job offer display >> class and has to do with 
	# what job_offer_display_id (some variable to that similar name) is set
	# as a shortcut for now I am adding this new block which will check to see if this case is met and 
	# will delete the old instance job_offer_display and make a new one
	var number_of_offers_before_adding:int = model.get_all_job_offers().size() # store number before adding to model
	
	# by adding to model here most of the orginal logic from before(when offer was added to model inside Job Generator) 
	# can be used without changing much else
	model.add_job_offer(offer) 
	
	if(number_of_offers_before_adding == 0 and is_job_offer_display_visible):
		hide_job_offer_display_menu() # remove the existing job offer display menu
		show_job_offer_display_menu() # add new menu
	
	## TODO END
	
	add_child(offer) # so its timmer and stuff can work
	offer.connect("remove_offer",remove_job_offer)
	job_offer_display.update_display() # this will pull from the model


func remove_job_offer(offer:Job_Offer) -> void:
	"""
	currently handles removing a job offer when it is timed out
	
	So currently:
		1.  timeout is triggered in the Job_offer object
	
		3. Signal is recived by this function.
			a. Either update the Job Display offer 
			b. in case something else is needed. Do that.
		4. Remove the Job Offer child from this object.
		
	NOTE: all job offers are a child of Job_Manager. 
	
	"""
	## remove from the model
	model.remove_job_offer(offer)
	
	# update the display
	job_offer_display.update_display()

	# remove child node 
	remove_child(offer)



func decline_job_offer(offer:Job_Offer):
	"""
	In the case the job offer is declined. This function will remove the child node relating 
	to that job offer. 
	
	NOTE: the reason this is seperate from the remove_job_offer is because in that function
	the offer is removed from the model and the update_display() function is called.
	
	This is not done with this function, since only removing the child node is neeeded
	the rest is done inside the Job_Offer_Display
	"""
	remove_child(offer)


func show_job_offer_display_menu() -> void:
	"""
	When the signal is recieved to display the job offer menue this function will make a fresh
	job_offer_display object and add it to the scene.
	
	"""
	job_offer_display = make_new_job_offer_display()
	
	job_offer_display_layer.add_child(job_offer_display)
	
	# attach all relevent signals 
	job_offer_display.connect("close_menu_signal",hide_job_offer_display_menu)
	job_offer_display.connect("decline_offer",decline_job_offer)
	
	is_job_offer_display_visible = true
	
func hide_job_offer_display_menu() ->void:
	"""
	When signal is recieved remove the menu from view (delete the object and it can be made again later)
	"""
	job_offer_display_layer.remove_child(job_offer_display)
	
	is_job_offer_display_visible = false

func make_new_job_offer_display() -> Job_Offer_Display:
	"""
	Return a Job Offer Display object encapsulated in a Canvas layer object
	
	Return direct reference to the Job Offer Display object
	"""
	var job_offer_display_object:Job_Offer_Display = job_offer_display_scene.instantiate()
	
	
	return job_offer_display_object
