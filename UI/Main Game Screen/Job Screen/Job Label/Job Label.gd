extends Control

signal remove_job(job_text)
signal accept_job(job_text)

onready var job_number = $"Job Number"
onready var elapse_number  = $Elaspe

var progress_bar_reduction = false
var progress_bar_reduction_mapping = 1

func set_label_text(text):
	$"Job Number".text = text


func remove():
	emit_signal("remove_job",$"Job Number".text)

func accept():
	emit_signal("accept_job",$"Job Number".text)

func set_elaspe(val):
	$Elaspe.text = "Accept within: " + str(val)
	$Timer.wait_time = val

	begin_progress_bar(val)


func begin_progress_bar(mapping_val):
	$"Elapse Left".value = 100
	progress_bar_reduction_mapping = 100/mapping_val

	progress_bar_reduction = true


func _process(delta):
	if progress_bar_reduction:
		$"Elapse Left".value -= 1
