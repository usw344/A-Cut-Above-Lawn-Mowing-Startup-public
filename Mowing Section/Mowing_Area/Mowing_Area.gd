extends Node3D

var data:Job_Data_Container = null


# grass instance reference
var repalce_grass_scene = load("res://Assets/Foliage/mowed_grass_thick.glb") 
var simple_grass_scene = load("res://Assets/Scenes/LargeSingleMeshGrass.tscn")
var fence_to_down = load("res://Assets/Scenes/fenceupdown.tscn")
# store the grass object name and the object reference
var grass_location:Dictionary = {}

var mesure = Mesurment.new("Mowing Area")

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
#	$CanvasLayer/Label.text = str(get_child_count())
	pass


func setup(new_data:Job_Data_Container):
	"""
	Main function for this class. Pass in the Job_Data_Container object here. This function will setup the 
	mowing objects and ground
	"""
	data = new_data
	
	var type = data.get_house_type()
	var variant = data.get_house_variant()
	
	var level_reference = model.get_level(type,variant)
	
	# setup ground and house
	var level = level_reference.instantiate()
	add_child(level)


#	$CanvasLayer/Label2.text = "From setup" + str(get_child_count()) + "\n"


func handle_collision(collision:KinematicCollision3D):
	var name_of_collider = collision.get_collider().name
	if grass_location.has(name_of_collider):
		var current_grass =  grass_location[name_of_collider]
		
		remove_child(current_grass)
		grass_location.erase(name_of_collider)
		data.set_grass_data(grass_location) # this can then get updated to model


func set_data(d:Job_Data_Container):
	data = d
