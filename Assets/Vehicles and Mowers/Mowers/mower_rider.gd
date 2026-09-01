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
## Levels, pitches and response rates are `ACAMowerAudio.PROFILES` now -
## one table for all three machines instead of three copies of the same
## six numbers. Nothing about the mix lives in a controller.


## Where the engine loop fades to when the tank runs dry, before the player is
## stopped. Low enough to be silence, high enough that the fade is audible as
## the engine dying rather than an abrupt cut.

var last_speed: float = 0.0
#end of sound variables


func _ready():
	# The cursor is owned by AppUI, not by the mower: declaring the context here
	# means the pause menu can hold it visible without this _ready() fighting it.
	AppUI.set_mouse_context(Input.MOUSE_MODE_CAPTURED)
	# THE MACHINE'S OWN ENGINE. Falls back to whatever the scene authored if the
	# recording cannot be loaded, which is the old sound rather than silence.
	var engine := ACAMowerAudio.engine_stream(MOWER_ID)
	if engine != null:
		mower_audio.stream = engine
	mower_audio.play()
	mower_audio.volume_db = ACAMowerAudio.ENGINE_OFF_DB

	target_body_yaw = rotation.y
	target_camera_pitch = $Camera3D.rotation.x
	# The rest pose the lean is composed onto, and the pitch it offsets.
	_mesh_rest = _visual.transform
	_camera_pitch = _camera.rotation.x
	# ...and the framing the precision view dollies in from.
	_camera_rest_position = _camera.position
	_camera_rest_fov = _camera.fov


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
	# PERSONALITY. `model.get_speed()` is still the ONE shared base speed and the
	# development slider still moves it; this machine's profile and the purchased
	# upgrade are multipliers on top of it. See `ACAMowerHandling`.
	var prof := ACAMowerHandling.profile(MOWER_ID)

	# What the player is ASKING for, as a signed speed along the machine's own
	# forward axis. A mower is geared for forward work, so reverse is a fraction
	# of top speed on every machine and a small fraction of it on the rider.
	var forward_request: float = user_input.dot(global_transform.basis.z)
	var wanted_speed: float = 0.0
	if forward_request > 0.01:
		wanted_speed = _top_speed()
	elif forward_request < -0.01:
		wanted_speed = -_top_speed() * float(prof["reverse"])

	# MOMENTUM. The speed is APPROACHED, never assigned. Before this pass all
	# three machines reached full speed and stopped dead in about three
	# milliseconds, which is most of the reason they felt like the same machine.
	_ground_speed = ACAMowerHandling.approach_speed(
		_ground_speed, wanted_speed, prof, delta)

	# Kept ALONG THE HEADING rather than integrated in world space: wheels do
	# not slide sideways, so the machine's velocity turns exactly with its body
	# and its turn radius is exactly speed divided by yaw rate.
	#
	# NORMALISED. `basis.z` is not a unit vector - the mowing scene scales the
	# machines - and the original drive multiplied by it raw, which is why the
	# authored speed and the speed that reached the ground were never the same
	# number. That factor is now applied once, and deliberately, in
	# `_top_speed()`; here the heading is only a direction.
	var forward := global_transform.basis.z / _body_scale()
	velocity.x = forward.x * _ground_speed
	velocity.z = forward.z * _ground_speed

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
	#
	# THE MACHINE'S OWN ENGINE, AND HOW HARD IT IS WORKING.
	#
	# The numbers live in `ACAMowerAudio`, one table for all three machines, so
	# a change to how the fleet sounds is a change to one file rather than to
	# three near-identical blocks. Two continuous inputs and no state machine:
	# SPEED raises the note, LOAD lowers it and thickens it. See that file.
	#
	# `_cut_load` is written by `ACAMowerCutAudio` from the cutter's own signal,
	# so the engine bogs exactly when the blades are in standing grass. With no
	# such node bound it stays zero and this is the old speed-only behaviour.

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var accel: float = horizontal_speed - last_speed
	last_speed = horizontal_speed

	# AGAINST THE MACHINE'S REAL TOP SPEED, which is what `_top_speed()` is.
	# This used to divide by `model.get_speed() * 3.0` - the SHARED base,
	# before the body scale the mowing scene applies and before the machine's
	# own `top_speed` multiplier. On the push mower that made a flat-out run
	# read as 0.34 of full throttle, so it never reached its own level or its
	# own pitch: measured at -32.8 dB against an authored -1.
	var speed_ratio: float = clampf(
		horizontal_speed / maxf(_top_speed(), 0.001), 0.0, 1.0)

	var audio_profile := ACAMowerAudio.profile(MOWER_ID)

	# A refuel restarts the loop; running dry fades it out and stops it.
	if engine_running and not mower_audio.playing:
		mower_audio.volume_db = ACAMowerAudio.ENGINE_OFF_DB
		mower_audio.play()

	var target_volume: float = ACAMowerAudio.target_volume_db(
		audio_profile, speed_ratio, _cut_load, engine_running)
	var target_pitch: float = ACAMowerAudio.target_pitch(
		audio_profile, speed_ratio, _cut_load, accel > 0.1)
	if not engine_running:
		# Dropping the pitch as it fades reads as the engine dying rather than
		# as somebody turning the volume down.
		target_pitch = float(audio_profile["idle_pitch"]) * 0.8

	var response: float = float(audio_profile["response"]) * delta
	mower_audio.volume_db = lerpf(mower_audio.volume_db, target_volume, response)
	mower_audio.pitch_scale = lerpf(mower_audio.pitch_scale, target_pitch, response)

	if not engine_running and mower_audio.playing and \
			mower_audio.volume_db <= ACAMowerAudio.ENGINE_OFF_DB + 1.0:
		mower_audio.stop()

	# --- END AUDIO SECTION ---


	mower_mesh_parts.send_speed_data(velocity,delta)
	_apply_body_lean(delta)
	_apply_precision_view(delta)
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
	# STEERING. Two things shape the turn now, and they do different jobs.
	#
	# `mouse_yaw_smoothing` is still the SHAPE - an exponential approach, so the
	# machine settles onto a heading rather than snapping to it.
	#
	# The machine's own `turn_rate` is a HARD CAP on how fast the body may come
	# round, and that is what actually gives it a turning circle: radius is speed
	# divided by yaw rate. Measured before this pass, every machine could pivot
	# inside about one world unit at full speed while being five units wide.
	var prof := ACAMowerHandling.profile(MOWER_ID)
	target_body_yaw = ACAMowerHandling.clamp_lead(
		target_body_yaw, rotation.y, float(prof["lead"]))

	var speed_ratio: float = clampf(
		absf(_ground_speed) / maxf(_top_speed(), 0.001), 0.0, 1.0)
	var cap: float = ACAMowerHandling.turn_rate(prof, speed_ratio,
		MowerUpgrades.handling_multiplier(MOWER_ID)) * delta

	var wanted: float = lerp_angle(
		rotation.y,
		target_body_yaw,
		1.0 - exp(-mouse_yaw_smoothing * delta)
	)
	_yaw_rate = clampf(wrapf(wanted - rotation.y, -PI, PI), -cap, cap) \
		/ maxf(delta, 0.0001)
	rotation.y += _yaw_rate * delta

	var applied_rot_y: float = shortest_angle_difference(old_yaw, rotation.y)

	if abs(applied_rot_y) > 0.00001:
		mower_mesh_parts.send_rotation_data(applied_rot_y)

	_camera_pitch = lerp_angle(
		_camera_pitch,
		target_camera_pitch,
		1.0 - exp(-mouse_pitch_smoothing * delta)
	)
	_camera.rotation.x = _camera_pitch


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
		if event.is_action_pressed(&"precision_view"):
			toggle_precision_view()

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


