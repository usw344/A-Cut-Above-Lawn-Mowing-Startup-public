extends Node
## Probe for the SUPER DEBUGGER (day, weather, completed contracts, money).
##
## Windowed run: drives REAL H key events through Input.parse_input_event so the
## `_unhandled_key_input` binding itself is exercised, and screenshots the panel.

var _passes: int = 0
var _failures: int = 0
var _shot_dir: String = "user://debugger_shots"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shot_dir = arg.substr(8)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	_run.call_deferred()


func _run() -> void:
	print("\n============ DEBUGGER PROBE ============")
	await _step(4)
	await _town()
	await _mowing()
	print("[DEBUGGER PROBE] %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## A real key press, through the real input pipeline.
func _press_h() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_H
	down.physical_keycode = KEY_H
	down.pressed = true
	Input.parse_input_event(down)
	await _step(3)
	var up := InputEventKey.new()
	up.keycode = KEY_H
	up.physical_keycode = KEY_H
	up.pressed = false
	Input.parse_input_event(up)
	await _step(3)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("%s/%s.png" % [_shot_dir, file_name])


func _town() -> void:
	GameSession.start_new_game()
	await _step(8)
	await _wait_for_screen(ACAGameSession.Screen.TOWN)
	await _step(10)

	var layer := get_tree().current_scene.get_node_or_null(^"Pause Layer") as ACAPauseLayer
	_check("Town: pause layer present", layer != null)
	if layer == null:
		return
	var dbg: ACADeveloperDebugger = layer.developer_debugger()
	_check("Town: debugger mounted", dbg != null)
	_check("Town: debugger hidden on launch", not dbg.is_open())
	_check("Town: no mouse hold before opening", not AppUI.is_mouse_held())

	await _press_h()
	_check("Town: REAL H KEY opens the debugger", dbg.is_open())
	_check("Town: cursor usable while open",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_VISIBLE)

	# Weather goes through WorldClock.
	for preset in WorldClock.WEATHER_PRESETS:
		dbg.set_weather(preset)
		if WorldClock.weather_preset() != preset:
			_fail("Town: weather preset %s applied" % preset)
			break
	_check("Town: every WorldClock preset applies", WorldClock.weather_preset() ==
		WorldClock.WEATHER_PRESETS[WorldClock.WEATHER_PRESETS.size() - 1])
	_check("Town: debugger builds a button per preset",
		dbg._weather_buttons.size() == WorldClock.WEATHER_PRESETS.size())

	# A weather button pressed as a real button, not through the API.
	dbg.set_weather("Clear")
	var rain_button: Button = dbg._weather_buttons["Rain"]
	rain_button.pressed.emit()
	await _step()
	_check("Town: weather BUTTON reaches WorldClock",
		WorldClock.weather_preset() == "Rain")

	# Money goes through GameSession.
	dbg.set_balance(5000)
	_check("Town: balance set upward", GameSession.money() == 5000)
	dbg.set_balance(250)
	_check("Town: balance set downward", GameSession.money() == 250)
	dbg.adjust_balance(1000)
	_check("Town: +$1,000 quick control", GameSession.money() == 1250)
	dbg.adjust_balance(-100)
	_check("Town: -$100 quick control", GameSession.money() == 1150)
	dbg.set_balance(-9999)
	_check("Town: money cannot go negative", GameSession.money() == 0)
	dbg.adjust_balance(-500)
	_check("Town: quick subtract cannot go negative", GameSession.money() == 0)

	# SET BALANCE as the field + button, the way it is actually used.
	dbg._amount_field.text = "1250"
	dbg._apply_field()
	await _step()
	_check("Town: SET BALANCE field applies", GameSession.money() == 1250)
	_check("Town: balance readout refreshes",
		dbg._balance.text == "Balance: $1,250")
	_check("Town: weather readout refreshes",
		dbg._current_weather.text == "Current: %s" % WorldClock.weather_preset())
	_check("Town: junk in the field changes nothing",
		_apply_junk(dbg) == 1250)

	await _day_and_contracts(dbg)

	await _shot("town_debugger_open")

	# Pause must still work with the debugger up.
	layer.open_pause()
	await _step()
	_check("Town: opening pause closes the debugger", not dbg.is_open())
	_check("Town: pause still pauses the tree", get_tree().paused)
	layer.close_pause()
	await _step()
	_check("Town: resume unpauses", not get_tree().paused)
	_check("Town: no stranded mouse hold after resume", not AppUI.is_mouse_held())

	await _press_h()
	_check("Town: H reopens after pause", dbg.is_open())
	await _press_h()
	_check("Town: REAL H KEY closes the debugger", not dbg.is_open())
	_check("Town: closing releases the mouse hold", not AppUI.is_mouse_held())


## ------------------------------------------------- day and contract controls
##
## The point of both is that the AUTHORITIES move, not that a label changed. So
## every assertion here reads WorldClock or Business, never the panel, except
## the two that are specifically about the readouts.
func _day_and_contracts(dbg: ACADeveloperDebugger) -> void:
	var day_before := WorldClock.day_index()
	var minutes_before := WorldClock.game_minutes()

	# `day_changed` ONCE PER DAY CROSSED is the whole reason these are walked
	# rather than assigned: Business and Agreements do one day's work per call.
	var emitted: Array[int] = []
	var tally := func(d: int) -> void: emitted.append(d)
	WorldClock.day_changed.connect(tally)

	dbg.advance_days(1)
	await _step()
	_check("Town: +1 DAY moves WorldClock", WorldClock.day_index() == day_before + 1)
	# The clock is RUNNING, so a few game minutes pass between the two reads.
	# What the jump promises is the TIME OF DAY, within that drift.
	var drift := absf(fposmod(WorldClock.game_minutes(), 1440.0)
		- fposmod(minutes_before, 1440.0))
	_check("Town: +1 DAY keeps the time of day", drift < 5.0)

	dbg.advance_days(7)
	await _step()
	_check("Town: +7 DAYS moves WorldClock", WorldClock.day_index() == day_before + 8)
	WorldClock.day_changed.disconnect(tally)
	_check("Town: day_changed fired once per day crossed", emitted.size() == 8)

	# SET DAY, through the field and the button, the way it is used.
	var target := WorldClock.day_number() + 12
	dbg._day_field.text = str(target)
	dbg._apply_day_field()
	await _step()
	_check("Town: SET DAY lands on the exact day", WorldClock.day_number() == target)
	_check("Town: day readout refreshes",
		dbg._day.text.begins_with("Day %d" % WorldClock.day_number()))

	# Backwards is refused rather than silently ignored.
	dbg._day_field.text = str(target - 5)
	dbg._apply_day_field()
	await _step()
	_check("Town: SET DAY backwards is refused", WorldClock.day_number() == target)
	_check("Town: refusing a past day says so", not dbg._day_note.text.is_empty())
	dbg._day_field.text = "not a day"
	dbg._apply_day_field()
	await _step()
	_check("Town: junk in the day field changes nothing",
		WorldClock.day_number() == target)

	# ------------------------------------------------------------- contracts
	var completed_before: int = Business.contracts_completed()
	var reputation_before: float = Business.reputation()
	var money_before: int = GameSession.money()
	var past_before: int = JobManager.past_jobs().size()

	dbg.add_completed_contracts(1)
	await _step()
	_check("Town: +1 COMPLETED reaches Business",
		Business.contracts_completed() == completed_before + 1)
	_check("Town: a synthetic contract is real business history",
		JobManager.past_jobs().size() == past_before + 1)
	_check("Town: a synthetic contract moves reputation",
		Business.reputation() > reputation_before)
	_check("Town: a synthetic contract pays NOTHING",
		GameSession.money() == money_before)

	dbg.add_completed_contracts(10)
	await _step()
	_check("Town: +10 COMPLETED settles ten",
		Business.contracts_completed() == completed_before + 11)
	_check("Town: contract readout refreshes",
		dbg._contracts.text == "Completed: %d" % Business.contracts_completed())
	_check("Town: ten contracts left the board clear",
		JobManager.current_jobs().is_empty())
	_check("Town: contracts still pay nothing in a batch",
		GameSession.money() == money_before)

	# The books the completion is supposed to reach besides the tally.
	_check("Town: reviews were posted", Business.recent_reviews(5).size() > 0)
	_check("Town: regional presence was recorded",
		Territory.contracts_completed_in(Territory.active_region()) > 0)


func _apply_junk(dbg: ACADeveloperDebugger) -> int:
	dbg._amount_field.text = "not a number"
	dbg._apply_field()
	return GameSession.money()


func _mowing() -> void:
	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(1)
		offers = JobManager.available_jobs()
	if offers.is_empty():
		_fail("Mowing: no contract available")
		return
	var job: ACAJob = offers[0]
	JobManager.accept_job(job.id)
	JobManager.begin_new_job(job.id)
	await _wait_for_screen(ACAGameSession.Screen.MOWING)
	await _step(20)

	var ui := get_tree().current_scene.get_node_or_null(^"Gameplay UI") as ACAGameplayUI
	_check("Mowing: gameplay UI present", ui != null)
	if ui == null:
		return
	var dbg: ACADeveloperDebugger = ui.developer_debugger()
	_check("Mowing: debugger mounted on the same class", dbg != null)
	_check("Mowing: debugger hidden on arrival", not dbg.is_open())
	_check("Mowing: cursor is captured before opening",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_CAPTURED)

	await _press_h()
	_check("Mowing: REAL H KEY opens the debugger", dbg.is_open())
	_check("Mowing: MOUSE BECOMES USABLE",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_VISIBLE)

	dbg._weather_buttons["Rain"].pressed.emit()
	await _step(4)
	_check("Mowing: weather change reaches WorldClock",
		WorldClock.weather_preset() == "Rain")
	dbg.set_balance(7777)
	_check("Mowing: money change reaches GameSession", GameSession.money() == 7777)

	await _shot("mowing_debugger_open")

	await _press_h()
	_check("Mowing: REAL H KEY closes the debugger", not dbg.is_open())
	_check("Mowing: CURSOR RETURNS TO CAPTURED MOWING",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	await _shot("mowing_debugger_closed")

	# The legacy HUD must not have come up with it.
	var mvp := get_tree().current_scene
	var hud: Node = mvp.get_node_or_null(^"CanvasLayer/MVP_HUD")
	_check("Mowing: legacy MVP HUD stayed hidden after H", hud != null and not hud.visible)
	_check("Mowing: legacy HUD helper still exists",
		mvp.has_method("dev_toggle_debug_hud"))

	# Mowing carries on: the machine still drives after the overlay closes.
	var mower: Node3D = mvp.get("current_mower")
	var before: Vector3 = mower.global_position
	Input.action_press("move_forward")
	await _step(40)
	Input.action_release("move_forward")
	await _step(6)
	_check("Mowing: the mower still drives after the debugger closes",
		mower.global_position.distance_to(before) > 0.05)


func _wait_for_screen(screen: int, max_frames: int = 1800) -> void:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen and not GameSession.is_changing_scene():
			return
		await get_tree().process_frame
		frames += 1
	_fail("Timed out waiting for screen %d" % screen)


func _step(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_passes += 1
		print("[DEBUGGER PROBE] %s: PASS" % label)
	else:
		_failures += 1
		printerr("[DEBUGGER PROBE] %s: FAIL" % label)


func _fail(label: String) -> void:
	_check(label, false)
