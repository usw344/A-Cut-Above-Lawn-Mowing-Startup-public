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

var job_offer_display_layer:CanvasLayer 

var job_offer_display_scene = load("res://Managers/Job manager/Job Display/Job_offer_display.tscn")

func _ready():
	job_generator = $"Job Generator"
	show_job_offer_display_menu()
	
	
#var control_rect:ColorRect = $"Job Display/Background shadow"
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

	add_child(offer)
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
		
	NOTE: all job offers are a child of Job_Manager. So removing 
	
	"""
	## remove from the model
	model.remove_job_offer(offer)
	
	
	# TODO: ADD CHECK TO SEE IF THE JOB_OFFER_DISPLAY IS STILL IN SCENE
	
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


func show_job_offer_display_menu():
	"""
	When the signal is recieved to display the job offer menue this function will make a fresh
	job_offer_display object and add it to the scene.
	
	"""
	var return_objects:Array = make_new_job_offer_display()
	var layer:CanvasLayer = return_objects[0]
	
	
	job_offer_display = return_objects[1] # reference to scene
	job_offer_display_layer =layer # store this layer variable in a script variable
	
	add_child(job_offer_display_layer)
	job_offer_display_layer.add_child(job_offer_display)
	
	# attach all relevent signals 
	job_offer_display.connect("close_menu_signal",hide_job_offer_display_menu)
	job_offer_display.connect("decline_offer",decline_job_offer)
	
	is_job_offer_display_visible = true
	
func hide_job_offer_display_menu():
	"""
	When signal is recieved remove the menu from view (delete the object and it can be made again later)
	"""
	remove_child(job_offer_display_layer)
	
	is_job_offer_display_visible = false

func make_new_job_offer_display():
	"""
	Return a Job Offer Display object encapsulated in a Canvas layer object
	
	Return a two item array. One with the reference to the Canvas layer (which can be added to the scene)
	
	and the other is the direct reference to the Job Offer Display object
	"""
	var canvas_layer:CanvasLayer = CanvasLayer.new()
	var job_offer_display_object:Job_Offer_Display = job_offer_display_scene.instantiate()
	
	
	return [canvas_layer,job_offer_display_object]