# ------------------------------------------------------------- BODY FEEL STATE
#
# PRESENTATION ONLY. Every one of these moves a MESH or the CAMERA. None of them
# touches the collider - see `_apply_body_lean()` for why that line matters.

## How much of the chassis attitude the camera takes.
##
## THE CAMERA DOES NOT ROLL. It used to take 35% of the chassis roll, and a
## horizon that tips every time the machine is steered is the single thing most
## responsible for how unpleasant this was to drive. The horizon is now level:
## the MOWER moves with the ground, the view does not tip with it.
##
## Pitch keeps a small share, because a machine cresting a rise while the view
## stays perfectly rigid reads as a camera detached from the machine. 0.15 of a
## signal that is itself far smaller than it was.
const CAMERA_ROLL_SHARE := 0.0
const CAMERA_PITCH_SHARE := 0.15

@onready var _visual: Node3D = $LawnTractor01
@onready var _camera: Camera3D = $Camera3D

## The mesh transform the SCENE authored. The lean is composed onto this rather
## than replacing it, so the machine keeps whatever offset and orientation it
## was built with.
var _mesh_rest := Transform3D.IDENTITY

## The smoothed camera pitch, held here rather than read back off the node,
## because the lean adds an offset to the camera and reading that back would
## feed it into the next frame's smoothing.
var _camera_pitch: float = 0.0

