extends Node3D
## DEVELOPMENT ONLY. Renders a generated property from a fixed set of viewpoints
## and writes one image per shot, so the terrain, the grass, the cut, the forest
## and the pond can be judged from pixels instead of from assertions.
##
##   godot --path . "res://Dev tools/Validation/Property Probe.tscn" -- \
##     "--property-output=<dir>" "--property-preset=wooded_pond" \
##     "--property-size=144" "--property-weather=Clear" "--property-hour=12"
##
## Needs a real renderer; it captures the viewport.
##
## Arguments
##   --property-output=<dir>     where the images go
##   --property-preset=<name>    open | light_forest | wooded | pond | wooded_pond
##   --property-seed=<int>       overrides the preset seed
##   --property-archetype=<name> rural | suburban | park | landscaped
##   --property-size=<int>       lawn size in world units (96 / 144 / 192)
##   --property-weather=<name>   Clear | Foggy | Rain
##   --property-hour=<float>     0 - 24
##   --property-cut=<0..1>       mow this fraction in stripes before capturing
##   --property-shots=<a,b,c>    only these shots
##   --property-fps              hold each viewpoint and report frame cost
##   --property-wind             compare two frames per viewpoint and report motion
##
## PUBLIC API: None.

const PRESET_MANAGER := "res://Weather/Preset Manager/Preset Manager.tscn"
const SETTLE_FRAMES := 26
## How many frames each measured viewpoint is held for.
const FPS_FRAMES := 90
## Frames between the two captures the wind check compares.
const WIND_FRAMES := 34

var _dir := "user://property_probe"
var _property: ACAProperty = null
var _camera: Camera3D = null
var _preset := &"light_forest"
var _size := 144
var _seed := -1
var _archetype := ACAPropertyArchetype.Kind.RURAL
var _weather := "Clear"
var _hour := 12.0
var _cut := 0.0
var _only: PackedStringArray = PackedStringArray()
var _measure_fps := false
var _measure_wind := false


func _ready() -> void:
	_read_arguments()
	DirAccess.make_dir_recursive_absolute(_dir)
	_run.call_deferred()


func _read_arguments() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--property-output="):
			_dir = arg.trim_prefix("--property-output=")
		elif arg.begins_with("--property-preset="):
			_preset = StringName(arg.trim_prefix("--property-preset="))
		elif arg.begins_with("--property-archetype="):
			_archetype = _parse_archetype(arg.trim_prefix("--property-archetype="))
		elif arg.begins_with("--property-size="):
			_size = arg.trim_prefix("--property-size=").to_int()
		elif arg.begins_with("--property-seed="):
			_seed = arg.trim_prefix("--property-seed=").to_int()
		elif arg.begins_with("--property-weather="):
			_weather = arg.trim_prefix("--property-weather=")
		elif arg.begins_with("--property-hour="):
			_hour = arg.trim_prefix("--property-hour=").to_float()
		elif arg.begins_with("--property-cut="):
			_cut = arg.trim_prefix("--property-cut=").to_float()
		elif arg.begins_with("--property-shots="):
			_only = arg.trim_prefix("--property-shots=").split(",", false)
		elif arg == "--property-fps":
			_measure_fps = true
		elif arg == "--property-wind":
			_measure_wind = true


## Match a name to a Kind, so the archetypes can be reviewed by name from the
## command line rather than by remembering which integer each one is.
static func _parse_archetype(text: String) -> int:
	for kind in ACAPropertyArchetype.NAMES:
		if ACAPropertyArchetype.name_of(kind) == text.strip_edges().to_lower():
			return kind
	push_warning("[PROBE] unknown archetype '%s', using rural" % text)
	return ACAPropertyArchetype.Kind.RURAL


