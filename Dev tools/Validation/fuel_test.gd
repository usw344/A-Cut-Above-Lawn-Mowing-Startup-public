extends Node
## DEVELOPMENT ONLY. The real mower fuel system (Milestone 9).
##
##   godot --headless --path <project> "res://Dev tools/Validation/Fuel Test.tscn" -- "--save-root=<dir>"
##
## What this suite is for: fuel used to be a per-PHYSICS-TICK counter that
## emptied a tank in about four seconds at this project's 576 Hz, and every
## controller then silently refilled it to 100. All three of those faults are
## behavioural, so they are asserted behaviourally here rather than by reading
## the source.
##
##   1  a powered mower consumes fuel
##   2  consumption is delta/TIME based, not per tick
##   3  fuel cannot go negative
##   4  zero fuel stops the blades  (no grass is cut)
##   5  zero fuel stops propulsion  (the mower does not move)
##   6  refuelling restores both
##   7  Auto Refuel OFF lets the tank actually reach zero and stay there
##   8  Auto Refuel ON refills once, AFTER empty - it is not a fuel lock
##   9  the production HUD gauge tracks the authoritative value
##  10  save/load preserves a partial tank
##  11  save/load preserves an EMPTY tank - it must not reset to 100
##  12  the Push Mower is manual: it burns nothing and never stops cutting

const SLOT_PARTIAL := "fuel_partial"
const SLOT_EMPTY := "fuel_empty"

## Long enough for a difference in position to be unambiguous.
## HOW LONG each drive test holds the throttle, in SECONDS of simulated time,
## counted off the fixed 576 Hz physics step.
##
## It was a count of ninety RENDER frames, which assumed both that a render
## frame is a fixed slice of time and that a machine reaches its speed
## instantly. The second stopped being true when the machines were given
## acceleration, and the drives became too short to reach standing grass - which
## is what made "refuelling restores the blades" fail while "refuelling restores
## propulsion" passed on the same drive.
const DRIVE_SECONDS := 1.2
## World units. The rider does ~30 u/s, so "moved" and "did not move" are far
## apart; these only have to separate them.
const MOVED_UNITS := 2.0
const STILL_UNITS := 0.5

var _passes: int = 0
var _failures: int = 0
var _empties: int = 0


func _count_empty() -> void:
	_empties += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("\n================= FUEL TEST =================")

	await _step()
	_test_rules()
	await _test_powered_mower()
	await _test_push_mower_is_manual()
	await _test_persistence()

	# Never leave a development cheat on for whatever runs next.
	MowerFuel.set_auto_refuel(false)

	print("=============================================")
	print("[FUEL TEST] %d passed, %d failed" % [_passes, _failures])
	print("=============================================\n")
	get_tree().quit(0 if _failures == 0 else 1)


# ===================================================================== rules
##
## Pure API. No scene, so these run in milliseconds and pin the arithmetic
## itself rather than a symptom of it.

