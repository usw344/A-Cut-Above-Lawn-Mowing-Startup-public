extends Node
## DEVELOPMENT ONLY. Renders the things the BUSINESS put on a contract - the
## work truck, the trailer, and an autonomous machine working beside the player -
## in the REAL mowing scene, and measures where they ended up.
##
##   godot --path . "res://Dev tools/Validation/Site Probe.tscn" \
##       -- "--site-output=<dir>" "--save-root=<dir>"
##
## Needs a real renderer.
##
## WHY THIS EXISTS
##
## `Property Probe` renders a property built on its own, and the truck and the
## escort are not part of a property - they belong to the mowing runtime, which
## only exists when a contract is being played. So neither was visible to any
## existing tool, and the first version of the truck shipped at a fifth of the
## size it should have been, parked in front of the machine instead of behind
## it, filling the bottom of the screen with a grey slab. That is exactly the
## class of fault a screenshot finds in one second and no assertion finds at all.
##
## It also ASSERTS the two things about the truck that must be true whatever it
## looks like: that it is outside the mowable lawn, and that the point the player
## is told to drive to is the point that notices them arriving.

const DEFAULT_OUTPUT_DIR := "user://site_probe"

## name, position relative to the truck, look-at target, fov
const SHOTS := [
	["truck-side", Vector3(16.0, 7.0, 16.0), Vector3(0.0, 2.0, -13.0), 50.0],
	["truck-behind-machine", Vector3(-26.0, 9.0, 6.0), Vector3(0.0, 2.0, -13.0), 55.0],
	["arrival-wide", Vector3(-34.0, 22.0, 34.0), Vector3(6.0, 0.0, -13.0), 55.0],
]

var _dir: String = DEFAULT_OUTPUT_DIR
var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--site-output="):
			_dir = arg.trim_prefix("--site-output=")
	DirAccess.make_dir_recursive_absolute(_dir)
	print("[SITE] writing to %s" % _dir)
	_run.call_deferred()


