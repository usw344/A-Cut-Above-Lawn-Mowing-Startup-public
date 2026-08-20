extends Node
class_name Model

"""
This is an autoload script that stores global game variables
"""


"""------------------------------------------- Mower.tscn variables AND functions -------------------------------------------"""
var speed = 10 
var blade_length = 1

## MOWER FUEL - STORAGE ONLY.
##
## `mower_fuel` (0-100) is the authoritative fuel LEVEL and is what SaveService
## persists. The RULES - burn rates, what empty means, the refuel interface and
## the development Auto Refuel toggle - all live in `MowerFuel`
## (Game/App/mower_fuel.gd). Nothing else may implement a burn rate.
##
## Changed 2026-08-19 (Milestone 9): fuel is now a float and is burned per
## SECOND. The old model added a fixed amount per PHYSICS TICK, and this project
## runs physics at 576 Hz, so a tank emptied in about four seconds.
var mower_fuel: float = 100.0

## LEGACY, no longer read by any mower. Kept only because they are fields of the
## current save format; removing them would need a save-format version bump for
## no gain. `MowerFuel` ignores both.
var mower_fuel_idle_counter = 0
var idle_fuel_use = 26

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
	Get and Set for the mower fuel LEVEL. Storage only - see the note above the
	variable. Gameplay goes through MowerFuel, which clamps and announces.
"""
func get_mower_fuel():
	return mower_fuel
func set_mower_fuel(f):
	mower_fuel = clampf(float(f), 0.0, 100.0)

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



"""------------------------------------------- Job system  -------------------------------------------"""
# Jobs are owned by ACAJobManager (the `JobManager` autoload), not by this
# model. The old 'testing grounds' job-offer dictionary that used to live here
# was removed with the rest of that prototype - see Soft Delete/MANIFEST.md.

"""------------------------------------------- Model functions  -------------------------------------------"""
func save_game_data(file_name):
	var variables = {
		"speed": get_speed(),
		"blade_length":get_blade_length(),
		"mower_fuel":get_mower_fuel(),
		"mower_fuel_idle_counter":get_mower_fuel_idle_counter(),
		"idle_fuel_use":get_idle_fuel_use()
	}

## ENTER releases / re-captures the cursor while playing. The cursor itself is
## owned by AppUI, which refuses the toggle while a menu is holding it - without
## that, confirming a pause-menu button with ENTER would grab the mouse back.
func _input(event):
	if Input.is_action_just_pressed("ui_accept"):
		var app_ui := get_node_or_null(^"/root/AppUI")
		if app_ui != null:
			app_ui.call(&"toggle_mouse_capture")


func load_game_data(file_name):
	pass

func get_game_profile_object():
	pass
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func _process(delta):
#	print("Current fuel " ,get_mower_fuel()," counter: ",get_mower_fuel_idle_counter())
	pass
