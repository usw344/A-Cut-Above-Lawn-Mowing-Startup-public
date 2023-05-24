extends Node3D


# data for this job
var data:Job_Data_Container

# TODO make this dynamic so that the mower can be changed out.
# This could be done via the model
@onready var mower: CharacterBody3D = $"Small Gas Mower"


# static rerference to mowing area 
@onready var mowing_area:Node3D = $"Mowing Area2"

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func set_data(d:Job_Data_Container):
	data = d
	mowing_area.setup(data)
	
	# now set mower start position based on current job area
	set_mower_position()

	
func set_mower_position():
	mower.position.y =50
	



func _on_mower_normal_collided(collision:KinematicCollision3D):
	if collision.get_collider().name == "GridMap":
		mowing_area.handle_collision(collision)
