extends CanvasLayer

##time since the "job" started
var elaspsed_time = 0.0
onready var timer_label = $Time_and_Job_Container/Current_Elasped_Time


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	elaspsed_time += delta
	
	timer_label.text = calc_time_in_string_format(elaspsed_time)

"""
	Internal function that takes in a float that is in seconds and converts it to string format:
	minute:seconds:milliseconds
	
	@param time_in_raw_seconds: float that represents seconds
	@return time_string: A string representing time_in_raw_seconds in format minute:seconds:milliseconds
"""
func calc_time_in_string_format(time_in_raw_seconds):
	var minutes = time_in_raw_seconds/60
	var seconds = fmod(time_in_raw_seconds, 60)
	var milliseconds = fmod(time_in_raw_seconds,1)*100
	
	var time_string := "%02d:%02d:%02d" % [minutes, seconds, milliseconds]
	
	return time_string

"""
	Function to keep updating the the label listing money made.
	
"""
func update_money_label():
	return timer_label.text
