extends Node3D
class_name Job_Generator
"""

	Generate Job options and display them.
	Handles which difficulty the jobs should have 
	
	EXPECTS: to be added to scene (this uses the Model and process functions)

"""

const MAX_ACTIVE_JOB_OFFERS = 100 

## contains job offer objects ( key unique_job_id, value = Job Offer Object)
var job_offers:Dictionary = {}

# keep track of the last generated job id. 
var last_generated_job_id:int = -1

# Called when the node enters the scene tree for the first time.
func _ready():
	randomize()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _init():
	pass

func make_new_job_offer(): 
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
	
	# sample rand_float again for size
	rand_float = randf_range(0.0,100.0)
	var size_pick:String = ""
	if rand_float < 0.3: # 30%
		size_pick = sizes[0] # small
	elif rand_float < 0.8: # 50%
		size_pick = sizes[1] # medium 
	elif rand_float < 100.1: # 20%
		size_pick = sizes[2] # large
	
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
	while job_offers.has(id):
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
	
	#while not yet tested. Try to make sure the size is a multiple of 16
	
	return Vector2i()
func generate_job_time_limit(type:Job_Type) -> Dictionary:
	"""
	Param type: Type of the Job must be of type Job_Type datastructure
	This contains whether this is a easy, medium, hard job and whether it is 
	a small, medium or large job etc.
	
	Abstraction that returns how long the player has to complete this job. This
	a range based on the Job_Type object.
	
	Note: This should be fine tuned so that is is phyiscally possible to complete
	every job. 
	"""
	return {}
func generate_job_base_pay(type:Job_Type) -> int:
	"""
	Param type: Type of the Job must be of type Job_Type datastructure
	This contains whether this is a easy, medium, hard job and whether it is 
	a small, medium or large job etc.
	
	Abstraction to return how much is the base pay (Excluding any bonuses) that 
	a player gets. The idea is to set the base based on different variables EVEN outside
	of the Job_Type object. (example tough ecnonmic situation, player ratings etc)
	
	Currently: Just return a basic range method. TODO implement economic implications 
	
	"""
	return 0
func generate_job_display_name(type:Job_Type) -> String:
	"""
	Param type: Type of the Job must be of type Job_Type datastructure
	This contains whether this is a easy, medium, hard job and whether it is 
	a small, medium or large job etc.
	
	Abstractions to come up with somewhat-nique job display names. These are the 
	names that player will see (not the job id)
	"""
	return ""
	
func generate_time_accept(type:Job_Type) -> int:
	"""
	Param type: Type of the Job must be of type Job_Type datastructure
	This contains whether this is a easy, medium, hard job and whether it is 
	a small, medium or large job etc.
	
	Abstraction to calculate how long the player should have to accept the job offer.
	This 
	"""
	return 0

func if_new_job_is_to_be_added(type:Job_Type) ->bool:
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

