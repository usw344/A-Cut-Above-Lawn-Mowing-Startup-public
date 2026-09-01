extends Node
## DEVELOPMENT. Measures how each machine actually HANDLES, in the real mowing
## scene, so mower differentiation can be judged from numbers as well as from
## driving it.
##
## Every figure is measured by driving the real CharacterBody3D with the real
## input path. Nothing is read from a tuning constant, which is the point: a
## constant that does not reach the wheels would still print here as unchanged.
##
## Reported per machine:
##   top speed        u/s held after a long full-throttle run
##   0-90%            seconds to reach 90% of that
##   stop             seconds from top speed to rest after releasing throttle
##   reverse          top speed backwards, and seconds to cross from full
##                    forward to full reverse
##   turn radius      units, driving at full throttle with the steering held at
##                    a constant lead - the radius of the circle it traces
##   spin rate        rad/s yaw while stationary with the same steering lead

const MOWERS: Array[String] = ["rider", "powered", "push"]

## The steering lead held during a turn measurement, in radians. A fixed lead
## for every machine is what makes the radii comparable.
const STEER_LEAD := 0.9

var _mvp: Node = null
var _centre := Vector3.ZERO
var _shot_dir: String = ""
var _passes: int = 0
var _failures: int = 0
var _rows: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shot_dir = arg.substr(8)
			DirAccess.make_dir_recursive_absolute(_shot_dir)
	_run.call_deferred()


