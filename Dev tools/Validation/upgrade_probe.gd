extends Node
## DEVELOPMENT ONLY. PROVES that upgrades change the machine, in the real
## mowing scene, by DRIVING it.
##
##   godot --headless --path <project> "res://Dev tools/Validation/Upgrade Probe.tscn" \
##     -- "--save-root=../Test User Data/<dir>"
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS SEPARATELY FROM `Economy Test`
## ---------------------------------------------------------------------------
##
## `Economy Test` asserts that `MowerUpgrades.speed_multiplier("rider")` returns
## a bigger number after a purchase. That is a statement about a dictionary.
##
## It is NOT a statement about the mower. A controller could ignore the
## multiplier entirely, or apply it to the wrong term, or apply it twice, and
## every one of those assertions would still pass. The only way to know the
## machine got faster is to press the throttle and measure how far it went.
##
## So this probe holds real `Input` actions down, in the real scene, through the
## real controllers, and measures displacement per second and fuel burned per
## second — stock, then upgraded, from the same start under the same conditions.

## Seconds of held throttle per measurement.
const DRIVE_SECONDS := 1.6
## Frames to let the scene settle after a mower swap or a teleport.
const SETTLE_FRAMES := 40

var _pass := 0
var _fail := 0
var _rows: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	GameSession.start_new_game()
	await _await_screen(ACAGameSession.Screen.TOWN)

	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(1)
		await _settle(10)
		offers = JobManager.available_jobs()
	if offers.is_empty():
		printerr("[UPGRADE] no offers; cannot enter the mowing scene")
		get_tree().quit(1)
		return
	JobManager.accept_job(offers[0].id)
	JobManager.begin_new_job(offers[0].id)
	await _await_screen(ACAGameSession.Screen.MOWING)
	await _settle(60)

	var scene := get_tree().current_scene
	GameSession.add_money(500000)

	for mower_id: String in ACAMowerUpgrades.MOWER_IDS:
		await _test_speed(scene, mower_id)
	for mower_id: String in ["rider", "powered"]:
		await _test_fuel(scene, mower_id)

	print("\n[UPGRADE] ---- measured in the real scene ----")
	for row: Array in _rows:
		print("[UPGRADE] %-28s stock %8.3f   upgraded %8.3f   %+6.1f%%"
			% [row[0], row[1], row[2], row[3]])

	print("[UPGRADE PROBE] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ======================================================================= speed

func _test_speed(scene: Node, mower_id: String) -> void:
	MowerUpgrades.reset_all()
	await _select_mower(scene, mower_id)

	var stock := await _measure_speed(scene)

	# Max every category that moves this machine.
	for category: String in ACAMowerUpgrades.categories_for(mower_id):
		if String(ACAMowerUpgrades.CATEGORIES[category]["stat"]) == "speed":
			MowerUpgrades.dev_set_level(mower_id, category,
				ACAMowerUpgrades.max_level(category))
	var expected := MowerUpgrades.speed_multiplier(mower_id)

	var upgraded := await _measure_speed(scene)

	var change := (upgraded / maxf(stock, 0.001) - 1.0) * 100.0
	_rows.append(["%s — speed (u/s)" % mower_id, stock, upgraded, change])

	_check("Speed: %s actually moves (stock %.2f u/s)" % [mower_id, stock],
		stock > 1.0)
	_check("Speed: %s DRIVES FASTER upgraded (%.2f -> %.2f u/s, %+.1f%%)"
		% [mower_id, stock, upgraded, change], upgraded > stock * 1.05)
	# The measured gain should resemble the multiplier that was asked for. A
	# generous window: this is a physical body sliding through grass, not a
	# spreadsheet.
	var predicted := (expected - 1.0) * 100.0
	_check("Speed: %s gain (%.1f%%) resembles the asked-for multiplier (%.1f%%)"
		% [mower_id, change, predicted],
		absf(change - predicted) < maxf(predicted * 0.6, 8.0))
	MowerUpgrades.reset_all()


## Hold the throttle down and see how far it gets. Normalised by ELAPSED TIME,
## so a difference in frame rate between the two runs cannot masquerade as a
## difference in speed.
func _measure_speed(scene: Node) -> float:
	await _reset_scene(scene)
	var mower: Node3D = scene.get(&"current_mower")
	if mower == null:
		return 0.0

	var start_position := mower.global_position
	var start_time := Time.get_ticks_msec()
	Input.action_press(&"move_forward")
	while Time.get_ticks_msec() - start_time < int(DRIVE_SECONDS * 1000.0):
		await get_tree().process_frame
	Input.action_release(&"move_forward")
	var elapsed := float(Time.get_ticks_msec() - start_time) / 1000.0

	# Horizontal only. A mower settling on to its wheels is not travel.
	var moved := mower.global_position - start_position
	moved.y = 0.0
	await _settle(6)
	return moved.length() / maxf(elapsed, 0.001)


# ======================================================================== fuel

func _test_fuel(scene: Node, mower_id: String) -> void:
	MowerUpgrades.reset_all()
	await _select_mower(scene, mower_id)

	var stock := await _measure_burn(scene)
	MowerUpgrades.dev_set_level(mower_id, "fuel_system",
		ACAMowerUpgrades.max_level("fuel_system"))
	var expected := MowerUpgrades.fuel_multiplier(mower_id)
	var upgraded := await _measure_burn(scene)

	var change := (upgraded / maxf(stock, 0.00001) - 1.0) * 100.0
	_rows.append(["%s — fuel burn (units/s)" % mower_id, stock, upgraded, change])

	_check("Fuel: %s burns fuel at all (stock %.4f units/s)" % [mower_id, stock],
		stock > 0.0001)
	_check("Fuel: %s BURNS LESS upgraded (%.4f -> %.4f units/s, %+.1f%%)"
		% [mower_id, stock, upgraded, change], upgraded < stock * 0.95)
	var predicted := (expected - 1.0) * 100.0
	_check("Fuel: %s saving (%.1f%%) matches the asked-for multiplier (%.1f%%)"
		% [mower_id, change, predicted],
		absf(change - predicted) < maxf(absf(predicted) * 0.4, 6.0))
	MowerUpgrades.reset_all()


func _measure_burn(scene: Node) -> float:
	await _reset_scene(scene)
	MowerFuel.refuel_full()
	await _settle(4)

	var before := MowerFuel.fuel()
	var start_time := Time.get_ticks_msec()
	Input.action_press(&"move_forward")
	while Time.get_ticks_msec() - start_time < int(DRIVE_SECONDS * 1000.0):
		await get_tree().process_frame
	Input.action_release(&"move_forward")
	var elapsed := float(Time.get_ticks_msec() - start_time) / 1000.0
	return (before - MowerFuel.fuel()) / maxf(elapsed, 0.001)


# ==================================================================== helpers

## Swap the mower the way the scene's own HUD does, so the probe exercises the
## real path rather than a private one.
func _select_mower(scene: Node, mower_id: String) -> void:
	if scene.has_method("_on_mvp_hud_mower_change_selected"):
		scene.call("_on_mvp_hud_mower_change_selected", mower_id)
	await _settle(SETTLE_FRAMES)


## Put the grass and the mower back, so both runs of a pair start identical.
## Without this the second run drives through a lane the first one already cut,
## and the measurement compares two different worlds.
func _reset_scene(scene: Node) -> void:
	if scene.has_method("_on_mvp_hud_reset_map_and_location"):
		scene.call("_on_mvp_hud_reset_map_and_location")
	await _settle(SETTLE_FRAMES)


func _await_screen(screen: int) -> void:
	var guard := 0
	while GameSession.current_screen() != screen and guard < 600:
		await get_tree().process_frame
		guard += 1
	await _settle(6)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[UPGRADE] %s: PASS" % label)
	else:
		_fail += 1
		printerr("[UPGRADE] %s: FAIL" % label)
