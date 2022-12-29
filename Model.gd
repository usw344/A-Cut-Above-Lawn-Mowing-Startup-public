extends Node

var grass_stored = 0
var funds = 0
var fuel = 100

var jobs_on_offer = {} ##array of label objects
var jobs_current  = {}
var jobs_past     = {}

var current_job

var num = RandomNumberGenerator.new()

##Signals
signal set_current_scene_to_job



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
	
	job_label: a 'Job Label' object
"""
func add_job_on_offer(job_label):
	jobs_on_offer[job_label.get_text()] = job_label
	
"""
	Function to remove a job on offer and also return
	
	job_number: job number which is not duplicated to other jobs in this game
	return the job label 
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
func add_job_to_current_jobs(job):
	jobs_current[job["Job Text"]] = job
	
"""
	Function to remove a job that is currently on going and also return the job object
	
	job_number: job number which is not duplicated to other jobs in this game
	return the job object 
"""	
func remove_job_current(job_number):
	var job = jobs_current[job_number]
	jobs_current.erase(job_number)
	return job


"""
	Set the current job that is being displayed (meaning that is being played)
"""
func set_current_job(job_object):
	current_job = job_object
	emit_signal("set_current_scene_to_job")

"""
	Get the current job object
	
	return current_job: a job object
"""
func get_current_job():
	return current_job

"""
	From the current jobs list that matches the job number as key
	
	return job object
"""
func get_from_current_jobs(job_number):
	return jobs_current[job_number]

####################################################################### FUNCTIONS relating to number

"""
	Function to get a float in range x to y
	
	return a float x where va1 < x < val2
"""
func get_float_in_range(val1, val2):
	return num.randf_range(val1, val2)

func get_int_in_range(val1, val2):
	return num.randi_range(val1, val2)


