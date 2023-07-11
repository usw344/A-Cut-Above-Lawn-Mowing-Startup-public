extends Node3D


var location_rounded:Vector3
var job_data:Job_Data_Container

# array index references
const MOWED_LOW = 0
const MOWED_HIGH = 1
const UNMOWED_LOW = 2
const UNMOWED_HIGH = 3

# array to hold the Node references. Populated in the _ready function
var grass_references = []

var mowed = false

func _ready():
	# for easier access add the Node references to the dictionary
	grass_references.append($"Mowed Grass Low LOD")
	grass_references.append($"Mowed Grass High LOD")
	grass_references.append($"Unmowed Grass Low LOD")
	grass_references.append($"Unmowed Grass High LOD")



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func set_location(location:Vector3):
	location_rounded = location

func set_job_data(data:Job_Data_Container):
	job_data = data

func setup_cell(location_rounded_val:Vector3,job_data_obj:Job_Data_Container,):
	"""
	Function called from outside this scene. Pass in data to setup the grass cell
	"""
	# set these internal values
	set_location(location_rounded_val)
	set_job_data(job_data_obj)
	
	# set the scale and size for each of the grass
	for grass in grass_references:
		grass.position = location_rounded
		grass.scale = job_data.get_grass_scale() # value is derived from the model
	
func flip_to_mow():
	mowed = true
	
func flip_to_high_lod():
	if mowed:
		grass_references[MOWED_LOW].hide()
		grass_references[MOWED_HIGH].show()
	else:
		grass_references[UNMOWED_LOW].hide()
		grass_references[UNMOWED_HIGH].show()

func flip_to_low_lod():
	if mowed:
		grass_references[MOWED_LOW].show()
		grass_references[MOWED_HIGH].hide()
	else:
		grass_references[UNMOWED_LOW].show()
		grass_references[UNMOWED_HIGH].hide()

func get_this_global_position():
	"""
	Because the actual node (grass cell) may not have a global position set
	this function grabs the global position 
	"""
	# only need to return one since they all have the same local position
	return $"Mowed Grass High LOD".global_position
