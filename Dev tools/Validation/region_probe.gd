extends Node
## DEVELOPMENT ONLY. Renders EVERY REGION'S HUB, so five markets can be compared
## side by side from pixels rather than from a layout table.
##
##   godot --path . "res://Dev tools/Validation/Region Probe.tscn" \
##       -- "--region-output=<dir>" [--region-conditions=clear,evening,rain]
##
## Needs a REAL renderer; it captures the viewport. Nothing here asserts - it
## produces images and a printed index, and the judgement is made by looking.
##
## The question this probe exists to answer is the one the pass is measured on:
##
##   CAN THE REGION BE IDENTIFIED FROM THE SCREENSHOT, WITH THE UI COVERED UP?
##
## So every region is shot from its own overview camera under the same
## conditions, and the five images are meant to be looked at as a set.
##
## IT ALSO MEASURES. A hub is a screen the player stands still on, so the number
## that matters is the steady frame rate with the traffic running, and it is
## printed beside every shot: five markets of very different density is exactly
## the situation where a layout table quietly costs more than it looks.

const DEFAULT_OUTPUT_DIR := "user://region_probe"
const SETTLE := 70

## `weather` is a `WorldClock` preset; `hour` is driven through the clock's own
## public API, exactly as the game does it.
const CONDITIONS := {
	"clear": {"weather": "Clear", "hour": 11.0},
	"morning": {"weather": "Clear", "hour": 8.2},
	"evening": {"weather": "Clear", "hour": 16.6},
	"overcast": {"weather": "Overcast", "hour": 12.0},
	"rain": {"weather": "Rain", "hour": 13.0},
	"mist": {"weather": "Mist", "hour": 8.0},
}

var _dir: String = DEFAULT_OUTPUT_DIR
var _wanted: PackedStringArray = ["clear"]
var _shots: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dir = _argument("--region-output=", DEFAULT_OUTPUT_DIR)
	_wanted = _argument("--region-conditions=", "clear").split(",", false)
	DirAccess.make_dir_recursive_absolute(_dir)
	print("[REGION PROBE] writing to %s" % _dir)
	_run.call_deferred()


func _argument(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback


func _run() -> void:
	GameSession.start_new_game()
	await _wait_for_screen(ACAGameSession.Screen.TOWN)

	# Every market open, and established enough that the lots have their plant
	# on them: this probe is about the PLACES, not about the progression.
	for region in ACAServiceTerritory.REGION_ORDER:
		Territory.dev_grant_region(region)
		Territory.dev_set_presence(region, 74.0)

	for name in _wanted:
		var condition: Dictionary = CONDITIONS.get(name, CONDITIONS["clear"])
		# `set_weather()` TAKES the schedule until it is handed back, so a probe
		# that runs for several game hours is never rained off halfway down its
		# own list. See `ACAWorldClock.resume_scheduled_weather()`.
		WorldClock.set_weather(String(condition["weather"]))
		WorldClock.advance_to_hour(float(condition["hour"]))
		for region in ACAServiceTerritory.REGION_ORDER:
			Territory.set_active_region(region)
			GameSession.go_to_town()
			await _wait_for_region(region)
			WorldClock.advance_to_hour(float(condition["hour"]))
			await _settle(SETTLE)
			var rate: Vector2 = await _measure(60)
			await _shot("%s-%s" % [
				String(ACAServiceTerritory.region_id(region)), name])
			print("[REGION PROBE]   %-16s %-9s %6.1f fps avg, %6.1f min"
				% [ACAServiceTerritory.region_name(region), name,
					rate.x, rate.y])

	WorldClock.resume_scheduled_weather()
	print("[REGION PROBE] done, %d shots" % _shots)
	get_tree().quit(0)


# ==================================================================== plumbing

func _wait_for_screen(screen: int) -> void:
	var guard := 0
	while GameSession.current_screen() != screen and guard < 2400:
		guard += 1
		await get_tree().process_frame


## WAIT FOR THE HUB ITSELF, not for the screen state.
##
## Moving from one hub to another never changes `current_screen()` - every hub
## and the Business Town are all `Screen.TOWN`, deliberately - so waiting on the
## screen returns instantly and photographs the region the player just left with
## the new region's name fading in over it. Two of the first five shots this
## probe ever took were exactly that.
func _wait_for_region(region: int) -> void:
	await _wait_for_screen(ACAGameSession.Screen.TOWN)
	var guard := 0
	while guard < 2400:
		guard += 1
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene == null:
			continue
		if region == ACAServiceTerritory.HOME_REGION:
			# The home market is the authored town, which has no hub on it.
			if not scene.has_method(&"hub"):
				return
			continue
		if not scene.has_method(&"hub"):
			continue
		var hub: ACARegionalHub = scene.call(&"hub")
		if hub != null and hub.region() == region:
			return


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## Average and worst frame rate over `frames` frames, AFTER the scene has
## settled. Measured from the engine's own monitor rather than from a delta
## accumulated here, so it is the same number the performance overlay shows.
func _measure(frames: int) -> Vector2:
	var total := 0.0
	var worst := INF
	for i in frames:
		await get_tree().process_frame
		var fps := Performance.get_monitor(Performance.TIME_FPS)
		total += fps
		worst = minf(worst, fps)
	return Vector2(total / float(maxi(frames, 1)), worst)


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_warning("[REGION PROBE] no image for %s" % label)
		return
	var path := "%s/%s.png" % [_dir, label]
	image.save_png(path)
	_shots += 1
	print("[REGION PROBE] %s" % path)
