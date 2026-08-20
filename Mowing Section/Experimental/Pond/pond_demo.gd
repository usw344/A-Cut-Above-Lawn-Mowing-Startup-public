extends Node3D
## EXPERIMENTAL. Standalone development scene for `ACAPond`.
##
##   godot --path <project> "res://Mowing Section/Experimental/Pond/Pond Demo.tscn"
##
## Loads none of the game: it builds its own ground, lighting and camera. That
## is the point — the pond tool must be usable and reviewable without standing
## up a mowing job.
##
## Keys:  arrows radius/depth · [ ] water level · N new seed · C toggle carve
##        T orbit camera · Space cycle a demo sweep
## Headless capture:
##   ... -- "--pond-shots=<dir>"   renders a review set and quits.

const SOURCE_SIZE := 90.0
## Subdivisions of the source ground. THE thing the carver depends on: at 4
## subdivisions the same pond parameters are refused, which the capture set
## deliberately demonstrates.
const SOURCE_SUBDIVISIONS := 110

var pond: ACAPond = null
var _source: MeshInstance3D = null
var _camera: Camera3D = null
var _label: Label = null
var _orbit: float = 0.0
var _orbiting: bool = false
var _shots_dir: String = ""


func _ready() -> void:
	_build_world()
	_build_pond()
	_build_ui()
	_shots_dir = _arg("--pond-shots=")
	if not _shots_dir.is_empty():
		_run_capture.call_deferred()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.46, 0.72)
	sky_mat.sky_horizon_color = Color(0.78, 0.84, 0.88)
	sky_mat.ground_bottom_color = Color(0.32, 0.34, 0.30)
	sky_mat.ground_horizon_color = Color(0.72, 0.76, 0.74)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-46.0, -38.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = true
	add_child(sun)

	# THE SOURCE. Dense enough to carry a pond; the capture set also builds a
	# coarse one to show the refusal.
	_source = MeshInstance3D.new()
	_source.name = "Source Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(SOURCE_SIZE, SOURCE_SIZE)
	plane.subdivide_width = SOURCE_SUBDIVISIONS
	plane.subdivide_depth = SOURCE_SUBDIVISIONS
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.33, 0.42, 0.25)
	mat.roughness = 0.95
	plane.material = mat
	_source.mesh = plane
	add_child(_source)

	_camera = Camera3D.new()
	_camera.far = 500.0
	_camera.current = true
	add_child(_camera)
	_place_camera(38.0)


func _build_pond() -> void:
	pond = ACAPond.new()
	pond.name = "Pond"
	add_child(pond)
	pond.source_path = pond.get_path_to(_source)
	pond.pond_centre = Vector3.ZERO
	pond.radius = 11.0
	pond.ellipse_ratio = 1.35
	pond.depth = 2.4
	pond.bank_fraction = 0.5
	pond.irregularity = 0.2
	pond.water_level = -0.45
	pond.carved.connect(func(msg: String) -> void: _refresh(msg))
	pond.carve()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(18, 14)
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	add_child(layer)


func _place_camera(distance: float) -> void:
	var height := distance * 0.42
	_camera.position = Vector3(
		sin(_orbit) * distance, height, cos(_orbit) * distance)
	_camera.look_at(Vector3(0, -1.0, 0), Vector3.UP)


# ======================================================================= input

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.is_echo():
		return
	match (e as InputEventKey).keycode:
		KEY_UP: pond.radius = minf(pond.radius + 1.0, 34.0)
		KEY_DOWN: pond.radius = maxf(pond.radius - 1.0, 3.0)
		KEY_RIGHT: pond.depth = minf(pond.depth + 0.25, 8.0)
		KEY_LEFT: pond.depth = maxf(pond.depth - 0.25, 0.3)
		KEY_BRACKETLEFT: pond.water_level -= 0.1
		KEY_BRACKETRIGHT: pond.water_level += 0.1
		KEY_N:
			pond.pond_seed = randi() & 0x7FFFFFFF
		KEY_C:
			if pond.is_built():
				pond.restore_source()
				_refresh("Source restored — the ORIGINAL mesh, untouched.")
			else:
				pond.carve()
		KEY_T:
			_orbiting = not _orbiting
		KEY_ESCAPE:
			get_tree().quit()
	_refresh("")