func _test_rules() -> void:
	MowerFuel.set_auto_refuel(false)
	MowerFuel.refuel_full()

	_check("Rules: a full tank is the capacity",
		is_equal_approx(MowerFuel.fuel(), ACAMowerFuel.CAPACITY))
	_check("Rules: a full tank reads 1.0", is_equal_approx(MowerFuel.fraction(), 1.0))
	_check("Rules: idling burns less than driving",
		MowerFuel.burn_rate_per_second(0.0) < MowerFuel.burn_rate_per_second(1.0))

	# THE tuning claim, asserted rather than left in a comment.
	var drive_rate := MowerFuel.burn_rate_per_second(1.0)
	var drive_seconds := ACAMowerFuel.CAPACITY / drive_rate
	print("[FUEL] full tank: %.0f s driving (%.1f min), %.0f s idling (%.1f min)" % [
		drive_seconds, drive_seconds / 60.0,
		ACAMowerFuel.CAPACITY / MowerFuel.burn_rate_per_second(0.0),
		ACAMowerFuel.CAPACITY / MowerFuel.burn_rate_per_second(0.0) / 60.0])
	# THE TANK IS A DIFFICULTY SETTING NOW, so the claim is asserted against the
	# rule layer's own answer rather than against the constant - and then each
	# profile is checked to produce the length its table says it does. Asserting
	# the constant alone would have gone on passing with difficulty ignored
	# entirely, which is exactly the bug worth catching.
	_check("Rules: a full tank lasts %.0f s of driving, as the rule layer says"
		% drive_seconds,
		is_equal_approx(drive_seconds, MowerFuel.full_tank_driving_seconds()))
	var restore_difficulty := ACADifficulty.active_id()
	var profile_mismatches := 0
	for id: StringName in [&"legacy", &"easy", &"medium", &"hard"]:
		ACADifficulty.set_active(id)
		var expected := float(ACADifficulty.profile(id)["full_tank_driving_seconds"])
		var measured := ACAMowerFuel.CAPACITY / MowerFuel.burn_rate_per_second(1.0)
		print("[FUEL] %-7s tank: %.0f s (%.1f min)" % [id, measured, measured / 60.0])
		if not is_equal_approx(measured, expected):
			profile_mismatches += 1
	ACADifficulty.set_active(restore_difficulty)
	_check("Rules: every difficulty burns at its own documented rate",
		profile_mismatches == 0)
	_check("Rules: the legacy profile is exactly the shipped constant",
		is_equal_approx(
			float(ACADifficulty.profile(&"legacy")["full_tank_driving_seconds"]),
			ACAMowerFuel.FULL_TANK_DRIVING_SECONDS))
	_check("Rules: a tank outlasts a small contract but not a large one"
		+ " (%.1f min vs 4.6 / 18.4 min estimates)" % [drive_seconds / 60.0],
		drive_seconds / 60.0 > 4.6 and drive_seconds / 60.0 < 18.4)

	# TIME BASED. Ten small steps must equal one big one; a per-tick model
	# cannot satisfy this.
	MowerFuel.refuel_full()
	for _i in 10:
		MowerFuel.consume(0.2, 1.0)
	var in_steps := MowerFuel.fuel()
	MowerFuel.refuel_full()
	MowerFuel.consume(2.0, 1.0)
	var in_one := MowerFuel.fuel()
	_check("Rules: consumption is time based - 10 x 0.2s == 1 x 2.0s"
		+ " (%.4f vs %.4f)" % [in_steps, in_one],
		absf(in_steps - in_one) < 0.001)
	_check("Rules: two seconds of driving burned the documented amount",
		absf((ACAMowerFuel.CAPACITY - in_one) - drive_rate * 2.0) < 0.001)

	# Cannot go negative, however hard it is pushed.
	MowerFuel.refuel_full()
	MowerFuel.consume(10000.0, 1.0)
	_check("Rules: fuel cannot go negative (%.4f)" % MowerFuel.fuel(),
		MowerFuel.fuel() >= 0.0)
	_check("Rules: it reads as empty", MowerFuel.is_empty() and not MowerFuel.has_fuel())
	MowerFuel.consume(10.0, 1.0)
	_check("Rules: burning an empty tank is still not negative",
		MowerFuel.fuel() >= 0.0)

	# The refuel interface.
	_check("Rules: refuel(30) adds 30", is_equal_approx(MowerFuel.refuel(30.0), 30.0))
	_check("Rules: the tank is at 30", is_equal_approx(MowerFuel.fuel(), 30.0))
	_check("Rules: refuel_full() tops up the remainder",
		is_equal_approx(MowerFuel.refuel_full(), 70.0))
	_check("Rules: a full tank cannot be overfilled",
		is_equal_approx(MowerFuel.refuel(50.0), 0.0)
		and is_equal_approx(MowerFuel.fuel(), ACAMowerFuel.CAPACITY))

	# Empty is announced exactly once per transition. `_empties` is a member,
	# not a local: GDScript lambdas capture locals BY VALUE.
	_empties = 0
	MowerFuel.emptied.connect(_count_empty)
	MowerFuel.refuel_full()
	MowerFuel.consume(10000.0, 1.0)
	MowerFuel.consume(10.0, 1.0)
	MowerFuel.consume(10.0, 1.0)
	_check("Rules: `emptied` fires once per transition, not once per frame (%d)"
		% _empties, _empties == 1)
	MowerFuel.emptied.disconnect(_count_empty)

	# AUTO REFUEL, as an API. Off is the default and off must allow zero.
	_check("Rules: Auto Refuel defaults OFF", not MowerFuel.auto_refuel())
	MowerFuel.set_auto_refuel(false)
	MowerFuel.refuel_full()
	MowerFuel.consume(10000.0, 1.0)
	_check("Rules: Auto Refuel OFF leaves the tank empty", MowerFuel.is_empty())

	MowerFuel.set_auto_refuel(true)
	_check("Rules: switching Auto Refuel ON recovers an already dry tank",
		not MowerFuel.is_empty())
	MowerFuel.consume(1.0, 1.0)
	_check("Rules: Auto Refuel is NOT a fuel lock - the tank still drains"
		+ " (%.2f)" % MowerFuel.fuel(),
		MowerFuel.fuel() < ACAMowerFuel.CAPACITY)
	MowerFuel.consume(10000.0, 1.0)
	_check("Rules: Auto Refuel ON refills after empty (%.2f)" % MowerFuel.fuel(),
		is_equal_approx(MowerFuel.fuel(), ACAMowerFuel.CAPACITY))
	MowerFuel.set_auto_refuel(false)
	_check("Rules: `auto_refuel_text()` reports the state",
		MowerFuel.auto_refuel_text() == "OFF")

	# Mower TYPE is a property of the controller, not of the fuel system.
	var powered: Array = [
		"res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn",
		"res://Assets/Vehicles and Mowers/Mowers/Non Rider Mower.tscn"]
	for path: String in powered:
		var node: Node = load(path).instantiate()
		_check("Type: %s is POWERED" % path.get_file(),
			node.has_method("is_powered") and bool(node.call(&"is_powered")))
		node.free()
	var push: Node = load(
		"res://Assets/Vehicles and Mowers/Mowers/Push Mower.tscn").instantiate()
	_check("Type: Push Mower.tscn is MANUAL",
		push.has_method("is_powered") and not bool(push.call(&"is_powered")))
	push.free()


