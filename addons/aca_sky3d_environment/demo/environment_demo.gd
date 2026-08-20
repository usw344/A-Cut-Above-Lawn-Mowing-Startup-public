extends Node3D
## STANDALONE DEMO for `ACASky3DEnvironment`.
##
## This scene is the package's own proof that it does not need a game. It
## builds its own ground, its own props, its own camera and its own Sky3D at
## runtime, and drives the adapter through nothing but its public API.
##
## If this scene ever needs an import from outside `res://addons/`, the
## boundary has been broken and the package is no longer portable.
##
##   godot --path <project> "res://addons/aca_sky3d_environment/demo/Environment Demo.tscn"
##
## Keys:  1/2/3 weather · Q/W/E/R time · F1/F2/F3 quality · Space auto-cycle
## Headless capture:
##   ... -- "--demo-shots=<dir>"   renders the whole matrix and quits.

const SKY3D_SCRIPT := "res://addons/sky_3d/src/Sky3D.gd"

const WEATHERS := ["Clear", "Foggy", "Rain"]
const TIMES := [["morning", 7.0], ["day", 12.0], ["evening", 16.3], ["night", 22.0]]

var env: ACASky3DEnvironment = null
var rig: ACAPrecipitationRig = null
var _sky: WorldEnvironment = null
var _camera: Camera3D = null
var _label: Label = null
var _hour: float = 12.0
var _weather: int = 0
var _quality: int = 0
var _auto: bool = false
var _shots_dir: String = ""


func _ready() -> void:
	_build_world()
	_build_sky()
	_build_environment()
	_build_ui()
	_shots_dir = _arg("--demo-shots=")
	if not _shots_dir.is_empty():
		_run_capture.call_deferred()


# ======================================================================= world

func _build_world() -> void:
	# Ground. Big enough that the fog ramp has somewhere to happen.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	plane.subdivide_width = 24
	plane.subdivide_depth = 24
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.40, 0.24)
	gm.roughness = 0.95
	plane.material = gm
	ground.mesh = plane
	add_child(ground)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(900, 1, 900)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	add_child(body)

	# Props at a spread of distances, so near / mid / far fog is all visible in
	# one frame. That is the whole point of the demo: fog is about DEPTH, and a
	# scene with nothing at 200 units cannot show it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260820
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.62, 0.60, 0.56)
	pillar_mat.roughness = 0.85
	for i in range(150):
		var dist := 12.0 + pow(rng.randf(), 1.6) * 420.0
		var angle := rng.randf_range(-1.35, 1.35)
		var h := rng.randf_range(3.0, 16.0)
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(1.2, 3.4), h, rng.randf_range(1.2, 3.4))
		bm.material = pillar_mat
		m.mesh = bm
		m.position = Vector3(sin(angle) * dist, h * 0.5, -cos(angle) * dist)
		add_child(m)

	# A near subject, so "is the foreground still sharp?" has an answer.
	var subject := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.6, 1.1, 2.6)
	var subj_mat := StandardMaterial3D.new()
	subj_mat.albedo_color = Color(0.85, 0.35, 0.10)
	subj_mat.roughness = 0.6
	sm.material = subj_mat
	subject.mesh = sm
	subject.position = Vector3(0.9, 0.55, -4.0)
	subject.name = "Subject"
	add_child(subject)

	_camera = Camera3D.new()
	_camera.position = Vector3(0, 2.2, 1.5)
	_camera.rotation_degrees = Vector3(-4, 0, 0)
	_camera.far = 2000.0
	_camera.current = true
	add_child(_camera)


