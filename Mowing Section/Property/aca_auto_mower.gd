class_name ACAAutoMower
extends Node3D
## ROLE
## An owned autonomous machine, working a section of the same lawn the player
## is on. The visible form of the business having grown.
##
## ---------------------------------------------------------------------------
## THERE IS NO OPERATOR
## ---------------------------------------------------------------------------
## No driver, no walker, no figure of any kind. The machine IS the actor. That
## is the project's standing art direction and it is also the design: a business
## grows here by owning better machines, not by hiring people.
##
## ---------------------------------------------------------------------------
## LANES, NOT NAVIGATION
## ---------------------------------------------------------------------------
## This is deliberately not a general-purpose navigation agent. It is given a
## rectangle of lawn, it walks that rectangle in strips, and it asks the lawn
## itself whether the next stretch is mowable before it drives down it. There is
## no NavigationServer, no pathfinding, no dynamic obstacle avoidance and no
## steering behaviour.
##
## What makes that reliable rather than crude is that the SAME authority answers
## every question:
##
##   * `ACALawn.is_mowable()` decides whether a point may be driven at. It is
##     already false over the pond, inside every obstacle's clearance band and
##     outside the contract, so respecting it respects all three at once with no
##     per-feature code here.
##   * `ACALawn.mow_swath()` does the cutting - the same call the player's deck
##     ultimately reaches, against the same grid, feeding the same completion
##     denominator. The machine cannot cut anything the player could not, and
##     what it cuts really is cut.
##   * `ACATerrain.height_at()` puts it on the ground.
##
## A lane whose next step is not mowable is ABANDONED and the machine moves to
## the next one. It never reverses into a corner, never gets stuck against a
## rock, and in the worst case simply runs out of lanes and stops - which is a
## machine that has finished, not a machine that is broken.
##
## ---------------------------------------------------------------------------
## IT DOES NOT TAKE THE LAWN
## ---------------------------------------------------------------------------
## The section it is given is a band along the FAR side of the property, sized
## by what its tier can cover, and never more than `MAX_SHARE` of the contract.
## The player is paid for the whole lawn either way; what the machine buys them
## is time, not the job.
##
## PUBLIC API
##   deploy(property, tier, from_transform) -> bool
##   is_working() / is_finished() -> bool
##   cells_cut() -> int
##   status_text() -> String
##   stop()
##
## SIGNALS
##   section_finished()
##
## PERSISTENCE OWNERSHIP: None. An escort is a decision about ONE contract, and
## a save taken mid-contract restores the lawn, which is where its work already
## is.

signal section_finished()

## Overlap between neighbouring lanes, so a strip boundary never leaves a ridge.
const LANE_OVERLAP := 0.18

## How long a section is sized to take, in real seconds. A medium contract takes
## the player somewhere between ten and twenty minutes, so a machine given ten
## minutes of work finishes about when they do - which is the point of bringing
## one.
const SECTION_SECONDS := 600.0

## The largest share of the contract an escort may be given, whatever its tier.
## The player came here to mow.
const MAX_SHARE := 0.34
## ...and the smallest, so deploying a machine is never pointless.
const MIN_SHARE := 0.12

## How far the machine looks ahead before committing to the next step. One step
## is one physics-ish update, so this is "can I be there next".
const LOOKAHEAD := 1.2
## Yaw approach rate. Fast enough to turn at the end of a lane without a visible
## pivot, slow enough that it reads as a machine rather than a sprite.
const TURN_RATE := 3.2

## How far off the property boundary the section keeps, so the machine never
## drives at the fence.
const EDGE_INSET := 2.0

enum State { IDLE, DRIVING, TURNING, RETURNING, DONE }

var _property: ACAProperty = null
var _lawn: ACALawn = null
var _tier: String = "auto_compact"
var _speed: float = 2.4
## Half the width of this machine's cut. Per tier: a commercial unit takes a
## wider strip than a compact one, which is most of what makes it worth owning.
var _deck_half_width: float = 0.55
var _bag_capacity: float = 0.0
var _bag: float = 0.0

var _state: int = State.IDLE
var _lanes: Array[Dictionary] = []
var _lane_index: int = -1
var _target := Vector3.ZERO
var _cells: int = 0
var _last_position := Vector3.ZERO
var _model: Node3D = null
## Where it goes to empty itself. The truck's service point.
var _unload_point := Vector3.ZERO
var _has_unload_point: bool = false


