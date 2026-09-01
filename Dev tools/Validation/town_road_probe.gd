extends Node
## DEVELOPMENT ONLY. The Business Town's ROAD NETWORK and the traffic on it,
## measured rather than looked at.
##
##   godot --headless --path . "res://Dev tools/Validation/Town Road Probe.tscn"
##   godot --path . "res://Dev tools/Validation/Town Road Probe.tscn" \
##       -- "--road-output=<dir>"          # adds a top-down plan render
##
## WHY THIS EXISTS
##
## "Do the cars stay on the road?" was being answered from perspective
## screenshots of a stylised town at thirty units, which is exactly the view
## that hides a wheel half a metre onto a verge. It is a geometry question, so
## it is answered with geometry:
##
##   1. The ROAD FOOTPRINT is collected from the real `Roads` node - every tile's
##      mesh AABB, in world space, flattened to the ground plane.
##   2. Every traffic lane is SAMPLED along its curve, and each sample is tested
##      against that footprint with the car's own half-width added. A car whose
##      body overhangs the tarmac fails, not just one whose centre leaves it.
##   3. The tiles themselves are checked for GAPS and for DANGLING ARMS - a
##      junction piece whose fourth arm faces open grass is the thing that makes
##      a road network read as unfinished.
##
## It prints an ASCII plan of the network, which is the fastest way to see what
## the town's streets actually are.

const DEFAULT_OUTPUT_DIR := "user://town_roads"

## Road tiles are two units square. Half of that, less a hair, is how far from a
## tile's centre line the tarmac reaches.
const TILE := 2.0
## Half the width of a car body, from the models the traffic uses. A lane closer
## than this to the edge of the tarmac puts a wheel on the verge.
const CAR_HALF_WIDTH := 0.42
## How finely each lane is walked. A quarter of a unit is about a sixth of a car
## length, so nothing slips between two samples.
const SAMPLE_STEP := 0.25
## Grid resolution of the printed plan, in world units per cell.
const PLAN_CELL := 1.0

var _dir: String = DEFAULT_OUTPUT_DIR
var _render: bool = false
var _pass: int = 0
var _fail: int = 0
var _road_rects: Array[Rect2] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--road-output="):
			_dir = arg.trim_prefix("--road-output=")
			_render = true
	_run.call_deferred()