## `[value, velocity]` for the two lean springs. Reused in place every frame and
## never reallocated - this runs at 576 Hz.
var _roll_state: Array = [0.0, 0.0]
var _pitch_state: Array = [0.0, 0.0]

## The eased ground angle, `(pitch, roll)` in radians. Held so the reading is
## smoothed BEFORE the spring sees it - see `_apply_body_lean()`.
var _ground_tilt := Vector2.ZERO

## Yaw actually applied last frame, rad/s. The roll is driven from this rather
## than from the input, so the body leans by what the machine DID.
var _yaw_rate: float = 0.0
var _last_forward_speed: float = 0.0

## Signed speed along the machine's forward axis, in WORLD u/s. THE state the
## momentum model integrates; `velocity` is derived from it every frame.
var _ground_speed: float = 0.0


## How much the mowing scene has scaled this machine. The drive has always
## multiplied its speed by the unnormalised `basis.z`, so this factor has always
## been in the game's real top speed; it is applied here on purpose instead of
## by accident, which is what lets everything else work in world units.
func _body_scale() -> float:
	return maxf(global_transform.basis.z.length(), 0.001)


## Top speed for this machine right now, in WORLD u/s: the one shared base, the
## body scale, this machine's own profile and the purchased Engine & Drive
## upgrade. `_ground_speed` is in these units, and so is everything in
## `ACAMowerHandling` that is compared against it.
func _top_speed() -> float:
	return model.get_speed() * 3.0 * _body_scale() \
		* MowerUpgrades.speed_multiplier(MOWER_ID) \
		* float(ACAMowerHandling.profile(MOWER_ID)["top_speed"])


## PRESENTATION ONLY, and never the collider: these machines are CharacterBody3D
## and tilting the body that `move_and_slide()` resolves against is how a mower
## ends up climbing its own fence.
##
## TWO SOURCES, AND WHICH OF THEM IS THE MAIN ONE MATTERS.
##
## THE GROUND. `get_floor_normal()` is the surface `move_and_slide()` actually
## resolved against this frame, so a machine crossing a broad rise sits on the
## rise. That is REAL movement: it is the world being uneven, not a number
## derived from what the player did with the mouse, and it is where the vertical
## movement in this game is meant to come from.
##
## STEERING, much reduced. Yaw rate scaled by speed still shifts the body, at
## about a sixth of what it used to - a weight transfer visible at the edge of
## the mesh rather than a machine banking into a corner. Acceleration still
## squats and braking still noses down, also much reduced.
##
## Both go through ONE OVERDAMPED spring, so the body settles onto an attitude
## and STOPS there. The old spring overshot every input; on ground that keeps
## changing, that is a machine which never stops rocking.
func _apply_body_lean(delta: float) -> void:
	if _visual == null:
		return
	var prof := ACAMowerHandling.profile(MOWER_ID)
	var forward_speed: float = _ground_speed
	var speed_ratio: float = clampf(absf(forward_speed) / maxf(_top_speed(), 0.001),
		0.0, 1.0)

	var lean: float = clampf(
		_yaw_rate / maxf(float(prof["turn_rate"]), 0.001), -1.0, 1.0) * speed_ratio
	var roll_target: float = deg_to_rad(float(prof["roll"])) * lean

	var accel: float = (forward_speed - _last_forward_speed) / maxf(delta, 0.0001)
	_last_forward_speed = forward_speed
	var pitch_target: float = deg_to_rad(float(prof["pitch"])) \
		* -clampf(accel / float(prof["brake"]), -1.0, 1.0)

	# THE GROUND, added on top. Eased towards rather than taken raw: the floor
	# normal steps as the body resolves against a different triangle, and that
	# step is a twitch the spring alone would happily pass straight through.
	var ground := ACAMowerHandling.ground_tilt(
		get_floor_normal() if is_on_floor() else Vector3.ZERO,
		global_transform.basis)
	var settle: float = clampf(ACAMowerHandling.GROUND_SETTLE_RATE * delta, 0.0, 1.0)
	_ground_tilt = _ground_tilt.lerp(ground, settle)
	pitch_target += _ground_tilt.x
	roll_target += _ground_tilt.y

	var roll: float = ACAMowerHandling.settle(_roll_state, roll_target, delta)
	var pitch: float = ACAMowerHandling.settle(_pitch_state, pitch_target, delta)

	_visual.transform = Transform3D(
		Basis.from_euler(Vector3(pitch, 0.0, roll)) * _mesh_rest.basis,
		_mesh_rest.origin)

	if _camera != null:
		_camera.rotation.x = _camera_pitch + pitch * CAMERA_PITCH_SHARE
		# DELIBERATELY NOT `roll`. The horizon stays level - see
		# CAMERA_ROLL_SHARE above. `roll` moves the MESH and nothing else.
		_camera.rotation.z = 0.0


