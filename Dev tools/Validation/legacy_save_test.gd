extends Node
## DEVELOPMENT ONLY. Loads REAL saves written before any of this pass existed and
## checks that they still work — and that the economy they were played under has
## not been moved underneath them.
##
##   godot --headless --path . "res://Dev tools/Validation/Legacy Save Test.tscn" \
##     -- "--save-root=<a COPY of Test User Data/baseline-saves>"
##
## ---------------------------------------------------------------------------
## WHY REAL SAVES AND NOT SYNTHESISED ONES
## ---------------------------------------------------------------------------
## `Save Test` writes a save with this build and reads it back, which proves the
## round trip and nothing about compatibility. `Economy Test` hands
## `from_save_dict()` a dictionary with no `difficulty` key, which is closer but
## is still a dictionary this build made up.
##
## These are files on disk from 2026-08-20. They were written before difficulty
## existed, before the boundary existed, before a pond was compulsory and before
## the lawn had anything solid on it. One of them
## (`test_active_job.json`) is a MID-CONTRACT save, so loading it rebuilds a
## property from parameters that predate three of those things and puts a machine
## back on to it.
##
## THIS TEST NEVER WRITES TO THE FILES IT READS. Point `--save-root` at a copy.
##
## PUBLIC API: None.

var _passes := 0
var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("=== LEGACY SAVE TEST ===")
	print("[LEGACY] save root: %s" % SaveService.storage_root())

	var saves := SaveService.list_saves()
	_check("the save root holds legacy saves (%d found)" % saves.size(),
		saves.size() >= 3)
	if saves.is_empty():
		_finish()
		return

	for entry in saves:
		var slot := String(entry["slot"])
		# The .bak files are not slots and list_saves() does not return them.
		if slot.ends_with(".bak"):
			continue
		await _test_slot(slot)

	_finish()


func _finish() -> void:
	print("===========================================")
	print("[LEGACY SAVE TEST] %d passed, %d failed" % [_passes, _failures])
	print("===========================================")
	get_tree().quit(1 if _failures > 0 else 0)


func _test_slot(slot: String) -> void:
	print("[LEGACY] --- %s" % slot)
	var before := _read_raw(slot)
	var had_difficulty: bool = (before.get("session", {}) as Dictionary).has("difficulty")
	var expected_money := int((before.get("profile", {}) as Dictionary).get("money", -1))
	var was_mid_job := before.has("mowing")

	# WAIT FOR THE PREVIOUS LOAD TO FINISH FIRST. `GameSession._change_scene()`
	# refuses while a transition is still covering the screen, so loading five
	# saves back to back silently drops the navigation on all but the first -
	# which is what the first run of this test reported as a mid-job save
	# failing to resume.
	await _wait_for_idle()

	var loaded: bool = SaveService.load_game(slot)
	_check("%s: loads" % slot, loaded)
	if not loaded:
		return
	await _wait_for_idle()
	await _settle(40)

	# THE POINT OF THE WHOLE TEST.
	_check("%s: had no difficulty field (%s)" % [slot, not had_difficulty],
		not had_difficulty)
	_check("%s: loads as the legacy profile (got %s)"
		% [slot, GameSession.difficulty()],
		GameSession.difficulty() == ACADifficulty.LEGACY_ID)
	_check("%s: the shipped fuel price is restored ($%.2f)"
		% [slot, Economy.base_fuel_price()],
		is_equal_approx(Economy.base_fuel_price(), ACAEconomyManager.BASE_FUEL_PRICE))
	_check("%s: the shipped tank length is restored (%.0f s)"
		% [slot, MowerFuel.full_tank_driving_seconds()],
		is_equal_approx(MowerFuel.full_tank_driving_seconds(),
			ACAMowerFuel.FULL_TANK_DRIVING_SECONDS))
	if expected_money >= 0:
		_check("%s: the balance is untouched ($%d)" % [slot, GameSession.money()],
			GameSession.money() == expected_money)

	if not was_mid_job:
		return

	# A MID-CONTRACT SAVE. It rebuilds a property that now has a fence round it, a
	# pond in it and rocks on it that it did not have when it was written, and it
	# puts the machine back where the player left it. Neither of those is allowed
	# to strand the player.
	await _settle(60)
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method(&"property"):
		_check("%s: resumed into the mowing scene" % slot, false)
		return
	var property: ACAProperty = scene.call(&"property")
	var mower := scene.get(&"current_mower") as Node3D
	_check("%s: resumed into the mowing scene" % slot,
		property != null and property.is_built() and mower != null)
	if property == null or not property.is_built() or mower == null:
		return

	var boundary := property.boundary()
	var at := mower.global_position
	_check("%s: the property rebuilt with a boundary" % slot, boundary != null)
	if boundary != null:
		var outside := boundary.distance_outside(at.x, at.z)
		_check("%s: the machine came back INSIDE the fence (%.2f units outside)"
			% [slot, outside], outside <= 1.0)

	var pond: ACAPondFeature = null
	var obstacles: ACALawnObstacles = null
	for f in property.features().features():
		if f is ACAPondFeature:
			pond = f
		elif f is ACALawnObstacles:
			obstacles = f
	_check("%s: the rebuilt property has a pond" % slot, pond != null)
	if pond != null:
		var ground := property.ground_height_at(at.x, at.z)
		var in_water: bool = pond.shore_factor_at(at.x, at.z) > 0.0 \
			and ground < pond.water_world_height()
		_check("%s: the machine did not come back in the water" % slot, not in_water)

	if obstacles != null:
		var inside_rock := false
		for o: Dictionary in obstacles.obstacles():
			if Vector2(at.x, at.z).distance_to(o["position"] as Vector2) \
					< float(o["radius"]):
				inside_rock = true
		_check("%s: the machine did not come back inside a rock" % slot,
			not inside_rock)

	# And the contract is still finishable, which is the thing a player would
	# actually lose if any of the above had gone wrong.
	var lawn := property.lawn()
	_check("%s: the resumed contract still has mowable ground left" % slot,
		lawn != null and lawn.total_item_count() > 0
			and lawn.mowed_item_count() <= lawn.total_item_count())
	print("[LEGACY] %s resumed at %.1f%% of %d mowable cells"
		% [slot, lawn.mowed_fraction() * 100.0, lawn.total_item_count()])


# =================================================================== helpers

func _read_raw(slot: String) -> Dictionary:
	var path := "%s/%s.json" % [SaveService.storage_root(), slot]
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


## Block until no scene transition is in flight.
func _wait_for_idle(timeout_frames: int = 600) -> void:
	for _i in timeout_frames:
		if not GameSession.is_changing_scene():
			await _settle(3)
			if not GameSession.is_changing_scene():
				return
		await get_tree().process_frame


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _check(what: String, ok: bool) -> void:
	if ok:
		_passes += 1
		print("[LEGACY SAVE TEST] %s: ok" % what)
	else:
		_failures += 1
		print("[LEGACY SAVE TEST] %s: FAIL" % what)
