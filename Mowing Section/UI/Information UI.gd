extends Control

# store static references to the nodes
@onready var fuel_bar = $"Fuel Progress Bar"
@onready var grass_bar = $"Cuttings Progress Bar"
@onready var time_remaing_bar = $"Time Left Progress Bar"

# buttons
@onready var press_m_manage = $"Press M to Manage" # this remains visible throughout
@onready var press_o_open = $"Press O to Manage"   # hide this unless on truck zone

#store the reference to whatever is the current job data object
var job_data:Job_Data_Container = null

func _ready():
	pass 

func _process(delta):
	update_fuel_display()

func update_fuel_display():
	var current_fuel = model.get_mower_fuel()
	fuel_bar.value = current_fuel
func update_cuttings_display():
	var cuttings = model.get_cuttings()

func set_job_data(d: Job_Data_Container):
	"""
	Set the job data.

	Parameters:
	- d: Job_Data_Container object containing the data to be set.
	"""
	job_data = d

func get_job_data() -> Job_Data_Container:
	"""
	Get the job data.

	Parameters:
	None

	Returns:
	- Job_Data_Container object containing the job data.
	"""
	return job_data
