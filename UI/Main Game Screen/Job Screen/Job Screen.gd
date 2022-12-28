extends Control


var label_scene = preload("res://UI/Main Game Screen/Job Screen/Job Label/Job Label.tscn")
onready var container = $VBoxContainer
var list_of_job_on_offer = {}


var time_elaspe_val_for_label = [3.56,8,3,2,12,9,12,7.89]

var model 

func _ready():
	pass
	
	



func add_label(label_text):
	var a_label = label_scene.instance()
	
	##store in the dictionary to be able to remove
	list_of_job_on_offer[label_text] = a_label
	
	##connect singal for removing job
	a_label.connect("remove_job",self,"removing_label") 
	a_label.connect("accept_job",self,"accept_job")
	
	##other function to setup up label
	a_label.set_label_text(label_text)
	var elapse_time = model.get_int_in_range(0,time_elaspe_val_for_label.size()-1)
	
	a_label.set_elaspe(time_elaspe_val_for_label[elapse_time]*2.2)
	
	
	
	
	container.add_child(a_label)

"""
	Remove a job from the job offer list
"""
func removing_label(text):
	container.remove_child(list_of_job_on_offer[text])

"""
	Function to form the game-job object and store it in the 
"""
func accept_job(val):
	print("accepted job with label: " + str(val))

func set_model(m):
	model = m
