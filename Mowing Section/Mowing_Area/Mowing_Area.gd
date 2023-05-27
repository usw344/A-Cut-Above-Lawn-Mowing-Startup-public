extends Node3D

var data:Job_Data_Container = null

# store the grass object name and the object reference
var grass_location:Dictionary = {}

var mesure = Mesurment.new("Mowing Area")

var gridmap_referene:GridMap = null
var truck_area:MeshInstance3D = null
var level = null
# Called when the node enters the scene tree for the first time.
func _ready():
	pass


func _process(delta):
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
	var _level = level_reference.instantiate()
	add_child(_level)
	level = _level
	# set the reference to the gridmap
	gridmap_referene = level.get_node("StaticBody3D/Mowing Area/GridMap")
	
	# since the size can vary. Calculate the size and set it for the data
	var mesh = level.get_node("StaticBody3D/Mowing Area")
	var scaling = level.get_node(".").scale

	# setting the sie
	data.set_width(mesh.mesh.size.x * scaling.x)
	data.set_length(mesh.mesh.size.y * scaling.z)
	
	# get the truck zone area
	var truck_zone = level.get_node("Truck Zone")
	truck_zone.connect("body_entered",handle_truck_zone)
	
	# setup up the grid map using this function
	setup_grass()


func setup_grass():
	var rotations:Array = [0,10,16,22] # these are the only available rotations
	
	var start = -data.get_amount_of_grass()
	var stop = data.get_amount_of_grass()
	for x in range(start,stop,1):
		for z in range(start,stop,1):
			
			gridmap_referene.set_cell_item(Vector3(x,0,z),1,0)

#OUT DATED. This func
func handle_collision(collision:KinematicCollision3D):
#	var name_of_collider = collision.get_collider().name
	
	var string:String = ""
	
	# first need to convert global position to local position
	var collision_position = collision.get_position()
	
	string += "Collision position unlocal:" + str(collision_position) +"\n"
	
	var local_position:Vector3i = level.get_node("StaticBody3D").to_local(collision_position)
	string += "Local position:" + str(local_position) +"\n"
	
	local_position = gridmap_referene.local_to_map(local_position)
	string += "Local position to gridmap:" + str(local_position) +"\n"
	local_position.y =0 # since the collision occurs at some y > 0

	gridmap_referene.set_cell_item(local_position,-1)
	print("collision")
	local_position.y =2
	gridmap_referene.set_cell_item(local_position,0)
	$CanvasLayer/Label.text = string

func handle_truck_zone(node):
	print(node.name)

func set_data(d:Job_Data_Container):
	data = d
