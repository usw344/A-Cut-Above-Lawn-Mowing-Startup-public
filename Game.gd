extends Node3D


var job_scene:PackedScene = load("res://Mowing Section/Job/job.tscn")

# Called when the node enters the scene tree for the first time.
func _ready():
	# for testing. remove this and replace with a job generator
	var job_data = Job_Data_Container.new()
	var type: String = "very large"
	var variant: int = 1
	
	var size_of_job:Array = model.get_size_of_mowing_area_by_job_type(type)
	job_data.init_default(1, size_of_job[0],size_of_job[1])
	job_data.set_house_type(type)
	job_data.set_house_variant(variant)

	var job = job_scene.instantiate()
	add_child(job)
	job.set_data(job_data)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
