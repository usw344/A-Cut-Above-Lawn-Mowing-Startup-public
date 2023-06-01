extends Node3D


var job_scene:PackedScene = load("res://Mowing Section/Job/job.tscn")

# Called when the node enters the scene tree for the first time.
func _ready():
	# for testing. remove this and replace with a job generator
	var job_data = Job_Data_Container.new()
	var type: String = "large"
	var variant: int = 1
	
	job_data.init_default(1)
	job_data.set_house_type(type)
	job_data.set_house_variant(variant)

	# set the size and scale for the job
	var grass_info = model.get_grass_info(type)
	job_data.set_house_scale(model.get_house_scale(type))
	job_data.set_grass_size(grass_info["size"])
	job_data.set_grass_scale(grass_info["scale"])

	var job = job_scene.instantiate()
	add_child(job)
	job.set_data(job_data)

# this is for testing to toggle 
func _process(delta):
	if Input.is_action_just_pressed("Toggle Mouse Capture"):
		var mouse_mode = Input.mouse_mode
		if mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
		
