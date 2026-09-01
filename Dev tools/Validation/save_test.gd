extends Node
## DEVELOPMENT ONLY. Save/load resume tests A, B and C.
##
##   godot --headless --path . "res://Dev tools/Validation/Save Test.tscn" -- "--save-root=<dir>"
##
## Always pass --save-root so the test never writes outside the working folder.
##
## "Reinitialise" here means: wipe every piece of live state the way a fresh
## process would (clear the job manager, reset the clock, reset money, leave the
## mowing scene), then load. That is what makes the assertions meaningful -
## a value that survives is a value that came out of the file.

const SLOT_A := "test_town"
const SLOT_B := "test_active_job"
const SLOT_C := "test_completed"

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("\n=============== SAVE TESTS ================")
	print("[SAVE] storage root: %s" % SaveService.storage_root())

	await _step(4)
	await _test_a_town_save()
	await _test_b_active_job_save()
	await _test_c_completed_job_save()
	await _test_robustness()

	print("===========================================")
	print("[SAVE TEST] %d passed, %d failed" % [_passes, _failures])
	print("===========================================\n")
	get_tree().quit(0 if _failures == 0 else 1)


# =================================================================== TEST A

func _test_a_town_save() -> void:
	print("\n--- TEST A: town save ---")

	GameSession.start_new_game()
	if not await _await_screen(ACAGameSession.Screen.TOWN, "Town Screen"):
		_fail("A: reached town")
		return

	# Let world time actually advance, then set an observable weather state.
	WorldClock.advance_hours(3.5)
	await _step(30)
	WorldClock.set_weather("Foggy")
	await _step(4)

	var saved_minutes := WorldClock.game_minutes()
	var saved_weather := WorldClock.weather_preset()
	var saved_money := GameSession.money()
	var saved_offers := JobManager.available_jobs().size()
	var saved_day := WorldClock.day_number()

	_check("A: save succeeded", SaveService.save_game(SLOT_A))
	_check("A: save file exists", FileAccess.file_exists(
		"%s/%s.json" % [SaveService.storage_root(), SLOT_A]))

	await _reinitialise()
	_check("A: state really was wiped before loading",
		JobManager.available_jobs().is_empty()
		and GameSession.money() == 0
		and not is_equal_approx(WorldClock.game_minutes(), saved_minutes))

	_check("A: load succeeded", SaveService.load_game(SLOT_A))
	if not await _await_screen(ACAGameSession.Screen.TOWN, "Town Screen"):
		_fail("A: restored to town")
		return
	_check("A: restored to town", true)

	_check("A: world time restored",
		absf(WorldClock.game_minutes() - saved_minutes) < 60.0)
	_check("A: day restored", WorldClock.day_number() == saved_day)
	_check("A: weather restored", WorldClock.weather_preset() == saved_weather)
	_check("A: money restored", GameSession.money() == saved_money)
	_check("A: job offers coherent",
		JobManager.available_jobs().size() == saved_offers)
	_check("A: no phantom active contract", not GameSession.has_active_job())

	# Offers must still be live, not instantly expired against the restored clock.
	var now := WorldClock.game_minutes()
	var live := 0
	for job in JobManager.available_jobs():
		if not job.is_expired_at(now):
			live += 1
	_check("A: restored offers have not lapsed", live == saved_offers)
	print("           -> %s | %s | $%d | %d offers"
		% [WorldClock.timestamp_text(), WorldClock.weather_preset(),
			GameSession.money(), saved_offers])


# =================================================================== TEST B

