extends Control

var model 
onready var job_screen = $"Screen Container/Job Screen"
onready var a_game = preload("res://Mowing/Current_Job/Current_Job.tscn")

var job_counter
signal save_current_game_data
func _ready():
	$"Screen Container/Save/Save button".connect("pressed",self,"save_signal_handler")


	
"""
	Function to periodically add a new game offer
	
"""
func new_game_offer_adder():
	job_counter = model.get_job_counter()
	var label_text = "Job " + str(job_counter)
	job_counter += 1
	model.set_job_counter(job_counter)
	
	add_job_label(label_text,model.get_next_job_size())
	var wait_time = model.get_float_in_range(1,3)
	$"New Job Offer Timer".wait_time = wait_time
	
	$Label.text = str(wait_time)


"""
	Functiont to add a label to the 
"""
func add_job_label(label_text,size):
	job_screen.add_label(label_text,size)


func pause():
	$"New Job Offer Timer".stop()

func unpause():
	$"New Job Offer Timer".start()

############################################# OTHER

func set_model(m):
	model = m
	
	job_screen.set_model(model)

"""
	Function to add layer to save button signal
"""
func save_signal_handler():
	emit_signal("save_current_game_data")

func load_data():
	job_screen = $"Screen Container/Job Screen"
	job_screen.load_data()