func _ready() -> void:
	set_process(false)


# ==================================================================== deploy

## Put the machine on the property and give it a section. Returns false when
## there is nothing sensible for it to do, in which case nothing is added to the
## scene and the contract runs exactly as it would have without it.
func deploy(property: ACAProperty, tier: String) -> bool:
	if property == null or not property.is_built():
		return false
	var spec := ACAEquipment.tier_spec(tier)
	if spec.is_empty():
		return false
	_property = property
	_lawn = property.lawn()
	_tier = tier
	# THE ON-SCREEN RATE, declared by the tier rather than converted from the
	# off-screen one. See the note on `ACAEquipment.AUTONOMOUS_TIERS`.
	_speed = float(spec.get("escort_speed", 2.6))
	_deck_half_width = float(spec.get("escort_deck", 0.55))
	_bag_capacity = float(spec["bag_kg"])
	_bag = 0.0

	_build_model()
	_plan_lanes()
	if _lanes.is_empty():
		return false
	_lane_index = -1
	_advance_lane()
	set_process(true)
	return true


func set_unload_point(where: Vector3) -> void:
	_unload_point = where
	_has_unload_point = true


func stop() -> void:
	_state = State.DONE
	set_process(false)


func is_working() -> bool:
	return _state == State.DRIVING or _state == State.TURNING \
		or _state == State.RETURNING


func is_finished() -> bool:
	return _state == State.DONE


func cells_cut() -> int:
	return _cells


func tier() -> String:
	return _tier


func display_name() -> String:
	return ACAEquipment.tier_name(_tier)


## One short line for the HUD. Never a dashboard: the player is mowing.
func status_text() -> String:
	match _state:
		State.DRIVING, State.TURNING:
			var done := 0 if _lanes.is_empty() else int(round(
				float(maxi(_lane_index, 0)) / float(_lanes.size()) * 100.0))
			return "Mowing · %d%%" % clampi(done, 0, 100)
		State.RETURNING:
			return "Returning to unload"
		State.DONE:
			return "Section finished"
	return "Standing by"


# =================================================================== planning

## THE SECTION. A band along the far edge of the lawn, laid out as strips
## running the same way the player naturally drives.
##
## Sized from what the tier covers: a compact unit gets a narrow band, a
## commercial one a wide one, and both are clamped so the machine can never take
## more than a third of the contract or so little that deploying it was a waste
## of the player's money.
func _plan_lanes() -> void:
	_lanes.clear()
	if _lawn == null:
		return
	var centre := _lawn.lawn_centre()
	var half := _lawn.lawn_half_extent() - EDGE_INSET
	if half <= 2.0:
		return

	# HOW MUCH THIS MACHINE CAN ACTUALLY GET THROUGH, from its own speed and its
	# own deck rather than from a number that meant something else: distance
	# travelled times width cut is area, and area over the contract is a share.
	var total := float(maxi(_lawn.total_item_count(), 1))
	var reachable := _speed * SECTION_SECONDS * (_deck_half_width * 2.0)
	var share := clampf(reachable / total, MIN_SHARE, MAX_SHARE)

	# THE FAR SIDE. The player arrives at -X and drives in; giving the machine
	# the +X band puts it where the player is not, which is what stops the two
	# machines fighting over the same ground for the first minute.
	var band := half * 2.0 * share
	var from_x := centre.x + half - band
	var to_x := centre.x + half

	var step := _deck_half_width * 2.0 - LANE_OVERLAP
	var x := from_x
	var forward := true
	while x <= to_x:
		var a := Vector3(x, 0.0, centre.z - half)
		var b := Vector3(x, 0.0, centre.z + half)
		_lanes.append({"from": a if forward else b, "to": b if forward else a})
		forward = not forward
		x += step


## Move to the next lane whose ends are actually mowable. A lane over the pond,
## or one that only exists inside an obstacle's clearance band, is skipped
## rather than driven at.
func _advance_lane() -> void:
	while true:
		_lane_index += 1
		if _lane_index >= _lanes.size():
			_finish()
			return
		var lane: Dictionary = _lanes[_lane_index]
		var start: Vector3 = lane["from"]
		if not _is_drivable(start):
			# Try to find a mowable start further along the lane before giving
			# up on it: a strip that begins in the water usually does not end
			# there.
			var found := _first_drivable_along(lane)
			if not bool(found["found"]):
				continue
			start = found["at"]
			lane["from"] = start
		_place_at(start)
		_target = lane["to"]
		_state = State.DRIVING
		return