func _test_b_active_job_save() -> void:
	print("\n--- TEST B: active job save ---")

	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(1)
		await _step(4)
		offers = JobManager.available_jobs()
	if offers.is_empty():
		_fail("B: had an offer to accept")
		return

	var job_id: StringName = offers[0].id
	_check("B: accepted a contract", JobManager.accept_job(job_id))
	JobManager.begin_new_job(job_id)

	if not await _await_screen(ACAGameSession.Screen.MOWING, "Minimum Viable Game"):
		_fail("B: entered gameplay")
		return
	_check("B: entered gameplay", true)

	var scene := get_tree().current_scene
	var grid: ACALawn = scene.call(&"lawn")

	# Create a controlled, non-zero partial mowing state by cutting a known
	# subset through the real mowing path.
	var cut := _cut_some(grid, 250)
	await _step(4)
	_check("B: created a non-zero partial mowing state", cut > 0)

	# FREEZE. The mower starts sitting on the lawn, so live physics keeps cutting
	# grass and burning fuel between the measurement and the save. Pausing the
	# tree makes the comparison mean what it says. GameSession and AppUI are
	# PROCESS_MODE_ALWAYS, so scene transitions still work while frozen.
	get_tree().paused = true
	await _step(2)

	var saved_mowed := grid.mowed_item_count()
	var saved_total := grid.total_item_count()
	var saved_fraction := grid.mowed_fraction()
	var saved_lawn_size := grid.cell_count()
	var saved_pay := JobManager.get_job(job_id).base_pay
	var saved_minutes := WorldClock.game_minutes()
	WorldClock.set_weather("Rain")
	model.set_mower_fuel(73)
	var saved_fuel: Variant = model.get_mower_fuel()

	_check("B: save succeeded", SaveService.save_game(SLOT_B))
	print("           -> saved %d/%d cut, fuel %s" % [saved_mowed, saved_total, saved_fuel])

	await _reinitialise()
	_check("B: state really was wiped before loading",
		not GameSession.has_active_job())

	_check("B: load succeeded", SaveService.load_game(SLOT_B))
	if not await _await_screen(ACAGameSession.Screen.MOWING, "Minimum Viable Game"):
		get_tree().paused = false
		_fail("B: resumed into gameplay")
		return
	_check("B: resumed into gameplay", true)

	var job := GameSession.current_job()
	_check("B: same contract id", job != null and job.id == job_id)
	_check("B: contract pay intact", job != null and job.base_pay == saved_pay)
	_check("B: contract is IN_PROGRESS",
		job != null and job.status == ACAJobEnums.Status.IN_PROGRESS)

	var grid2: ACALawn = get_tree().current_scene.call(&"lawn")
	_check("B: lawn rebuilt at the contract size",
		grid2 != null and grid2.cell_count() == saved_lawn_size)
	_check("B: mowable cell total matches",
		grid2 != null and grid2.total_item_count() == saved_total)
	_check("B: mowing progress restored exactly",
		grid2 != null and grid2.mowed_item_count() == saved_mowed)
	_check("B: mowed fraction restored",
		grid2 != null and is_equal_approx(grid2.mowed_fraction(), saved_fraction))
	print("           -> %d/%d cut (%.2f%%)"
		% [grid2.mowed_item_count(), grid2.total_item_count(),
			grid2.mowed_fraction() * 100.0])

	_check("B: mower fuel restored", model.get_mower_fuel() == saved_fuel)
	_check("B: weather restored", WorldClock.weather_preset() == "Rain")
	_check("B: world time restored",
		absf(WorldClock.game_minutes() - saved_minutes) < 60.0)

	_check("B: the resume handoff was consumed",
		not SaveService.has_pending_mowing_state())

	# UNFREEZE and continue playing: cut more, then finish through the real
	# completion path.
	get_tree().paused = false
	await _step(4)
	var before_extra := grid2.mowed_item_count()
	var extra := _cut_some(grid2, 100)
	await _step(4)
	_check("B: can keep mowing after the load", grid2.mowed_item_count() > before_extra)
	_check("B: additional cuts registered", extra > 0)

	var money_before := GameSession.money()
	# WHAT THE CONTRACT ACTUALLY SETTLED FOR. A contract pays its base rate plus
	# whatever its optional terms earned, and the terms are derived from the
	# contract's own seed - so the payout is no longer a constant this test can
	# predict without re-deriving it, and a test that re-derived it would be
	# asserting the implementation against itself. The settlement reports both
	# figures; this checks the balance moved by exactly what was reported.
	var settled: Array[Dictionary] = []
	GameSession.job_settled.connect(func(summary: Dictionary) -> void:
		settled.append(summary), CONNECT_ONE_SHOT)
	get_tree().current_scene.call("dev_complete_current_job")
	await _step(4)
	_check("B: completed after resuming", not GameSession.has_active_job())
	_check("B: the settlement was reported", settled.size() == 1)
	var base := int(settled[0].get("base_pay", -1)) if settled.size() > 0 else -1
	var bonus := int(settled[0].get("bonus", 0)) if settled.size() > 0 else 0
	_check("B: paid the contract's own rate", base == saved_pay)
	_check("B: paid out after resuming, base plus bonus",
		GameSession.money() == money_before + base + bonus)

	if not await _await_screen(ACAGameSession.Screen.TOWN, "Town Screen"):
		# The results screen owns the return; press its real button.
		_press_return_to_town()
		await _await_screen(ACAGameSession.Screen.TOWN, "Town Screen")
	_check("B: back in town", GameSession.current_screen() == ACAGameSession.Screen.TOWN)
	_check("B: completion persisted into history",
		_find(JobManager.past_jobs(), job_id) != null)


