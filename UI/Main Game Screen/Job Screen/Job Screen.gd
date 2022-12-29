extends Control


var label_scene = preload("res://UI/Main Game Screen/Job Screen/Job Label/Job Label.tscn")
var game_job = preload("res://Mowing/Current_Job/Current_Job.tscn")

onready var container = $VBoxContainer
var list_of_job_on_offer = {}


var time_elaspe_val_for_label = [3.56,8,3,2,12,9,12,7.89]

var model 

func _ready():
	pass
	
	


"""
	Function periodcally adds jobs offers
"""
func add_label(label_text):
	var a_label = label_scene.instance()
	
	##store in the dictionary to be able to remove
	list_of_job_on_offer[label_text] = a_label
	
	##connect singals
	a_label.connect("remove_job",self,"remove_label") 
	a_label.connect("accept_job",self,"accept_job")
	a_label.connect("start_job",self,"set_curent_job")
	
	##other function to setup up label
	a_label.set_label_text(label_text)
	
	var elapse_time = model.get_int_in_range(0,time_elaspe_val_for_label.size()-1)
	a_label.set_elaspe(time_elaspe_val_for_label[elapse_time]*2.2)
	
	
	##add to VBox
	
	model.add_job_on_offer(a_label)
	container.add_child(a_label)

"""
	Remove a job from the job offer list
"""
func remove_label(text):
	container.remove_child(list_of_job_on_offer[text])
	model.remove_job_on_offer(text) ##remove it from the model as well

"""
	Function to form the game-job object and store it in the 
"""
func accept_job(val):
	var game = game_job.instance()
	var job_object = {"Job Text":val,"Game": game} ####
	
	var current_label = list_of_job_on_offer[val]
	
	current_label.stop_elapse()
	current_label.change_to_current()
	
	list_of_job_on_offer.erase(val)
	
	model.add_job_to_current_jobs(job_object)

"""
	Start a job (this function sets it in the model)
"""
func set_curent_job(text):
	model.set_current_job(model.get_from_current_jobs(text))



func set_model(m):
	model = m