# ============================================================ powered mower
##
## The real rider, in the real mowing scene, under its own physics.

func _test_powered_mower() -> void:
	print("\n--- POWERED MOWER (rider) ---")
	if not await _enter_mowing():
		_fail("Powered: reached the mowing scene")
		return

	var scene := get_tree().current_scene
	var grid: ACALawn = scene.call(&"lawn")
	var mower: Node3D = scene.get(&"current_mower")
	_check("Powered: the rider is the active mower",
		mower != null and bool(mower.call(&"is_powered")))

	MowerFuel.set_auto_refuel(false)
	MowerFuel.refuel_full()
	await _step(4)

	# 1 - it consumes, and 2 - at the documented rate for the time that passed.
	var before := MowerFuel.fuel()
	var t0 := Time.get_ticks_msec()
	var drove := await _drive(DRIVE_SECONDS)
	var seconds := float(Time.get_ticks_msec() - t0) / 1000.0
	var burned := before - MowerFuel.fuel()
	var expected := MowerFuel.burn_rate_per_second(1.0) * seconds
	print("[FUEL] drove %.2f s: burned %.3f, expected ~%.3f, moved %.1f u"
		% [seconds, burned, expected, drove])
	_check("Powered: driving consumes fuel (%.3f burned)" % burned, burned > 0.0)
	# A BAND, not a point. `seconds` is wall clock and the throttle is not held
	# for every millisecond of it, so the honest expectation is somewhere
	# between the idle and the driving rate. What this rules out is the model
	# the old code used: at 576 physics ticks per second a per-tick burn would
	# overshoot this by roughly a hundredfold.
	_check("Powered: the burn matches the TIME that passed, not the tick count"
		+ " (%.3f in [%.3f, %.3f])" % [burned, expected * 0.35, expected * 1.3],
		burned >= expected * 0.35 and burned <= expected * 1.3)
	_check("Powered: the mower actually moved (%.1f u)" % drove, drove > MOVED_UNITS)

	# 9 - the production HUD is showing the authoritative value.
	var ui := scene.get_node_or_null(^"Gameplay UI")
	var hud: GameplayHUD = ui.get_node_or_null(^"Gameplay HUD") if ui != null else null
	await _step(8)
	_check("Powered: the production HUD tracks the real fuel (%.3f vs %.3f)"
		% [hud.fuel() if hud != null else -1.0, MowerFuel.fraction()],
		hud != null and absf(hud.fuel() - MowerFuel.fraction()) < 0.02)

	# 4 and 5 - empty stops the blades AND the wheels, from the SAME state.
	MowerFuel.dev_drain()
	await _step(6)
	_check("Powered: the tank is empty", MowerFuel.is_empty())

	var cut_before := grid.mowed_item_count()
	var moved_empty := await _drive(DRIVE_SECONDS)
	var cut_empty := grid.mowed_item_count() - cut_before
	print("[FUEL] empty: moved %.2f u, cut %d" % [moved_empty, cut_empty])
	_check("Powered: an empty tank stops propulsion (moved %.2f u)" % moved_empty,
		moved_empty < STILL_UNITS)
	_check("Powered: an empty tank stops the blades (cut %d)" % cut_empty,
		cut_empty == 0)
	_check("Powered: the tank did NOT silently refill itself (%.2f)" % MowerFuel.fuel(),
		MowerFuel.is_empty())
	_check("Powered: the HUD shows an empty gauge",
		hud != null and hud.fuel() < 0.01)

	# 6 - refuelling brings it back.
	MowerFuel.refuel_full()
	await _step(6)
	cut_before = grid.mowed_item_count()
	var moved_after := await _drive(DRIVE_SECONDS)
	var cut_after := grid.mowed_item_count() - cut_before
	print("[FUEL] refuelled: moved %.2f u, cut %d" % [moved_after, cut_after])
	_check("Powered: refuelling restores propulsion (%.1f u)" % moved_after,
		moved_after > MOVED_UNITS)
	_check("Powered: refuelling restores the blades (cut %d)" % cut_after,
		cut_after > 0)

	# 7 and 8 - the development toggle, in the real scene this time.
	MowerFuel.set_auto_refuel(false)
	MowerFuel.dev_drain()
	await _drive(30)
	_check("Powered: Auto Refuel OFF lets the mower sit at zero",
		MowerFuel.is_empty())

	MowerFuel.set_auto_refuel(true)
	await _step(6)
	_check("Powered: Auto Refuel ON recovered the empty mower (%.0f%%)"
		% (MowerFuel.fraction() * 100.0), not MowerFuel.is_empty())
	var after_auto := await _drive(DRIVE_SECONDS)
	_check("Powered: Auto Refuel ON lets it drive again (%.1f u)" % after_auto,
		after_auto > MOVED_UNITS)
	_check("Powered: Auto Refuel is not pinning the gauge at full (%.2f)"
		% MowerFuel.fuel(),
		MowerFuel.fuel() < ACAMowerFuel.CAPACITY)
	MowerFuel.set_auto_refuel(false)


