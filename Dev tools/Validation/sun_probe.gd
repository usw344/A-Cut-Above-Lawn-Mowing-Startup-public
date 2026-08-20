extends Node
## DEVELOPMENT ONLY, throwaway probe. Prints Sky3D's sun/moon altitude for every
## half hour so the time-of-day profile anchors can be placed against the actual
## sunrise/sunset this Skydome configuration produces, rather than guessed.
##
##   godot --path <project> "res://Dev tools/Validation/Sun Probe.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://Weather/Preset Manager/Preset Manager.tscn")
	var pm: Node = packed.instantiate()
	# Stop the preset manager driving the clock, or it overwrites every probe.
	pm.follow_world_clock = false
	get_tree().root.add_child(pm)
	await get_tree().process_frame
	await get_tree().process_frame

	var sky: Node = pm.get_node(^"Sky3D")
	var dome: Node = pm.get_node(^"Sky3D/Skydome")

	print("mode=", pm.get_node(^"Sky3D/TimeOfDay").celestials_calculations, " lat=", pm.get_node(^"Sky3D/TimeOfDay").latitude)
	print("hour, sun_altitude, moon_altitude")
	var h := 0.0
	while h < 24.0:
		sky.current_time = h
		await get_tree().process_frame
		print("%5.2f, %8.2f, %8.2f" % [h, dome.sun_altitude, dome.moon_altitude])
		h += 0.5
	get_tree().quit(0)
