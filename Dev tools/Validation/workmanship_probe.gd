extends Node
## DEVELOPMENT. Calibrates the workmanship readings on the Job Complete sheet by
## DRIVING, rather than by choosing a threshold that sounds about right.
##
## It runs a simple pure-pursuit driver over a real property: aim at the far end
## of the current lane, drive, step across by a deck width, come back. That is
## what a player mowing tidily is doing, and the machine's own acceleration and
## turning circle apply to it exactly as they do to a player - so the coverage
## it produces is a coverage a player can produce.
##
## Then it does it again badly, wandering off the lane, so the threshold sits
## between something worth praising and something that is not.
##
## Reported per machine: coverage tidy, coverage sloppy, contacts.

## Lanes to run. Enough to include the turn cost several times over, not so many
## that the run takes all afternoon at a 576 Hz physics step.
const LANES := 5
## How close to the end of a lane counts as having reached it.
const ARRIVE := 6.0

var _mvp: Node = null
var _centre := Vector3.ZERO
var _half: float = 0.0
var _passes: int = 0
var _failures: int = 0
var _rows: Array[Dictionary] = []
var _shot_dir: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shot_dir = arg.substr(8)
			DirAccess.make_dir_recursive_absolute(_shot_dir)
	_run.call_deferred()


func _run() -> void:
	print("\n============ WORKMANSHIP PROBE ============")
	await _enter_mowing()
	MowerFuel.set_auto_refuel(true)
	for id in ["rider", "push"]:
		await _measure(id)
	_report()
	await _results_sheet()
	print("[WORKMANSHIP PROBE] %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _enter_mowing() -> void:
	GameSession.start_new_game()
	await _step(8)
	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(1)
		offers = JobManager.available_jobs()
	JobManager.accept_job(offers[0].id)
	JobManager.begin_new_job(offers[0].id)
	var frames := 0
	while frames < 3600:
		if GameSession.current_screen() == ACAGameSession.Screen.MOWING \
				and not GameSession.is_changing_scene():
			break
		await get_tree().process_frame
		frames += 1
	await _step(40)
	_mvp = get_tree().current_scene
	var property_node = _mvp.get("property_node")
	_centre = property_node.lawn().lawn_centre()
	_half = property_node.lawn().lawn_half_extent()
	print("[WORKMANSHIP PROBE] lawn %.0f across at %s" % [_half * 2.0, _centre])


func _mower() -> CharacterBody3D:
	return _mvp.get("current_mower") as CharacterBody3D


func _cutter():
	return _mvp.get("cutter")


func _measure(id: String) -> void:
	_mvp.call("_on_mvp_hud_mower_change_selected", id)
	await _step(20)
	var deck_width: float = float(_mower().get("DECK_WIDTH"))

	var tidy := await _drive(deck_width, 1.0)
	var tidy_contacts := int(_cutter().call("contacts"))
	# THE CUT ITSELF, with several finished passes on the ground beside standing
	# grass. This is the shot the cutting-presentation audit is read from.
	await _shot("%s_cut_lawn" % id)
	# NO step across at all: the machine works the same strip over and over.
	#
	# Two other models of "sloppy" were tried first and neither is one. WANDERING
	# off the lane is not: on a lawn that is still mostly standing, a machine
	# that strays is still cutting fresh grass, and it scored as well as a tidy
	# one. HALF a deck width between lanes is not either, at least not for the
	# rider - its twelve-unit turning circle cannot execute a 2.8 unit lane
	# change, so the driver ends up laying something close to a normal pattern
	# anyway. Re-covering ground already cut is what the reading is about, and it
	# is the only one of the three every machine can actually be made to do.
	var sloppy := await _drive(deck_width, 0.0)

	_rows.append({"id": id, "tidy": tidy, "sloppy": sloppy,
		"contacts": tidy_contacts})


## One run of `LANES` lanes, from a clean lawn. `lane_step` is how far the driver
## moves across between lanes, as a fraction of a deck width: 1.0 is a player
## laying passes edge to edge, 0.5 is one re-cutting half of every pass.
func _drive(deck_width: float, lane_step: float) -> float:
	_mvp.get("property_node").lawn().reset()
	var mower := _mower()
	var cutter = _cutter()
	cutter.call("reset_counters")
	# `reset_counters` does not touch the cut tally, which is what coverage is
	# measured against, so the cutter is rebound to start both from nothing.
	cutter.call("bind", mower, _mvp.get("property_node").lawn())

	# Start at one corner of the working area, driving along +X.
	var lane_z: float = _centre.z - _half + deck_width
	mower.velocity = Vector3.ZERO
	mower.set("_ground_speed", 0.0)
	mower.global_position = Vector3(_centre.x - _half + 4.0,
		mower.global_position.y, lane_z)
	mower.rotation.y = 0.0
	mower.set("target_body_yaw", 0.0)
	await _step(6)

	var forward := true
	Input.action_press("move_forward")
	for lane in LANES:
		var target_x: float = (_centre.x + _half - 4.0) if forward \
			else (_centre.x - _half + 4.0)
		var target := Vector2(target_x, lane_z)
		var guard := 0.0
		while guard < 20.0:
			var at := Vector2(mower.global_position.x, mower.global_position.z)
			if at.distance_to(target) < ARRIVE:
				break
			# The machine's forward is +Z, so a bearing in the XZ plane is
			# measured from +Z towards +X.
			var to_aim := target - at
			mower.set("target_body_yaw", atan2(to_aim.x, to_aim.y))
			await get_tree().physics_frame
			guard += 1.0 / 576.0
		forward = not forward
		lane_z += deck_width * lane_step
		if lane_z > _centre.z + _half - deck_width:
			break
	Input.action_release("move_forward")
	await _step(4)
	return float(cutter.call("coverage"))


func _report() -> void:
	print("\n machine   tidy    sloppy  contacts")
	print(" -----------------------------------")
	for row in _rows:
		print(" %-9s %-7.2f %-7.2f %-3d" % [row["id"], row["tidy"],
			row["sloppy"], row["contacts"]])

	var worst_tidy := 1.0
	var best_sloppy := 0.0
	for row in _rows:
		worst_tidy = minf(worst_tidy, float(row["tidy"]))
		best_sloppy = maxf(best_sloppy, float(row["sloppy"]))
	print("\n CLEAN PASSES is awarded at %.2f, LOW OVERLAP at %.2f"
		% [JobCompleteScreen.CLEAN_PASSES_COVERAGE, JobCompleteScreen.LOW_OVERLAP_COVERAGE])

	_check("tidy driving earns CLEAN PASSES on every machine",
		worst_tidy >= JobCompleteScreen.CLEAN_PASSES_COVERAGE,
		"worst tidy run was %.2f" % worst_tidy)
	_check("sloppy driving does not",
		best_sloppy < JobCompleteScreen.CLEAN_PASSES_COVERAGE,
		"best sloppy run was %.2f" % best_sloppy)
	_check("tidy is measurably better than sloppy",
		worst_tidy > best_sloppy + 0.1)


## END TO END: finish the contract and photograph the sheet, so the workmanship
## callouts are seen where the player sees them rather than only asserted.
##
## The development completion shortcut fills the lawn in through the lawn's own
## API, NOT through the cutter, so the coverage on the sheet is still the
## coverage of the driving that really happened.
func _results_sheet() -> void:
	var before := float(_cutter().call("coverage"))
	_mvp.call("dev_complete_current_job")
	await _step(90)
	await _shot("results_sheet")
	print("[WORKMANSHIP PROBE] sheet shown with coverage %.2f" % before)
	_check("the completion shortcut does not inflate the reading",
		absf(float(_cutter().call("coverage")) - before) < 0.001)


func _shot(file_name: String) -> void:
	if _shot_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("%s/%s.png" % [_shot_dir, file_name])


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passes += 1
		print("[WORKMANSHIP PROBE] %s: PASS" % label)
	else:
		_failures += 1
		printerr("[WORKMANSHIP PROBE] %s: FAIL %s" % [label, detail])


func _step(frames: int = 1) -> void:
	for i in frames:
		await get_tree().process_frame
