extends CharacterBody3D

##Variables localva
var rotate_speed:int = 20

var base_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var gravity = base_gravity
var mouse_sensitivity:float = 0.002 


## Smooth mouse movement
@export var mouse_yaw_smoothing: float = 9.0
@export var mouse_pitch_smoothing: float = 8.0
@export var min_camera_pitch_degrees: float = -75.0
@export var max_camera_pitch_degrees: float = 45.0

var target_body_yaw: float = 0.0
var target_camera_pitch: float = 0.0

## P mode:
## Left/right mouse turning still works.
## Up/down mouse camera movement is disabled.
var p_mode: bool = false


##Signals
signal collided
signal fuel_empty

# This is the mesh instance of the Rider Mower
# The mesh instance has the functions to do movement of individual parts of the mower
@onready var mower_mesh_parts =  $LawnTractor01
@onready var mower_audio:AudioStreamPlayer3D = $AudioStreamPlayer3D

# variables to simulate mower engine running
var max_scale = Vector3(1.0, 1.0, 1.0)
var min_scale = Vector3(0.98, 0.98, 0.98)
var cycle_duration:float = 0.08 # how fast it pulsates
var elapsed_time:float = 0.0
var incr:float = 0.0

var decreasing:bool = false
var moving: bool = false

var show_dev_hud:bool = true

# sound effect stuff 
var idle_volume_db: float = -12.0
var moving_volume_db: float = 1.0
var volume_lerp_speed: float = 4.0

var idle_pitch: float = 0.9
var moving_pitch: float = 1.15

var last_speed: float = 0.0
#end of sound variables


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mower_audio.play()
	mower_audio.volume_db = idle_volume_db

	target_body_yaw = rotation.y
	target_camera_pitch = $Camera3D.rotation.x


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	#dev_hud()
	velocity.y -= gravity * delta

	## Apply smoothed mouse turning/camera movement.
	handle_smoothed_mouse_movement(delta)

	model.set_mower_position(position)

	##get the total user input. This function could also return from screen joystick
	var user_input = get_input() 

	##assign user input to the velocity variable. which is BUILT-IN
	velocity.x = user_input.x * model.get_speed() * 3
	velocity.z = user_input.z * model.get_speed() * 3

	if velocity.x != 0 and velocity.z != 0:
		moving = true
	else:
		moving = false


	# --- AUDIO CONTROL SECTION ---

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()

	# --- acceleration detection ---
	var accel = horizontal_speed - last_speed
	last_speed = horizontal_speed

	# convert speed to 0-1 range
	var max_speed: float = model.get_speed() * 3
	var speed_ratio: float = clamp(horizontal_speed / max_speed, 0.0, 1.0)

	# target values
	var target_volume: float = lerp(idle_volume_db, moving_volume_db, speed_ratio)
	var target_pitch: float = lerp(idle_pitch, moving_pitch, speed_ratio)

	# extra rev when accelerating
	if accel > 0.1:
		target_pitch += 0.02

	# smooth changes
	mower_audio.volume_db = lerp(mower_audio.volume_db, target_volume, volume_lerp_speed * delta)
	mower_audio.pitch_scale = lerp(mower_audio.pitch_scale, target_pitch, volume_lerp_speed * delta)

	# --- END AUDIO SECTION ---


	mower_mesh_parts.send_speed_data(velocity,delta)
	move_and_slide()
	
	## other input related functions
	##calculate how much fuel has been used
	if not model.is_mower_fuel_idle_counter(): 		  ##value is still less than counter
		model.increment_mower_fuel_idle_counter(0.05) ##this is general fuel used due to idling
	else:
		model.set_mower_fuel(model.get_mower_fuel() - 1) ##substract one value of fuel due to counter being reached
		model.set_mower_fuel_idle_counter(0)			 ##reset the counter to zero
	
	##collision signal is based if fuel is full or not
	if model.get_mower_fuel() <= 0:
		handle_collision("fuel_empty")
		model.set_mower_fuel(100) #TODO !!!!! remove this when done testing
	else:
		handle_collision("collided")


func handle_smoothed_mouse_movement(delta):
	var old_yaw: float = rotation.y

	rotation.y = lerp_angle(
		rotation.y,
		target_body_yaw,
		1.0 - exp(-mouse_yaw_smoothing * delta)
	)

	var applied_rot_y: float = shortest_angle_difference(old_yaw, rotation.y)

	if abs(applied_rot_y) > 0.00001:
		mower_mesh_parts.send_rotation_data(applied_rot_y)

	$Camera3D.rotation.x = lerp_angle(
		$Camera3D.rotation.x,
		target_camera_pitch,
		1.0 - exp(-mouse_pitch_smoothing * delta)
	)


func shortest_angle_difference(from_angle: float, to_angle: float) -> float:
	return wrapf(to_angle - from_angle, -PI, PI)


func handle_collision(signal_name):
	"""
	Function to handle collision and send correct signal
	This code used to be in the _physics_process function but due to 
	checking for empty fuel then there are 2 two signals
	"""
	
	# try to see if this causes the jittering
	var collision_array:Array = []
	for z in get_slide_collision_count():
		collision_array.append(get_slide_collision(z))
	emit_signal(signal_name, collision_array)


func _input(event):
	"""
	"""
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			p_mode = !p_mode

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Left/right mower turning is now smoothed.
		target_body_yaw -= event.relative.x * mouse_sensitivity

		# In P mode, disable up/down camera movement.
		if not p_mode:
			target_camera_pitch += event.relative.y * mouse_sensitivity
			target_camera_pitch = clamp(
				target_camera_pitch,
				deg_to_rad(min_camera_pitch_degrees),
				deg_to_rad(max_camera_pitch_degrees)
			)


"""
	Encapsulation function to handle getting user input.
	
	TODO: add virtual movement stick as well

	return input_direction: Vector3 containg x, y, z movement input
"""
func get_input():
	"""
		Main input function. This also handles wheel rotation
	"""
	var input_direction = Vector3()

	var use_fuel = false
	if Input.is_action_pressed("move_forward"):
		input_direction += global_transform.basis.z
		use_fuel = true
	if Input.is_action_pressed("move_back"):
		input_direction += -global_transform.basis.z
		use_fuel = true

	##if movement happened then increment fuel counter
	if use_fuel:
		model.increment_mower_fuel_idle_counter(1)

	return input_direction 


func dev_hud():
	var string_to_print:String = ""
	string_to_print += str(round(position/16)) + "\n"
	string_to_print += "FPS: " + str(Performance.get_monitor(Performance.TIME_FPS)) + "\n"
	string_to_print += "Rendered calls: " + str(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)) + "\n"
	string_to_print += "Memory: " + str(round(Performance.get_monitor(Performance.MEMORY_STATIC)/1000000)) + "\n"
	string_to_print += "Vertices" + str(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) + "\n"
	string_to_print += "P Mode: " + str(p_mode)

	$CanvasLayer/Label.text = string_to_print