func _run() -> void:
	print("\n============ HANDLING PROBE ============")
	await _enter_mowing()
	if _mvp == null:
		get_tree().quit(1)
		return
	# Fuel must never be the thing being measured.
	MowerFuel.set_auto_refuel(true)
	# FIRST, WHILE THE LAWN IS STILL STANDING. Every other section of this probe
	# drives the machine, and by the time they are done the middle of the
	# property is mown - which is exactly the ground that must NOT be used to
	# measure what cutting fresh grass feels like.
	await _cut_load()
	for id in MOWERS:
		await _measure(id)
	_report()
	await _engine_audio()
	await _comfort()
	await _precision_view()
	print("[HANDLING PROBE] %d checks passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _enter_mowing() -> void:
	print("[HANDLING PROBE] starting a game")
	GameSession.start_new_game()
	await _step(8)
	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(1)
		offers = JobManager.available_jobs()
	var job: ACAJob = offers[0]
	JobManager.accept_job(job.id)
	JobManager.begin_new_job(job.id)
	print("[HANDLING PROBE] waiting for the mowing scene")
	var frames := 0
	while frames < 3600:
		if GameSession.current_screen() == ACAGameSession.Screen.MOWING 				and not GameSession.is_changing_scene():
			break
		await get_tree().process_frame
		frames += 1
	await _step(30)
	_mvp = get_tree().current_scene
	var property_node = _mvp.get("property_node")
	_centre = property_node.lawn().lawn_centre()
	print("[HANDLING PROBE] in mowing after %d frames, lawn centre %s"
		% [frames, _centre])


func _mower() -> CharacterBody3D:
	return _mvp.get("current_mower") as CharacterBody3D


## Put the machine at THE LAWN CENTRE, facing a known direction, genuinely at
## rest. The lawn centre matters: measured from the world origin the rider ran
## into the boundary inside three seconds and every figure after that was a
## reading of the fence rather than of the machine.
##
## `_ground_speed` is the state the momentum model integrates, so zeroing
## `velocity` alone would leave the next run starting at speed.
func _reset(at_angle: float = 0.0) -> void:
	var m := _mower()
	m.velocity = Vector3.ZERO
	m.set("_ground_speed", 0.0)
	m.global_position = Vector3(_centre.x, m.global_position.y, _centre.z)
	m.rotation.y = at_angle
	m.set("target_body_yaw", at_angle)
	# AND ON THE GROUND. `_reset()` used to keep whatever height the previous
	# measurement left the machine at, so a run that ended off the property
	# began the next one in mid-air - which read as 85 units of "ground rise"
	# and as no ground contact at all.
	var terrain = _mvp.get("property_node")
	if terrain != null and terrain.has_method(&"terrain"):
		var ground = terrain.call(&"terrain")
		if ground != null and ground.has_method(&"height_at"):
			m.global_position.y = float(ground.call(&"height_at",
				m.global_position.x, m.global_position.z)) + 1.5
	await _step(10)
	var settle := 0
	while not m.is_on_floor() and settle < 240:
		await get_tree().physics_frame
		settle += 1



func _measure(id: String) -> void:
	print("[HANDLING PROBE] measuring %s" % id)
	_mvp.call("_on_mvp_hud_mower_change_selected", id)
	await _step(20)
	var row := {"id": id}

	# ---- top speed and acceleration
	await _reset()
	var m := _mower()
	Input.action_press("move_forward")
	var t := 0.0
	var reached := -1.0
	var top := 0.0
	while t < 3.5:
		await get_tree().physics_frame
		t += 1.0 / 576.0
		top = maxf(top, _speed())
	Input.action_release("move_forward")
	row["top"] = top

	# 0-90% of the top speed just measured
	await _reset()
	m = _mower()
	Input.action_press("move_forward")
	t = 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / 576.0
		if _speed() >= top * 0.9:
			reached = t
			break
	row["accel"] = reached

	# ---- stopping distance in time, from full speed
	var stop := -1.0
	Input.action_release("move_forward")
	t = 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / 576.0
		if _speed() < 0.5:
			stop = t
			break
	row["stop"] = stop

	# ---- reverse: top speed, and the time to cross from full forward
	await _reset()
	m = _mower()
	Input.action_press("move_forward")
	await _seconds(2.2)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	t = 0.0
	var cross := -1.0
	var rev_top := 0.0
	while t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / 576.0
		var forward_speed := float(m.get("_ground_speed"))
		rev_top = maxf(rev_top, -forward_speed)
		if cross < 0.0 and forward_speed < -0.5:
			cross = t
	Input.action_release("move_back")
	row["reverse"] = rev_top
	row["cross"] = cross

	# ---- turn radius at full throttle, steering held at a constant lead
	await _reset()
	m = _mower()
	Input.action_press("move_forward")
	await _seconds(2.2)
	# Sampled over exactly a QUARTER TURN rather than a fixed time. A push mower
	# comes round at 4.6 rad/s, so a two-second window is nine complete circles
	# and the three points the radius is fitted through land almost on top of
	# each other - it read 83 units for a machine that turns inside 2.
	var samples: Array[Vector3] = []
	var arc := 0.0
	var arc_previous := m.rotation.y
	t = 0.0
	while t < 4.0 and arc < PI * 0.5:
		m.set("target_body_yaw", m.rotation.y + STEER_LEAD)
		await get_tree().physics_frame
		t += 1.0 / 576.0
		arc += absf(wrapf(m.rotation.y - arc_previous, -PI, PI))
		arc_previous = m.rotation.y
		samples.append(m.global_position)
	# Caught at full lock and full speed, which is where the chassis lean is
	# doing the most - see `_apply_body_lean()` in the controllers.
	await _shot("%s_turning" % id)
	Input.action_release("move_forward")
	# ...and again a fifth of a second into the stop, where it pitches forward.
	await _seconds(0.2)
	await _shot("%s_braking" % id)
	row["radius"] = _radius(samples)

	# ---- yaw rate standing still, same steering lead
	await _reset()
	m = _mower()
	# Accumulated per frame, not measured start to end: a push mower turns more
	# than a full half-circle in a second, and a start-to-end reading wraps and
	# reports it as slower than the rider.
	var turned := 0.0
	var previous := m.rotation.y
	t = 0.0
	while t < 1.0:
		m.set("target_body_yaw", m.rotation.y + STEER_LEAD)
		await get_tree().physics_frame
		t += 1.0 / 576.0
		turned += absf(wrapf(m.rotation.y - previous, -PI, PI))
		previous = m.rotation.y
	row["spin"] = turned

	# ---- deck, straight off the machine
	row["deck"] = float(m.get("DECK_WIDTH"))
	_rows.append(row)


## The machine's OWN speed along its forward axis, which is the state the
## momentum model integrates. Deliberately not `velocity`: `move_and_slide()`
## projects that onto the floor, so on a lawn with any relief its horizontal
## length measures the SLOPE as much as the machine - it read an 18 u/s rider
## as 13.5 on the first attempt.
func _speed() -> float:
	return absf(float(_mower().get("_ground_speed")))


## Radius of the circle the samples lie on, from the chord and the sagitta -
## cheap, and it does not care where the centre is.
func _radius(samples: Array[Vector3]) -> float:
	if samples.size() < 3:
		return -1.0
	var a := samples[0]
	var b := samples[samples.size() / 2]
	var c := samples[samples.size() - 1]
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var bc := Vector2(c.x - b.x, c.z - b.z)
	var cross := ab.cross(bc)
	if absf(cross) < 0.0001:
		return -1.0
	var ab_len := ab.length()
	var bc_len := bc.length()
	var ca_len := Vector2(a.x - c.x, a.z - c.z).length()
	return (ab_len * bc_len * ca_len) / (2.0 * absf(cross))


## THE PRECISION VIEW (C). Checked on all three machines: it has to move the
## camera and narrow the field of view, it has to come back, and it must not
## disturb anything the player steers with.
func _precision_view() -> void:
	print("
============ PRECISION VIEW ============")
	for id in MOWERS:
		_mvp.call("_on_mvp_hud_mower_change_selected", id)
		await _step(20)
		await _reset()
		var m := _mower()
		var camera := m.get_node(^"Camera3D") as Camera3D
		var rest_position: Vector3 = camera.position
		var rest_fov: float = camera.fov

		# Somewhere worth using it from: rolling forward, pointed at the lawn.
		Input.action_press("move_forward")
		await _seconds(1.2)
		await _shot("%s_view_normal" % id)

		var pitch_before: float = float(m.get("target_camera_pitch"))
		m.call("toggle_precision_view")
		_check("%s: C engages the precision view" % id,
			bool(m.call("precision_view_active")))
		await _seconds(0.6)
		await _shot("%s_view_precision" % id)

		_check("%s: the camera dollies in" % id,
			camera.position.length() < rest_position.length() - 0.5)
		_check("%s: the camera drops" % id, camera.position.y < rest_position.y)
		_check("%s: the field of view narrows" % id, camera.fov < rest_fov - 5.0)
		_check("%s: aiming pitch is untouched" % id,
			is_equal_approx(float(m.get("target_camera_pitch")), pitch_before))

		# Steering still steers, which is the thing a second camera rig breaks.
		var yaw_before: float = m.rotation.y
		m.set("target_body_yaw", yaw_before + 0.5)
		await _seconds(0.4)
		_check("%s: it still steers in the precision view" % id,
			absf(wrapf(m.rotation.y - yaw_before, -PI, PI)) > 0.05)

		m.call("toggle_precision_view")
		await _seconds(0.8)
		Input.action_release("move_forward")
		_check("%s: C returns to the normal view" % id,
			camera.position.distance_to(rest_position) < 0.35
				and absf(camera.fov - rest_fov) < 1.0)
	await _reset()


## ---------------------------------------------------------------------------
## ENGINE AUDIO
## ---------------------------------------------------------------------------
## The three machines are supposed to be recognisable with the eyes shut. That
## needs three different recordings actually reaching three different players,
## and the load response actually reaching the engine - both of which are
## exactly the kind of thing that can be written, look right, and be wired to
## nothing.
##
## So this reports, per machine, WHICH FILE is loaded, and the level and pitch
## the engine reaches standing still and at full speed. It is the same
## measurement as the handling table above: driven, in the real scene, read off
## the real node.
func _engine_audio() -> void:
	print("
============ ENGINE AUDIO ============")
	print(" machine   idle dB   full dB   idle pitch   full pitch   recording")
	print(" ---------------------------------------------------------------------")
	for id in MOWERS:
		_mvp.call("_on_mvp_hud_mower_change_selected", id)
		await _step(20)
		await _reset()
		var m := _mower()
		var player := m.get_node_or_null(^"AudioStreamPlayer3D") as AudioStreamPlayer3D
		if player == null:
			_check("%s: has an engine player" % id, false)
			continue
		# Standing still, engine running.
		await _seconds(1.4)
		var idle_db: float = player.volume_db
		var idle_pitch: float = player.pitch_scale
		# And at full throttle.
		Input.action_press("move_forward")
		await _seconds(2.4)
		var full_db: float = player.volume_db
		var full_pitch: float = player.pitch_scale
		Input.action_release("move_forward")
		await _seconds(0.6)

		var file := "none"
		if player.stream != null:
			file = player.stream.resource_path.get_file()
		print(" %-9s %7.2f %9.2f %12.3f %12.3f   %s" % [
			id, idle_db, full_db, idle_pitch, full_pitch, file])

		var wanted := String(ACAMowerAudio.profile(StringName(id))["engine"])
		_check("%s: plays its OWN recording" % id,
			player.stream != null and player.stream.resource_path == wanted)
		_check("%s: the engine is audible under way" % id, full_db > -50.0)
		_check("%s: speed raises the note" % id, full_pitch > idle_pitch + 0.01)
	await _reset()


## ---------------------------------------------------------------------------
## THE LOAD LAYER
## ---------------------------------------------------------------------------
## Driving through STANDING grass must sound different from crossing ground the
## machine has already cut. That is the whole claim of the cutting audio, and it
## is measurable: `ACAMowerCutAudio` publishes the load it is feeding the
## engine, so drive the same lawn twice and the second pass must read lower.
func _cut_load() -> void:
	print("
============ CUTTING LOAD ============")
	var audio = _mvp.get("cut_audio")
	_check("the cut audio node is bound", audio != null)
	if audio == null:
		return

	# ---- one pass through standing grass
	await _reset()
	var fresh := await _drive_and_measure(audio, "move_forward", 2.6)
	var engine_load := float(_mower().call(&"cut_load"))

	# ---- AND BACK DOWN THE SAME LANE, IN REVERSE.
	#
	# Turning round and driving away would cross fresh grass, which is what the
	# first version of this did: it reported a full load on the "already cut"
	# pass and was right to. Reversing retraces the exact strip the deck has
	# just been over, which is the only way to ask the question.
	var again := await _drive_and_measure(audio, "move_back", 2.6)

	print(" load through standing grass  %.3f" % fresh)
	print(" load back over the same cut lane %.3f" % again)
	_check("cutting standing grass loads the machine (%.3f)" % fresh,
		fresh > 0.25)
	_check("re-crossing cut ground loads it far less (%.3f vs %.3f)"
		% [again, fresh], again < fresh * 0.6)
	_check("the load reaches the engine (%.3f)" % engine_load,
		engine_load > 0.1)


## The MEAN load once the machine is up to speed, not the peak.
##
## A peak is the wrong statistic here for a specific reason: these machines have
## momentum. A rider asked to reverse spends most of a second still rolling
## FORWARD into standing grass, so the peak of a "drive back over cut ground"
## pass is the load from the grass it was still cutting while it stopped. The
## settle below is longer than the rider's 0.925 s stopping time.
const LOAD_SETTLE_SECONDS := 1.3


func _drive_and_measure(audio: Node, action: String, seconds: float) -> float:
	Input.action_press(action)
	var total := 0.0
	var samples := 0
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += 1.0 / 576.0
		if t < LOAD_SETTLE_SECONDS:
			continue
		total += float(audio.call(&"load_amount"))
		samples += 1
	Input.action_release(action)
	await _seconds(0.5)
	return total / maxf(float(samples), 1.0)


## ---------------------------------------------------------------------------
## COMFORT
## ---------------------------------------------------------------------------
## The body lean was retuned because it made people feel ill, and "it feels
## better now" is not a measurement. This drives each machine through the two
## things that used to produce the worst of it - a hard turn at speed, and a
## straight run across ordinary ground - and reports what the CAMERA and the
## CHASSIS actually did.
##
## The camera figures are the ones that matter. A horizon that tips is what
## causes discomfort; a mesh that leans is what reads as weight.
const COMFORT_LIMITS := {
	"camera_roll": 0.05,   # degrees. The camera does not roll at all now.
	"camera_pitch": 2.5,   # degrees of deviation from the aiming pitch
	# degrees. THE CEILING THE DESIGN ALLOWS, not a taste: a machine's own roll
	# at full lock plus everything the ground is permitted to add
	# (GROUND_TILT_LIMIT_DEGREES x GROUND_FOLLOW). On the rider that is
	# 1.2 + 6.6. Anything past it is the lean model exceeding its own table,
	# which is what the old underdamped spring did at 7.64 against 7.0.
	"chassis_roll": 7.8,
}


func _comfort() -> void:
	print("
============ COMFORT ============")
	print(" machine   cam roll   cam pitch   body roll   body pitch   ground tilt   rise")
	print(" -------------------------------------------------------------------------------")
	for id in MOWERS:
		_mvp.call("_on_mvp_hud_mower_change_selected", id)
		await _step(20)
		var worst := await _comfort_run(id)
		print(" %-9s %8.2f   %9.2f   %9.2f   %10.2f   %11.2f   %4.2f" % [
			id, worst["camera_roll"], worst["camera_pitch"],
			worst["chassis_roll"], worst["chassis_pitch"], worst["ground"],
			worst["rise"]])
		_check("%s: the camera never rolls" % id,
			worst["camera_roll"] <= COMFORT_LIMITS["camera_roll"])
		_check("%s: camera pitch stays comfortable" % id,
			worst["camera_pitch"] <= COMFORT_LIMITS["camera_pitch"])
		_check("%s: the chassis never banks" % id,
			worst["chassis_roll"] <= COMFORT_LIMITS["chassis_roll"])
	await _reset()


## A hard turn at full throttle, then a long straight run. Returns the worst
## angle seen on each axis, in DEGREES, and how far the ground moved the machine
## vertically on the straight - which is the movement that is supposed to be
## there.
func _comfort_run(_id: String) -> Dictionary:
	await _reset()
	var m := _mower()
	var camera := m.get_node(^"Camera3D") as Camera3D
	var aiming: float = float(m.get("target_camera_pitch"))
	var worst := {"camera_roll": 0.0, "camera_pitch": 0.0,
		"chassis_roll": 0.0, "chassis_pitch": 0.0, "rise": 0.0, "ground": 0.0}

	# ---- a hard turn at speed, which is what used to bank the machine over
	Input.action_press("move_forward")
	await _seconds(1.6)
	var t := 0.0
	while t < 3.0:
		m.set("target_body_yaw", m.rotation.y + STEER_LEAD)
		await get_tree().physics_frame
		t += 1.0 / 576.0
		_note(worst, camera, m, aiming)

	# ---- a straight run ACROSS THE LAWN, which is where the ground should show
	#
	# BOUNDED BY DISTANCE, NOT BY TIME. A rider covers ninety units in five
	# seconds and the lawn is a hundred and forty-four across: a timed run drove
	# off the property, fell down the surrounds, and reported a hundred and
	# twenty units of "ground rise" that was the machine falling off the world.
	var half: float = _mvp.get("property_node").lawn().lawn_half_extent() - 12.0
	await _reset()
	m = _mower()
	var low := INF
	var high := -INF
	Input.action_press("move_forward")
	t = 0.0
	while t < 8.0:
		await get_tree().physics_frame
		t += 1.0 / 576.0
		if Vector2(m.global_position.x - _centre.x,
				m.global_position.z - _centre.z).length() > half:
			break
		_note(worst, camera, m, aiming)
		# NOT THE FIRST HALF SECOND. `_reset()` keeps whatever height the last
		# run left the machine at, so the first thing it does is drop onto the
		# ground - and a drop is not the lawn rising.
		if t < 0.6:
			continue
		low = minf(low, m.global_position.y)
		high = maxf(high, m.global_position.y)
	Input.action_release("move_forward")
	worst["rise"] = (high - low) if high > low else 0.0
	return worst


func _note(worst: Dictionary, camera: Camera3D, machine: CharacterBody3D,
		aiming: float) -> void:
	worst["camera_roll"] = maxf(worst["camera_roll"],
		absf(rad_to_deg(camera.rotation.z)))
	worst["camera_pitch"] = maxf(worst["camera_pitch"],
		absf(rad_to_deg(camera.rotation.x - aiming)))
	# THE LEAN, NOT THE MESH'S ORIENTATION. Two of the three machines are
	# authored rotated in their own scenes, so reading the mesh basis measures
	# the rest pose. The spring states hold exactly what the lean ADDED.
	if machine == null:
		return
	var roll_state: Array = machine.get("_roll_state")
	var pitch_state: Array = machine.get("_pitch_state")
	if roll_state == null or pitch_state == null:
		return
	worst["chassis_roll"] = maxf(worst["chassis_roll"],
		absf(rad_to_deg(float(roll_state[0]))))
	worst["chassis_pitch"] = maxf(worst["chassis_pitch"],
		absf(rad_to_deg(float(pitch_state[0]))))
	# What the GROUND contributed, separately from what the driving did.
	var tilt: Vector2 = machine.get("_ground_tilt")
	worst["ground"] = maxf(worst["ground"], rad_to_deg(tilt.length()))


func _check(label: String, condition: bool) -> void:
	if condition:
		_passes += 1
		print("[HANDLING PROBE] %s: PASS" % label)
	else:
		_failures += 1
		printerr("[HANDLING PROBE] %s: FAIL" % label)


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
		await get_tree().physics_frame
		t += 1.0 / 576.0


func _step(frames: int = 1) -> void:
	for i in frames:
		await get_tree().process_frame


func _report() -> void:
	print("\n machine   deck   top     0-90%   stop    reverse  cross   radius   spin")
	print(" -------------------------------------------------------------------------")
	for row in _rows:
		print(" %-9s %-6.1f %-7.2f %-7.3f %-7.3f %-8.2f %-7.3f %-8.1f %-6.2f" % [
			row["id"], row["deck"], row["top"], row["accel"], row["stop"],
			row["reverse"], row["cross"], row["radius"], row["spin"]])
	print("\n u/s, seconds, units, rad/s. 'cross' is full forward to reversing.")
	print("[HANDLING PROBE] done")
