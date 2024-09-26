extends Node3D


var job_scene:PackedScene = load("res://Mowing Section/Job/job.tscn")

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

# this is for testing to toggle 
func _process(delta):
	if Input.is_action_just_pressed("Toggle Mouse Capture"):
		var mouse_mode = Input.mouse_mode
		if mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
		
