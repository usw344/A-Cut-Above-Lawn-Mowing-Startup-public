extends Node
## DEVELOPMENT ONLY. Drives the REAL mowers in the REAL mowing scene and checks
## that mowing works end to end: a machine that moves cuts grass, the cut lands
## where it drove, progress reaches the HUD and the Job System, every machine
## cuts its own width, and finishing the lawn completes the contract.
##
##   godot --headless --path . "res://Dev tools/Validation/Mowing Test.tscn" -- "--save-root=<dir>"
##
## Everything here uses `Input.action_press` and the mower's own controller. It
## never calls the cutter directly, because the thing under test is whether the
## machine, the deck and the lawn agree.
##
## PUBLIC API: None.

## HOW LONG each drive test holds the throttle, in SECONDS of simulated time.
##
## It used to be a count of ninety RENDER frames, which is two assumptions that
## are both wrong: that a render frame is a fixed slice of time, and that a
## machine reaches its speed instantly. The second stopped being true when the
## machines were given acceleration - a rider now takes 1.6 s to reach 90% of
## its speed, so ninety frames of it was a machine still getting going, and the
## assertion measured the acceleration curve rather than whether the throttle
## worked.
##
## Counted off the PHYSICS step, which is a fixed 576 Hz, so this is the same
## test on any machine at any frame rate.
const DRIVE_SECONDS := 1.5

var _passes := 0
var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("=== MOWING TEST ===")
	await _test_driving_cuts()
	await _test_each_mower_cuts_its_own_width()
	await _test_completion()
	print("===========================================")
	print("[MOWING TEST] %d passed, %d failed" % [_passes, _failures])
	print("===========================================")
	get_tree().quit(1 if _failures > 0 else 0)


# =================================================================== the tests

## A machine that drives leaves cut grass behind it, and only behind it.
func _test_driving_cuts() -> void:
	if not await _enter_mowing():
		_fail("driving: reached the mowing scene")
		return
	var scene := get_tree().current_scene
	var lawn: ACALawn = scene.call(&"lawn")
	var mower: Node3D = scene.get(&"current_mower")
	_check("driving: the scene exposes its lawn", lawn != null)
	_check("driving: the lawn is the contract size",
		lawn != null and lawn.cell_count() == GameSession.current_job().grid_size.x)
	if lawn == null or mower == null:
		return

	MowerFuel.set_auto_refuel(false)
	MowerFuel.refuel_full()

	# Put the machine somewhere with lawn in front of it, pointing across it.
	var centre := lawn.lawn_centre()
	_place(mower, Vector3(centre.x - 20.0, 0.0, centre.z), PI * 0.5)
	await _step(6)

	var before := lawn.mowed_item_count()
	var start := mower.global_position
	var travelled := await _drive(DRIVE_SECONDS)
	var after := lawn.mowed_item_count()

	_check("driving: the machine actually moved (%.1f units)" % travelled,
		travelled > 4.0)
	_check("driving: driving cut grass (%d cells)" % (after - before),
		after > before)

	# The cut is where the machine went.
	var direction := (mower.global_position - start)
	direction.y = 0.0
	var along := direction.normalized()
	var cut_on_path := 0
	var samples := 0
	for i in range(2, 9):
		var p := start + along * (direction.length() * float(i) / 10.0)
		p.y = 0.0
		if not lawn.is_mowable(p):
			continue
		samples += 1
		if lawn.is_cut(p):
			cut_on_path += 1
	_check("driving: the path it drove is cut (%d of %d)" % [cut_on_path, samples],
		samples > 0 and cut_on_path == samples)

	var beside := start + Vector3(-along.z, 0.0, along.x) * 22.0
	_check("driving: ground well to the side is untouched",
		not lawn.is_cut(beside) or not lawn.is_mowable(beside))

	# The progress the HUD reads is the lawn's own number.
	var ui := _gameplay_ui()
	if ui != null and ui.has_method(&"debug_progress_value"):
		_check("driving: the HUD shows the lawn's progress",
			is_equal_approx(float(ui.call(&"debug_progress_value")),
				lawn.mowed_fraction()))

	# ...and the Job System is told about it.
	await _step(70)
	var job := GameSession.current_job()
	_check("driving: the contract records the progress (%.4f)" % job.progress,
		job != null and job.progress > 0.0)

	# An empty tank stops the blades.
	MowerFuel.dev_drain()
	await _step(4)
	var dry_before := lawn.mowed_item_count()
	await _drive(40)
	_check("driving: an empty tank stops the blades",
		lawn.mowed_item_count() == dry_before)
	MowerFuel.refuel_full()


