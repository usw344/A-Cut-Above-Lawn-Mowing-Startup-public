extends Node
## DEVELOPMENT ONLY. Drives the REAL mower in the REAL mowing scene AT the
## things that are supposed to stop it, and checks that they do.
##
##   godot --headless --path . "res://Dev tools/Validation/Containment Test.tscn" \
##     -- "--save-root=<dir>"
##
## ---------------------------------------------------------------------------
## WHY THIS IS A DRIVING TEST AND NOT A GEOMETRY TEST
## ---------------------------------------------------------------------------
## `Property Test` already asserts that the boundary rectangle contains the
## lawn and that the pond has a shoreline. Neither of those facts is the thing
## the player experiences. A wall can be in exactly the right place and still be
## too thin to stop a machine at speed, too short to stop one coming down a
## slope, or have a gap at a corner that only exists at one seed.
##
## So every check here presses `move_forward` through the real controller,
## against the real collision, and then asks where the machine ended up.
##
## PUBLIC API: None.

## How long the machine is held at full throttle for one attempt. At 576 Hz
## physics this is a good few seconds of real driving.
const CHARGE_FRAMES := 150
## Frames given to the machine to settle on the ground after being placed.
const SETTLE_FRAMES := 12

## How far past the boundary rectangle counts as escaped. Generous: the machine
## is allowed to touch the fence and to have its far corner overhang the line a
## little, because the collision is on its body rather than on its silhouette.
const ESCAPE_TOLERANCE := 3.0

var _passes := 0
var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("=== CONTAINMENT TEST ===")
	if not await _enter_mowing():
		_fail("reached the mowing scene")
		_finish()
		return
	_report_property()
	await _test_outer_boundary()
	await _test_corners()
	await _test_pond()
	await _test_obstacles()
	await _test_background_is_unreachable()
	_finish()


func _finish() -> void:
	print("===========================================")
	print("[CONTAINMENT TEST] %d passed, %d failed" % [_passes, _failures])
	print("===========================================")
	get_tree().quit(1 if _failures > 0 else 0)


func _report_property() -> void:
	var property := _property()
	if property == null:
		return
	var stats := property.statistics()
	var boundary: Dictionary = stats.get("boundary", {})
	print("[CONTAINMENT] lawn %d | boundary half %.1f (margin %.1f, %s) | %d wall segments"
		% [property.params().lawn_size, float(boundary.get("half_extent", 0.0)),
			float(boundary.get("margin", 0.0)), boundary.get("treatment", "?"),
			int(boundary.get("segments", 0))])
	print("[CONTAINMENT] physics bodies on the property: %d" % _count_bodies(property))


# =================================================================== the tests

## STRAIGHT AT THE FENCE, on all four sides. The machine is started well inside
## the property so it arrives at the wall with speed on it rather than being
## parked against it.
func _test_outer_boundary() -> void:
	var property := _property()
	var boundary := property.boundary()
	if boundary == null:
		_fail("the property has a boundary")
		return
	var centre := boundary.centre()
	var half := boundary.half_extent()
	var escapes := 0
	var worst := 0.0
	var directions := {
		"+X": Vector2(1.0, 0.0),
		"-X": Vector2(-1.0, 0.0),
		"+Z": Vector2(0.0, 1.0),
		"-Z": Vector2(0.0, -1.0),
	}
	for label in directions:
		var dir: Vector2 = directions[label]
		# Start two thirds of the way out, aimed at the wall.
		var from := Vector3(centre.x + dir.x * half * 0.55, 0.0,
			centre.z + dir.y * half * 0.55)
		_place(from, atan2(dir.x, dir.y))
		await _step(SETTLE_FRAMES)
		await _charge()
		var outside := boundary.distance_outside(
			_mower().global_position.x, _mower().global_position.z)
		worst = maxf(worst, outside)
		if outside > ESCAPE_TOLERANCE:
			escapes += 1
			print("[CONTAINMENT] escaped %s by %.2f units" % [label, outside])
	_check("boundary: four head-on charges, none escapes (worst %.2f units past the line)"
		% worst, escapes == 0)