# ============================================================= PRECISION VIEW
#
# A CLOSER WORKING VIEW, on C. The default camera is the one to drive a lawn
# from; this is the one to finish an edge from. It dollies in towards the
# machine and narrows the field of view, which together bring the cutting edge
# of the deck into clear sight against a fence, a pond bank or a rock.
#
# It moves the camera and NOTHING else. Steering, pitch, sensitivity, invert Y,
# P mode, the pause stack and AppUI's cursor authority all behave exactly as
# they do in the normal view - which is the whole reason this is a few numbers
# on the existing camera rather than a second camera rig.

## The rest camera offset, scaled per axis. One rule for all three machines,
## because it is a move along the line the scene already framed each of them
## from - every machine keeps its own authored composition and simply gets
## closer to its own deck.
##
## CHOSEN FROM RENDERS, not from arithmetic (`Dev tools/Validation/Precision
## Sweep.tscn`, eight candidates on two machines). The Z is what does the work:
## it brings the camera from behind the seat to just above the nose, so the
## ground the deck is about to reach fills the frame. Y is barely touched on
## purpose - the first attempt scaled all three axes together, dropped the
## camera behind the seat back and filled the screen with upholstery. Pulling
## the camera far enough forward to lose the machine entirely was tried too, and
## it is worse: with no part of the machine in frame there is nothing to judge
## the deck's position against.
const PRECISION_DOLLY := Vector3(0.85, 0.96, 0.35)
## Narrower than the 59.9 the machines are framed at. Enough to pick an edge out
## against the grass, not so much that it reads as a scope.
const PRECISION_FOV := 47.0
## e-foldings per second on the blend. Short and smooth; this is a working view,
## not a cinematic move.
const PRECISION_BLEND_RATE := 14.0

## 0.0 normal, 1.0 fully in the precision view. Blended, not switched.
var _precision: float = 0.0
var _precision_wanted: float = 0.0
var _camera_rest_position := Vector3.ZERO
var _camera_rest_fov: float = 59.9


func precision_view_active() -> bool:
	return _precision_wanted > 0.5


func toggle_precision_view() -> void:
	_precision_wanted = 0.0 if _precision_wanted > 0.5 else 1.0


## Position and field of view only. The camera's ROTATION is owned by the mouse
## smoothing and the body lean, and is deliberately not touched here.
func _apply_precision_view(delta: float) -> void:
	if _camera == null:
		return
	_precision = lerpf(_precision, _precision_wanted,
		1.0 - exp(-PRECISION_BLEND_RATE * delta))
	_camera.position = _camera_rest_position.lerp(
		_camera_rest_position * PRECISION_DOLLY, _precision)
	_camera.fov = lerpf(_camera_rest_fov, PRECISION_FOV, _precision)


# ================================================================== cut load
##
## HOW HARD THE BLADES ARE WORKING, 0 to 1. Written by `ACAMowerCutAudio`, which
## reads it off `ACAMowerCutter.cut` - the same authoritative signal the
## clippings particles run from. Nothing here guesses at cut state, and with no
## such node bound this stays zero and the engine behaves exactly as it used to.
var _cut_load: float = 0.0


func set_cut_load(value: float) -> void:
	_cut_load = clampf(value, 0.0, 1.0)


func cut_load() -> float:
	return _cut_load
