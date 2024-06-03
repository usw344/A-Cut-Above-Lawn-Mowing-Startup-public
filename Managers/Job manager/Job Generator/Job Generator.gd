extends Node3D
class_name Job_Generator
"""

	Generate Job options and display them.
	Handles which difficulty the jobs should have 
	
	EXPECTS: to be added to scene (this uses the Model and process functions)

"""

const MAX_ACTIVE_JOB_OFFERS = 100 

# when there is a new job offer waiting to be displayed via job manager
signal job_offer_waiting
signal remove_job_offer

# the timer that cycles to trigger new jobs being added
@onready var timer:Timer = $"Add Job Timer"

# Called when the node enters the scene tree for the first time.
func _ready():
	randomize()
	var wt: int = randi_range(2,4)
#	print("set inital wait time: " + str(wt))
	timer.set_wait_time(wt) # a random first job start time of 2-10 seconds
	timer.start()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _init():
	pass

func add_remove_job_offer(job_offer:Job_Offer, action:String) ->void:
	"""
	This function is triggered by the timer running out. That calls the 
	signal_to_add_new_job_offer which makes the job offer
	and thenc calls this function in this mode`
	"""
	if action == "add":
		# notify the manager that there is a new job offer
		push_to_manager(job_offer,"add") 

	elif action == "remove":
		# this should be triggered when another function listening for the timer from the Job Offer node goes off
		# tell mangaer to update display to remove job offer
		push_to_manager(job_offer,"remove") 
	
func push_to_manager(o:Job_Offer,type:String) ->void:
	"""
	Signal to anyone listening that a new job offer has arrived.
	Currently this is connected in the <<Job Manager object>>
	"""
	if type == "add":
		emit_signal("job_offer_waiting",o)
	elif type =="remove":
		emit_signal("remove_job_offer",o)

func make_new_job_offer() -> Job_Offer: 
	"""
	Abstraction function to return a new job offer.
	The purpose of this function is to abstract away the calculation 
	that is used to control the diffculty and stats of a job offer
	
	Currently: return a job offer randome within 1 predfined diffculty range
	these ranges are temporarly defined here. 
	
	TODO: add in a job offer stats generator so that each job offer is slighty different
	in terms of time limit, size etc. 
	
	Current params
	job_id = 
	job_size = 
	time_limit = 
	base_pay = 
	display_name = 
	time_to_accept = 
	"""
	
	var job_type:Job_Type = generate_job_type()
	var job_id:int = generate_job_id(job_type)
	var job_size:Vector2i = generate_job_size(job_type)
	var time_limit:Dictionary = generate_job_time_limit(job_type,job_size)
	var base_pay:int = generate_job_base_pay(job_type,job_size)
	var display_name:String = generate_job_display_name(job_type,job_id)
	var time_to_accept:int = generate_job_time_accept(job_type)
	
	var offer:Job_Offer = Job_Offer.new()
	offer.setup_job_offer(job_id, job_size, time_limit, base_pay, display_name, time_to_accept)
	
	return offer
	
func generate_job_type() -> Job_Type:
	"""
	Abstraction function to calculate which type of Job this should be. 
	
	The idea here to have a complex equation/system that determines 
	based on factors like how well the player is doing, market state etc
	to decide what type of job this should be. 
	
	Currently: This is just a weighed random 
	
	"""
	var type:Job_Type = Job_Type.new()
	
	var sizes:Array = type.get_size_values()
	var diffculties:Array = type.get_diffculty_values()
	
	# TODO: Replace this with a more deep system later
	# currently take a weighted random number
	var rand_float:float = randf_range(0.0,100.0)
	var diff:String = ""
	if rand_float < 0.3: # 30%
		diff = diffculties[0] #easy
	elif rand_float < 0.8: # 50%
		diff = diffculties[1] # medium
	elif rand_float < 100.1: # 20%
		diff = diffculties[2] # hard
	else:
		print("Error in Job_Generator --> generate_job_type(): for get type for diffculty")
	
	# sample rand_float again for size
	rand_float = randf_range(0.0,100.0)
	var size_pick:String = ""
	if rand_float < 0.3: # 30%
		size_pick = sizes[0] # small
	elif rand_float < 0.8: # 50%
		size_pick = sizes[1] # medium 
	elif rand_float < 100.1: # 20%
		size_pick = sizes[2] # large
	else:
		print("Error in Job_Generator --> generate_job_type(): for type for picking size")
	type.set_size(size_pick)
	type.set_diffculty(diff)
	
	return type