## Three machines, three decks. A rider must cut a wider strip than a push mower
## over the same distance, or declaring a deck per machine bought nothing.
func _test_each_mower_cuts_its_own_width() -> void:
	var widths := {}
	for id in ["push", "powered", "rider"]:
		var scene := get_tree().current_scene
		scene.call(&"_on_mvp_hud_mower_change_selected", id)
		await _step(10)
		var lawn: ACALawn = scene.call(&"lawn")
		var mower: Node3D = scene.get(&"current_mower")
		if mower == null:
			_fail("%s: became the active mower" % id)
			continue
		_check("%s: became the active mower" % id, true)

		MowerFuel.set_auto_refuel(false)
		MowerFuel.refuel_full()
		lawn.reset()
		var centre := lawn.lawn_centre()
		_place(mower, Vector3(centre.x - 30.0, 0.0, centre.z + 20.0), PI * 0.5)
		if scene.get(&"cutter") != null:
			(scene.get(&"cutter") as ACAMowerCutter).resync()
		await _step(6)

		var before := lawn.mowed_item_count()
		var travelled := await _drive(DRIVE_SECONDS)
		var cells := lawn.mowed_item_count() - before
		var width: float = float(cells) / maxf(travelled, 0.001)
		widths[id] = width
		print("[MOWING TEST]   %s cut %d cells over %.1f units -> %.2f wide"
			% [id, cells, travelled, width])
		_check("%s: cutting happened while driving" % id, cells > 0)

	if widths.size() == 3:
		_check("decks: the rider cuts a wider strip than the push mower",
			float(widths["rider"]) > float(widths["push"]) * 1.05)
		_check("decks: every machine cuts a strip of a believable width",
			float(widths["push"]) > 2.5 and float(widths["rider"]) < 9.0)


## Finishing the lawn finishes the contract, through the same completion path
## the game always used.
func _test_completion() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method(&"lawn"):
		_fail("completion: still in the mowing scene")
		return
	var lawn: ACALawn = scene.call(&"lawn")
	var job := GameSession.current_job()
	if lawn == null or job == null:
		_fail("completion: there is a lawn and a contract")
		return
	var job_id := job.id

	# Mow the rest of it geometrically. This is the SAME api the trailer uses and
	# the same bookkeeping driving performs.
	var centre := lawn.lawn_centre()
	var half := lawn.lawn_half_extent()
	lawn.mow_swath(
		Vector3(centre.x - half - 10.0, 0.0, centre.z),
		Vector3(centre.x + half + 10.0, 0.0, centre.z), half + 10.0)
	_check("completion: the lawn reports exactly 100%%",
		lawn.mowed_item_count() == lawn.total_item_count()
			and lawn.mowed_fraction() >= 1.0)

	await _step(20)
	var finished := JobManager.get_job(job_id)
	_check("completion: the contract is no longer in progress",
		finished == null or finished.status != ACAJobEnums.Status.IN_PROGRESS)
	_check("completion: reaching 100% completed the contract",
		not GameSession.has_active_job()
			or GameSession.current_job_id() != job_id)


# =================================================================== helpers

func _place(mower: Node3D, where: Vector3, yaw: float) -> void:
	var scale := mower.transform.basis.get_scale()
	var scene := get_tree().current_scene
	var y: float = where.y
	if scene != null and scene.has_method(&"property"):
		var property: ACAProperty = scene.call(&"property")
		y = property.ground_height_at(where.x, where.z) + 1.2
	mower.global_transform = Transform3D(
		Basis(Vector3.UP, yaw).scaled(scale), Vector3(where.x, y, where.z))
	if scene != null and scene.get(&"cutter") != null:
		(scene.get(&"cutter") as ACAMowerCutter).resync()


func _drive(seconds: float) -> float:
	var scene := get_tree().current_scene
	var mower: Node3D = scene.get(&"current_mower") if scene != null else null
	if mower == null:
		return 0.0
	var from := mower.global_position
	Input.action_press(&"move_forward")
	var elapsed := 0.0
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	while elapsed < seconds:
		await get_tree().physics_frame
		elapsed += step
	Input.action_release(&"move_forward")
	await _step(2)
	var to := mower.global_position
	return Vector2(to.x - from.x, to.z - from.z).length()


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
	return GameSession.current_screen() == ACAGameSession.Screen.MOWING


func _wait_for_screen(screen: int, timeout_frames: int = 400) -> void:
	for i in timeout_frames:
		if GameSession.current_screen() == screen \
				and not GameSession.is_changing_scene():
			return
		await get_tree().process_frame


func _gameplay_ui() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null(^"Gameplay UI") if scene != null else null


func _step(frames: int = 1) -> void:
	for _i in frames:
		await get_tree().process_frame


func _check(what: String, ok: bool) -> void:
	if ok:
		_passes += 1
		print("[MOWING TEST] %s: PASS" % what)
	else:
		_failures += 1
		printerr("[MOWING TEST] %s: FAIL" % what)


func _fail(what: String) -> void:
	_check(what, false)
