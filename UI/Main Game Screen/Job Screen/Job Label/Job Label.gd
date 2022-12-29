extends Control

signal remove_job(job_text)
signal accept_job(job_text)
signal start_job(job_text
)
onready var job_number = $"Job Number"
onready var elapse_number  = $Elaspe

var progress_bar_reduction = false
var progress_bar_reduction_mapping = 1

var text_this = "empty"

func set_label_text(text):
	$"Job Number".text = text
	text_this = text


func remove():
	emit_signal("remove_job",$"Job Number".text)

func accept():
	emit_signal("accept_job",$"Job Number".text) 

func set_elaspe(val):
	$Elaspe.text = "Accept within: " + str(val)
	$Timer.wait_time = val

	begin_progress_bar(val)

func stop_elapse():
	$Timer.stop()
	progress_bar_reduction = false
	self.remove_child($"Elapse Left")

func change_to_current():
	self.remove_child($"Accept Job")
	self.remove_child($Decline)
	self.remove_child($Elaspe)
	
	var a_button = Button.new()
	a_button.text = "Start Job"
	a_button.rect_position = Vector2(510,16)
	a_button.connect("pressed",self,"start_job")

	self.add_child(a_button)

func start_job():
	emit_signal("start_job",$"Job Number".text)

func begin_progress_bar(mapping_val):
	$"Elapse Left".value = 100
	progress_bar_reduction_mapping = 100/mapping_val

	progress_bar_reduction = true

############################################################################### Other functions

func get_text():
	return $"Job Number".text

func _process(delta):
	if progress_bar_reduction:
		$"Elapse Left".value -= 1
