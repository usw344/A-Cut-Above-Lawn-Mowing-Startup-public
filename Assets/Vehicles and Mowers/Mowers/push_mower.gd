extends CharacterBody3D

##Variables localva
var rotate_speed:int = 20

var base_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var gravity = base_gravity
## Authored base sensitivity. The player's Settings multiplier is applied on top
## through look_sensitivity(); do not read this directly.
var mouse_sensitivity:float = 0.002

## Base sensitivity scaled by the player's Settings value.
func look_sensitivity() -> float:
	return mouse_sensitivity * GameSettings.mouse_sensitivity_scale()

# ---------------------------------------------------------------- LOOK FEEL
#
# GAMEPLAY camera tuning. Same convention as the rider mower (see
# mower_rider.gd for the full note): the number is roughly "e-foldings per
# second" of exponential approach, so higher = tighter.
#
# A walk-behind is hand-steered rather than driven, so it turns noticeably
# quicker than the rider. Pitch is near-immediate on every mower.
@export var mouse_yaw_smoothing: float = 26.0
@export var mouse_pitch_smoothing: float = 32.0
@export var min_camera_pitch_degrees: float = -75.0
@export var max_camera_pitch_degrees: float = 45.0

var target_body_yaw: float = 0.0
var target_camera_pitch: float = 0.0



##Signals
signal collided

# ------------------------------------------------------------------ MOWER TYPE
#
# THE PUSH MOWER IS MANUAL. It is a reel mower: its blades are turned by its own
# wheels, which is why its audio is silent when it is standing still and only
# rises as it is pushed (see the audio block below) and why the development
# HUD's own menu calls the OTHER walk-behind "Push Power Powered".
#
# It therefore burns NO gasoline: it does not call MowerFuel.consume(), it never
# runs out, and it never stops cutting. It shares the fuel gauge's model state
# with nothing - the gauge simply does not move while this mower is in use.
#
# The two powered mowers declare POWERED = true and carry all of that behaviour.
# There is no `fuel_empty` signal here because there is nothing to emit it for.
const POWERED := false

## THE STABLE UPGRADE ID for this machine. Matches `MVP.mowers_scene_list` and
## `model.current_mower`, so a save refers to the mower by NAME and moving the
## scene file cannot invalidate it.
const MOWER_ID := &"push"

## Uniform across the canonical mowers so nothing has to check a scene name.
func is_powered() -> bool:
	return POWERED


# The mesh instance has the functions to do movement of individual parts of the mower

# variables to simulate mower engine running
var max_scale = Vector3(1.0, 1.0, 1.0)
var min_scale = Vector3(0.98, 0.98, 0.98)
var cycle_duration:float = 0.08 # how fast it pulsates
var elapsed_time:float = 0.0
var incr:float = 0.0

var decreasing:bool = false
var moving: bool = false

var show_dev_hud:bool = true

# audio effects 
@onready var mower_audio: AudioStreamPlayer3D = $AudioStreamPlayer3D

var stopped_volume_db: float = -60.0
var moving_volume_db: float = 18.0
var volume_lerp_speed: float = 8.0

var stopped_pitch: float = 0.95
var moving_pitch: float = 1.03


func _ready():
	# The cursor is owned by AppUI, not by the mower: declaring the context here
	# means the pause menu can hold it visible without this _ready() fighting it.
	AppUI.set_mouse_context(Input.MOUSE_MODE_CAPTURED)
	target_body_yaw = rotation.y
	target_camera_pitch = $Camera3D.rotation.x
	mower_audio.play()
	mower_audio.volume_db = stopped_volume_db
	mower_audio.pitch_scale = stopped_pitch

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
	# Authored speed x purchased upgrades. The base value stays exactly what
	# the scene and the dev slider say; the upgrade is a multiplier on top, so
	# selling the upgrade back would restore the stock machine precisely.
	var drive_speed: float = model.get_speed() * 3.0 		* MowerUpgrades.speed_multiplier(MOWER_ID)
	velocity.x = user_input.x * drive_speed
	velocity.z = user_input.z * drive_speed

	if velocity.x != 0 and velocity.z != 0:
		moving = true
	else:
		moving = false


	# --- AUDIO CONTROL SECTION ---

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var max_speed: float = model.get_speed() * 3.0 \
		* MowerUpgrades.speed_multiplier(MOWER_ID)
	var speed_ratio: float = clamp(horizontal_speed / max_speed, 0.0, 1.0)

	var target_volume: float = lerp(stopped_volume_db, moving_volume_db, speed_ratio)
	var target_pitch: float = lerp(stopped_pitch, moving_pitch, speed_ratio)

	mower_audio.volume_db = lerp(mower_audio.volume_db, target_volume, volume_lerp_speed * delta)
	mower_audio.pitch_scale = lerp(mower_audio.pitch_scale, target_pitch, volume_lerp_speed * delta)

	# --- END AUDIO SECTION ---



	move_and_slide()

	## No fuel check: a reel mower cuts whenever it is pushed. See the MOWER
	## TYPE note at the top.
	handle_collision("collided")



## Exponential approach towards the values the mouse asked for. Runs from
## _physics_process so the feel does not change with frame rate.
func handle_smoothed_mouse_movement(delta: float) -> void:
	# Steering upgrades raise the approach RATE, which is what "tighter" means
	# for an exponential smooth - not a different curve, just a faster one.
	var yaw_rate: float = mouse_yaw_smoothing 		* MowerUpgrades.handling_multiplier(MOWER_ID)
	rotation.y = lerp_angle(
		rotation.y,
		target_body_yaw,
		1.0 - exp(-yaw_rate * delta)
	)
	$Camera3D.rotation.x = lerp_angle(
		$Camera3D.rotation.x,
		target_camera_pitch,
		1.0 - exp(-mouse_pitch_smoothing * delta)
	)


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
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Left/right turns the mower; smoothing is applied in _physics_process.
		target_body_yaw -= event.relative.x * look_sensitivity()

		# CONVENTIONAL: mouse up looks up. relative.y is positive downwards and
		# camera pitch is positive upwards, so this subtracts.
		var pitch_delta: float = -event.relative.y * look_sensitivity()
		if GameSettings.invert_look_y():
			pitch_delta = -pitch_delta
		target_camera_pitch = clamp(
			target_camera_pitch + pitch_delta,
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
#	var rotate_wheel = {"forward": 0, "backward": 0, "right": 0, "left": 0}

	if Input.is_action_pressed("move_forward"):
		input_direction += global_transform.basis.z
#		rotate_wheel["forward"] = rotate_speed
	if Input.is_action_pressed("move_back"):
		input_direction += -global_transform.basis.z
#		rotate_wheel["backward"] = -rotate_speed

	## Nothing to burn - this mower is pushed, not driven.

#	##function to rotate all wheel according to given values
#	rotate_wheels(rotate_wheel)
	

	return input_direction 
func dev_hud():
	var string_to_print:String = ""
	string_to_print += str(round(position/16)) + "\
"
	string_to_print += "FPS: " + str(Performance.get_monitor(Performance.TIME_FPS)) + "\
"
	string_to_print += "Rendered calls: " + str(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)) + "\
"
	string_to_print += "Memory: " + str(round(Performance.get_monitor(Performance.MEMORY_STATIC)/1000000)) + "\
"
	string_to_print += "Vertices" + str(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	$CanvasLayer/Label.text = string_to_print