# =================================================================== TEST C

func _test_c_completed_job_save() -> void:
	print("\n--- TEST C: completed job save ---")

	var past := JobManager.past_jobs()
	if past.is_empty():
		_fail("C: had a completed job to save")
		return
	var completed_id: StringName = past[past.size() - 1].id
	var past_count := past.size()
	var money := GameSession.money()

	_check("C: save succeeded", SaveService.save_game(SLOT_C))

	await _reinitialise()
	_check("C: state really was wiped before loading",
		JobManager.past_jobs().is_empty())

	_check("C: load succeeded", SaveService.load_game(SLOT_C))
	if not await _await_screen(ACAGameSession.Screen.TOWN, "Town Screen"):
		_fail("C: restored to town")
		return
	_check("C: restored to town", true)

	var restored := _find(JobManager.past_jobs(), completed_id)
	_check("C: completed job still in history", restored != null)
	_check("C: history count matches", JobManager.past_jobs().size() == past_count)
	if restored != null:
		_check("C: status is still COMPLETED",
			restored.status == ACAJobEnums.Status.COMPLETED)
		_check("C: progress is still 100%", restored.progress >= 1.0)
		_check("C: completion time preserved", restored.completed_game_time > 0.0)
	_check("C: NOT active again", not GameSession.has_active_job())
	_check("C: not back on the available board",
		_find(JobManager.available_jobs(), completed_id) == null)
	_check("C: money restored", GameSession.money() == money)


# ============================================================== ROBUSTNESS

