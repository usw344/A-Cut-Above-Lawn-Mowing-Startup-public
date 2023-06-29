extends Node
class_name Model

"""
This is an autoload script that stores global game variables
"""


"""------------------------------------------- Mower.tscn variables AND functions -------------------------------------------"""
var speed = 10 + 80 #REMOVE TEMP ADDITION OF +
var blade_length = 1

##mower fuel variables 
var mower_fuel = 100			#total mower fuel
var mower_fuel_idle_counter = 0 #keeps track of movements. Since fuel icnrements are in whole numbers
var idle_fuel_use = 26			#After this much movement substract fuel. PLANNED: to allow this value to be increased

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
var current_job_offers:Dictionary = {}

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


# store the houses. To simplfy process first make dictionaries with houses
var holder = "res://Mowing Section/Mowing_Area/15x15_1/15x_15_mowing_scene__2.tscn"
var small_houses:Dictionary = {
	1: load(holder),
	2: load(holder),
	3: load(holder),
	"previous variant":0,
	"grass information":{"size":2,"scale":Vector3(5,5,5)},
	"house scale": Vector3(100,50,100)
	
}

var medium_houses:Dictionary = { # for scale of level 4,4,4 (400x400)
	1: load(holder),
	2: load(holder),
	3: load(holder),
	"previous variant":0,
	"grass information":{"size":4,"scale":Vector3(4,4,4)},
	"house scale": Vector3(4,4,4)
}

var large_houses:Dictionary = { # for scale of level of 8,8,8 ( 800x800)
	1: load(holder),
	2: load(holder),
	3: load(holder),
	"previous variant":0,
	"grass information":{"size":8,"scale":Vector3(2,2,2)},
	"house scale": Vector3(55,55,55)
}

var very_large_houses:Dictionary = { # for scale of level of 16,16,16 ( 1600x1600)
	1: load("res://Assets/Level Scenes/very_large_1.tscn"), # this is correct
	2: null,
	3: null,
	"previous variant":0,
	"grass information":{"size":14,"scale":Vector3(2,2,2)},
	"house scale": Vector3(16,16,16)
	
}
var extremely_large_houses:Dictionary = { # for scale of level 32, 32, 32 (3200x3200)
	1: load("res://Assets/Level Scenes/very_large_1.tscn"), # this is correct
	2: null,
	3: null,
	"previous variant":0,
	"grass information":{"size":16,"scale":Vector3(1,1,1)},
	"house scale": Vector3(32,32,32)
	
}

# in a dictionary of dictionaries where a key is a type of house (small, expensive ... )
# and value is a dictionary (key = house_variant_id, value: reference to scene)
var houses:Dictionary = {
	"small":small_houses,
	"medium":medium_houses,
	"large":large_houses,
	"very large":very_large_houses,
	"extremely large":extremely_large_houses
	
}

# function access this information
func get_level(type:String, variant:int):
	"""
		Return the house type variant reference (path to object) to be used for given house tyoe
		
		NOTE: a way to ensure that the variants are cycled and say
		that a player does not pick every 3rd job and keeps getting same variant
		is to only update previous variant WHEN a job object is added to the queue of current jobs
	"""
	return houses[type][variant]

func get_grass_info(type:String) -> Dictionary:
	return houses[type]["grass information"] 

func get_house_scale(type:String) -> Vector3:
	return houses[type]["house scale"]

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
