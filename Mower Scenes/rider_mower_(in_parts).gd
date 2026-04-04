extends MeshInstance3D

"""

This is only the mesh instance of the Rider Mower

This script allows the manipluation of the indivial parts of the mower

The complete functionallity of the mower is in the Mower Rider scene

"""

@onready var wheels:Array[MeshInstance3D] = [$WheelBL,$WheelBR,$WheelFL,$WheelFR]
@onready var steering:MeshInstance3D = $SteeringWheel

var max_steering_angle_deg: float = 35.0
var steering_turn_speed: float = 10.0
var steering_return_speed: float = 6.0
var steering_input_scale: float = 12.0

var steering_rest_rotation: Vector3
var steering_target_angle: float = 0.0

func _ready() -> void:
	steering_rest_rotation = steering.rotation

func _physics_process(delta: float) -> void:
	engine_pulsation(delta)
	_update_steering(delta)
	

func send_speed_data(speed:Vector3,delta):
	#var movement_speed:float = maxf(speed.x,speed.z)
	var movement_speed: float = maxf(abs(speed.x), abs(speed.z))
	var rot_amount = movement_speed * 2.0 * delta
	rotate_wheels(rot_amount)

#func send_rotation_data(rotation_data:float):
	## rotate the steering Wheel 
	#steering.rotate_y(rotation_data)
	#$Timer.start(0.08)
func send_rotation_data(rotation_data: float):
	var max_angle_rad = deg_to_rad(max_steering_angle_deg)
	steering_target_angle += rotation_data * steering_input_scale
	steering_target_angle = clamp(steering_target_angle, -max_angle_rad, max_angle_rad)

func _update_steering(delta: float) -> void:
	steering_target_angle = move_toward(steering_target_angle, 0.0, steering_return_speed * delta)
	var desired_y = steering_rest_rotation.y + steering_target_angle
	steering.rotation.y = lerp_angle(steering.rotation.y, desired_y, steering_turn_speed * delta)

func rotate_wheels(amount_to_rotate):
	for wheel:MeshInstance3D in wheels:
		if wheel.rotation_degrees.x == 360.0:
			wheel.rotation_degrees.x = 0.0
		else:
			wheel.rotate_x(amount_to_rotate)
	
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
