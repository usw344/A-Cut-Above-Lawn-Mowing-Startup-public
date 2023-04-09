extends CharacterBody3D

##Variables stored in model. THESE are defaults



##Variables localva
var rotate_speed = 20
var model
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var mouse_sensitivity = 0.002 

##Signals
signal collided
signal fuel_empty


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):

#	if "rotate_speed" in get_node("."):
#		print("has it")
#	else:
#		print("does not have it")
		
#	##if not on floor start moving downwards
	velocity.y -= gravity * delta
	
	##get the total user input. This function could also return from screen joystick
	var user_input = get_input() 

	##assign user input to the velocity variable. which is BUILT-IN
	velocity.x = user_input.x * model.get_speed()
	velocity.z = user_input.z * model.get_speed()

	
	move_and_slide()
	##calculate how much fuel has been used
	if not model.is_mower_fuel_idle_counter(): 		  ##value is still less than counter
		model.increment_mower_fuel_idle_counter(0.05) ##this is general fuel used due to idling
	else:
		model.set_mower_fuel(model.get_mower_fuel() - 1) ##substract one value of fuel due to counter being reached
		model.set_mower_fuel_idle_counter(0)			 ##reset the counter to zero
	
	##collision signal is based if fuel is full or not
	if model.get_mower_fuel() <= 0:
		handle_collision("fuel_empty")
	else:
		handle_collision("collided")
"""
	Function to handle collision and send correct signal
	This code used to be in the _physics_process function but due to 
	checking for empty fuel then there are 2 two signals
"""
func handle_collision(signal_name):
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		emit_signal(signal_name, collision) ## send collision since if it is with block then a notification can be sent

"""
	Rotates the mower around based on the mouse. T
	TODO: change this to handle mobile input as well
"""
func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
#		$Camera3D.rotate_x(-event.relative.y * mouse_sensitivity)


"""
	Encapsulation function to handle getting user input.
	
	TODO: add virtual movement stick as well

	return input_direction: Vector3 containg x, y, z movement input
"""
func get_input():
	var input_direction = Vector3()
	var rotate_wheel = {"forward": 0, "backward": 0, "right": 0, "left": 0}
	rotate_speed = model.get_speed() *4 ##update in case the speed changed from model
	
	var use_fuel = false
	if Input.is_action_pressed("move_forward"):
		input_direction += global_transform.basis.x
		rotate_wheel["forward"] = rotate_speed
		use_fuel = true
	if Input.is_action_pressed("move_back"):
		input_direction += -global_transform.basis.x
		rotate_wheel["backward"] = -rotate_speed
		use_fuel = true
	if Input.is_action_pressed("move_left"):
		input_direction += -global_transform.basis.z
		rotate_wheel["left"] = rotate_speed
		use_fuel = true
	if Input.is_action_pressed("move_right"):
		input_direction += global_transform.basis.z
		rotate_wheel["right"] = -rotate_speed
		use_fuel = true
	
	##if movement happened then increment fuel counter
	if use_fuel:
		model.increment_mower_fuel_idle_counter(1)

	##function to rotate all wheel according to given values
	rotate_wheels(rotate_wheel)
	

	return input_direction 

"""
	Function to rotate each wheel by the angle give. 
	Use -> this function is used in the get_input() method. The angles are set by the movement input
	side effects -> the wheels are rotated. if the node's name is changed this will break
"""
func rotate_wheels(angles):
	##construct list of wheels
	var wheels = [$Wheel_1_F_L, $Wheel_1_F_R,$Wheel_1_B_L,$Wheel_1_B_R]

	for wheel in wheels:
		wheel.rotate_x(angles["forward"])
		wheel.rotate_x(angles["backward"])
		wheel.rotate_z(angles["right"])
		wheel.rotate_z(angles["left"])
	
"""
	Function to set the size of the mesh and collision shape of the mower
	This function uses the value set in the model
	
	TODO: set this to update after the value is changed in the model 
"""
func set_blade_width():
	$Cutter.mesh.size.z = model.get_blade_length() * 2.5
	$"Cutter collision".shape.extents.z = model.get_blade_length() * 2.5


func set_model(m):
	model = m
	set_blade_width()
	
	
