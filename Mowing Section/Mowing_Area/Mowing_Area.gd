extends Node3D

var data:Job_Data_Container = null

var grid_size:Vector2
var simple_grass_scene = load("res://Assets/Foliage/Scenes/Some Grass.tscn")

var grass_location:Dictionary = {}


# Called when the node enters the scene tree for the first time.
func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	$CanvasLayer/Label.text = str(get_child_count())


func setup(new_data:Job_Data_Container):
	"""
	Main function for this class. Pass in the Job_Data_Container object here. This function will setup the 
	mowing objects and ground
	"""
	data = new_data
	setup_ground_below_grass()
	setup_ground_below_mower_start_position()
	setup_house()
	add_grass()
	$CanvasLayer/Label2.text = "From setup" + str(get_child_count()) + "\n"


func setup_house():
	pass


func setup_ground_below_mower_start_position():
	# since the grass area is set to 0,0,0. this should be to the south side of that
	# grass_area_width, 0, grass_area_length
	var static_body_of_ground:StaticBody3D = $"Start Point For Mower"
	var mesh_of_ground:MeshInstance3D = $"Start Point For Mower/MeshInstance3D"
	var collision_shape_for_ground:CollisionShape3D = $"Start Point For Mower/CollisionShape3D"
	
	# BUG. for some reason there is a very small ofset different. that is accounted 
	# for with the alignment_margin 
	
	var alignment_margin:int = 2
	
	# calculate where to place the start ground. the minus 2 due to some mis calculation issue somewhere
	static_body_of_ground.transform.origin.x += data.get_width() -alignment_margin
	static_body_of_ground.transform.origin.y = 0
	static_body_of_ground.transform.origin.z = - alignment_margin
	
	
	collision_shape_for_ground.shape.extents.x = data.get_width()/2 
	collision_shape_for_ground.shape.extents.z = data.get_length()/2
	
	mesh_of_ground.mesh.size.x = data.get_width()
	mesh_of_ground.mesh.size.z = data.get_length()

func setup_ground_below_grass():
	"""
		Internal function to setup ground for mowing
	"""

	# For easier referencing get the variable references 
	var static_body_of_ground:StaticBody3D = $"Grass Area"
	var mesh_of_ground:MeshInstance3D = $"Grass Area/MeshInstance3D"
	var collision_shape_for_ground:CollisionShape3D = $"Grass Area/CollisionShape3D"
	
	# zero location of the static mesh in case it was moved in editor
	static_body_of_ground.transform.origin.x = 0
	static_body_of_ground.transform.origin.y = 0
	static_body_of_ground.transform.origin.z = 0

	# set the collision shape and mesh sizes
	collision_shape_for_ground.shape.extents.x = data.get_width()/2
	collision_shape_for_ground.shape.extents.z = data.get_length()/2
	
	mesh_of_ground.mesh.size.x = data.get_width()
	mesh_of_ground.mesh.size.z = data.get_length()
	

func calculate_and_get_mower_start_position() -> Vector3:
	var static_body_of_ground:StaticBody3D = $"Start Point For Mower"
	var start_point_position = static_body_of_ground.transform.origin
	return Vector3( start_point_position.x+10, start_point_position.y, start_point_position.z    )


func setup_store():
	"""
		Instance and set the location and scale of the store
	"""
	pass

func add_grass():
	"""
		Setup the x,z location and heights of the grass.
		This function will add this dictionary (key = location) value: mesh to the job container
	"""
	var amount_of_grass:int = round((data.get_width()/6)-5)
	var some_noise:FastNoiseLite = FastNoiseLite.new()
	some_noise.frequency = 0.4
		
	# establish bounds on how much grass is desired
	print(amount_of_grass)
	amount_of_grass = max(50, amount_of_grass)
	amount_of_grass = min(50, amount_of_grass)
	
	var some_scale:int = 12
	var reduction:int =5 # reduce the density of the grass
	
	var margin_on_edges = 5
	
	# because we multiply x and z later sometimes the grass can go out of bounds
	var margin_offset = 20 # 30 here is an estimate to get them all in the mowing area
	
	for x in range(-data.get_width()/2,data.get_width()/2-margin_on_edges,reduction):
		for z in range(-data.get_length()/2+margin_on_edges, data.get_length()/2-margin_on_edges,reduction):
				var grass = simple_grass_scene.instantiate()
				add_child(grass)
				var set_x = x + abs(randf_range(1,2) - reduction) # minus reduction to account for reduction offset
				var set_z = z + abs(randf_range(1,2) - reduction)
				
				if set_x < -data.get_width() or set_x > data.get_width():
					remove_child(grass)
					print("true")
					continue
				grass.position.x = set_x
				grass.position.z = set_z
				grass.position.y = 0
				
				grass.rotation.y = randf_range(1,12)

				grass.scale.x = some_scale
				grass.scale.z = some_scale
				grass.scale.y = randf_range(some_scale,some_scale+5)
				
				grass_location[Vector3(x,0,z)] = grass
				
				
func handle_collisons():
	pass


func set_data(d:Job_Data_Container):
	data = d
