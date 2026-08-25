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
# GAMEPLAY camera tuning. Everything that decides how the mower feels to steer
# is in these four values.
#
# Smoothing is an exponential approach: the number is roughly "e-foldings per
# second", so higher means tighter and more responsive.
#
#     ~6 - 9    cinematic drift     <- what this used to be, and why it floated
#     ~16 - 20  responsive vehicle steering
#     ~30+      effectively raw
#
# The mower is a physical vehicle, so the body keeps moderate smoothing. The
# camera pitch is not attached to anything physical, so it is much more
# immediate. They are deliberately NOT the same number.
#
# The trailer's cinematic camera is a separate rig. Do not slow these down to
# make video look nicer.

## Body yaw (steering). Moderate smoothing - the mower has mass.
@export var mouse_yaw_smoothing: float = 18.0
## Camera pitch. Near-immediate; only enough smoothing to take the jitter off.
@export var mouse_pitch_smoothing: float = 32.0
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

# ------------------------------------------------------------------ MOWER TYPE
#
# THIS mower burns gasoline. That single fact is what makes every fuel rule
# below apply to it; the Push Mower declares POWERED = false and has none of
# them. The rates themselves live in one place - `MowerFuel` - and are never
# reimplemented here.
const POWERED := true

## THE STABLE UPGRADE ID for this machine. Matches `MVP.mowers_scene_list` and
## `model.current_mower`, so a save refers to the mower by NAME and moving the
## scene file cannot invalidate it.
const MOWER_ID := &"rider"

## ------------------------------------------------------------- CUTTING DECK
##
## The footprint this machine cuts, in WORLD units, resolved by `ACAMowerDeck`
## and swept across the lawn by `ACAMowerCutter`. It is a GAMEPLAY value and is
## deliberately NOT derived from the model or the collision box: re-scaling the
## mower to look better must never change how long a contract takes or whether
## a tank of fuel is enough to finish one.
##
## The rider has the widest deck of the three, which is the reason to own it.
const DECK_WIDTH := 5.6
const DECK_LENGTH := 2.4
## Along the machine's local +Z, which is forward.
const DECK_FORWARD := 0.4

## Uniform across the canonical mowers so nothing has to check a scene name.
func is_powered() -> bool:
	return POWERED

## 0.0 idling, 1.0 driving. Set by get_input() each physics frame and read by
## the fuel burn, so throttle is decided in exactly one place.
var _throttle: float = 0.0

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

## Where the engine loop fades to when the tank runs dry, before the player is
## stopped. Low enough to be silence, high enough that the fade is audible as
## the engine dying rather than an abrupt cut.
var engine_off_volume_db: float = -60.0

var last_speed: float = 0.0
#end of sound variables


func _ready():
	# The cursor is owned by AppUI, not by the mower: declaring the context here
	# means the pause menu can hold it visible without this _ready() fighting it.
	AppUI.set_mouse_context(Input.MOUSE_MODE_CAPTURED)
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
	## Returns ZERO while the tank is empty - a dead engine does not drive.
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

	# ------------------------------------------------------------------- FUEL
	#
	# TIME based, through the one owner. `_throttle` was decided by get_input()
	# a few lines up. Burning BEFORE the audio section means the engine reacts
	# on the same frame the tank runs dry.
	# Fuel-system upgrades multiply the BURN, below 1.0 being an
	# improvement. The rates themselves still live only in MowerFuel.
	MowerFuel.consume(delta * MowerUpgrades.fuel_multiplier(MOWER_ID), _throttle)
	var engine_running: bool = MowerFuel.has_fuel()

	# --- AUDIO CONTROL SECTION ---

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()

	# --- acceleration detection ---
	var accel = horizontal_speed - last_speed
	last_speed = horizontal_speed

	# convert speed to 0-1 range
	var max_speed: float = model.get_speed() * 3.0 \
		* MowerUpgrades.speed_multiplier(MOWER_ID)
	var speed_ratio: float = clamp(horizontal_speed / max_speed, 0.0, 1.0)

	# A refuel restarts the loop; running dry fades it out and stops it.
	if engine_running and not mower_audio.playing:
		mower_audio.volume_db = engine_off_volume_db
		mower_audio.play()

	# target values
	var target_volume: float = engine_off_volume_db
	# Dropping the pitch as it fades reads as the engine dying rather than as
	# somebody turning the volume down.
	var target_pitch: float = idle_pitch * 0.8

	if engine_running:
		target_volume = lerp(idle_volume_db, moving_volume_db, speed_ratio)
		target_pitch = lerp(idle_pitch, moving_pitch, speed_ratio)

		# extra rev when accelerating
		if accel > 0.1:
			target_pitch += 0.02

	# smooth changes
	mower_audio.volume_db = lerp(mower_audio.volume_db, target_volume, volume_lerp_speed * delta)
	mower_audio.pitch_scale = lerp(mower_audio.pitch_scale, target_pitch, volume_lerp_speed * delta)

	if not engine_running and mower_audio.playing \
			and mower_audio.volume_db <= engine_off_volume_db + 1.0:
		mower_audio.stop()

	# --- END AUDIO SECTION ---


	mower_mesh_parts.send_speed_data(velocity,delta)
	move_and_slide()

	## THE blade contract. `collided` is what the mowing grid cuts from, so an
	## empty tank stops the blades for the same reason it stops the wheels -
	## one fuel state, not a separate visual fudge.
	if engine_running:
		handle_collision("collided")
	else:
		handle_collision("fuel_empty")


func handle_smoothed_mouse_movement(delta):
	var old_yaw: float = rotation.y

	# Steering upgrades raise the approach RATE, which is what "tighter" means
	# for an exponential smooth - not a different curve, just a faster one.
	var yaw_rate: float = mouse_yaw_smoothing 		* MowerUpgrades.handling_multiplier(MOWER_ID)
	rotation.y = lerp_angle(
		rotation.y,
		target_body_yaw,
		1.0 - exp(-yaw_rate * delta)
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
		# Left/right mower turning is smoothed in _physics_process.
		target_body_yaw -= event.relative.x * look_sensitivity()

		# In P mode, disable up/down camera movement.
		if not p_mode:
			# CONVENTIONAL: mouse up looks up. relative.y is positive downwards,
			# and camera pitch is positive upwards, so this subtracts.
			var pitch_delta: float = -event.relative.y * look_sensitivity()
			if GameSettings.invert_look_y():
				pitch_delta = -pitch_delta
			target_camera_pitch += pitch_delta
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

	var throttle_pressed := false
	if Input.is_action_pressed("move_forward"):
		input_direction += global_transform.basis.z
		throttle_pressed = true
	if Input.is_action_pressed("move_back"):
		input_direction += -global_transform.basis.z
		throttle_pressed = true

	## A powered mower with an empty tank has no propulsion. The throttle is
	## still recorded as zero rather than as "asked for", because a dead engine
	## is not revving.
	if not MowerFuel.has_fuel():
		_throttle = 0.0
		return Vector3.ZERO

	_throttle = 1.0 if throttle_pressed else 0.0

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
	string_to_print += "Vertices" + str(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) + "\
"
	string_to_print += "P Mode: " + str(p_mode)

	$CanvasLayer/Label.text = string_to_print
