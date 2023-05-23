extends Node3D

var data:Job_Data_Container = null

# store the grass object name and the object reference
var grass_location:Dictionary = {}

var mesure = Mesurment.new("Mowing Area")

var gridmap_referene:GridMap = null
var truck_area:MeshInstance3D = null
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
	
	#get the referene (load () ) of the level that is needed
	var level_reference = model.get_level(type,variant)
	
	# setup ground and house
	var level = level_reference.instantiate()
	add_child(level)
	
	# set the reference to the gridmap
	gridmap_referene = level.get_node("StaticBody3D/Mowing Area/GridMap")
	
	# since the size can vary. Calculate the size and set it for the data
	var mesh = level.get_node("StaticBody3D/Mowing Area")
	var scaling = level.get_node(".").scale

	# setting the sie
	data.set_width(mesh.mesh.size.x * scaling.x)
	data.set_length(mesh.mesh.size.y * scaling.z)
	
	# setup up the grid map using this function
	setup_grass()

#	$CanvasLayer/Label2.text = "From setup" + str(get_child_count()) + "\n"


func setup_grass():
	var rotations:Array = [0,10,16,22] # these are the only available rotations
	
	var start = -(data.get_width()/12)
	var stop = data.get_width()/12
	print(start)
	for x in range(-start,stop,1):
		for z in range(-start,stop,1):
			
			
			gridmap_referene.set_cell_item(Vector3(x,0,z),1,rotations.pick_random())

#OUT DATED. This func
func handle_collision(collision:KinematicCollision3D):
	var name_of_collider = collision.get_collider().name
	if grass_location.has(name_of_collider):
		var current_grass =  grass_location[name_of_collider]
		
		remove_child(current_grass)
		grass_location.erase(name_of_collider)
		data.set_grass_data(grass_location) # this can then get updated to model


func set_data(d:Job_Data_Container):
	data = d
