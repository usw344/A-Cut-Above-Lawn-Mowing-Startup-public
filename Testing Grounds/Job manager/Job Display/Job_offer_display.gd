extends Control
class_name Job_Offer_Display


# key = Job_ID, value = Job_Offer object
var job_offer_display_order:Dictionary = {} # keep track of display order


# which job offer is currently being displayed on the screen
var job_id_for_displayed_offer:int =-1

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	refresh_display()

func update_display() ->void:
	"""
	Grab all current job offers from the model. Updaate the display.
	Preserve the ordering if possible (so if a user is looking at a offer the reset should 
	ensure they continues to look at that offer.).
	
	This function should be able to seemlessly pick up after a long time when this 
	function was last called
	
	This is since the user can be outside of the the job offer display screen
	and this node will be outside of the scene tree.
	"""
	var current_job_offers:Dictionary = model.get_all_job_offers()
	## error checking
	# check if there even any job offers to be displayed.
	if current_job_offers.size() == 0:
		# note this condition should not be met if this function is called in the right place
		print("Error: Trying to update display when there are no job offers in the model")
		return
	
	# check if there has been any changes since last update (this does not compare ordering)
	if if_diff(current_job_offers.values(),job_offer_display_order.values()) == false:
		# note this condition should not be met if this function is called in the right place
		print("Error: Trying to update display when there are no job offers to update")
		return 
	

	## general case ##
	remove_old_offers(current_job_offers)
	add_new_offers(current_job_offers)
	pass

func if_diff(a1:Array, a2:Array) ->bool:
	"""
	Take in two array with Job_Offer objects as their items and see if they match
	Note: this does not check order. 
	so a1 = [1,2,3], a2 = [2,1,3] return false
	"""
	for item_in_a1 in a1:
		if item_in_a1 in a2:
			continue
		else:
			return true
	return false

func remove_old_offers(current_offers:Dictionary) -> void:
	"""
	Remove any job offers that need to be removed
	
	This function does not return anything. Instead it will 
	alter job_offer_display_order.
	
	param current_offers: list of up to date offers from the model (key = job id, value = Job_Offer )
	"""
	
	var current_ids:Array = current_offers.keys()
	var local_copy_ids:Array = job_offer_display_order.keys()
	var remove_these_id:Array = []
	# now by looping through local_copy_ids we can find if any of them are 
	# no longer in the current_ids. If so remove those
	for id in local_copy_ids:
		if id not in current_ids:
			remove_these_id.append(id)
	
	# now delete from job_offer_display_order the relevent job offers
	for id_to_remove in remove_these_id:
		job_offer_display_order.erase(id_to_remove)
	
	#make sure the current job_id is still in the list. if not then select the next job offer over
	if job_id_for_displayed_offer not in job_offer_display_order.keys():
		if job_offer_display_order.size() == 0:
			job_id_for_displayed_offer = -1
		else:
			job_id_for_displayed_offer = job_offer_display_order.keys()[0]
		refresh_display()
		return 


func refresh_display() ->void:
	"""
	Grab the current job offer that is in "focus" (as denoted by the job_id_for_displayed_offer)
	and update the UI information to reflect that. 
	
	This function is called every frame (to keep the accept by updated)
	"""
	if job_id_for_displayed_offer == -1:
		# show ui for no job offer
		$"No Job Offers".visible = true
	else:
		$"No Job Offers".visible = false # just in case
		
		# now grab the job offer object and laod its data into the relevent labels
		var job_offer:Job_Offer = job_offer_display_order[job_id_for_displayed_offer]
		
		# set the job name
		$"Information Display/Job Name".text = str(job_offer.get_display_name())
		$"Information Display/Base Pay Background/Base Pay".text = str(job_offer.get_base_pay())
		$"Information Display/Total Time To Do Job".text = str(job_offer.get_time_limit()["string"])
		$"Background For Left_Right  Buttons/Job Counter".text = str(job_offer_display_order.size())


func get_diff(current_offers:Dictionary) ->Array:
	"""
	Get which offers are new as compared to the current offers on displau
	
	Return the job offer objects that are new.
	
	NOTE: this should only be called after old (now invalid to accept) job offers
	have been removed
	
	NOTE: this should only be called if there any new offers to add
	otherwise it will return an empty array and print an error message
	"""
	var new_offers:Array = []
	
	var current_offer_ids:Array = current_offers.keys()
	var local_offer_ids:Array = job_offer_display_order.keys()
	
	for current_id in current_offer_ids:
		if current_id not in local_offer_ids:
			# this means this is a new job offer so add its Job_Offer object into the new list
			new_offers.append(current_offers[current_id]) 
		
	
	if new_offers.size() == 0:
		print("Error get_diff returining an empty array.")
		return []
	
	return new_offers
func add_new_offers(current_offers:Dictionary) ->void:
	"""
	Given a list of new job offers this will insert them into the job_offer_display data structure
	This function will not return anything, but instead it will modify the job_offer_display_order
	variable
	"""
	var new_offers:Array = get_diff(current_offers)
	print("got new offers: " + str(len(new_offers)))
	if new_offers.size() == 0:
		print("Error in add_new_offers in Job_Offer_display: Trying to add new offers when an empty array was passed in")
		return
	
	for offer in new_offers:
		var id:int = offer.get_id()
		if job_offer_display_order.has(id):
			print("Error in add_new_offer in Job_Offer_Display. This should not happen since old offers should be removed")
			continue
		job_offer_display_order[id] = offer
	
	if job_id_for_displayed_offer == -1:
		# now set it to the first job offer there is
		job_id_for_displayed_offer = job_offer_display_order.keys()[0]
		refresh_display()
	


