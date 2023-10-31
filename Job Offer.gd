extends Node3D
class_name Job_Offer

"""
Most basic of the job containers. contains offer information.

EXTENDED BY: Job, Job_Declined (todo) 
"""

# unique per1
var job_id: int 

# store the size (Must comply to custom gridmap restrictions. If not)
var job_size:Vector2i

# key:hour, key:minute, key:second
var time_limit:Dictionary 

# how much money the job offer 
var base_pay:float

# Name of job to display to the user 
var display_name:String

# in seconds
var time_to_accept:int

# Called when the node enters the scene tree for the first time.
func _ready():
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

