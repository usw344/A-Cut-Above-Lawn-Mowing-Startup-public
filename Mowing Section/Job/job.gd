extends Node3D


# data for this job
var data:Job_Data_Container

# TODO make this dynamic so that the mower can be changed out.
# This could be done via the model
@onready var mower: CharacterBody3D = $"Small Gas Mower"

var mesure = Mesurment.new("Job Scene peformance measure")
# static rerference to mowing area 
@onready var mowing_area:Node3D = $"Mowing Area2"

# Called when the node enters the scene tree for the first time.
func _ready():

	pass

var avg:float = 0
var calls:float = 0.0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	mowing_area.calculate_grass_loading(mower.global_position)
#	mowing_area.get_grid_edges()
#	pass


func set_data(d:Job_Data_Container):
	data = d
	mowing_area.setup(data)
	
	# now set mower start position based on current job area
	set_mower_position()

	
func set_mower_position():

	var new_pos:Vector3 = mowing_area.return_truck_zero_position()
	mower.position.x += new_pos.x # gives position of the truck pad
	mower.position.z += new_pos.z
	mower.position.y = 30
	
#	mower.position = Vector3(0,30,0)
	



func _on_mower_normal_collided(collisions): # collision:KinematicCollision3D
	mowing_area.handle_collision(collisions)
