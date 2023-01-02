extends CanvasLayer

##time since the "job" started
var elaspsed_time = 0.0

##store refernces of the different nodes
onready var timer_label = $Time_and_Job_Container/Current_Elasped_Time
onready var storage_progress_bar = $Storage_ProgressBar
onready var money_label = $Top_bar_Container/Money_And_Label_Container/Money_Number

var current_storage_value = 0
var current_fuel_value = 100

signal Return
############################################### Main file Functions $$$$$$$$$$$$$

onready var press_key_for_grass_deposit_screen = $"Press K"

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	elaspsed_time += delta
	
	timer_label.text = calc_time_in_string_format(elaspsed_time)

func display_deposit_grass_key_label(key):
	press_key_for_grass_deposit_screen.text = "Press " + str(key)

func clear_press_key_labels():
	press_key_for_grass_deposit_screen.text = ""


############################################### Timer-related Functions $$$$$$$$$$$$$


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

func get_elapse():
	return elaspsed_time
	
func set_elapse(elapse):
	elaspsed_time = elapse
################################################################################ OTHER
"""
	Function to keep updating the the label listing money made.
	
"""
func update_money_label():
	return timer_label.text


############################################### Storage ProgressBar Functions $$$$$$$$$$$$$

"""
	Function to add to the storage 
	#param value: the value to be added to the storage DEFAULT = 1
"""
func add_to_storage(value = 1):
	current_storage_value += value
	update_progress_bar()

"""
	Internal function to update the display of the progress bar
"""
func update_progress_bar():
	storage_progress_bar.value = current_storage_value

func clear_storage_handler():
	current_storage_value = 0
	update_progress_bar()
	
func get_storage_value():
	return current_storage_value
############################################### Fuel Bar Functions $$$$$$$$$$$$$
"""
	Internal function to set the fuel progress bar to be the fuel stored in script
"""
func update_fuel():
	$Fuel_Bar.value = current_fuel_value 

func set_current_fuel_value(new_value):
	current_fuel_value = new_value
	update_fuel()

func get_current_fuel_value():
	return $Fuel_Bar.value

"""
	Function to update money label
"""
func add_value_to_money_label(value):
	var current_value = int(money_label.text)
	current_value+= value
	money_label.text = String(current_value)


"""
	Function to prep data and emit signal to return to current job screen
"""
func exit_current_job_screen():
	emit_signal("Return")



#######################################################################
func set_current_job_label(text):
	$Time_and_Job_Container/Current_Job.text = text
	
func get_current_job_label():
	return $Time_and_Job_Container/Current_Job.text 
