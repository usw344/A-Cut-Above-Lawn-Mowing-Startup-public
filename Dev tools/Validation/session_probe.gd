extends Node
## DEVELOPMENT. THE INTEGRATED SESSION.
##
## Everything the final refinement pass touched, exercised together in one run
## of the real game, from the real entry point, through the real screens - not
## through a harness that stands in for them.
##
##   Main Menu  ->  new game  ->  Town
##   Super Debugger (H): money, weather, day, completed contracts
##   accept a contract  ->  Mowing  ->  drive  ->  cut  ->  complete
##   back to Town, with the progression the debugger created still there
##
## It is mounted OVER the running game by `runner_boot`, so the game boots the
## way a player's copy does. Screenshots at every stage.

var _passes := 0
var _failures := 0
var _shot_dir: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shot_dir = arg.substr(8)
			DirAccess.make_dir_recursive_absolute(_shot_dir)
	_run.call_deferred()


func _run() -> void:
	print("\n============ SESSION PROBE ============")
	await _step(30)
	await _menu()
	await _town()
	await _contract()
	print("[SESSION] %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# ======================================================================= menu

## The probe is mounted on /root by `runner_boot`, which means the boot shim's
## own scene is the current one; so the first thing it does is load the real
## entry point named in `project.godot` - by path, not by a copy of it - and
## check the game arrives there.
func _menu() -> void:
	var entry := String(ProjectSettings.get_setting("application/run/main_scene"))
	_check("the entry point is the Main Menu Screen",
		entry.ends_with("Main Menu Screen.tscn"))
	get_tree().change_scene_to_file(entry)
	await _step(60)
	var scene := get_tree().current_scene
	_check("the game reaches the Main Menu",
		scene != null and scene.scene_file_path == entry)
	await _shot("session_1_main_menu")


# ======================================================================= town

func _town() -> void:
	GameSession.start_new_game()
	await _wait_for_screen(ACAGameSession.Screen.TOWN)
	await _step(20)
	_check("a new game reaches Business Town",
		GameSession.current_screen() == ACAGameSession.Screen.TOWN)

	var layer := get_tree().current_scene.get_node_or_null(^"Pause Layer") as ACAPauseLayer
	if layer == null:
		_fail("the pause layer is mounted in Town")
		return
	var dbg: ACADeveloperDebugger = layer.developer_debugger()

	# ---- H, the real key, through the real binding
	await _press(KEY_H)
	_check("H opens the Super Debugger in Town", dbg.is_open())
	_check("the cursor is usable with it open",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_VISIBLE)

	# ---- reach a later game with it
	var day_before := WorldClock.day_number()
	var contracts_before: int = Business.contracts_completed()

	dbg.set_balance(48000)
	dbg.set_weather("Clearing")
	dbg.advance_days(7)
	dbg._day_field.text = str(WorldClock.day_number() + 21)
	dbg._apply_day_field()
	dbg.add_completed_contracts(25)
	await _step(30)

	_check("money reached the figure asked for (%s)"
		% UITheme.format_money(GameSession.money()), GameSession.money() == 48000)
	_check("the sky is the one asked for (%s)" % WorldClock.weather_preset(),
		WorldClock.weather_preset() == "Clearing")
	_check("the world is 28 days further on (day %d -> %d)"
		% [day_before, WorldClock.day_number()],
		WorldClock.day_number() == day_before + 28)
	_check("25 contracts are on the books (%d -> %d)"
		% [contracts_before, Business.contracts_completed()],
		Business.contracts_completed() == contracts_before + 25)

	# ---- and the progression that depends on them actually moved
	_check("reputation moved with the work", Business.reputation() > 0.0)
	_check("the business has reviews to show",
		Business.recent_reviews(5).size() > 0)
	_check("regional presence was recorded",
		Territory.contracts_completed_in(Territory.active_region()) > 0)
	print("[SESSION]   reputation %.1f, %d reviews, %d contracts, day %d, $%d" % [
		Business.reputation(), Business.recent_reviews(5).size(),
		Business.contracts_completed(), WorldClock.day_number(),
		GameSession.money()])

	# THE TOWN HUD REFRESHES ITS CALENDAR AT 2 Hz, deliberately, to keep the town
	# off the per-frame path. Photographed sooner than that, the strip still
	# reads the old day and the shot libels a panel that is correct.
	await _seconds(1.2)
	await _shot("session_2_super_debugger")
	await _press(KEY_H)
	_check("H closes it again", not dbg.is_open())
	await _step(10)
	await _shot("session_3_town_after")


# =================================================================== contract

func _contract() -> void:
	var job := JobManager.commission_offer(4242)
	if job == null:
		_fail("a contract could be commissioned")
		return
	JobManager.accept_job(job.id)
	JobManager.begin_new_job(job.id)
	await _wait_for_screen(ACAGameSession.Screen.MOWING)
	await _step(30)
	_check("the contract opens the mowing scene",
		GameSession.current_screen() == ACAGameSession.Screen.MOWING)

	# Skip the intro card the way a player does.
	await _press(KEY_SPACE)
	await _step(120)

	var mvp := get_tree().current_scene
	var mower := mvp.get("current_mower") as CharacterBody3D
	var lawn: ACALawn = mvp.get("property_node").lawn()
	var cut_audio = mvp.get("cut_audio")
	var env = mvp.get("environment_audio")

	_check("the machine is on the property", mower != null)
	_check("the cutting audio is bound", cut_audio != null)
	_check("the environment audio is mounted", env != null)

	# ---- drive, and cut something
	var before := lawn.mowed_item_count()
	var start := mower.global_position
	Input.action_press("move_forward")
	var load_peak := 0.0
	var camera_roll := 0.0
	var camera := mower.get_node(^"Camera3D") as Camera3D
	var t := 0.0
	while t < 4.0:
		await get_tree().physics_frame
		t += 1.0 / 576.0
		if cut_audio != null:
			load_peak = maxf(load_peak, float(cut_audio.call(&"load_amount")))
		camera_roll = maxf(camera_roll, absf(rad_to_deg(camera.rotation.z)))
	Input.action_release("move_forward")
	await _step(30)

	var moved := start.distance_to(mower.global_position)
	_check("the machine drove (%.1f units)" % moved, moved > 8.0)
	_check("it cut grass (%d cells)" % (lawn.mowed_item_count() - before),
		lawn.mowed_item_count() > before)
	_check("the blades loaded the machine (%.2f)" % load_peak, load_peak > 0.25)
	_check("the horizon stayed level through it (%.2f deg)" % camera_roll,
		camera_roll <= 0.05)
	await _shot("session_4_mowing")

	# ---- and a turn, which is what used to be unpleasant
	Input.action_press("move_forward")
	var turn_roll := 0.0
	t = 0.0
	while t < 2.5:
		mower.set("target_body_yaw", mower.rotation.y + 0.9)
		await get_tree().physics_frame
		t += 1.0 / 576.0
		turn_roll = maxf(turn_roll, absf(rad_to_deg(camera.rotation.z)))
	Input.action_release("move_forward")
	await _step(20)
	_check("the horizon stayed level through a hard turn (%.2f deg)" % turn_roll,
		turn_roll <= 0.05)
	await _shot("session_5_turning")

	# ---- finish it through the real completion path
	var money_before: int = GameSession.money()
	var contracts_before: int = Business.contracts_completed()
	var settled: bool = GameSession.complete_current_job(1.0, 120.0, {
		"collected_kg": 999.0, "pattern_met": true, "pattern_score": 0.8,
		"protected_damage": 0.0, "ran_dry": false, "fuel_used": 1.0,
	})
	await _step(30)
	_check("the contract settled", settled)
	_check("it paid", GameSession.money() > money_before)
	_check("it went on the books",
		Business.contracts_completed() == contracts_before + 1)
	await _shot("session_6_results")


# ==================================================================== helpers

func _press(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	await _step(4)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await _step(6)


func _wait_for_screen(screen: int) -> void:
	var frames := 0
	while frames < 3600:
		if GameSession.current_screen() == screen \
				and not GameSession.is_changing_scene():
			return
		await get_tree().process_frame
		frames += 1


func _shot(file_name: String) -> void:
	if _shot_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("%s/%s.png" % [_shot_dir, file_name])


func _seconds(amount: float) -> void:
	var t := 0.0
	while t < amount:
		await get_tree().process_frame
		t += get_process_delta_time()


func _step(frames: int = 1) -> void:
	for _i in frames:
		await get_tree().process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_passes += 1
		print("[SESSION] %s: PASS" % label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	printerr("[SESSION] %s: FAIL" % label)
