extends Node
## DEVELOPMENT ONLY. MEASURES temporal instability in the Business Town.
##
##   godot --path <project> "res://Dev tools/Validation/Flicker Probe.tscn" \
##     -- "--flicker-output=<dir>"
##
## Needs a real renderer.
##
## ---------------------------------------------------------------------------
## WHY A SCREENSHOT CANNOT ANSWER THIS
## ---------------------------------------------------------------------------
##
## "The shadows flicker" is a statement about the difference between CONSECUTIVE
## FRAMES. One screenshot of a flickering town and one of a stable town look
## identical. So this holds the camera still, captures a run of frames, and
## reports the mean absolute difference between each pair.
##
## A converged, stationary scene should measure near zero. Anything else is
## something moving that nobody asked to move.
##
## ---------------------------------------------------------------------------
## THREE CONDITIONS, SO THE CAUSE IS ISOLATED RATHER THAN GUESSED
## ---------------------------------------------------------------------------
##
##   A  clock STOPPED, shadows ON    - does the adapter settle at all?
##   B  clock RUNNING, shadows ON    - the real scenario the player reported
##   C  clock RUNNING, shadows OFF   - the proposed fix
##
## If A is high, the adapter never converges. If A is low and B is high, the
## moving sun is the cause. If C is low, removing the shadows is the fix.

const DEFAULT_OUTPUT_DIR := "user://flicker_probe"
## Frames compared per condition. Enough to catch a slow crawl, cheap enough to
## run in a validation pass.
const SAMPLES := 14
## Frames allowed for the light adapter to settle before measuring.
const SETTLE_FRAMES := 90
## Comparison resolution. NEAREST rather than bilinear on purpose: smoothing is
## exactly what would hide a one-pixel shimmer.
const COMPARE_W := 480
const COMPARE_H := 270

var _dir: String = DEFAULT_OUTPUT_DIR
var _results: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dir = _output_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	_run.call_deferred()


func _output_dir() -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--flicker-output="):
			return arg.trim_prefix("--flicker-output=")
	return DEFAULT_OUTPUT_DIR


func _run() -> void:
	GameSession.start_new_game()
	await _await_screen(ACAGameSession.Screen.TOWN)
	await _settle(60)

	var scene := get_tree().current_scene
	var lights := scene.get_node_or_null(^"Town Light Adapter") as ACATownLightAdapter
	var sun := _find_sun(scene)
	if sun == null:
		printerr("[FLICKER] no Sun DirectionalLight3D in the town")
		get_tree().quit(1)
		return
	print("[FLICKER] sun shadow_enabled=%s mode=%d max_distance=%.0f"
		% [str(sun.shadow_enabled), sun.directional_shadow_mode,
			sun.directional_shadow_max_distance])
	print("[FLICKER] light adapter bound: %s" % str(lights != null and lights.is_bound()))

	# The town HUD has a clock label that ticks; it would count as flicker and
	# it is not what is being measured.
	_hide_ui(scene)

	# Each condition FORCES its own shadow state rather than inheriting the
	# scene's. Otherwise changing the scene default silently turns the whole
	# probe into three measurements of the same thing.
	var authored_shadows := sun.shadow_enabled

	# ---- A: clock stopped, shadows on. Isolates the adapter's own convergence.
	sun.shadow_enabled = true
	WorldClock.set_running(false)
	await _settle(SETTLE_FRAMES)
	await _measure("A  clock stopped, shadows ON")

	# ---- B: clock running, shadows on. What the player reported.
	WorldClock.set_running(true)
	await _settle(SETTLE_FRAMES)
	await _measure("B  clock running, shadows ON")

	# ---- C: clock running, shadows off. What the town ships.
	sun.shadow_enabled = false
	await _settle(SETTLE_FRAMES)
	await _measure("C  clock running, shadows OFF")

	sun.shadow_enabled = authored_shadows
	print("[FLICKER] restored authored shadow_enabled=%s" % str(authored_shadows))

	print("\n[FLICKER] ---- summary (mean abs frame-to-frame difference, 0-255) ----")
	for row: Array in _results:
		print("[FLICKER] %-30s mean %6.3f   peak %6.3f" % [row[0], row[1], row[2]])
	print("[FLICKER] done")
	get_tree().quit(0)


## Capture a run of frames with nothing intentionally moving, and report how
## different consecutive frames actually are.
func _measure(label: String) -> void:
	var frames: Array[Image] = []
	for i in range(SAMPLES):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(COMPARE_W, COMPARE_H, Image.INTERPOLATE_NEAREST)
		img.convert(Image.FORMAT_RGB8)
		frames.append(img)

	var total := 0.0
	var peak := 0.0
	for i in range(1, frames.size()):
		var d := _difference(frames[i - 1], frames[i])
		total += d
		peak = maxf(peak, d)
	var mean := total / maxf(float(frames.size() - 1), 1.0)
	_results.append([label, mean, peak])
	print("[FLICKER] %-30s mean %6.3f   peak %6.3f" % [label, mean, peak])

	# Keep one frame per condition so the LOOK can be judged alongside the
	# stability number - a perfectly stable black screen also measures zero.
	frames[-1].save_png("%s/%s.png" % [_dir, label.split(" ")[0].to_lower()])
	var full := get_viewport().get_texture().get_image()
	full.save_png("%s/%s-full.png" % [_dir, label.split(" ")[0].to_lower()])


func _difference(a: Image, b: Image) -> float:
	var da := a.get_data()
	var db := b.get_data()
	if da.size() != db.size():
		return -1.0
	var total := 0
	var count := 0
	# Every third byte: one channel is enough to detect a shimmer and this runs
	# in GDScript.
	var i := 0
	while i < da.size():
		total += absi(int(da[i]) - int(db[i]))
		count += 1
		i += 3
	return float(total) / maxf(float(count), 1.0)


# ==================================================================== helpers

func _find_sun(scene: Node) -> DirectionalLight3D:
	var direct := scene.get_node_or_null(^"BusinessTown/Sun")
	if direct is DirectionalLight3D:
		return direct
	for node in _all(scene):
		if node is DirectionalLight3D and String(node.name).to_lower().contains("sun"):
			return node
	return null


func _all(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_all(child))
	return out


func _hide_ui(scene: Node) -> void:
	for node in _all(scene):
		if node is CanvasLayer or node is Control:
			node.visible = false
	AppUI.clear_notifications()


func _await_screen(screen: int) -> void:
	var guard := 0
	while GameSession.current_screen() != screen and guard < 600:
		await get_tree().process_frame
		guard += 1
	await _settle(4)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