## AT THE CORNERS, diagonally, where two walls meet and a gap would be easiest
## to make.
func _test_corners() -> void:
	var boundary := _property().boundary()
	var centre := boundary.centre()
	var half := boundary.half_extent()
	var escapes := 0
	var worst := 0.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var dir := Vector2(sx, sz).normalized()
			var from := Vector3(centre.x + dir.x * half * 0.45, 0.0,
				centre.z + dir.y * half * 0.45)
			_place(from, atan2(dir.x, dir.y))
			await _step(SETTLE_FRAMES)
			await _charge()
			var p := _mower().global_position
			var outside := boundary.distance_outside(p.x, p.z)
			worst = maxf(worst, outside)
			if outside > ESCAPE_TOLERANCE:
				escapes += 1
	_check("boundary: four corner charges, none escapes (worst %.2f units past the line)"
		% worst, escapes == 0)


## STRAIGHT AT THE WATER, and then at it obliquely. The machine must be able to
## get close - a bank the player cannot trim is a contract they cannot finish -
## and must not get in.
func _test_pond() -> void:
	var pond := _pond()
	if pond == null:
		_fail("the property has a pond")
		return
	var centre := pond.centre()
	var property := _property()
	var water := pond.water_world_height()
	var entries := 0
	var closest := INF
	# Eight approaches: four square on, four oblique.
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var dir := Vector2(cos(angle), sin(angle))
		# Start outside the pond, aimed at its middle.
		var start_distance: float = pond.radius() * maxf(pond.carver_params().ellipse_ratio, 1.0) + 22.0
		var from := Vector3(centre.x + dir.x * start_distance, 0.0,
			centre.y + dir.y * start_distance)
		# An approach that would start outside the property is skipped rather
		# than started in mid-air.
		if property.boundary().distance_outside(from.x, from.z) > 0.0:
			continue
		_place(from, atan2(-dir.x, -dir.y))
		await _step(SETTLE_FRAMES)
		await _charge()
		var p := _mower().global_position
		# IN THE WATER means the machine's own position is inside the traced
		# shoreline AND below the surface. Either alone is not enough: a machine
		# on the bank is inside the outline of the bowl but above the water.
		var ground := property.ground_height_at(p.x, p.z)
		if ground < water and pond.shore_factor_at(p.x, p.z) > 0.0:
			entries += 1
			print("[CONTAINMENT] entered the water on approach %d" % i)
		closest = minf(closest, Vector2(p.x, p.z).distance_to(centre))
	_check("pond: eight approaches, the machine never reaches the water", entries == 0)
	# ...and the point of the ring is that it stops the machine AT the water
	# rather than a field away from it.
	_check("pond: the machine can still get to the bank (closest %.1f units from the centre, radius %.1f)"
		% [closest, pond.radius()],
		closest < pond.radius() * pond.carver_params().ellipse_ratio + 12.0)


## A rock on the lawn is solid. Driven into head on, the machine stops or slides
## off; it does not pass through.
func _test_obstacles() -> void:
	var field := _obstacles()
	if field == null or field.count() == 0:
		_fail("the property has lawn obstacles")
		return
	var passes_through := 0
	var tried := 0
	var property := _property()
	for o: Dictionary in field.obstacles():
		if tried >= 4:
			break
		var at: Vector2 = o["position"]
		var radius: float = float(o["radius"])
		var from := Vector3(at.x - 16.0, 0.0, at.y)
		if property.boundary().distance_outside(from.x, from.z) > 0.0:
			continue
		tried += 1
		_place(from, PI * 0.5)
		await _step(SETTLE_FRAMES)
		await _charge()
		var p := _mower().global_position
		# Past the rock's far side means it went through it.
		if p.x > at.x + radius + 2.0 and absf(p.z - at.y) < radius:
			passes_through += 1
	_check("obstacles: %d lawn rocks driven into head on, none is passed through"
		% tried, tried > 0 and passes_through == 0)


