extends Node
## DEVELOPMENT. Does the graphics-quality setting actually cost less?
##
## Two measurements, both on the REAL production mowing scene rather than on an
## empty world, because a quality tier that only shows a difference in a test
## harness has not shown anything.
##
##   GEOMETRY   the wood built at every level from the same seeds, headless:
##              species, instances, vertices and the mesh memory behind them.
##              Deterministic, so two runs agree.
##   RUNTIME    frames, draw calls and primitives in a real contract at the
##              level this run was launched with.
##
## Launched with `-- "--quality=low|medium|high"`. The level is applied through
## `GameSettings` - the real setting the player changes - so a run also proves
## the setting REACHES the wood, which is the thing most likely to be quietly
## wrong.

const LEVELS: PackedStringArray = ["low", "medium", "high"]

## Seeds the geometry table is averaged over. Enough that one unusual property
## does not decide the answer; few enough that the table is cheap.
const GEOMETRY_SEEDS: Array[int] = [11, 4242, 90210, 777001, 313377, 8]

## Frames sampled once the scene has settled.
const SAMPLE_FRAMES := 300

## The ONE contract every runtime measurement is taken on. A fixed seed makes
## the three levels comparable; any seed would do, this one is a large lawn with
## a wood around it, which is the case that costs something.
const RUNTIME_JOB_SEED := 4242

var _quality: String = "medium"
var _shot_dir: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			_quality = arg.substr(10).to_lower()
		elif arg.begins_with("--shots="):
			_shot_dir = arg.substr(8)
			DirAccess.make_dir_recursive_absolute(_shot_dir)
	_run.call_deferred()


func _run() -> void:
	print("\n============ QUALITY PROBE ============")
	_geometry_table()
	_gameplay_is_the_same()
	await _runtime()
	get_tree().quit(0)


# ==================================================================== geometry
##
## Builds the real `ACAForest` against the real generated property at each
## level. Nothing is rendered, so this is the cost of the CONTENT rather than of
## a particular frame.

func _geometry_table() -> void:
	print("\n---- geometry, mean over %d seeds ----" % GEOMETRY_SEEDS.size())
	print(" level     species   instances   vertices    mesh KB   build ms")
	print(" ---------------------------------------------------------------")
	var baseline := {}
	for level in LEVELS:
		var row := _measure_level(level)
		if baseline.is_empty():
			baseline = row
		print(" %-9s %7d %11.0f %10.0f %10.0f %10.2f" % [
			level, row["species"], row["instances"], row["vertices"],
			row["bytes"] / 1024.0, row["build_ms"]])
	print("")
	print(" Low against High, on the same six properties:")
	var low := _measure_level("low")
	var high := _measure_level("high")
	_ratio("vertices", low["vertices"], high["vertices"])
	_ratio("mesh memory", low["bytes"], high["bytes"])
	_ratio("instances", low["instances"], high["instances"])
	_ratio("build time", low["build_ms"], high["build_ms"])