func _run() -> void:
	GameSession.start_new_game()
	while GameSession.current_screen() != ACAGameSession.Screen.TOWN:
		await get_tree().process_frame
	await _settle(30)

	var town := get_tree().current_scene.get_node_or_null(^"BusinessTown") as Node3D
	if town == null:
		printerr("[ROAD] no BusinessTown in the town screen")
		get_tree().quit(1)
		return

	_collect_roads(town)
	_report(_road_rects.size() > 0, "road footprint: %d tiles" % _road_rects.size())
	_print_plan()
	_check_lanes(town)
	_check_dangling_arms(town)

	if _render:
		DirAccess.make_dir_recursive_absolute(_dir)
		await _render_plan(town)

	print("[ROAD] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# =================================================================== footprint

## Every road tile as a ground-plane rectangle in world space, taken from the
## tile's own mesh AABB rather than from an assumed tile size, so a tile that is
## not two units square is still measured correctly.
func _collect_roads(town: Node3D) -> void:
	_road_rects.clear()
	var roads := town.get_node_or_null(^"Roads") as Node3D
	if roads == null:
		return
	for tile in roads.get_children():
		var node3d := tile as Node3D
		if node3d == null:
			continue
		var rect := _ground_rect(node3d)
		if rect.size.x > 0.01 and rect.size.y > 0.01:
			_road_rects.append(rect)


## The ground-plane extent of every MeshInstance3D under `root`, unioned.
func _ground_rect(root: Node3D) -> Rect2:
	var rect := Rect2()
	var first := true
	for node in _all_meshes(root):
		var aabb := node.get_aabb()
		var basis_xform := node.global_transform
		# The eight corners, so a rotated tile is measured where it really is.
		for i in 8:
			var corner := aabb.get_endpoint(i)
			var world := basis_xform * corner
			var point := Vector2(world.x, world.z)
			if first:
				rect = Rect2(point, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(point)
	return rect


func _all_meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		found.append(root as MeshInstance3D)
	for child in root.get_children():
		found.append_array(_all_meshes(child))
	return found


## True when `point` is on tarmac with `margin` to spare on every side.
func _on_road(point: Vector2, margin: float) -> bool:
	for rect in _road_rects:
		if rect.grow(-margin).has_point(point):
			return true
	# A point in the seam between two abutting tiles is on the road even though
	# it clears neither tile's shrunken rectangle. Accept it if the UNSHRUNKEN
	# footprint covers the whole margin disc, sampled on the four axes.
	var covered := true
	for offset in [Vector2(margin, 0), Vector2(-margin, 0),
			Vector2(0, margin), Vector2(0, -margin)]:
		var here := false
		for rect in _road_rects:
			if rect.has_point(point + offset):
				here = true
				break
		if not here:
			covered = false
			break
	return covered


# ======================================================================= lanes

func _check_lanes(town: Node3D) -> void:
	var traffic := town.find_children("*", "ACATownTraffic", true, false)
	if traffic.is_empty():
		_report(false, "no ACATownTraffic in the town")
		return
	var node := traffic[0] as Node3D

	var lanes := 0
	for path in node.get_children():
		var curve_path := path as Path3D
		if curve_path == null or curve_path.curve == null:
			continue
		lanes += 1
		var curve := curve_path.curve
		var length := curve.get_baked_length()
		var steps := maxi(int(length / SAMPLE_STEP), 8)
		var off := 0
		var worst := Vector2.ZERO
		for i in steps:
			var at := curve.sample_baked(float(i) / float(steps) * length)
			var world := curve_path.global_transform * at
			var point := Vector2(world.x, world.z)
			if not _on_road(point, CAR_HALF_WIDTH):
				off += 1
				worst = point
		_report(off == 0, "lane %-22s %5.1f units, %d/%d samples off tarmac%s" % [
			curve_path.name, length, off, steps,
			("  worst near (%.1f, %.1f)" % [worst.x, worst.y]) if off > 0 else ""])

	_report(lanes > 0, "traffic lanes present: %d" % lanes)


# =============================================================== dangling arms

## A junction or T-split arm that points at open grass. The tile is measured
## rather than named: for each of the four compass directions a junction serves,
## the probe asks whether there is any road tile in the next two units that way.
func _check_dangling_arms(town: Node3D) -> void:
	var roads := town.get_node_or_null(^"Roads") as Node3D
	if roads == null:
		return
	var dangling: Array[String] = []
	for tile in roads.get_children():
		var node3d := tile as Node3D
		if node3d == null:
			continue
		var arms := _arms_of(node3d)
		if arms.is_empty():
			continue
		var centre := Vector2(node3d.global_position.x, node3d.global_position.z)
		for arm: Vector2 in arms:
			var probe_at := centre + arm * TILE
			var served := false
			for rect in _road_rects:
				if rect.grow(-0.2).has_point(probe_at):
					served = true
					break
			if not served:
				dangling.append("%s -> (%.0f, %.0f)" % [
					node3d.name, probe_at.x, probe_at.y])
	_report(dangling.is_empty(), "junction arms all served%s" % (
		("; DANGLING: " + ", ".join(dangling)) if not dangling.is_empty() else ""))


## Which directions a tile's own geometry offers a carriageway in. Derived from
## the scene file it was instanced from, because that is what decides whether
## the tile is drawn with tarmac reaching its edge.
func _arms_of(tile: Node3D) -> Array:
	var file := tile.scene_file_path
	var basis_xform := tile.global_transform.basis
	var local: Array = []
	if file.ends_with("road_junction.gltf"):
		local = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	elif file.ends_with("road_tsplit.gltf"):
		# A T-split's own +Z is the stem; the crossbar runs along its X.
		local = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1)]
	else:
		return []
	var world: Array = []
	for direction: Vector2 in local:
		var rotated := basis_xform * Vector3(direction.x, 0.0, direction.y)
		world.append(Vector2(rotated.x, rotated.z).normalized())
	return world


# ======================================================================== plan

## The network as text. Two characters per world unit so the aspect is roughly
## square in a terminal.
func _print_plan() -> void:
	if _road_rects.is_empty():
		return
	var bounds := _road_rects[0]
	for rect in _road_rects:
		bounds = bounds.merge(rect)
	print("[ROAD] plan, x %.0f..%.0f  z %.0f..%.0f  ('##' road, '..' not)" % [
		bounds.position.x, bounds.end.x, bounds.position.y, bounds.end.y])
	var z := bounds.position.y
	while z < bounds.end.y:
		var row := ""
		var x := bounds.position.x
		while x < bounds.end.x:
			var centre := Vector2(x + PLAN_CELL * 0.5, z + PLAN_CELL * 0.5)
			var on := false
			for rect in _road_rects:
				if rect.has_point(centre):
					on = true
					break
			row += "##" if on else ".."
			x += PLAN_CELL
		print("[ROAD] z=%6.1f |%s" % [z, row])
		z += PLAN_CELL


## A top-down orthographic render of the whole town, which is the view a road
## layout is actually judged in.
func _render_plan(town: Node3D) -> void:
	var hud := town.get_node_or_null(^"BusinessHUD") as CanvasItem
	if hud != null:
		hud.visible = false
	AppUI.clear_notifications()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 34.0
	cam.near = 0.1
	cam.far = 200.0
	town.add_child(cam)
	cam.global_position = Vector3(0.0, 60.0, -3.0)
	cam.look_at(Vector3(0.0, 0.0, -3.0), Vector3.FORWARD)
	cam.make_current()
	await _settle(30)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/town-plan.png" % _dir
	if image.save_png(path) == OK:
		print("[ROAD] %s" % path)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _report(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
		print("[ROAD]  ok   %s" % message)
	else:
		_fail += 1
		print("[ROAD] FAIL  %s" % message)