## THE POINT OF ALL OF THIS. The nearest scenery is beyond the fence, and the
## fence has just been shown to hold, so the scenery does not need collision -
## and this asserts that it has none, because a body added there later would be
## paid for on every property at every size.
func _test_background_is_unreachable() -> void:
	var property := _property()
	var foliage := property.foliage()
	_check("background: the wood carries no physics bodies at all",
		foliage == null or _count_bodies(foliage) == 0)
	_check("background: the whole property is four bodies - ground, fence, pond, rocks",
		_count_bodies(property) <= 4,
		"%d bodies" % _count_bodies(property))

	# And nothing the wood planted is inside the fence.
	var boundary := property.boundary()
	_check("background: the fence is inside the ground that has collision",
		boundary.half_extent() < property.params().near_extent())


# =================================================================== helpers

func _charge() -> void:
	Input.action_press(&"move_forward")
	await _step(CHARGE_FRAMES)
	Input.action_release(&"move_forward")
	await _step(4)


func _place(where: Vector3, yaw: float) -> void:
	var mower := _mower()
	if mower == null:
		return
	var property := _property()
	var y: float = property.ground_height_at(where.x, where.z) + 1.2
	var mower_scale := mower.transform.basis.get_scale()
	mower.global_transform = Transform3D(
		Basis(Vector3.UP, yaw).scaled(mower_scale), Vector3(where.x, y, where.z))
	# The controller smooths body yaw towards a target captured in its _ready();
	# without this the machine spends its first second turning back to that.
	if mower.get(&"target_body_yaw") != null:
		mower.set(&"target_body_yaw", yaw)
	mower.set(&"velocity", Vector3.ZERO)
	var scene := get_tree().current_scene
	if scene != null and scene.get(&"cutter") != null:
		(scene.get(&"cutter") as ACAMowerCutter).resync()
	MowerFuel.refuel_full()


func _property() -> ACAProperty:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method(&"property"):
		return null
	return scene.call(&"property")


func _mower() -> Node3D:
	var scene := get_tree().current_scene
	return scene.get(&"current_mower") if scene != null else null


func _pond() -> ACAPondFeature:
	var property := _property()
	if property == null or property.features() == null:
		return null
	for f in property.features().features():
		if f is ACAPondFeature:
			return f
	return null


func _obstacles() -> ACALawnObstacles:
	var property := _property()
	if property == null or property.features() == null:
		return null
	for f in property.features().features():
		if f is ACALawnObstacles:
			return f
	return null


func _enter_mowing() -> bool:
	if GameSession.current_screen() == ACAGameSession.Screen.MOWING:
		return true
	GameSession.start_new_game()
	await _wait_for_screen(ACAGameSession.Screen.TOWN)
	await _step(8)

	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(1)
		await _step(4)
		offers = JobManager.available_jobs()
	if offers.is_empty():
		return false

	var job: ACAJob = offers[0]
	JobManager.accept_job(job.id)
	JobManager.begin_new_job(job.id)
	await _wait_for_screen(ACAGameSession.Screen.MOWING)
	await _step(20)
	MowerFuel.set_auto_refuel(true)
	return GameSession.current_screen() == ACAGameSession.Screen.MOWING


func _wait_for_screen(screen: int, timeout_frames: int = 400) -> void:
	for i in timeout_frames:
		if GameSession.current_screen() == screen \
				and not GameSession.is_changing_scene():
			return
		await get_tree().process_frame


func _step(frames: int = 1) -> void:
	for _i in frames:
		await get_tree().process_frame


func _count_bodies(node: Node) -> int:
	var total := 1 if node is PhysicsBody3D else 0
	for child in node.get_children():
		total += _count_bodies(child)
	return total


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("[CONTAINMENT TEST] %s: ok" % what)
	else:
		_failures += 1
		print("[CONTAINMENT TEST] %s: FAIL  %s" % [what, detail])


func _fail(what: String) -> void:
	_check(what, false)