## ---------------------------------------------------------------------------
## THE SAFETY CHECK THIS WHOLE PHASE STANDS ON
## ---------------------------------------------------------------------------
## A player must not be able to hit a rock on High that is not there on Low, and
## must not have MORE LAWN TO CUT at one level than another - a contract whose
## denominator moved with a graphics setting is a broken contract.
##
## `ACAForest` places no colliders at all and `ACALawnObstacles` never reads the
## quality level, so this cannot happen by construction. It is asserted anyway,
## on the real generated property, because "cannot happen by construction" is a
## claim about code that is one careless edit away from being false.
func _gameplay_is_the_same() -> void:
	print("
---- gameplay geometry is identical at every level ----")
	var failures := 0
	for property_seed in GEOMETRY_SEEDS:
		var reference := {}
		for level in LEVELS:
			GameSettings.set_value("quality", LEVELS.find(level))
			var params := ACAPropertyParams.for_seed(property_seed, 144)
			var features := ACAProperty.make_features(params, Vector2.ZERO)
			var terrain := ACATerrain.new()
			add_child(terrain)
			terrain.build(params, features)
			var lawn := ACALawn.new()
			lawn.build(params, terrain, features)
			var forest := ACAForest.new()
			add_child(forest)
			forest.build(params, terrain, lawn, features)
			var reading := {
				"mowable": lawn.total_item_count(),
				"cells": lawn.cell_count(),
				"solids": _solid_footprints(features),
				"colliders": _collider_count(forest),
			}
			if reference.is_empty():
				reference = reading
			elif reading != reference:
				failures += 1
				printerr("[QUALITY PROBE] seed %d differs at %s: %s vs %s"
					% [property_seed, level, reading, reference])
			forest.queue_free()
			lawn.free()
			terrain.queue_free()
	if failures == 0:
		print(" %d seeds x %d levels: mowable cells, solid footprints and"
			% [GEOMETRY_SEEDS.size(), LEVELS.size()])
		print(" collider counts all identical. PASS")
	else:
		printerr(" %d differences. FAIL" % failures)


## Every solid feature's footprint, rounded, as one comparable string. Position
## as well as count, so a rock that MOVED would be caught too.
func _solid_footprints(features: ACAFeatureSet) -> String:
	var out: Array[String] = []
	for feature in features.features():
		if not feature.is_solid():
			continue
		var box := feature.bounds()
		out.append("%s@%.2f,%.2f,%.2f" % [feature.feature_id(),
			box.position.x, box.position.z, box.size.x])
	out.sort()
	return ";".join(out)


## The wood should own no physics bodies at all, at any level.
func _collider_count(node: Node) -> int:
	var total := 0
	for child in _walk(node):
		if child is CollisionObject3D:
			total += 1
	return total


func _ratio(label: String, low: float, high: float) -> void:
	if high <= 0.0:
		return
	print("   %-14s %5.1f%% of High" % [label, low / high * 100.0])


func _measure_level(level: String) -> Dictionary:
	GameSettings.set_value("quality", LEVELS.find(level))
	var species := 0
	var instances := 0.0
	var vertices := 0.0
	var bytes := 0.0
	var build_ms := 0.0
	for property_seed in GEOMETRY_SEEDS:
		var params := ACAPropertyParams.for_seed(property_seed, 144)
		var features := ACAProperty.make_features(params, Vector2.ZERO)
		var terrain := ACATerrain.new()
		add_child(terrain)
		terrain.build(params, features)
		var lawn := ACALawn.new()
		lawn.build(params, terrain, features)
		var forest := ACAForest.new()
		add_child(forest)
		forest.build(params, terrain, lawn, features)
		var stats := forest.statistics()
		instances += float(stats.get("instances", 0))
		build_ms += float(stats.get("build_ms", 0.0))
		species = maxi(species, _species_count(forest))
		var counted := _count_geometry(forest)
		vertices += counted.x
		bytes += counted.y
		forest.queue_free()
		lawn.free()
		terrain.queue_free()
	var n := float(GEOMETRY_SEEDS.size())
	return {
		"species": species,
		"instances": instances / n,
		"vertices": vertices / n,
		"bytes": bytes / n,
		"build_ms": build_ms / n,
	}


func _species_count(forest: ACAForest) -> int:
	var quality := forest.graphics_quality()
	var trees: Array = ACAForest.TREE_SOURCES_MEDIUM
	if quality == &"low":
		trees = ACAForest.TREE_SOURCES_LOW
	elif quality == &"high":
		trees = ACAForest.TREE_SOURCES_HIGH
	return trees.size()


## Vertices actually submitted, and the bytes of unique mesh behind them. A
## MultiMesh draws one mesh many times, so the two answer different questions
## and both matter: vertices is what the GPU processes, bytes is what is
## resident.
func _count_geometry(node: Node) -> Vector2:
	var out := Vector2.ZERO
	var seen := {}
	for child in _walk(node):
		var mesh: Mesh = null
		var copies := 1
		if child is MultiMeshInstance3D:
			var mm := (child as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			mesh = mm.mesh
			copies = mm.instance_count
		elif child is MeshInstance3D:
			mesh = (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		var verts := _mesh_vertices(mesh)
		out.x += float(verts * copies)
		var id := mesh.get_instance_id()
		if not seen.has(id):
			seen[id] = true
			# Position, normal and UV at four bytes a channel is a fair estimate
			# of resident vertex data; the index buffer is small beside it.
			out.y += float(verts) * 32.0
	return out


func _mesh_vertices(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


# ===================================================================== runtime

func _runtime() -> void:
	var index := LEVELS.find(_quality)
	if index < 0:
		index = 1
		_quality = "medium"
	GameSettings.set_value("quality", index)
	print("\n---- runtime, a real contract at %s ----" % _quality.to_upper())

	GameSession.start_new_game()
	await _step(8)
	# THE SAME CONTRACT EVERY RUN, or the three levels are measured on three
	# different properties and the comparison is worthless. The first attempt
	# took whatever was on the board: Low drew a 192-unit lawn with ninety
	# thousand grass instances on it and read 56 fps, High drew a 144 and read
	# 89, and neither number was about the graphics setting.
	var job := JobManager.commission_offer(RUNTIME_JOB_SEED)
	if job == null:
		printerr("[QUALITY PROBE] could not commission the measurement contract")
		return
	JobManager.accept_job(job.id)
	JobManager.begin_new_job(job.id)
	# ONE SKY FOR ALL THREE SHOTS. The weather schedule is seeded per world, so
	# without this the three levels are photographed under three different skies
	# and the comparison is about the weather.
	WorldClock.set_weather("Partly Cloudy")

	var frames := 0
	while frames < 3600:
		if GameSession.current_screen() == ACAGameSession.Screen.MOWING \
				and not GameSession.is_changing_scene():
			break
		await get_tree().process_frame
		frames += 1
	# THE FIRST FRAMES OF ANY SCENE ARE SHADER COMPILATION, not the scene. Let
	# it settle before anything is believed.
	# THE JOB INTRO CARD COVERS THE WORLD. It is skippable with any key since
	# the game-feel pass; the world renders behind it either way, which is why
	# the draw-call and primitive counts were right while the screenshots were
	# black. Dismiss it so a shot shows the property.
	await _step(30)
	var skip := InputEventKey.new()
	skip.keycode = KEY_SPACE
	skip.physical_keycode = KEY_SPACE
	skip.pressed = true
	Input.parse_input_event(skip)
	await _step(4)
	skip.pressed = false
	Input.parse_input_event(skip)

	await _step(360)
	# THE SHOT IS TAKEN BEFORE THE FRAME CAP IS LIFTED. With vsync off and no
	# cap, `frame_post_draw` handed back a viewport texture with nothing but the
	# HUD in it; on the ordinary presentation path it captures the world.
	# Roll forward a little first so the shot is of a machine on a lawn rather
	# than of the spot it was parked on.
	Input.action_press("move_forward")
	await _step(90)
	Input.action_release("move_forward")
	await _step(20)
	await _shot("quality_%s" % _quality)

	# AFTER the scene change: entering a scene puts the project cap back, and
	# with a 240 cap in place a level that renders comfortably reads exactly
	# 240.0 and the comparison says nothing about it.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _step(60)

	var fps := 0.0
	var worst := INF
	var draws := 0.0
	var primitives := 0.0
	for _i in SAMPLE_FRAMES:
		await get_tree().process_frame
		var f := Performance.get_monitor(Performance.TIME_FPS)
		fps += f
		worst = minf(worst, f)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var n := float(SAMPLE_FRAMES)

	var forest_stats := {}
	var scene := get_tree().current_scene
	var property_node = scene.get("property_node") if scene != null else null
	if property_node != null and property_node.has_method(&"statistics"):
		forest_stats = property_node.call(&"statistics")

	print(" %-8s  %6.1f fps avg   %6.1f min   %7.0f draw calls   %9.0f primitives"
		% [_quality, fps / n, worst, draws / n, primitives / n])
	print(" video memory %.1f MB" % (Performance.get_monitor(
		Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
	if not forest_stats.is_empty():
		print(" property: %s" % forest_stats)


func _shot(file_name: String) -> void:
	if _shot_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("%s/%s.png" % [_shot_dir, file_name])


func _step(frames: int = 1) -> void:
	for _i in frames:
		await get_tree().process_frame
