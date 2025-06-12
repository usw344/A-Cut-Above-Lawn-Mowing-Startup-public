extends MeshInstance3D

"""

This is only the mesh instance of the Rider Mower

This script allows the manipluation of the indivial parts of the mower

The complete functionallity of the mower is in the Mower Rider scene

"""

@onready var wheels = [$WheelBL,$WheelBR,$WheelFL,$WheelFR]

func _physics_process(delta: float) -> void:
	engine_pulsation(delta)

func send_speed_data(speed:Vector3):
	pass

func send_rotation_data(rotation_data:float):
	# rotate the steering Wheel 
	$SteeringWheel.rotate_y(rotation_data)
	


func rotate_wheels():
	pass
	
# variables to simulate mower engine running
var max_scale = Vector3(1.0, 1.0, 1.0)
var min_scale = Vector3(0.98, 0.98, 0.98)
var cycle_duration:float = 0.08 # how fast it pulsates
var elapsed_time:float = 0.0
var incr:float = 0.0

var decreasing:bool = false
var moving: bool = false



func engine_pulsation(one_frame:float):
	# code to simulate engine running
	incr = one_frame
	
	if moving:
		incr /= 4
	
	if elapsed_time >= cycle_duration: # use cycle duration to increase or decrease speed
		decreasing = true
	if elapsed_time <= 0:
		decreasing = false
		incr = abs(incr)
	
	if decreasing == true:
		incr *= -1

	# code to pulsate the mower to imitate engine
	elapsed_time += incr
	var cycle_progress = elapsed_time / cycle_duration

	var scale_val = lerp(min_scale, max_scale, cycle_progress)
	$Bag.scale = scale_val
	$Bag.scale = scale_val


func lerp(a, b, t):
	"""
		To interpolate between two values.
		This function is used to smoothly pulsate the engine
	"""
	return a + (b - a) * t
