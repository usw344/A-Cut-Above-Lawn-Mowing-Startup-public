extends Node
class_name Game_Profile

"""
Data structure to hold game save data
"""
## version this profile was last saved with
var version:Dictionary

## name of profile
var profile_name:String

## a copy of the model
var data:Dictionary

func _init(Major, Minor, Smallest, name_of_this_profile, data_dict):
	set_version(Major, Minor, Smallest)
	set_profile_name(name_of_this_profile)
	set_data(data_dict)

func set_version(major:int, minor:int, smallest:int) -> void: 
	"""
	Pass in version number in 3 point format
	in int format -> Major,Minor,Smallest
	
	ex. 0.4.5
	"""
	version = {"Major":major,"Minor":minor,"Smallest":smallest}
	
func get_version() -> Dictionary:
	return version
	
func set_profile_name(name_of_profile:String) -> void:
	profile_name = name_of_profile
func get_profile_name() ->String:
	return profile_name
	
func set_data(game_data:Dictionary) -> void:
	data = game_data
func get_data() -> Dictionary:
	return data
