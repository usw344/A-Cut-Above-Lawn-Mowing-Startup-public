extends Node

var grass_stored = 0
var funds = 0

var jobs_on_offer = {}
var jobs_current  = {}
var jobs_past     = {}

var num = RandomNumberGenerator.new()


func _ready():
	pass


############################################################### FUNCTIONS related to grass
func set_grass(val):
	grass_stored = val


func get_grass():
	return grass_stored 

func set_funds(val):
	funds = val
	
func get_funds():
	return funds


################################################################ FUNCTIONS relating to jobs
"""
	Function to add jobs that are on offer
	
	job_number: job number which is not duplicated to other jobs in this game
	job: a job object containing information to construct a map
"""
func add_job_on_offer(job_number,job):
	jobs_on_offer[job_number] = job
	
"""
	Function to remove a job on offer and also return
	
	job_number: job number which is not duplicated to other jobs in this game
	return the job object 
"""	
func remove_job_on_offer(job_number):
	var job = jobs_on_offer[job_number]
	jobs_on_offer.erase(job_number)
	return job

"""
	Function to add jobs that are currently going
	
	job_number: job number which is not duplicated to other jobs in this game
	job: a job object containing information to construct a map
"""
func add_job_to_current_jobs(job_number,job):
	jobs_current[job_number] = job
	
"""
	Function to remove a job that is currently on going and also return the job object
	
	job_number: job number which is not duplicated to other jobs in this game
	return the job object 
"""	
func remove_job_current(job_number):
	var job = jobs_current[job_number]
	jobs_current.erase(job_number)
	return job


####################################################################### FUNCTIONS relating 

"""
	Function to get a float in range x to y
	
	return a float x where va1 < x < val2
"""
func get_float_in_range(val1, val2):
	return num.randf_range(val1, val2)

func get_int_in_range(val1, val2):
	return num.randi_range(val1, val2)