# =============================================================== push mower
##
## 12 - the Push Mower is a MANUAL reel mower. It must not burn gasoline just
## because it shares a scene with two that do.

func _test_push_mower_is_manual() -> void:
	print("\n--- PUSH MOWER (manual) ---")
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("_on_mvp_hud_mower_change_selected"):
		_fail("Push: could not swap mower")
		return

	scene.call(&"_on_mvp_hud_mower_change_selected", "push")
	await _step(10)
	var grid: ACALawn = scene.call(&"lawn")
	var mower: Node3D = scene.get(&"current_mower")
	_check("Push: the push mower is active",
		mower != null and mower.has_method("is_powered")
		and not bool(mower.call(&"is_powered")))
	_check("Push: the mowing scene reports it as manual",
		not bool(scene.call(&"current_mower_is_powered")))

	# It runs on an EMPTY tank, because it has no tank.
	MowerFuel.set_auto_refuel(false)
	MowerFuel.dev_drain()
	await _step(6)
	var fuel_before := MowerFuel.fuel()
	var cut_before := grid.mowed_item_count()
	var moved := await _drive(DRIVE_SECONDS)
	var cut := grid.mowed_item_count() - cut_before
	print("[FUEL] push on an empty tank: moved %.2f u, cut %d" % [moved, cut])
	_check("Push: it moves with no fuel at all (%.1f u)" % moved, moved > MOVED_UNITS)
	_check("Push: it still cuts grass with no fuel (cut %d)" % cut, cut > 0)

	# And it burns nothing when there IS fuel.
	MowerFuel.refuel_full()
	fuel_before = MowerFuel.fuel()
	await _drive(DRIVE_SECONDS)
	_check("Push: it consumes no fuel (%.4f -> %.4f)" % [fuel_before, MowerFuel.fuel()],
		is_equal_approx(fuel_before, MowerFuel.fuel()))

	# Put the canonical mower back for anything that follows.
	scene.call(&"_on_mvp_hud_mower_change_selected", "rider")
	await _step(10)