## Walk in from the lane's start looking for the first point the machine may be
## at. `{ found: bool, at: Vector3 }` rather than a nullable Vector3, because
## Vector3 has no null and a sentinel coordinate is a bug waiting for the day
## somebody generates a property centred on it.
func _first_drivable_along(lane: Dictionary) -> Dictionary:
	var missing := {"found": false, "at": Vector3.ZERO}
	var from: Vector3 = lane["from"]
	var to: Vector3 = lane["to"]
	var span := from.distance_to(to)
	if span <= 0.01:
		return missing
	var direction := (to - from) / span
	var walked := 0.0
	while walked < span:
		var at := from + direction * walked
		if _is_drivable(at):
			return {"found": true, "at": at}
		walked += 1.0
	return missing


func _is_drivable(at: Vector3) -> bool:
	if _lawn == null:
		return false
	# THE LAWN IS THE AUTHORITY. `is_mowable` is already false over the pond,
	# inside every obstacle's clearance band, and outside the contract.
	return _lawn.is_mowable(at)


# ==================================================================== driving

func _process(delta: float) -> void:
	match _state:
		State.DRIVING:
			_drive(delta)
		State.RETURNING:
			_return(delta)
		_:
			pass


func _drive(delta: float) -> void:
	var here := global_position
	var to_target := Vector3(_target.x - here.x, 0.0, _target.z - here.z)
	var distance := to_target.length()
	if distance < 0.35:
		_advance_lane()
		return

	var direction := to_target / distance
	var step := minf(_speed * delta, distance)
	var next := here + direction * step

	# LOOK BEFORE DRIVING. Anything the lawn will not let the machine mow is
	# also somewhere it must not be, so one question answers both.
	var ahead := here + direction * (step + LOOKAHEAD)
	if not _is_drivable(Vector3(ahead.x, 0.0, ahead.z)):
		# The lane is blocked from here on. Cut what it has and take the next
		# one, rather than nudging along a wall trying to find a way round.
		_advance_lane()
		return

	_move_to(next, direction, delta)
	_cut_between(here, next)

	if _bag_capacity > 0.0 and _bag >= _bag_capacity and _has_unload_point:
		_state = State.RETURNING


## Drive back to the truck, empty, and resume. The machine does its own
## logistics: a unit the player has to babysit is a unit that costs them time
## instead of saving it.
func _return(delta: float) -> void:
	var here := global_position
	var to_truck := Vector3(_unload_point.x - here.x, 0.0, _unload_point.z - here.z)
	var distance := to_truck.length()
	if distance < 3.0:
		var clippings := get_node_or_null(^"/root/Clippings")
		if clippings != null:
			clippings.call(&"deliver_direct", _bag)
		_bag = 0.0
		# Straight back to the lane it left, from wherever it is now.
		if _lane_index >= 0 and _lane_index < _lanes.size():
			_target = _lanes[_lane_index]["to"]
			_state = State.DRIVING
		else:
			_finish()
		return
	var direction := to_truck / distance
	_move_to(here + direction * minf(_speed * delta, distance), direction, delta)
	# NOTHING IS CUT ON THE WAY BACK. The machine is crossing ground it has
	# already been over; letting it cut here would be free progress for driving
	# in a straight line.


## THE CUT. `mow_swath` is the lawn's own call, against the lawn's own grid, so
## a cell the escort took is a cell the completion denominator now counts as
## done - and one the player is not asked to drive over again.
func _cut_between(from: Vector3, to: Vector3) -> void:
	if _lawn == null:
		return
	var cells := _lawn.mow_swath(from, to, _deck_half_width)
	if cells <= 0:
		return
	_cells += cells
	if _bag_capacity <= 0.0:
		return
	# A collecting unit fills up exactly the way the player's machine does, from
	# the same conversion, so a kilogram means one thing in this game.
	_bag = minf(_bag + float(cells) * ACAClippings.KG_PER_CELL, _bag_capacity)