func _run() -> void:
	# A MACHINE IN THE YARD BEFORE THE CONTRACT STARTS, so the escort is on the
	# lawn to be looked at. Granted rather than bought: this is a rendering
	# probe, not a test of the shop.
	GameSession.start_new_game()
	await _await_screen(ACAGameSession.Screen.TOWN)
	var uid := Equipment.dev_grant_autonomous("auto_grounds")
	Equipment.set_escort_unit(uid)

	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.debug_force_offer()
		offers = JobManager.available_jobs()
	if offers.is_empty():
		printerr("[SITE] no contract to take")
		get_tree().quit(1)
		return
	JobManager.accept_job(offers[0].id)
	JobManager.begin_new_job(offers[0].id)

	await _await_screen(ACAGameSession.Screen.MOWING)
	await _settle(2.0)

	var scene := get_tree().current_scene
	var truck := scene.get_node_or_null(^"Work Truck") as ACAWorkTruck
	var escort := scene.get_node_or_null(^"Autonomous Mower") as ACAAutoMower
	var property_node: ACAProperty = scene.call(&"property")

	_measure(truck, escort, property_node)

	# The HUD and the intro card are in the way of the thing being looked at.
	var ui := scene.get_node_or_null(^"Gameplay UI") as CanvasItem
	if ui != null:
		ui.visible = false
	AppUI.clear_notifications()
	await _settle(0.5)

	if truck != null:
		await _render(truck, scene)

	# LET THE ESCORT WORK for a while, then look at what it did. A machine that
	# drives beautifully for one frame and stops is not a working machine.
	if escort != null:
		await _settle(12.0)
		_check(escort.cells_cut() > 0,
			"the escort cut %d cells in twelve seconds" % escort.cells_cut())
		_check(not escort.is_finished() or escort.cells_cut() > 0,
			"it is either still working or finished having done something")
		await _render_escort(escort, scene)

	print("[SITE] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ==================================================================== measure

func _measure(truck: ACAWorkTruck, escort: ACAAutoMower,
		property_node: ACAProperty) -> void:
	_check(truck != null, "the contract has a work truck on it")
	if truck == null or property_node == null:
		return
	var lawn := property_node.lawn()

	# THE TRUCK MUST NOT STAND ON THE CONTRACT. A cell under the truck is a cell
	# the player is paid for and cannot see, and the completion denominator
	# counts it either way.
	var at := truck.service_point()
	_check(not lawn.is_mowable(at),
		"the service point is off the mowable lawn")
	var bounds := lawn.lawn_bounds()
	var inside := at.x >= bounds.position.x and at.x <= bounds.end.x \
		and at.z >= bounds.position.z and at.z <= bounds.end.z
	_check(not inside, "and outside the lawn rectangle entirely")

	# THE MARKER AND THE TRIGGER ARE THE SAME PLACE. If the HUD says "go there"
	# and the area that notices is somewhere else, the player stands on the
	# marker and nothing happens.
	var area := truck.get_node_or_null(^"Service Area") as Area3D
	_check(area != null, "the truck has a service area")
	if area != null:
		var shape := area.get_child(0) as CollisionShape3D
		var centre := area.global_transform * shape.position
		var apart := Vector2(centre.x - at.x, centre.z - at.z).length()
		_check(apart < 1.0,
			"the marker and the area agree to within %.2f units" % apart)

	# SIZE. A truck the size of a mower is a toy; one the size of a house is a
	# wall. Measured against the machine's own deck, which is authored in the
	# same world units.
	var body := truck.get_node_or_null(^"Truck") as Node3D
	if body != null:
		var length := 0.0
		for node in body.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.mesh != null:
				length = maxf(length, mesh.mesh.get_aabb().size.z
					* ACAWorkTruck.MODEL_SCALE)
		_check(length > 12.0 and length < 34.0,
			"the truck is %.1f units long - a pickup beside a ride-on" % length)

	_check(escort != null, "the escort was deployed")
	if escort != null:
		_check(escort.is_working() or escort.is_finished(),
			"and is doing something")


# ===================================================================== render

func _render(truck: ACAWorkTruck, scene: Node) -> void:
	var camera := Camera3D.new()
	camera.name = "Site Camera"
	camera.near = 0.1
	camera.far = 3000.0
	scene.add_child(camera)
	camera.make_current()
	for shot in SHOTS:
		var offset: Vector3 = shot[1]
		var target: Vector3 = truck.global_transform * (shot[2] as Vector3)
		camera.global_position = truck.global_transform * offset
		camera.look_at(target, Vector3.UP)
		camera.fov = float(shot[3])
		await _settle(0.35)
		await _capture(String(shot[0]))
	camera.queue_free()


## The escort, from above and behind, with the lawn it has been over in shot.
func _render_escort(escort: ACAAutoMower, scene: Node) -> void:
	var camera := Camera3D.new()
	camera.name = "Escort Camera"
	camera.near = 0.1
	camera.far = 3000.0
	scene.add_child(camera)
	camera.make_current()
	camera.global_position = escort.global_position + Vector3(-18.0, 12.0, 18.0)
	camera.look_at(escort.global_position, Vector3.UP)
	camera.fov = 55.0
	await _settle(0.35)
	await _capture("escort-working")
	camera.global_position = escort.global_position + Vector3(0.0, 46.0, 0.1)
	camera.look_at(escort.global_position, Vector3.UP)
	camera.fov = 70.0
	await _settle(0.35)
	await _capture("escort-from-above")
	camera.queue_free()


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, label]
	if image.save_png(path) == OK:
		print("[SITE] %s" % path)


## WAIT FOR THE SCREEN **AND** FOR THE TRANSITION TO FINISH.
##
## `current_screen()` flips to its destination in the middle of the swap, while
## `_changing_scene` is still true - and `_change_scene()` refuses a second
## request during that window. The first version of this probe waited on the
## screen alone, so it asked for the mowing scene one frame too early, the
## request was silently dropped, and it sat in the town forever. That window is
## precisely why the tour has an `_await_screen` of its own.
func _await_screen(screen: int, max_frames: int = 1800) -> void:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen 				and not GameSession.is_changing_scene() 				and get_tree().current_scene != null:
			return
		await get_tree().process_frame
		frames += 1
	printerr("[SITE] gave up waiting for screen %d" % screen)


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	await get_tree().process_frame


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
		print("[SITE]  ok   %s" % message)
	else:
		_fail += 1
		print("[SITE] FAIL  %s" % message)