# ============================================================== persistence
##
## 10 and 11. SaveService is unchanged - what is being proved is that the fuel
## VALUE round trips and that an empty tank stays empty.

func _test_persistence() -> void:
	print("\n--- SAVE / LOAD ---")
	MowerFuel.set_auto_refuel(false)

	# 10 - a partial tank.
	MowerFuel.refuel_full()
	MowerFuel.consume(120.0, 1.0)
	var partial := MowerFuel.fuel()
	_check("Save: a partial tank to save (%.2f)" % partial,
		partial > 1.0 and partial < ACAMowerFuel.CAPACITY)
	_check("Save: partial tank written", SaveService.save_game(SLOT_PARTIAL))

	MowerFuel.refuel_full()
	await _step(4)
	var loaded := SaveService.load_game(SLOT_PARTIAL)
	_check("Load: partial tank read back", loaded)
	# Read it BEFORE any frames run. `_apply_mower` restores the level inside
	# load_game(), and the moment the scene is live again an idling powered
	# mower legitimately starts burning it.
	var restored := MowerFuel.fuel()
	_check("Load: the partial tank is the same amount (%.2f vs %.2f)"
		% [partial, restored],
		absf(restored - partial) < 0.01)
	await _settle_after_load()
	_check("Load: and the mowing scene did not reset it on the way in (%.2f)"
		% MowerFuel.fuel(),
		absf(MowerFuel.fuel() - partial) < 1.0)

	# 11 - an EMPTY tank. This is the one the old forced refill made impossible.
	MowerFuel.dev_drain()
	await _step(4)
	_check("Save: empty tank written", SaveService.save_game(SLOT_EMPTY))
	MowerFuel.refuel_full()
	await _step(4)
	_check("Load: empty tank read back", SaveService.load_game(SLOT_EMPTY))
	await _settle_after_load()
	_check("Load: an empty tank loads EMPTY and does not reset to 100 (%.2f)"
		% MowerFuel.fuel(), MowerFuel.is_empty())

	# ...and gameplay obeys the restored state, then recovers from it.
	if GameSession.current_screen() == ACAGameSession.Screen.MOWING:
		var scene := get_tree().current_scene
		var grid: ACALawn = scene.call(&"lawn")
		if grid != null:
			var cut_before := grid.mowed_item_count()
			var moved := await _drive(DRIVE_SECONDS)
			_check("Load: a restored empty mower still will not drive (%.2f u)" % moved,
				moved < STILL_UNITS)
			_check("Load: a restored empty mower still will not cut",
				grid.mowed_item_count() == cut_before)
			MowerFuel.refuel_full()
			await _step(6)
			var recovered := await _drive(DRIVE_SECONDS)

			# MEASURED AGAINST THE EMPTY RUN, NOT AGAINST A CONSTANT.
			#
			# This used to assert `recovered > MOVED_UNITS` - a fixed two units
			# in ninety frames. Sampled five times it produced 10.6, 4.8, 1.3,
			# 0.9 and 0.0, because the machine is driven BLINDLY FORWARD from
			# wherever the property put it, and on some properties that is
			# straight into the boundary fence. The assertion was measuring the
			# generated geometry at least as much as the fuel system.
			#
			# What the fuel system actually promises is that a refuel puts the
			# tank back and lets the machine move again. Both halves are checked
			# here, and the distance is compared with the SAME machine on the
			# SAME ground moments earlier with an empty tank - which is the only
			# comparison the starting position cannot corrupt.
			_check("Load: a manual refuel puts the tank back (%.1f u)"
				% MowerFuel.fuel(),
				not MowerFuel.is_empty())
			_check("Load: ...and the machine moves again (%.2f u full against "
				% recovered + "%.2f u empty)" % moved,
				recovered > moved + STILL_UNITS)

	SaveService.delete_save(SLOT_PARTIAL)
	SaveService.delete_save(SLOT_EMPTY)


