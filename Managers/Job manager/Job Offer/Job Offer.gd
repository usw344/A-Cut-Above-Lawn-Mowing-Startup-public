extends Node3D
class_name Job_Offer

"""
Most basic of the job containers. contains offer information.

Note: This gets added to the scene tree in the Job Manager (recieve_job_offer) function
This way the timer can be used to trigger if this job is to be declined

EXTENDED BY: Job, Job_Declined (todo) 
"""

# unique per1
var job_id: int 

# store the size (Must comply to custom gridmap restrictions. If not)
var job_size:Vector2i

# key:D (days), key:H (hours), key:M (minutes)
var time_limit:Dictionary 

# how much money the job offer 
var base_pay:float

# Name of job to display to the user 
var display_name:String

# in seconds
var time_to_accept:int = -1
var timer:Timer

signal remove_offer
# Called when the node enters the scene tree for the first time.
func _ready():
	# set the wait time for the timer node
	timer = Timer.new()
	timer.wait_time = max(time_to_accept,0) # max just in case this is called when wait time is not set

	timer.connect("timeout",remove_job_offer)
	add_child(timer)
	timer.start()
	
	
func init():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func setup_job_offer(job_id_:int, job_size_:Vector2i,time_limit_:Dictionary,base_pay_:float,display_name_:String,time_to_accept_:int):
	"""
	This function should fill in the job offer and initlize the job offer.
	This function is NOT meant to be used with load_object()/save_object()
	"""
	job_id = job_id_
	job_size = job_size_
	time_limit = time_limit_
	base_pay = base_pay_
	display_name = display_name_
	time_to_accept = time_to_accept_
	



func get_as_string() ->String:
	"""
	Debugging function to get this job offer as a string that can be printed
	
	"""
	
	var str:String = ""
	
	str += "********* Start **********"+ "\n"
	str += "Job Display Name: " + str(display_name) + "\n"
	str += "Job ID: " + str(job_id) + "\n"
	str += "Job Size: " + str(job_size.x) + "x" + str(job_size.y)+ "\n"
	str += "Base Pay: " + str(base_pay)+ "\n"
	str += "Duration: Days" + str(time_limit["D"]) + " Hours: " + str(time_limit["H"]) + " Minute:" + str(time_limit["M"])+ "\n"
	str += "Time Left To Accept: " + str(time_to_accept)+ "\n"
	str += "*********  End  **********"
	
	return str

# get and set methods for the various variables in this object
func get_id() -> int:
	return job_id
func get_job_size() ->Vector2i :
	return job_size
func get_time_limit() -> Dictionary:
	return time_limit
func get_base_pay():
	return base_pay
func get_display_name() -> String:
	return display_name
func get_time_to_accept() -> int:
	return time_to_accept

### functions relating to accepting/declining and updating

func accept_job() ->Job:
	"""
	Make and return a Job object containing the following information.
	
	This function would be called in the Job_Offer_Display object. Since that is 
	where the job offer is rep
	"""
	return Job.new()

func remove_job_offer() ->void:
	"""
	If the timer to accept expires then remove offer.
	To encapsulate the timer (in case some other mechanism is used later) have this 
	function send another signal
	"""
	print("Emiting signal")
	emit_signal("remove_offer")
func get_remaining_time_to_accept_as_percentage() -> int:
	"""
	EXPECTS: to be called only when this object is inside the scene tree
	
	This function provides a 0-100 representation of how much time 
	is left in accepting 
	"""
	var inital_time_in_timer:int = time_to_accept
	var time_left_in_timer:int = timer.time_left
	var percentage:float = float(time_left_in_timer)/float(inital_time_in_timer)

	return int(percentage*100)
func get_remaining_time_to_accept_as_string_format() -> String:
	var time_in_seconds = timer.HORIZONTAL_ALIGNMENT_LEFT
	return ""
