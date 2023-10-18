extends CharacterBody3D


##Variables stored in model. THESE are defaults



##Variables localva
var rotate_speed:int = 20

var base_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var gravity = base_gravity
var mouse_sensitivity:float = 0.002 

##Signals
signal collided
signal fuel_empty

# variables to simulate mower engine running
var max_scale = Vector3(1.0, 1.0, 1.0)
var min_scale = Vector3(0.98, 0.98, 0.98)
var cycle_duration:float = 0.08 # how fast it pulsates
var elapsed_time:float = 0.0
var incr:float = 0.0

var decreasing:bool = false
var moving: bool = false

var show_dev_hud:bool = true

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	dev_hud() # can remove this 
	
	## mower animation ##
	
	# mower engine effect
	engine_pulsation(delta)
	
	#mower blade rotation
	$ring_bevelEdges.rotate_z(2)

	velocity.y -= gravity * delta
#
	model.set_mower_position(position)
	##get the total user input. This function could also return from screen joystick
	var user_input = get_input() 

	##assign user input to the velocity variable. which is BUILT-IN
	velocity.x = user_input.x * model.get_speed()
	velocity.z = user_input.z * model.get_speed()

	if velocity.x != 0 and velocity.z != 0:
		moving = true
	else:
		moving = false
	
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
		rotate_y(-event.relative.x * mouse_sensitivity)
		$Camera3D.rotate_z(event.relative.y * mouse_sensitivity)
	if Input.is_action_just_pressed("dev_hud"):
		show_dev_hud = !show_dev_hud


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
		input_direction += -global_transform.basis.x
#		rotate_wheel["forward"] = rotate_speed
		use_fuel = true
	if Input.is_action_pressed("move_back"):
		input_direction += global_transform.basis.x
#		rotate_wheel["backward"] = -rotate_speed
		use_fuel = true

	##if movement happened then increment fuel counter
	if use_fuel:
		model.increment_mower_fuel_idle_counter(1)

#	##function to rotate all wheel according to given values
#	rotate_wheels(rotate_wheel)
	

	return input_direction 

"""
	Function to set the size of the mesh and collision shape of the mower
	This function uses the value set in the model
	
	TODO: set this to update after the value is changed in the model 
"""
func set_blade_width():
	$Cutter.mesh.size.z = model.get_blade_length() * 2.5
	$"Cutter collision".shape.extents.z = model.get_blade_length() * 2.5


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
	$hull_body.scale = scale_val
	$hull_front.scale = scale_val


func lerp(a, b, t):
	"""
		To interpolate between two values.
		This function is used to smoothly pulsate the engine
	"""
	return a + (b - a) * t

func dev_hud():
	if !show_dev_hud:
		return
	
	var string_to_print:String = ""
	string_to_print += str(round(position/model.get_multimesh_size())) + "\n"
	string_to_print += "FPS: " + str(Performance.get_monitor(Performance.TIME_FPS)) + "\n"
	string_to_print += "Rendered calls: " + str(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)) + "\n"
	string_to_print += "Memory: " + str(round(Performance.get_monitor(Performance.MEMORY_STATIC)/1000000)) + "\n"
	string_to_print += "Vertices" + str(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	$CanvasLayer/Label.text = string_to_print
