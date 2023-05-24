extends Node3D
class_name Job_Data_Container

# width and height of the mowing space
var width:int
var length:int

# unique identifier for the job
var job_id:int

# contains key = grass_object_name location of grass location value = scale
var grass_data:Dictionary = {}

# to store rocks or trees etc key = type value = vector3 location
var other_objects_data:Dictionary = {}

# store the house type (small, medium etc) and variant (1,2,3) that should be used with level
var house_info:Dictionary = {
	"type":null,
	"variant":null
}

# contains amount of grass for the given level
var amount_of_grass:int

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


func _init():
	pass
	
func init_default(id:int,amount:int):
	"""
		This function is a short cut to make a default empty job object with a given width, length
		
		param
			id: a unique identifier for this job
			amount: amount of grass to be used for this level
		
		Return
			None
	"""
	set_job_id(id)
	set_amount_of_grass(amount)

	
	# data dictionaries are already empty
	

# Setters
func set_width(new_width: int) ->void:
	"""
	Set the width of the mowing space to a new value.
	
	Parameters:
	- new_width (int): the new width of the mowing space
	
	Returns:
	None
	"""
	width = new_width
	
func set_length(new_length: int) ->void:
	"""
	Set the length of the mowing space to a new value.
	
	Parameters:
	- new_length (int): the new length of the mowing space
	
	Returns:
	None
	"""
	length = new_length
	
func set_job_id(new_job_id: int) ->void:
	"""
	Set the unique identifier for the job to a new value.
	
	Parameters:
	- new_job_id (int): the new unique identifier for the job
	
	Returns:
	None
	"""
	job_id = new_job_id

func set_grass_data(data:Dictionary)->void:
	grass_data = data

func set_other_object_data(data:Dictionary) ->void:
	other_objects_data = data

func set_house_type(type:String):
	house_info["type"] = type
func set_house_variant(num:int):
	house_info["variant"] = num


func set_amount_of_grass(a:int):
	amount_of_grass = a

# Getters
func get_width() -> int:
	"""
	Get the current width of the mowing space.
	
	Parameters:
	None
	
	Returns:
	The current width of the mowing space as an integer.
	"""
	return width
	
func get_length() -> int:
	"""
	Get the current length of the mowing space.
	
	Parameters:
	None
	
	Returns:
	The current length of the mowing space as an integer.
	"""
	return length
	
func get_job_id() -> int:
	"""
	Get the current unique identifier for the job.
	
	Parameters:
	None
	
	Returns:
	The current unique identifier for the job as an integer.
	"""
	return job_id

func get_grass_data() ->Dictionary:
	return grass_data

func get_other_object_data() ->Dictionary:
	return other_objects_data

func get_house_type():
	return house_info["type"] # small, medium etc as listed in model
func get_house_variant():
	return house_info["variant"] # 1,2,3 etc as listed in model

func get_amount_of_grass() -> int:
	return amount_of_grass





func load_object(data:Dictionary) ->void:
	"""
		Function to load data from a Dictionary that was made by save_object()
	"""
	set_job_id(data["id"])
	set_width(data["width"])
	set_length(data["length"])
	set_grass_data(data["grass_data"])
	set_other_object_data(data["object_data"])

func save_object() ->Dictionary:
	"""
	For the purpose of saving the game. this function will return the following in a Dictionary
	id
	width
	length
	grass_data if any
	object_data if any
	"""
	var data:Dictionary = { 
		"id":get_job_id(),
		"width":get_width(),
		"length":get_length(),
		"grass_data":get_grass_data(),
		"object_data":get_other_object_data()
	}
	return data
	