# ================================================================== helpers

## Hold the throttle for `frames` process frames and return how far the mower
## moved on the horizontal plane. The real input action, the real controller.
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
	await _settle()
	var to := mower.global_position
	return Vector2(to.x - from.x, to.z - from.z).length()


## Wait until the machine has actually come to rest.
##
## The machines have momentum now: releasing the throttle asks them to stop and
## they take up to a second to do it. A test that drains the tank two frames
## after a drive is draining it into a machine that is still rolling, and the
## coast that follows is the previous drive's, not propulsion from an empty
## tank. That is exactly what made "an empty tank stops propulsion" read 0.55
## units against a half-unit limit.
func _settle() -> void:
	var scene := get_tree().current_scene
	var mower: Node3D = scene.get(&"current_mower") if scene != null else null
	var waited := 0.0
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	while waited < 2.0:
		await get_tree().physics_frame
		waited += step
		if mower == null or absf(float(mower.get("_ground_speed"))) < 0.01:
			return


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


## A load changes scene. `save_game()` refuses to write mid-transition - it
## would collect the mowing block from the outgoing scene - so a test that saves
## straight after loading has to let the swap finish first.
func _settle_after_load() -> void:
	var frames := 0
	while frames < 900 and GameSession.is_changing_scene():
		await get_tree().process_frame
		frames += 1
	await _step(20)


func _wait_for_screen(screen: int, max_frames: int = 900) -> void:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen and not GameSession.is_changing_scene():
			return
		await get_tree().process_frame
		frames += 1


func _step(frames: int = 1) -> void:
	for _i in frames:
		await get_tree().process_frame


func _check(what: String, ok: bool) -> void:
	if ok:
		_passes += 1
		print("[FUEL] %s: PASS" % what)
	else:
		_failures += 1
		printerr("[FUEL] %s: FAIL" % what)


func _fail(what: String) -> void:
	_check(what, false)
