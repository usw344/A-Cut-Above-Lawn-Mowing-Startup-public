extends CharacterBody3D

##Variables localva
var rotate_speed:int = 20

var base_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var gravity = base_gravity
var mouse_sensitivity:float = 0.002 

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

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	#dev_hud()
	velocity.y -= gravity * delta
#
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
	
#	for i in get_slide_collision_count():
#		var collision = get_slide_collision(i)
#		emit_signal(signal_name, collision) ## send collision since if it is with block then a notification can be sent


func _input(event):
	"""
	"""
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# rot_y moves the mower left and right
		var rot_y:float = -event.relative.x * mouse_sensitivity
		#rot_x_cam moves the camera up and down
		var rot_x_cam:float = event.relative.y * mouse_sensitivity
		
		mower_mesh_parts.send_rotation_data(rot_y)
		rotate_y(rot_y)
		$Camera3D.rotate_x(rot_x_cam)

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
#	var rotate_wheel = {"forward": 0, "backward": 0, "right": 0, "left": 0}

	var use_fuel = false
	if Input.is_action_pressed("move_forward"):
		input_direction += global_transform.basis.z
#		rotate_wheel["forward"] = rotate_speed
		use_fuel = true
	if Input.is_action_pressed("move_back"):
		input_direction += -global_transform.basis.z
#		rotate_wheel["backward"] = -rotate_speed
		use_fuel = true

	##if movement happened then increment fuel counter
	if use_fuel:
		model.increment_mower_fuel_idle_counter(1)

#	##function to rotate all wheel according to given values
#	rotate_wheels(rotate_wheel)
	

	return input_direction 
func dev_hud():
	var string_to_print:String = ""
	string_to_print += str(round(position/16)) + "\n"
	string_to_print += "FPS: " + str(Performance.get_monitor(Performance.TIME_FPS)) + "\n"
	string_to_print += "Rendered calls: " + str(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)) + "\n"
	string_to_print += "Memory: " + str(round(Performance.get_monitor(Performance.MEMORY_STATIC)/1000000)) + "\n"
	string_to_print += "Vertices" + str(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	$CanvasLayer/Label.text = string_to_print
