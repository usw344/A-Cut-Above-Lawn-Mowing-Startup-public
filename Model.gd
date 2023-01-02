extends Node

var grass_stored = 0
var funds = 0

var fuel_object = {"fuel_val":100,"fuel_per_idle":2, "fuel_used_per_block":2}

var jobs_on_offer = {} ##array of label objects
var jobs_current  = {}
var jobs_past     = {}

var current_job

var num = RandomNumberGenerator.new()

var game_difficulty
var game_number

var job_sizes = {
	"type 1":[8,10],
	"type 2":[11,16],
	"type 3":[20,25],
	"type 4":[26,30],
	"type 5":[31,32]}
var rotation_counter = 0
##Signals
signal set_current_scene_to_job
signal remove_job_from_screen(job_text)

var file = File.new()
var save_file_location

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


################################################################ FUNCTION relating Fuel

func set_fuel(f):
	fuel_object["fuel_val"] = f
	
func get_fuel_object():
	return fuel_object


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
	Remove current job.
"""
func remove_current_job():
	current_job = null

"""
	From the current jobs list that matches the job number as key
	this is in reference to the list of jobs that have been put in the taken job
	dictionary
	
	return job object
"""
func get_from_current_jobs(job_number):
	return jobs_current[job_number]

"""
	Adds the current job object into the past object list
	Clears the current_job value
	
	NOTE in the job screen code the remove_label function which connects 
	to the signal from here also REMOVES the job from the job offer list
	The erase is also done here
"""
func add_to_past_jobs():
	jobs_past[current_job["Job Text"]] = current_job	
	emit_signal("remove_job_from_screen",current_job["Job Text"])
	jobs_on_offer.erase(current_job["Job Text"])
	current_job = null





##################################################### FUNCTIONS other
"""
	Function to see if this game has already been started
"""
func started_game():
	pass
"""
	Rotates between type 1 - 5 job sizes
	
	return: the name of size cataogory
"""
func get_next_job_size():
	var return_key = job_sizes.keys()[rotation_counter]
	rotation_counter += 1
	if rotation_counter > job_sizes.size()-1:
		rotation_counter = 0
	return return_key

"""
	returns a value in range of the size range of the given cataogry
"""
func get_grid_size_relating_to_job_size(size):
	var range_size = job_sizes[size]
	
	return get_int_in_range(range_size[0],range_size[1])
	

####################################################################### FUNCTIONS relating to number

"""
	Function to get a float in range x to y
	
	return a float x where va1 < x < val2
"""
func get_float_in_range(val1, val2):
	return num.randf_range(val1, val2)

func get_int_in_range(val1, val2):
	return num.randi_range(val1, val2)


###################################################################### FUNCTIONS 
##																relating to saving/load

"""
	For current game_number save the information
"""
func save_information():
	##get data from all in-game jobs that are on going and store them
		#store the gridmap
		
		#store the location of the trucks
		
			
	##store the fuel, mower storage and money
	
	##Store the seeds for random num, fuel mode and grass price
	
	##Store the 
	var testing = {"x":[3,54,12],"y":[9,42,123],"This":[113,34,343]}
	var testing2 = {"x":["a","b","c"],"y":[2349,442,12343],"This":[1432413,34342,34343]}
	var file = File.new()
	var save = "res://testing.save"
	file.open(save,File.WRITE)
	file.store_var(testing,true)
	file.store_var(testing2,true)
	file.close()

"""
	For the given game number load the current game information
"""
func load_information():
	var file = File.new()
	var save = "res://testing.save"
	file.open(save, File.READ)
	var c = file.get_var(true)
	var c2 = file.get_var(true)
	file.close()
	print(c["x"])
	print(c2["x"])

func set_game_number(game_num):
	game_number = game_num

func get_game_number():
	return game_number

func set_game_difficulty(diff):
	game_difficulty = diff
func get_game_difficulty():
	return game_difficulty