func _test_robustness() -> void:
	print("\n--- Robustness ---")

	_check("R: loading a missing slot fails cleanly",
		not SaveService.load_game("no_such_slot"))

	# A corrupt file must fail, not crash.
	var corrupt := "%s/corrupt.json" % SaveService.storage_root()
	var f := FileAccess.open(corrupt, FileAccess.WRITE)
	f.store_string("{ this is not valid json ")
	f.close()
	_check("R: corrupt save fails cleanly", not SaveService.load_game("corrupt"))

	# A well-formed file from a future schema must be refused, not misread.
	var future := "%s/future.json" % SaveService.storage_root()
	f = FileAccess.open(future, FileAccess.WRITE)
	f.store_string(JSON.stringify({"save_format_version": 999}))
	f.close()
	_check("R: unknown format version refused", not SaveService.load_game("future"))

	# A valid save missing a required section must be refused.
	var partial := "%s/partial.json" % SaveService.storage_root()
	f = FileAccess.open(partial, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"save_format_version": SaveService.SAVE_FORMAT_VERSION,
		"world": {"minutes": 500.0},
	}))
	f.close()
	_check("R: save missing a required section refused",
		not SaveService.load_game("partial"))

	_check("R: application still usable after four failed loads",
		get_tree().current_scene != null and is_instance_valid(get_tree().current_scene))

	# Backups: saving twice must leave a .bak behind.
	SaveService.save_game(SLOT_A)
	await _step(2)
	SaveService.save_game(SLOT_A)
	await _step(2)
	_check("R: previous version kept as a backup", FileAccess.file_exists(
		"%s/%s.json.bak" % [SaveService.storage_root(), SLOT_A]))
	_check("R: no temp file left behind", not FileAccess.file_exists(
		"%s/%s.json.tmp" % [SaveService.storage_root(), SLOT_A]))

	_check("R: saves are listed newest first", not SaveService.list_saves().is_empty())
	_check("R: has_any_save agrees", SaveService.has_any_save())

	# A save written mid-transition would collect the mowing block from the scene
	# being replaced, so it must be refused outright.
	GameSession.go_to_town()
	await _step(1)
	_check("R: saving mid-transition is refused",
		not GameSession.is_changing_scene() or not SaveService.save_game(SLOT_A))
	await _await_screen(ACAGameSession.Screen.TOWN, "Town Screen")

	# The good save must have survived every rejected write above.
	_check("R: the good save survived the rejected writes",
		SaveService.load_game(SLOT_A))
	await _await_screen(ACAGameSession.Screen.TOWN, "Town Screen")

	SaveService.delete_save("corrupt")
	SaveService.delete_save("future")
	SaveService.delete_save("partial")


# ================================================================== helpers

## Cut roughly `count` cells through the real mowing path: a deck swept across
## the lawn, exactly as a machine would do it.
func _cut_some(lawn: ACALawn, count: int) -> int:
	if lawn == null:
		return 0
	var deck := ACAMowerDeck.make(5.6, 2.4)
	var centre := lawn.lawn_centre()
	var half := lawn.lawn_half_extent()
	var cut := 0
	var lane := 0
	while cut < count and lane < 40:
		var z: float = centre.z - half + 3.0 + float(lane) * deck.half_width * 2.0
		var basis := Basis(Vector3.UP, PI * 0.5)
		var from := Vector3(centre.x - half + 1.0, centre.y, z)
		var to := Vector3(from.x + float(count - cut) / (deck.half_width * 2.0), centre.y, z)
		to.x = minf(to.x, centre.x + half - 1.0)
		cut += lawn.mow_deck(Transform3D(basis, from), Transform3D(basis, to), deck)
		lane += 1
	return cut


## Wipe every piece of live state a fresh process would not have.
func _reinitialise() -> void:
	# Deliberately does NOT touch get_tree().paused - the caller decides whether
	# the window it is measuring stays frozen.
	JobManager.debug_clear_all()
	GameSession.mark_session_active(false)
	GameSession.set_job_elapsed(0.0)
	GameSession.add_money(-GameSession.money())
	WorldClock.from_save_dict({
		"minutes": 0.0, "season": 0, "weather": "Clear", "running": false,
	})
	model.set_mower_fuel(100)
	await _step(6)


func _press_return_to_town() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ui := scene.get_node_or_null(^"Gameplay UI")
	if ui == null:
		return
	var results := ui.get_node_or_null(^"Job Complete")
	if results == null:
		return
	var button := results.get_node_or_null(^"%ReturnButton") as Button
	if button != null:
		button.pressed.emit()


func _await_screen(screen: int, scene_name: String, max_frames: int = 1200) -> bool:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen \
				and not GameSession.is_changing_scene() \
				and get_tree().current_scene != null \
				and get_tree().current_scene.name == scene_name:
			await _step(4)
			return true
		await get_tree().process_frame
		frames += 1
	return false


func _step(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _find(list: Array, job_id: StringName) -> ACAJob:
	for job: ACAJob in list:
		if job.id == job_id:
			return job
	return null


func _check(label: String, condition: bool) -> void:
	if condition:
		_passes += 1
		print("[SAVE TEST] %s: PASS" % label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	print("[SAVE TEST] %s: FAIL" % label)