func generate_job_id(type:Job_Type) -> int:
	"""
	Param type: Type of the Job must be of type Job_Type datastructure
	This contains whether this is a easy, medium, hard job and whether it is 
	a small, medium or large job etc. 
	
	Abstraction that returns a job_id that is unique to this 
	request
	"""
	
	var id:int = randi()
	
	# check to see if this id is already assigned to a job
	while model.get_all_job_offers().has(id):
		id = randi()
	return id

func generate_job_size(type:Job_Type) -> Vector2i:
	"""
	Param type: Type of the Job must be of type Job_Type datastructure
	This contains whether this is a easy, medium, hard job and whether it is 
	a small, medium or large job etc.
	
	Abstraction that returns the actual width,length of the mowing area
	based on the size in the Job_Type object. The actual size has  a
	variable range. 
	
	Note: The return from this function complies with the implementation 
	restriction of the Custom Gridmap object
	"""
	
	# while not yet tested. Try to make sure the size is a multiple of 16 (or whatever the chunking size is)
	# later replace this to also take into account things like market conditions and such
	# for now just return a value withing a predefined range
	var size_type:String = type.get_size()
	var size_types:Array = type.get_size_values()
	var size_multiplier:int = 0
	if size_type == size_types[0]: # for now small
		size_multiplier = randi_range(3,6)
	elif size_type == size_types[1]: # for now medium
		size_multiplier = randi_range(7,11)
	elif size_type == size_types[2]: # large
		size_multiplier = randi_range(12,22)
	else:
		print("Error in Job_Generator --> generate_job_size() : will get zero as multiplier")
	
	var size:Vector2i = Vector2i(16*size_multiplier, 16*size_multiplier)
	
	return size
func generate_job_time_limit(type:Job_Type,job_size_vector:Vector2i) -> Dictionary:
	"""
	Param type: Type of the Job must be of type Job_Type datastructure
	This contains whether this is a easy, medium, hard job and whether it is 
	a small, medium or large job etc.
	
	Param Job size 
	
	Abstraction that returns how long the player has to complete this job. This
	a range based on the Job_Type object.
	
	Note TODO: This should be fine tuned so that is is phyiscally possible to complete
	every job. 
	"""
	# first get the general (median) time limit for the given job size. Then the size 
	# of the given job is taken into account to make sure the job can be completed in time
	# Although the job can be completed 
	
	# TODO calibrate this. For now just return from a range from 10 to 50
	var days:int = 0
	var hours:int = 0
	var minutes:int = randi_range(10,50)
	var string_rep:String = ""
	# to allow for later displaying this information in a label. Write a string representation
	# and store that in the dictionary as well
	if days > 0:
		string_rep += "Days: " + str(days) +" "
	string_rep += str(hours) +"H"
	string_rep += str(minutes)
	
	return {"D":days,"H":hours,"M":minutes,"string":string_rep}
