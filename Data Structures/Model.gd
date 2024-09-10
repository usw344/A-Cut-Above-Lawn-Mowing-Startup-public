extends Node
class_name Model

"""
This is an autoload script that stores global game variables
"""


"""------------------------------------------- Mower.tscn variables AND functions -------------------------------------------"""
var speed = 10 
var blade_length = 1

##mower fuel variables 
var mower_fuel = 100			#total mower fuel
var mower_fuel_idle_counter = 0 #keeps track of movements. Since fuel icnrements are in whole numbers
var idle_fuel_use = 26			#After this much movement substract fuel. PLANNED: to allow this value to be increased

var mower_position:Vector3 = Vector3()
var mower_grid_position:Vector2
# store the cuttings information
var stored_cuttings:int = 0
var cuttings_in_mower:int = 0

func get_stored_cuttings() -> int:
	return stored_cuttings
func set_stored_cuttings(c:int) ->void:
	stored_cuttings = c

func set_cuttings_in_mower(c:int) -> void:
	cuttings_in_mower = c
	
func get_cuttings_in_mower() -> int:
	return cuttings_in_mower

func set_mower_position(p:Vector3):
	mower_position = p

func get_mower_position() ->Vector3:
	return mower_position

func get_speed():
	"""
	Get and Set for mower speed
	"""
	return speed
func set_speed(s):
	speed = s


func get_blade_length():
	"""
	Get and Set for blade length for mower
	"""
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
func set_mower_fuel_idle_counter(s) ->void:
	mower_fuel_idle_counter = s
	
"""
	If the fuel counter has reached the idle_fuel_use limit 
	return true if mower_fuel_idle_counter is greater than or equal to idle_fuel_use
	return false if not
"""
func is_mower_fuel_idle_counter() -> bool:
	if mower_fuel_idle_counter >= idle_fuel_use:
		return true
	return false
"""
	Add a value to mower_fuel_idle_counter
"""
func increment_mower_fuel_idle_counter(add) ->void:
	mower_fuel_idle_counter += add

# store the current selected mower (this should be updated when a selection is made in store)
var current_mower:String = "Small Gas Mower" # key in the mower_scene_reference

# store references to all mower scenes (try to match dictionary keys with Node names in the mower scene)
# this can help with collision with the truck zone (which uses the name of the collider)
var mower_scene_references: Dictionary = {
	"Hand Mower":null,
	"Small Gas Mower": load("res://Mowing Section/Mower/Mower_Normal/Mower_Normal.tscn"),
	"Larger Grass Mower": null,
	"Electric Mower":null,
	"Large Electric Mower":null
}


"""------------------------------------------       Functions for Information Bar           -------------------------------------------"""

func get_game_time() -> String:
	"""
	Convert time from start of game instance to now into a day and hour equivlent. 
	
	"""
	return ""

func get_game_weather() -> String:
	return ""

func get_game_money() -> String:
	return ""
# model.get_game_time()
#	weather_button.text = model.get_game_weather()
#	money_button.text = model.get_game_money()



"""------------------------------------------- Functions from 'testing grounds' job system  -------------------------------------------"""
# store all current job offers
var job_offers:Dictionary = {}

func add_job_offer(o:Job_Offer) ->void:
	job_offers[o.get_id()] = o
func remove_job_offer(o:Job_Offer) -> void:
	var retr:bool = job_offers.erase(o.get_id())
	if retr == false:
		print("error in model.gd remove_job_offer: trying to remove a job offer that is not in model currently")
func get_all_job_offers() ->Dictionary:
	return job_offers

"""------------------------------------------- Model functions  -------------------------------------------"""
func save_game_data(file_name):
	var variables = {
		"speed": get_speed(),
		"blade_length":get_blade_length(),
		"mower_fuel":get_mower_fuel(),
		"mower_fuel_idle_counter":get_mower_fuel_idle_counter(),
		"idle_fuel_use":get_idle_fuel_use()
	}

func _input(event):
	if Input.is_action_just_pressed("ui_accept"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			

func load_game_data(file_name):
	pass


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func _process(delta):
#	print("Current fuel " ,get_mower_fuel()," counter: ",get_mower_fuel_idle_counter())
	pass
