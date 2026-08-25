class_name ACAMenuPropertyScenery
extends Node3D
## THE MAIN MENU'S 3D BACKGROUND: a real generated property, seen from the
## corner of the yard on a fine morning, with the machine parked on it.
##
## ---------------------------------------------------------------------------
## WHY IT IS THE REAL PROPERTY AND NOT A DIORAMA
## ---------------------------------------------------------------------------
## The menu this replaces was hand-built: its own trees, its own grass, its own
## ground plane, its own painted mountains. It was made before the mowing world
## existed and it had been left behind by it - different tree species, different
## turf, a dirt path the game does not have, and a warm palette the game does
## not use. A player arriving at the menu and then at a contract was looking at
## two different games.
##
## So the background is now `ACAProperty`: the same terrain, the same lawn, the
## same grass shader, the same wood, the same fence, the same pond and the same
## Sky3D integration the player is about to drive around in. It is built from
## one seed, it is MOWN before the first frame, and the canonical Rider is
## parked on it.
##
## Nothing about it is a special case. If the grass changes, the menu changes.
##
## ---------------------------------------------------------------------------
## SUBORDINATE TO THE MENU
## ---------------------------------------------------------------------------
## It is a background. The camera drifts slowly and does not cut; there is a
## scrim between the world and the controls so the radial menu stays legible on
## a bright morning; nothing moves fast enough to pull the eye off a button; and
## there is no audio of any kind.
##
## PUBLIC API
##   property() -> ACAProperty
##   statistics() -> Dictionary
##
## SIGNALS: None.
##
## PERSISTENCE OWNERSHIP: None. The menu owns no game state.

## The address the menu is set at. Chosen by looking at renders rather than by
## reasoning: this seed puts the pond off to the right of frame, keeps the
## treeline unbroken behind it and leaves the near corner open for the machine.
@export var property_seed: int = 20260824
## Medium. Large is more property than fits the shot and takes longer to build
## than a menu should; Small does not have room for the pond to read.
@export var lawn_size: int = 144

## Where the camera sits and looks, RELATIVE TO THE LAWN CENTRE and in world
## units, so the framing survives a change of lawn size.
@export var camera_offset := Vector3(-8.0, 3.0, 69.0)
@export var camera_target_offset := Vector3(34.0, 0.6, 4.0)
@export_range(30.0, 90.0, 0.5) var camera_fov := 56.0

## Where the machine is parked, relative to the lawn centre. It sits in the
## RIGHT third of the frame because the radial menu occupies the left of centre,
## and close enough to the camera to read as the subject rather than as a speck
## on a field. Both of these were set by looking at renders.
@export var mower_offset := Vector3(18.0, 0.0, 52.0)
@export_range(0.0, 6.3, 0.01) var mower_yaw := 2.45

@export_group("Ambient camera motion")
@export var camera_drift_enabled := true
@export_range(0.0, 0.25, 0.005) var camera_drift_speed := 0.028
@export var camera_position_drift := Vector3(1.1, 0.25, 0.8)
@export var camera_target_drift := Vector3(0.9, 0.2, 0.7)

@export_group("World")
## Morning. Low enough for long shadows across the stripes, high enough that the
## menu text is not sitting on a sunset.
@export_range(0.0, 24.0, 0.25) var hour_of_day: float = 9.25
@export var weather: String = "Clear"

const MOWER_SCENE := "res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn"
const PRESET_MANAGER := "res://Weather/Preset Manager/Preset Manager.tscn"

## How much of the lawn is cut before the first frame. A lawn-care business's
## own yard is kept; a couple of per cent left over is what stops the turf from
## reading as a single flat colour.
const STAGED_CUT := 0.97

var _property: ACAProperty = null
var _mower: Node3D = null
var _camera: Camera3D = null
var _preset_manager: Node3D = null
var _ambient: ACAAmbientLife = null
var _drift_time := 0.0
var _stats := {}


func _ready() -> void:
	_build_property()
	_build_environment()
	_build_camera()
	_build_mower()
	_build_ambient()
	set_process(true)


func property() -> ACAProperty:
	return _property


func statistics() -> Dictionary:
	return _stats.duplicate(true)


# ======================================================================= build

func _build_property() -> void:
	var params := ACAPropertyParams.for_seed(property_seed, lawn_size)
	# A KEPT PROPERTY. The generator draws an overgrown contract by default,
	# which is right for a job and wrong for the yard of the business selling
	# the service, so the two fields that read as "nobody has been here" are
	# pulled back. Everything else is exactly what the seed produced.
	params.dryness = minf(params.dryness, 0.16)
	params.meadow_density = minf(params.meadow_density, 1.0)

	_property = ACAProperty.new()
	_property.name = "Property"
	add_child(_property)
	var t0 := Time.get_ticks_usec()
	_property.build(params)
	_mow_the_yard()
	_stats = {
		"build_ms": float(Time.get_ticks_usec() - t0) / 1000.0,
		"seed": property_seed,
		"lawn_size": lawn_size,
		"mown": _property.lawn().mowed_fraction(),
	}