func _move_to(where: Vector3, direction: Vector3, delta: float) -> void:
	var ground := _property.ground_height_at(where.x, where.z) if _property != null else where.y
	global_position = Vector3(where.x, ground + 0.06, where.z)
	if direction.length_squared() > 0.0001:
		var wanted := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, wanted, clampf(TURN_RATE * delta, 0.0, 1.0))


func _place_at(where: Vector3) -> void:
	var ground := _property.ground_height_at(where.x, where.z) if _property != null else where.y
	global_position = Vector3(where.x, ground + 0.06, where.z)


func _finish() -> void:
	_state = State.DONE
	set_process(false)
	# Anything still in the catcher goes to the yard: the machine has finished
	# its section and the clippings are on the trailer either way.
	if _bag > 0.0:
		var clippings := get_node_or_null(^"/root/Clippings")
		if clippings != null:
			clippings.call(&"deliver_direct", _bag)
		_bag = 0.0
	section_finished.emit()


# ====================================================================== model

## ---------------------------------------------------------------------------
## THE MACHINE IS BUILT, NOT BORROWED
## ---------------------------------------------------------------------------
## The first version reused the walk-behind mesh and tried to hide its
## handlebar. It could not: both mower models in this project are a SINGLE
## merged mesh with one surface, so there is no handle to hide - it is the same
## triangles as the deck. What that produced was a walk-behind gliding across a
## lawn with nobody holding it, which does not read as an autonomous machine. It
## reads as an invisible person, and an invisible person is worse than either.
##
## So this machine is assembled from primitives: a low wide deck, four small
## wheels and a dark cutting slot under the front. That is what a robot mower
## actually looks like, it is unambiguously a thing rather than a thing somebody
## is pushing, and it costs six meshes.
##
## It also SIZES ITSELF to the deck it cuts, so a commercial unit is visibly the
## bigger machine rather than the same model going faster.

## Deck proportions, as multiples of the cut width.
const BODY_LENGTH_RATIO := 1.25
## Tall enough to sit ABOVE the lawn it is cutting. Unmown grass stands at 0.86
## units and the first version came out at 0.9 overall, which put the machine
## exactly at grass height and lost it in the field from any distance.
const BODY_HEIGHT_RATIO := 0.50
const WHEEL_RADIUS_RATIO := 0.20

## The machine's own colours. Deliberately not the mower orange the HUD reserves
## for a warning: this is equipment, not an alert.
const SHELL_COLOUR := Color(0.243, 0.267, 0.243)
const TRIM_COLOUR := Color(0.400, 0.612, 0.337)
const WHEEL_COLOUR := Color(0.098, 0.106, 0.098)


func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "Body"
	add_child(_model)

	var width := _deck_half_width * 2.0
	var length := width * BODY_LENGTH_RATIO
	var height := width * BODY_HEIGHT_RATIO
	var wheel := width * WHEEL_RADIUS_RATIO

	# The deck: low, wide, and sitting on its wheels.
	var shell := BoxMesh.new()
	shell.size = Vector3(width, height, length)
	_part(shell, SHELL_COLOUR, Vector3(0.0, wheel + height * 0.5, 0.0))

	# A band across the top, so the machine has a front and the player can see
	# which way it is pointing from across a property.
	var band := BoxMesh.new()
	band.size = Vector3(width * 0.82, height * 0.34, length * 0.22)
	_part(band, TRIM_COLOUR,
		Vector3(0.0, wheel + height * 0.92, length * 0.24))

	# The cut, under the front edge. Nothing turns; it is there so the machine
	# has an underside rather than floating on a closed box.
	var slot := BoxMesh.new()
	slot.size = Vector3(width * 0.92, height * 0.28, length * 0.5)
	_part(slot, WHEEL_COLOUR, Vector3(0.0, wheel * 0.75, -length * 0.05))

	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var tyre := CylinderMesh.new()
			tyre.top_radius = wheel
			tyre.bottom_radius = wheel
			tyre.height = wheel * 0.7
			tyre.radial_segments = 10
			var part := _part(tyre, WHEEL_COLOUR, Vector3(
				side * (width * 0.5 - wheel * 0.35), wheel,
				end * length * 0.32))
			# A cylinder stands on its end by default; a wheel lies on its side.
			part.rotation.z = PI * 0.5


func _part(mesh: Mesh, colour: Color, at: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.75
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	# Scenery, like everything else the property plants: it is never collided
	# with, and the lawn's own exclusions are what keep it out of the water.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_model.add_child(instance)
	return instance