func _run() -> void:
	var params := ACAPropertyParams.preset(_preset, _size)
	if _seed >= 0:
		params = ACAPropertyParams.for_seed(_seed, _size, _archetype)
	print("[PROBE] preset %s  archetype %s  size %d  seed %d  forestiness %.2f  pond %s"
		% [_preset, ACAPropertyArchetype.name_of(params.archetype), _size,
			params.seed, params.forestiness, params.pond_enabled])

	_property = ACAProperty.new()
	_property.name = "Property"
	add_child(_property)
	var t0 := Time.get_ticks_usec()
	_property.build(params)
	print("[PROBE] built in %.1f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))
	_print_statistics()

	_setup_environment()
	if _cut > 0.0:
		_stage_cut(params)

	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.far = 12000.0
	_camera.current = true
	add_child(_camera)

	await _settle(60)

	# WARM UP BEFORE MEASURING. The first frame from a new viewpoint compiles
	# whatever shader variants it needs, and a measurement taken across that
	# reports the compiler rather than the scene. Every viewpoint is visited
	# once with nothing recorded.
	if _measure_fps:
		for shot in _shots(params):
			_camera.global_position = shot["from"]
			_camera.look_at(shot["at"], Vector3.UP)
			await _settle(10)
		await _settle(30)

	for shot in _shots(params):
		if _only.size() > 0 and not _only.has(String(shot["name"])):
			continue
		_camera.global_position = shot["from"]
		_camera.look_at(shot["at"], Vector3.UP)
		await _settle(SETTLE_FRAMES)
		if _measure_fps:
			await _measure(String(shot["name"]))
		await _save("%s/%s.png" % [_dir, shot["name"]])
		if _measure_wind:
			await _measure_wind_at(String(shot["name"]))
	print("[PROBE] done")
	get_tree().quit(0)


## WIND CANNOT BE JUDGED FROM A STILL. Two frames a little apart are compared
## instead, which answers both halves of the question: that the grass moves at
## all, and that it is a breeze rather than a shake.
##
## The camera does not move between the two, so every difference is the grass.
func _measure_wind_at(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var before := get_viewport().get_texture().get_image()
	await _settle(WIND_FRAMES)
	await RenderingServer.frame_post_draw
	var after := get_viewport().get_texture().get_image()
	if before.get_size() != after.get_size():
		return

	var moved := 0
	var total := 0
	var worst := 0.0
	var sum := 0.0
	# Every eighth pixel: enough to characterise a whole frame, cheap enough to
	# run on every viewpoint.
	for y in range(0, before.get_height(), 8):
		for x in range(0, before.get_width(), 8):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			var d: float = (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			total += 1
			sum += d
			worst = maxf(worst, d)
			if d > 0.01:
				moved += 1
	if total == 0:
		return
	print("[PROBE WIND] %-12s %.1f%% of pixels moved, mean %.4f, peak %.3f"
		% [shot_name, 100.0 * float(moved) / float(total), sum / float(total), worst])


## Frame cost from a fixed viewpoint. Reported per shot, because the answer is
## completely different looking at the turf and looking down the property.
func _measure(shot_name: String) -> void:
	var frames := 0
	var total := 0.0
	var worst := INF
	var draw_calls := 0
	var primitives := 0
	for i in FPS_FRAMES:
		await get_tree().process_frame
		var fps := Performance.get_monitor(Performance.TIME_FPS)
		if fps <= 0.0:
			continue
		frames += 1
		total += fps
		worst = minf(worst, fps)
		draw_calls = maxi(draw_calls,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives = maxi(primitives,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	if frames == 0:
		return
	print("[PROBE FPS] %-12s avg %6.1f  min %6.1f  draw calls %5d  primitives %d"
		% [shot_name, total / float(frames), worst, draw_calls, primitives])


func _print_statistics() -> void:
	var s := _property.statistics()
	print("[PROBE] terrain %.1f ms | lawn %.1f ms | grass %.1f ms | foliage %.1f ms | total %.1f ms"
		% [s["terrain_ms"], s["lawn_ms"], s["grass_ms"], s["foliage_ms"], s["total_ms"]])
	print("[PROBE] lawn cells %d, mowable %d (%.1f%% excluded)" % [
		s["lawn_cells"], s["lawn_mowable"],
		100.0 * (1.0 - float(s["lawn_mowable"]) / maxf(float(s["lawn_cells"]), 1.0))])
	print("[PROBE] grass instances %d in %d nodes | foliage %s trees, %s shrubs, %s reeds, %s rocks in %d nodes"
		% [s["grass"]["instances"], s["grass"]["nodes"], s["foliage"]["trees"],
			s["foliage"]["shrubs"], s["foliage"].get("reeds", 0),
			s["foliage"]["rocks"], s["foliage"]["nodes"]])
	print("[PROBE] terrain triangles: core %d, distant %d"
		% [s["terrain"]["core_triangles"], s["terrain"]["ring_triangles"]])
	print("[PROBE] scene nodes %d, physics bodies %d"
		% [_count_nodes(self), _count_bodies(self)])


## Lay finished stripes across part of the lawn, so a capture shows cut grass,
## a cut boundary and stripes rather than an untouched field.
func _stage_cut(params: ACAPropertyParams) -> void:
	var lawn := _property.lawn()
	var half := params.lawn_half_extent()
	var centre := lawn.lawn_centre()
	var deck := ACAMowerDeck.make(5.6, 2.4)
	# LANES OVERLAP, the way an operator mows. Stepping over by exactly the deck
	# width leaves a cell-wide uncut hairline between every pair of passes, and
	# the ground shader - which samples the cut mask through a noise offset so
	# its own grid never shows - smears each hairline into a broad dark band.
	# The result was a staged capture of corduroy that no real mowing produces.
	var pitch: float = deck.half_width * 2.0 * 0.86
	var lanes: int = int(half * 2.0 * clampf(_cut, 0.0, 1.0) / pitch)
	for i in lanes:
		var z: float = centre.z - half + (float(i) + 0.5) * pitch
		var forward := 1.0 if i % 2 == 0 else -1.0
		var from := Vector3(centre.x - half, 0.0, z)
		var to := Vector3(centre.x + half, 0.0, z)
		if forward < 0.0:
			var swap := from
			from = to
			to = swap
		var yaw: float = PI * 0.5 if forward > 0.0 else -PI * 0.5
		var basis := Basis(Vector3.UP, yaw)
		# WALK the lane. `mow_deck` bounds one call's sweep at sixty-four
		# stamps, which is right for a machine reporting every physics frame and
		# hopeless for a single call spanning a two hundred unit lane: the stamps
		# end up further apart than the deck is long, so each pass comes out as a
		# ladder of cut and uncut rungs. Staged in strides no longer than the
		# deck, the same call lays a solid pass.
		var stride: float = deck.half_length
		var span := from.distance_to(to)
		var strides: int = maxi(int(ceil(span / maxf(stride, 0.1))), 1)
		var previous := Transform3D(basis, from)
		for step in strides:
			var next := Transform3D(basis,
				from.lerp(to, float(step + 1) / float(strides)))
			lawn.mow_deck(previous, next, deck)
			previous = next
	print("[PROBE] staged %d lanes, lawn is %.1f%% cut"
		% [lanes, lawn.mowed_fraction() * 100.0])


func _shots(params: ACAPropertyParams) -> Array[Dictionary]:
	var half := params.lawn_half_extent()
	var centre := _property.lawn().lawn_centre()
	var ground := func(x: float, z: float) -> float:
		return _property.ground_height_at(x, z)

	var shots: Array[Dictionary] = [
		{
			"name": "arrival",
			"from": Vector3(centre.x - half - 14.0,
				ground.call(centre.x - half - 14.0, centre.z) + 6.0, centre.z - 10.0),
			"at": Vector3(centre.x + half * 0.3, ground.call(centre.x, centre.z), centre.z),
		},
		{
			"name": "mower-eye",
			"from": Vector3(centre.x - half * 0.55,
				ground.call(centre.x - half * 0.55, centre.z - half * 0.4) + 4.2,
				centre.z - half * 0.4),
			"at": Vector3(centre.x + half * 0.5,
				ground.call(centre.x + half * 0.5, centre.z + half * 0.2) + 1.5,
				centre.z + half * 0.2),
		},
		{
			"name": "close-turf",
			"from": Vector3(centre.x - 6.0,
				ground.call(centre.x - 6.0, centre.z - 6.0) + 1.5, centre.z - 6.0),
			"at": Vector3(centre.x + 6.0, ground.call(centre.x + 6.0, centre.z + 4.0), centre.z + 4.0),
		},
		{
			"name": "overview",
			"from": Vector3(centre.x - half * 1.5,
				ground.call(centre.x, centre.z) + half * 1.15, centre.z - half * 1.5),
			"at": Vector3(centre.x, ground.call(centre.x, centre.z), centre.z),
		},
		{
			"name": "treeline",
			"from": Vector3(centre.x, ground.call(centre.x, centre.z) + 5.0, centre.z),
			"at": Vector3(centre.x, ground.call(centre.x, centre.z + half) + 12.0,
				centre.z + half + 60.0),
		},
		{
			"name": "horizon",
			"from": Vector3(centre.x, ground.call(centre.x, centre.z) + 14.0, centre.z),
			"at": Vector3(centre.x + 900.0, ground.call(centre.x, centre.z) + 60.0, centre.z),
		},
	]

	if params.pond_enabled:
		var p := Vector2(centre.x, centre.z) + params.pond_offset
		var r := params.pond_radius
		shots.append({
			"name": "pond",
			"from": Vector3(p.x - r * 2.2, ground.call(p.x - r * 2.2, p.y - r * 1.6) + 7.0,
				p.y - r * 1.6),
			"at": Vector3(p.x, ground.call(p.x, p.y) + 1.0, p.y),
		})
		# Standing back ON the near bank rather than in it. At a metre and a
		# half the camera ends up inside whatever is planted at the water's
		# edge, which says nothing about how the pond reads.
		shots.append({
			"name": "pond-bank",
			"from": Vector3(p.x - r * 1.75, ground.call(p.x - r * 1.75, p.y - r * 0.5) + 4.2,
				p.y - r * 0.5),
			"at": Vector3(p.x + r * 0.55, ground.call(p.x, p.y), p.y + r * 0.35),
		})
	return shots


# ================================================================ environment

func _setup_environment() -> void:
	var packed := load(PRESET_MANAGER) as PackedScene
	if packed == null:
		push_warning("[PROBE] no preset manager; falling back to a bare sun")
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-46.0, -35.0, 0.0)
		add_child(sun)
		return
	var manager := packed.instantiate()
	add_child(manager)
	await get_tree().process_frame
	var clock := get_node_or_null(^"/root/WorldClock")
	if clock != null:
		clock.call(&"set_weather", _weather)
		clock.call(&"advance_to_hour", _hour)
	if manager.has_method(&"apply_world_state_immediate"):
		manager.call(&"apply_world_state_immediate", _weather, _hour)
	if manager.has_method(&"set_weather_ground_reference"):
		manager.call(&"set_weather_ground_reference",
			_property.ground_height_at(0.0, 0.0))


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("[PROBE] %s" % path)


func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


func _count_bodies(node: Node) -> int:
	var total := 1 if node is PhysicsBody3D else 0
	for child in node.get_children():
		total += _count_bodies(child)
	return total
