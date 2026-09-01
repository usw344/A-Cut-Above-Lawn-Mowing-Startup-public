class_name ACAWorkTruck
extends Node3D
## ROLE
## The business's presence on the contract. A truck and a trailer parked at the
## arrival point, and the place the machine goes back to when the catcher is
## full.
##
## ---------------------------------------------------------------------------
## IT IS A PLACE, NOT A VEHICLE
## ---------------------------------------------------------------------------
## There is no driving, no ignition, no towing and no loading animation. The
## truck is scenery with ONE piece of function attached to it: an area the
## machine can be inside, which is what makes unloading a thing the player does
## somewhere rather than a button on a menu.
##
## That is deliberate. A drivable work truck is a whole second vehicle
## controller, a second camera, a second set of collision problems and a second
## thing to tune, and it would buy the player nothing that standing next to a
## trailer does not.
##
## ---------------------------------------------------------------------------
## NO ONE IS DRIVING IT
## ---------------------------------------------------------------------------
## No cab figure, no operator, no silhouette. The business is machines and
## paperwork; the truck is the machine that carries the other machines.
##
## PUBLIC API
##   place(property: ACAProperty)     put it at the arrival point
##   is_mower_inside() -> bool
##   service_point() -> Vector3       where the HUD's marker points
##   set_watched_mower(mower: Node3D)
##
## SIGNALS
##   mower_arrived()   the machine entered the service area
##   mower_left()
##
## INVARIANTS
##   * The truck stands OUTSIDE the lawn, so it can never occupy a cell the
##     player is paid to cut. It is placed from the property's own arrival
##     transform, which is already outside the mowable rectangle.
##   * ONE Area3D and no rigid bodies. The truck body has no collision at all -
##     a solid truck at the arrival point is a wall between the machine and the
##     lawn on the exact line the machine drives in on.
##
## PERSISTENCE OWNERSHIP: None. It is rebuilt from the property every visit.

signal mower_arrived()
signal mower_left()

const TRUCK_SCENE := "res://Assets/Vehicles and Mowers/Work Vehicles/truck.glb"
const TRAILER_SCENE := "res://Assets/Vehicles and Mowers/Work Vehicles/truck-flat.glb"

## The Kenney vehicles are authored at about two units long. THE WORLD IS ABOUT
## FOUR TIMES LIFE SIZE - one world unit is roughly a quarter of a metre - so a
## pickup at five and a half metres is about twenty-two units, and the model
## needs scaling by roughly eleven to be one.
##
## MEASURED, TWICE. The first version used 1.9 - what a two-unit model needs to
## be a two-unit truck - and produced a toy parked in front of a machine that
## towers over it. The second used 11.0 and `Site Probe` reported the body at
## 32.4 units long, which is eight metres: a lorry rather than a pickup.
##
## 7.5 puts it at 22 units - five and a half metres, and about four times the
## Rider's 5.6-unit deck, which is the right relationship between a pickup and
## the ride-on mower on its trailer.
const MODEL_SCALE := 7.5

## How far the service area reaches from the middle of the trailer. Generous on
## purpose: hunting for an exact spot to stand is not a skill worth testing, and
## the player has already driven back across the property to get here.
const SERVICE_RADIUS := 9.0
const SERVICE_HEIGHT := 8.0
## How far behind the cab the trailer is hitched, in world units.
##
## The truck is 22 units long and the flatbed is about the same, so anything
## under 22 parks one inside the other - which is what the first render showed.
const TRAILER_GAP := 25.0

## How far the truck sits from the arrival point, along the direction the machine
## is FACING AWAY from - so it is behind the machine and the way on to the lawn
## is clear.
const PARK_BEHIND := 9.0
## ...and how far to one side, so the machine reverses out beside it rather than
## through it.
const PARK_ASIDE := 5.5

var _service_area: Area3D = null
var _mower: Node3D = null
var _inside: bool = false
var _service_point := Vector3.ZERO


