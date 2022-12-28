extends Control

var model 
onready var job_screen = $"Screen Container/Job Screen"
onready var a_game = preload("res://Mowing/Current_Job/Current_Job.tscn")

var job_counter = 0

func _ready():
	pass


	
"""
	Function to periodically add a new game offer
	
"""
func new_game_offer_adder():
	var label_text = "Job " + str(job_counter)
	job_counter += 1
	
	add_job_label(label_text)
	var wait_time = model.get_float_in_range(3,15)
	$"New Job Offer Timer".wait_time = wait_time
	
	$Label.text = str(wait_time)


"""
	Functiont to add a label to the 
"""
func add_job_label(label_text):
	job_screen.add_label(label_text)

############################################# OTHER

func set_model(m):
	model = m
	
	job_screen.set_model(model)

