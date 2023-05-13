extends Node
class_name Model

"""------------------------------------------- Mower.tscn variables AND functions -------------------------------------------"""
var speed = 10
var blade_length = 1

##mower fuel variables 
var mower_fuel = 100			#total mower fuel
var mower_fuel_idle_counter = 0 #keeps track of movements. Since fuel icnrements are in whole numbers
var idle_fuel_use = 26			#After this much movement substract fuel. PLANNED: to allow this value to be increased
"""
	Get and Set for mower speed
"""
func get_speed():
	return speed
func set_speed(s):
	speed = s

"""
	Get and Set for blade length for mower
"""
func get_blade_length():
	return blade_length
func set_blade_length(l):
	blade_length = l

"""
	Get and Set for mower fuel
"""
func get_mower_fuel():
	return mower_fuel
func set_mower_fuel(f):
	mower_fuel = f

func get_idle_fuel_use():
	return idle_fuel_use
func set_idle_fuel_use(u):
	idle_fuel_use = u

"""
	Get and Set for mower fuel idle counter
	This counter keeps track of how much movement has occured.
	Per movement a certain amount is added to the mower_fuel_idle_counter
	when this reaches a set amount a certain amount of fuel is removed
"""
func get_mower_fuel_idle_counter():
	return mower_fuel_idle_counter
func set_mower_fuel_idle_counter(s):
	mower_fuel_idle_counter = s
	
"""
	If the fuel counter has reached the idle_fuel_use limit 
	return true if mower_fuel_idle_counter is greater than or equal to idle_fuel_use
	return false if not
"""
func is_mower_fuel_idle_counter():
	if mower_fuel_idle_counter >= idle_fuel_use:
		return true
	return false
"""
	Add a value to mower_fuel_idle_counter
"""
func increment_mower_fuel_idle_counter(add):
	mower_fuel_idle_counter += add
"""------------------------------------------- Job function and variables  -------------------------------------------"""

# store all current jobs. key = id and value = Job Data container
var current_jobs:Dictionary = {}

# store list of all completed jobs key = id and value = Job Data container
var past_jobs:Dictionary = {}

# store all jobs currently on offer

"""------------------------------------------- Model functions  -------------------------------------------"""
func save_game_data(file_name):
	var variables = {
		"speed": get_speed(),
		"blade_length":get_blade_length(),
		"mower_fuel":get_mower_fuel(),
		"mower_fuel_idle_counter":get_mower_fuel_idle_counter(),
		"idle_fuel_use":get_idle_fuel_use()
	}
	
func load_game_data(file_name):
	pass


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func _process(delta):
#	print("Current fuel " ,get_mower_fuel()," counter: ",get_mower_fuel_idle_counter())
	pass