func _process(delta: float) -> void:
	if _orbiting:
		_orbit += delta * 0.35
		_place_camera(38.0)


func _refresh(message: String) -> void:
	if _label == null:
		return
	var result := pond.last_result()
	var lines := [
		"ACA Pond — experimental carver + water   (NOT part of job generation)",
		"radius %.1f   depth %.2f   ratio %.2f   bank %.2f   irregularity %.2f"
			% [pond.radius, pond.depth, pond.ellipse_ratio, pond.bank_fraction,
				pond.irregularity],
		"water level %.2f   seed %d   built %s"
			% [pond.water_level, pond.pond_seed, str(pond.is_built())],
	]
	if result != null:
		lines.append("carver: %s" % result.message)
	if not message.is_empty():
		lines.append(message)
	lines.append("arrows radius/depth · [ ] water · N seed · C carve/restore · T orbit")
	_label.text = "\n".join(lines)


# ===================================================================== capture

func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


## A review set, plus the two cases that PROVE the guarantees: the source mesh
## is unchanged, and a mesh too coarse to carry a pond is refused rather than
## turned into a three-triangle pit.
func _run_capture() -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)

	await _shot("01-pond-overview")

	_orbit = 0.9
	_place_camera(24.0)
	await _shot("02-pond-close")

	_orbit = 0.0
	_place_camera(14.0)
	await _shot("03-shoreline")

	_place_camera(38.0)
	pond.water_level = -1.6
	await _shot("04-low-water")
	pond.water_level = -0.45

	pond.irregularity = 0.0
	await _shot("05-no-irregularity")
	pond.irregularity = 0.2

	pond.depth = 5.5
	pond.bank_fraction = 0.2
	await _shot("06-deep-steep")
	pond.depth = 2.4
	pond.bank_fraction = 0.5

	# THE NON-DESTRUCTIVE PROOF, from the pixels rather than from a comment.
	pond.restore_source()
	await _shot("07-source-restored")
	pond.carve()

	# THE DENSITY REFUSAL. A coarse plane cannot carry this pond, and the
	# carver must say so instead of producing something ugly.
	var coarse := PlaneMesh.new()
	coarse.size = Vector2(SOURCE_SIZE, SOURCE_SIZE)
	coarse.subdivide_width = 3
	coarse.subdivide_depth = 3
	var analysis := ACAPondCarver.analyse(coarse, pond.params())
	print("[POND] coarse-mesh analysis ok=%s  in_footprint=%d  %s"
		% [str(analysis["ok"]), int(analysis["in_footprint"]),
			String(analysis["message"])])
	var fine := ACAPondCarver.analyse(_source.mesh, pond.params())
	print("[POND] fine-mesh analysis   ok=%s  in_footprint=%d"
		% [str(fine["ok"]), int(fine["in_footprint"])])

	# And the exclusion API, printed so the numbers can be checked.
	var centre_in := pond.contains_world_point(Vector3.ZERO)
	var outside := pond.contains_world_point(Vector3(40, 0, 40))
	var bounds := pond.get_exclusion_bounds()
	var polygon := pond.get_exclusion_polygon(24)
	print("[POND] exclusion: centre inside=%s  far point inside=%s"
		% [str(centre_in), str(outside)])
	print("[POND] exclusion bounds %s" % str(bounds))
	print("[POND] exclusion polygon %d points, first %s"
		% [polygon.size(), str(polygon[0]) if polygon.size() > 0 else "none"])
	print("[POND] submerged at centre=%s  at bank=%s"
		% [str(pond.is_submerged(Vector3(0, -1.5, 0))),
			str(pond.is_submerged(Vector3(0, 2.0, 0)))])
	print("[POND] done")
	get_tree().quit(0)


func _shot(name: String) -> void:
	_refresh("")
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_shots_dir, name]
	img.save_png(path)
	print("[POND] ", path)