## Cut it before the first frame, in overlapping passes, so the menu opens on a
## finished lawn with real mowing stripes on it rather than on a job nobody has
## started. The passes are the same `mow_deck` sweep the machine performs, at
## the rider's real deck size, which is why the stripes are the stripes.
func _mow_the_yard() -> void:
	var lawn := _property.lawn()
	var deck := ACAMowerDeck.make(5.6, 2.4)
	var centre := lawn.lawn_centre()
	var half := lawn.lawn_half_extent()
	var pitch: float = deck.half_width * 2.0 * 0.86
	var basis := Basis(Vector3.UP, PI * 0.5)
	var lanes: int = int(ceil((half * 2.0) / pitch)) + 1
	# The last few lanes are left standing, which is what `STAGED_CUT` buys: a
	# strip of long grass at the far edge for the mown ground to read against.
	var cut_lanes: int = int(round(float(lanes) * STAGED_CUT))
	var stride: float = deck.half_length * 2.0 * 0.8
	for i in cut_lanes:
		var z: float = centre.z - half + pitch * (float(i) + 0.5)
		var x: float = centre.x - half - 3.0
		var finish: float = centre.x + half + 3.0
		var previous := Transform3D(basis, Vector3(x, 0.0, z))
		while x < finish:
			x = minf(x + stride, finish)
			var current := Transform3D(basis, Vector3(x, 0.0, z))
			lawn.mow_deck(previous, current, deck)
			previous = current


## THE PRODUCTION SKY. `Weather/Preset Manager` is the project's own Sky3D
## integration, and the menu uses it rather than a copy so the sky over the menu
## and the sky over a contract are the same sky. `follow_world_clock` is off:
## a menu should not drift into the night while somebody reads the credits.
func _build_environment() -> void:
	var packed := load(PRESET_MANAGER) as PackedScene
	if packed == null:
		push_warning("[MENU] no preset manager at %s" % PRESET_MANAGER)
		return
	_preset_manager = packed.instantiate() as Node3D
	_preset_manager.name = "PresetManager (Sky3D)"
	_preset_manager.set(&"follow_world_clock", false)
	add_child(_preset_manager)
	_preset_manager.call(&"apply_world_state_immediate", weather,
		clampf(hour_of_day, 0.0, 24.0))
	var centre := _property.lawn().lawn_centre()
	_preset_manager.call(&"set_weather_ground_reference",
		_property.ground_height_at(centre.x, centre.z))


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = camera_fov
	_camera.far = 6000.0
	_camera.current = true
	# A little depth of field, so the treeline sits behind the menu instead of
	# competing with it for attention.
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = 70.0
	attributes.dof_blur_far_transition = 40.0
	attributes.dof_blur_amount = 0.04
	_camera.attributes = attributes
	add_child(_camera)
	_aim_camera(Vector3.ZERO, Vector3.ZERO)
	if _preset_manager != null:
		_preset_manager.call(&"set_weather_tracking_target", _camera)


func _build_mower() -> void:
	var packed := load(MOWER_SCENE) as PackedScene
	if packed == null:
		return
	_mower = packed.instantiate() as Node3D
	# The machine is SCENERY here. Its controller would take the mouse, drive
	# it, burn fuel and fight the menu for input, so it is stripped to a model.
	_disable_behaviour(_mower)
	add_child(_mower)

	var centre := _property.lawn().lawn_centre()
	# Parked near the front edge of the lawn, turned away from the camera: a
	# machine that has finished, rather than one posed for a photograph.
	var at := centre + mower_offset
	at.y = _property.ground_height_at(at.x, at.z) + 0.10
	var mower_scale := _mower.transform.basis.get_scale()
	_mower.global_transform = Transform3D(
		Basis(Vector3.UP, mower_yaw).scaled(mower_scale), at)


## Everything on the machine that would try to play the game. The model, its
## meshes and its materials are kept; the script, the physics and the camera go.
func _disable_behaviour(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).current = false
	if node is CollisionObject3D:
		(node as CollisionObject3D).process_mode = Node.PROCESS_MODE_DISABLED
	if node.get_script() != null and node != _mower:
		node.set_script(null)
	for child in node.get_children():
		_disable_behaviour(child)


func _build_ambient() -> void:
	_ambient = ACAAmbientLife.new()
	_ambient.name = "Ambient Life"
	add_child(_ambient)
	_ambient.follow(_camera)
	_ambient.set_density(_ambient_density())


func _ambient_density() -> float:
	var settings := get_node_or_null(^"/root/GameSettings")
	if settings == null or not settings.has_method(&"graphics_quality"):
		return 1.0
	match String(settings.call(&"graphics_quality")):
		"low":
			return 0.0
		"medium":
			return 0.6
		_:
			return 1.0


# ====================================================================== motion

func _process(delta: float) -> void:
	if not camera_drift_enabled or _camera == null:
		return
	_drift_time += delta * camera_drift_speed
	# Three incommensurate rates, so the drift never repeats a position while
	# anybody is looking at it, and never moves fast enough to be a shot.
	var wobble := Vector3(
		sin(_drift_time * 1.00),
		sin(_drift_time * 0.61 + 1.3),
		sin(_drift_time * 0.83 + 2.7))
	_aim_camera(wobble * camera_position_drift, wobble * camera_target_drift)


func _aim_camera(position_drift: Vector3, target_drift: Vector3) -> void:
	if _camera == null or _property == null or _property.lawn() == null:
		return
	var centre := _property.lawn().lawn_centre()
	var ground := _property.ground_height_at(centre.x, centre.z)
	var base := Vector3(centre.x, ground, centre.z)
	_camera.global_position = base + camera_offset + position_drift
	_camera.look_at(base + camera_target_offset + target_drift, Vector3.UP)
