extends Node3D
class_name Job_Generator
"""

	Generate Job options and display them.
	Handles which difficulty the jobs should have 
	
	EXPECTS: to be added to scene (this uses the Model and process functions)

"""

# define job range to stats mapping
var job_range_to_stats:Dictionary = {}

# keep the different job ranges stored
var job_ranges:Array[String] = []

var current_range:String

## contains job offer objects ( key unique_job_id, value = Job Offer Object)
var jobs_offer:Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready():
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
	
	
	
	pass

func generate_job_id(type:Job_Type) -> int:
	"""
	Param type: Type of the Job must be of type Job_Type datastructure
	This contains whether this is a easy, medium, hard job and whether it is 
	a small, medium or large job etc. 
	
	Abstraction that returns a job_id that is unique to this 
	request
	"""
	return 0

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
	return ""
	
func generate_time_accept(type:Job_Type) -> int:
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