func generate_job_base_pay(type:Job_Type,job_size_vector:Vector2i) -> int:
	"""
	Param type: Type of the Job must be of type Job_Type datastructure
	This contains whether this is a easy, medium, hard job and whether it is 
	a small, medium or large job etc.
	
	Abstraction to return how much is the base pay (Excluding any bonuses) that 
	a player gets. The idea is to set the base based on different variables EVEN outside
	of the Job_Type object. (example tough ecnonmic situation, player ratings etc)
	
	Currently: Just return a basic range method. 
	TODO implement economic implications 
	
	"""
	var diff:String = type.get_diffculty()
	var diff_values:Array = type.get_diffculty_values()
	
	# due to haveing += in the conditionals, if one wants to scale the values
	# simple set these to a number higher or lower than 1.0 to reduce all of them
	# instead of having to reset the ranges
	var lower:float = 1.0 
	var upper:float = 1.0
	var multiplier:float = 1 # to scale up the jobs
	
	if diff == diff_values[0]: # easy
		lower += 1.1
		upper += 2.5
		multiplier += randf_range(2.0,5.0)
	elif diff == diff_values[1]: # medium
		lower += 2.6
		upper += 4.5
		multiplier += randf_range(2.1,7.5)
	elif diff == diff_values[2]: # hard
		lower += 4.6
		upper += 8.5
		multiplier += randf_range(7.5,8.5)
	
	# note we take the x of the size vector since it is assumed that both x and y are the same size
	# if one wants to add in a non-square mowing area then this assumption would have to be changed
	# TODO
	var base_pay:int = int((job_size_vector.x*multiplier) * log(randf_range(lower,upper)))

	
	return base_pay

func generate_job_display_name(type:Job_Type,id:int) -> String:
	"""
	Param type: Type of the Job must be of type Job_Type datastructure
	This contains whether this is a easy, medium, hard job and whether it is 
	a small, medium or large job etc.
	
	Abstractions to come up with somewhat-nique job display names. These are the 
	names that player will see (not the job id)
	
	TODO: make a file that contains job names that can be assigned to this
	For now just select at random with preventing duplication
	"""
	
	var diff:String = type.get_diffculty()
	
	
	return "A job name " + str(id)

func generate_job_time_accept(type:Job_Type) -> int:
	"""
	Param type: Type of the Job must be of type Job_Type datastructure
	This contains whether this is a easy, medium, hard job and whether it is 
	a small, medium or large job etc.
	
	Abstraction to calculate how long the player should have to accept the job offer.
	This 
	
	CURRENTLY: returns a value in a range
	
	TODO: factor in econmic situation (how many other companies are there are etc)
	
	RETURN: IN MINUTES not seconds. Note this for when using this with Timer
	"""
	# TEST: currently will only give 1 minute accept time.
	return randi_range(1,1)*60


func get_wait_time_until_next_job() ->int:
	"""
	Return the amount of time until the next job will be rendered.
	"""
	return timer.get_wait_time()



func signal_to_add_new_job_offer() -> void:
	"""
	Abstraction function to see if a new job should be added
	The purpose of this function is to abstract away the calculation 
	that is used to control the flow of jobs. (this is done via timer)
	
	Exmaple: this function can later use a complex equation that factors in 
	customer satisfaction, market state, Game difficulty setting etc.
	
	CURRENTLY: this just uses a timer which increaes with the number of unaccepted jobs
	So 0 or some jobs == faster timer etc. 
	
	Returns true if a new job should be added
	Returns false if a new job should not be added
	
	NOTE: this is the function called by the timer signal
	"""
	
	var max_time_to_next_job:int = 100 # max time is 100 seconds
	var wait_time:int = 0 # set the timer to this
	# check if there is space (under max limit)
	if model.get_all_job_offers().size() <= MAX_ACTIVE_JOB_OFFERS:
		var job_offer:Job_Offer = make_new_job_offer()
		add_remove_job_offer(job_offer,"add") # store it
		
#		print_string(job_offer)

		var total_current_jobs:int = model.get_all_job_offers().size()
		wait_time = (max_time_to_next_job + (randf_range(total_current_jobs, MAX_ACTIVE_JOB_OFFERS)) ) * (float(total_current_jobs)/float(MAX_ACTIVE_JOB_OFFERS)) +5
		
	else:
		# reset timer to the max time limit
		wait_time = max_time_to_next_job
	
	# now set the timer 
	
	
	timer.set_wait_time(wait_time)
	timer.start()

func print_string(offer):
	# to debug print that job offer out
	print()
	print(offer.get_as_string())
	print()
	print()
	print("new job")