func _build_sky() -> void:
	# A vanilla Sky3D, built the way the addon itself intends.
	#
	# Sky3D's `_initialize()` runs on NOTIFICATION_ENTER_TREE and creates its
	# own Environment, sky material, SunLight, MoonLight, Skydome and TimeOfDay
	# if they are missing. So the whole setup is: make the node, give it the
	# script, put it in the tree.
	#
	# Assigning `environment` BEFORE it is in the tree does not work and should
	# not be attempted: Sky3D overrides `_set("environment")` to forward to
	# `sky.environment`, and `sky` is still null that early.
	_sky = WorldEnvironment.new()
	_sky.name = "Sky3D"
	_sky.set_script(load(SKY3D_SCRIPT))
	add_child(_sky)
	# One clock only: the demo drives the hour through the adapter.
	_sky.set(&"enable_game_time", false)
	_sky.set(&"enable_editor_time", false)


func _build_environment() -> void:
	rig = ACAPrecipitationRig.new()
	rig.name = "Precipitation"
	add_child(rig)

	env = ACASky3DEnvironment.new()
	env.name = "Environment Adapter"
	add_child(env)
	env.bind(_sky, _sky.get_node_or_null(^"Skydome"))
	env.set_precipitation_rig(rig)
	env.set_tracking_target(_camera)
	env.set_quality(&"High")
	env.apply_immediate(&"Clear", _hour)
	_refresh()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(18, 14)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	add_child(layer)


# ======================================================================= input

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.is_echo():
		return
	match (e as InputEventKey).keycode:
		KEY_1: _set_weather(0)
		KEY_2: _set_weather(1)
		KEY_3: _set_weather(2)
		KEY_Q: _set_hour(7.0)
		KEY_W: _set_hour(12.0)
		KEY_E: _set_hour(16.3)
		KEY_R: _set_hour(22.0)
		KEY_F1: _set_quality(0)
		KEY_F2: _set_quality(1)
		KEY_F3: _set_quality(2)
		KEY_SPACE:
			_auto = not _auto
			_refresh()
		KEY_ESCAPE:
			get_tree().quit()


func _process(delta: float) -> void:
	if _auto:
		_hour = fposmod(_hour + delta * 0.9, 24.0)
		env.set_time_of_day(_hour)
		_refresh()


func _set_weather(i: int) -> void:
	_weather = i
	env.set_weather(StringName(WEATHERS[i]))
	_refresh()


func _set_hour(h: float) -> void:
	_hour = h
	env.set_time_of_day(h)
	_refresh()


func _set_quality(i: int) -> void:
	var ids := env.quality_ids()
	# quality_ids() is sorted; present them worst-to-best regardless of name.
	var order := ["High", "Medium", "Low"]
	var wanted: String = order[i] if ids.has(order[i]) else String(ids[0])
	_quality = i
	env.set_quality(StringName(wanted))
	_refresh()


func _refresh() -> void:
	if _label == null:
		return
	var state := env.current_visual_state()
	_label.text = "\n".join([
		"ACA Sky3D Environment — standalone demo",
		"weather  %s        (1 Clear  2 Fog  3 Rain)" % state["weather"],
		"time     %02d:%02d  %s   (Q morning  W day  E evening  R night)"
			% [int(_hour), int(fposmod(_hour, 1.0) * 60.0), state["time_profile"]],
		"quality  %s        (F1 High  F2 Medium  F3 Low)" % state["quality"],
		"rain     %.2f       auto-cycle %s (Space)"
			% [state["rain_intensity"], "ON" if _auto else "off"],
	])


# ===================================================================== capture

func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


## Renders the whole matrix and quits. Used by `Environment Test` so the demo
## is proven to work headlessly as well as by hand.
func _run_capture() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	for q in ["High", "Medium", "Low"]:
		env.set_quality(StringName(q))
		for w: String in WEATHERS:
			for t: Array in TIMES:
				env.apply_immediate(StringName(w), float(t[1]))
				_hour = float(t[1])
				_refresh()
				for i in range(24):
					await get_tree().process_frame
				var img := get_viewport().get_texture().get_image()
				var path := "%s/%s-%s-%s.png" % [
					_shots_dir, q.to_lower(), w.to_lower(), String(t[0])]
				img.save_png(path)
				print("[DEMO] ", path)
	print("[DEMO] done")
	get_tree().quit(0)