## Build the truck, the trailer and the service area at the property's own
## arrival point. Everything is derived from the property, so a truck can never
## end up somewhere the property does not have.
func place(property: ACAProperty) -> void:
	if property == null or not property.is_built():
		return
	var arrival := property.mower_start_transform()
	# WHERE THE MACHINE IS POINTING. Every canonical mower faces its own local
	# +Z, and the arrival transform yaws that to point across the lawn - so the
	# truck goes the OTHER way, and to one side, and the way on to the lawn is
	# left clear.
	var facing := (arrival.basis * Vector3.BACK).normalized()
	var aside := Vector3(-facing.z, 0.0, facing.x)
	var park := arrival.origin - facing * PARK_BEHIND + aside * PARK_ASIDE
	park.y = property.ground_height_at(park.x, park.z)

	# The truck stands square to the lawn edge rather than pointing at it: a work
	# vehicle pulls up ALONG a property, not at it.
	global_transform = Transform3D(Basis(Vector3.UP, atan2(aside.x, aside.z)), park)
	# WHERE "AT THE TRUCK" IS. Between the cab and the trailer, in world space -
	# the same place the service area is centred, so the marker the player drives
	# to and the area that notices them arriving cannot drift apart.
	_service_point = global_transform * Vector3(0.0, 0.0, -TRAILER_GAP * 0.5)
	_service_point.y = property.ground_height_at(_service_point.x, _service_point.z)

	_load_model(TRUCK_SCENE, "Truck")

	var trailer := _load_model(TRAILER_SCENE, "Trailer")
	if trailer != null:
		# Behind the cab, along the truck's own local axis, with a tow gap.
		var offset := Vector3(0.0, 0.0, -TRAILER_GAP)
		trailer.position = offset
		var world := global_transform * offset
		trailer.position.y = property.ground_height_at(world.x, world.z) 			- global_position.y

	_build_service_area()
	_report_size()


## MEASURED, NOT ASSUMED. The scale above is a claim about how big a Kenney
## pickup is next to a machine authored for this world; this prints what the
## truck actually came out as, so the claim can be checked rather than believed.
func _report_size() -> void:
	var truck := get_node_or_null(^"Truck") as Node3D
	if truck == null:
		return
	var extent := Vector3.ZERO
	for node in truck.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var size := mesh.mesh.get_aabb().size * MODEL_SCALE
		extent = Vector3(maxf(extent.x, size.x), maxf(extent.y, size.y),
			maxf(extent.z, size.z))
	print("[TRUCK] body %.1f x %.1f x %.1f world units at scale %.1f"
		% [extent.x, extent.y, extent.z, MODEL_SCALE])


func _load_model(path: String, node_name: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[TRUCK] could not load %s" % path)
		return null
	var model := packed.instantiate() as Node3D
	if model == null:
		return null
	model.name = node_name
	model.scale = Vector3.ONE * MODEL_SCALE
	# NO COLLISION, deliberately. See the invariant at the top: a solid truck on
	# the arrival line is a wall across the way in.
	add_child(model)
	return model


## The one piece of function. An Area3D rather than a body, because the truck
## must be somewhere the machine can BE, not something it bumps into.
func _build_service_area() -> void:
	_service_area = Area3D.new()
	_service_area.name = "Service Area"
	_service_area.monitoring = true
	_service_area.monitorable = false
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = SERVICE_RADIUS
	cylinder.height = SERVICE_HEIGHT
	shape.shape = cylinder
	# Centred BETWEEN the cab and the trailer, which is where a person would
	# stand to load a machine on to it.
	shape.position = Vector3(0.0, SERVICE_HEIGHT * 0.5, -TRAILER_GAP * 0.5)
	_service_area.add_child(shape)
	add_child(_service_area)


## Which machine counts as "back at the truck". Set by the mowing runtime, and
## re-set if the player changes machines, so the area follows the contract
## rather than a node that may have been replaced.
func set_watched_mower(mower: Node3D) -> void:
	_mower = mower
	_inside = false


func service_point() -> Vector3:
	return _service_point


func service_radius() -> float:
	return SERVICE_RADIUS


## TESTED BY DISTANCE, NOT BY SIGNAL.
##
## `body_entered` on an Area3D depends on the mower's collision layers lining up
## with the area's mask, and the three canonical machines were authored at
## different times with different layers. A distance test against the machine
## the runtime handed over cannot be broken by a layer, cannot miss an entry
## that happened during a physics pause, and is one subtraction per frame.
func is_mower_inside() -> bool:
	if _mower == null or not is_instance_valid(_mower):
		return false
	var here := _mower.global_position
	var there := _service_point
	# Horizontal only: the truck sits on the ground and the machine may be on a
	# slope beside it.
	return Vector2(here.x - there.x, here.z - there.z).length() <= SERVICE_RADIUS


func _process(_delta: float) -> void:
	var now := is_mower_inside()
	if now == _inside:
		return
	_inside = now
	if _inside:
		mower_arrived.emit()
	else:
		mower_left.emit()
