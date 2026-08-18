@tool
class_name ProceduralSceneryTree
extends Node3D

## Transferable, deterministic tree geometry with an authored vertex wind mask.
## It replaces the production scene's block canopies without modifying imports.

@export var tree_seed := 17:
	set(value):
		if tree_seed == value:
			return
		tree_seed = value
		_queue_rebuild()

@export_range(4.0, 10.0, 0.1) var tree_height := 6.3:
	set(value):
		value = maxf(value, 4.0)
		if is_equal_approx(tree_height, value):
			return
		tree_height = value
		_queue_rebuild()

@export_range(1.1, 3.5, 0.05) var canopy_radius := 2.05:
	set(value):
		value = maxf(value, 1.1)
		if is_equal_approx(canopy_radius, value):
			return
		canopy_radius = value
		_queue_rebuild()

@export_range(0.16, 0.65, 0.01) var trunk_radius := 0.31:
	set(value):
		value = maxf(value, 0.16)
		if is_equal_approx(trunk_radius, value):
			return
		trunk_radius = value
		_queue_rebuild()

@export_range(7, 16, 1) var canopy_cluster_count := 11:
	set(value):
		value = maxi(value, 7)
		if canopy_cluster_count == value:
			return
		canopy_cluster_count = value
		_queue_rebuild()

@export_range(5, 12, 1) var branch_count := 8:
	set(value):
		value = maxi(value, 5)
		if branch_count == value:
			return
		branch_count = value
		_queue_rebuild()

@export var bark_material: ShaderMaterial:
	set(value):
		if bark_material == value:
			return
		bark_material = value
		_queue_rebuild()

@export var foliage_material: ShaderMaterial:
	set(value):
		if foliage_material == value:
			return
		foliage_material = value
		_queue_rebuild()

var _rebuild_queued := false
static var _mesh_cache: Dictionary = {}


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	var wood := get_node_or_null("Wood") as MeshInstance3D
	var foliage := get_node_or_null("Foliage") as MeshInstance3D
	if wood == null or foliage == null:
		return

	var cache_key := "%d|%.3f|%.3f|%.3f|%d|%d" % [
		tree_seed,
		tree_height,
		canopy_radius,
		trunk_radius,
		canopy_cluster_count,
		branch_count,
	]
	if not _mesh_cache.has(cache_key):
		var rng := RandomNumberGenerator.new()
		rng.seed = tree_seed
		var branches := _create_branch_layout(rng)
		_mesh_cache[cache_key] = [
			_build_wood_mesh(branches),
			_build_foliage_mesh(rng, branches),
		]
	var cached_meshes: Array = _mesh_cache[cache_key]
	wood.mesh = cached_meshes[0] as ArrayMesh
	wood.material_override = bark_material
	foliage.mesh = cached_meshes[1] as ArrayMesh
	foliage.material_override = foliage_material


func _create_branch_layout(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var branches: Array[Dictionary] = []
	var phase := rng.randf_range(-PI, PI)
	for index in branch_count:
		var progress := float(index) / float(maxi(branch_count - 1, 1))
		var height_ratio := lerpf(0.46, 0.79, progress) + rng.randf_range(-0.035, 0.035)
		var start := _trunk_center(height_ratio) + Vector3.UP * (tree_height * height_ratio)
		var angle := phase + float(index) * 2.39996 + rng.randf_range(-0.24, 0.24)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var reach := canopy_radius * rng.randf_range(0.52, 0.86)
		var lift := tree_height * rng.randf_range(0.105, 0.205)
		var end := start + direction * reach + Vector3.UP * lift
		branches.append({
			"start": start,
			"end": end,
			"radius": trunk_radius * rng.randf_range(0.27, 0.43),
			"variation": rng.randf(),
		})
	return branches


func _trunk_center(height_ratio: float) -> Vector3:
	var seed_phase := float(posmod(tree_seed, 97)) * 0.071
	var sway := tree_height * 0.022
	return Vector3(
		sin(height_ratio * 3.2 + seed_phase) * sway * height_ratio,
		0.0,
		cos(height_ratio * 2.55 + seed_phase * 1.37) * sway * height_ratio
	)


func _build_wood_mesh(branches: Array[Dictionary]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_segments := 7
	for index in trunk_segments:
		var lower_ratio := float(index) / float(trunk_segments)
		var upper_ratio := float(index + 1) / float(trunk_segments)
		var lower := _trunk_center(lower_ratio) + Vector3.UP * tree_height * lower_ratio
		var upper := _trunk_center(upper_ratio) + Vector3.UP * tree_height * upper_ratio
		var lower_radius := trunk_radius * lerpf(1.18, 0.34, pow(lower_ratio, 0.72))
		var upper_radius := trunk_radius * lerpf(1.18, 0.34, pow(upper_ratio, 0.72))
		var trunk_variation := 0.22 + upper_ratio * 0.26
		_add_tapered_tube(surface, lower, upper, lower_radius, upper_radius, 9, lower_ratio, upper_ratio, trunk_variation)

	for branch in branches:
		var start: Vector3 = branch["start"]
		var end: Vector3 = branch["end"]
		var radius: float = branch["radius"]
		var variation: float = branch["variation"]
		var middle := start.lerp(end, 0.52) + Vector3.UP * tree_height * 0.035
		var start_ratio := start.y / tree_height
		var middle_ratio := middle.y / tree_height
		var end_ratio := end.y / tree_height
		_add_tapered_tube(surface, start, middle, radius, radius * 0.68, 7, start_ratio, middle_ratio, variation)
		_add_tapered_tube(surface, middle, end, radius * 0.68, radius * 0.22, 7, middle_ratio, end_ratio, variation)

	surface.generate_normals()
	return surface.commit()


func _build_foliage_mesh(rng: RandomNumberGenerator, branches: Array[Dictionary]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centres: Array[Vector3] = []
	for branch in branches:
		centres.append(branch["end"])
	centres.append(_trunk_center(0.91) + Vector3.UP * tree_height * 0.91)

	while centres.size() < canopy_cluster_count:
		var angle := rng.randf_range(-PI, PI)
		var radial := canopy_radius * sqrt(rng.randf()) * 0.62
		var height_ratio := rng.randf_range(0.64, 0.94)
		centres.append(
			_trunk_center(height_ratio)
			+ Vector3(cos(angle) * radial, tree_height * height_ratio, sin(angle) * radial)
		)

	for index in centres.size():
		var centre := centres[index]
		var horizontal_radius := canopy_radius * rng.randf_range(0.38, 0.57)
		var vertical_radius := tree_height * rng.randf_range(0.09, 0.145)
		if index == centres.size() - 1:
			horizontal_radius *= 0.94
			vertical_radius *= 1.08
		var dimensions := Vector3(
			horizontal_radius * rng.randf_range(0.84, 1.12),
			vertical_radius,
			horizontal_radius * rng.randf_range(0.84, 1.12)
		)
		var rotation := Basis.from_euler(Vector3(
			rng.randf_range(-0.2, 0.2),
			rng.randf_range(-PI, PI),
			rng.randf_range(-0.16, 0.16)
		))
		_add_leaf_clump(surface, centre, dimensions, rotation, rng.randf_range(-PI, PI), rng.randf())

	surface.generate_normals()
	return surface.commit()


func _add_tapered_tube(
	surface: SurfaceTool,
	start: Vector3,
	end: Vector3,
	start_radius: float,
	end_radius: float,
	sides: int,
	start_height_ratio: float,
	end_height_ratio: float,
	variation: float
) -> void:
	var axis := (end - start).normalized()
	var reference := Vector3.FORWARD if absf(axis.dot(Vector3.UP)) > 0.92 else Vector3.UP
	var tangent := axis.cross(reference).normalized()
	var bitangent := axis.cross(tangent).normalized()
	for side in sides:
		var angle_a := TAU * float(side) / float(sides)
		var angle_b := TAU * float(side + 1) / float(sides)
		var radial_a := tangent * cos(angle_a) + bitangent * sin(angle_a)
		var radial_b := tangent * cos(angle_b) + bitangent * sin(angle_b)
		var p0 := start + radial_a * start_radius
		var p1 := end + radial_a * end_radius
		var p2 := end + radial_b * end_radius
		var p3 := start + radial_b * start_radius
		var color_start := Color(pow(clampf(start_height_ratio, 0.0, 1.0), 2.4) * 0.11, variation, 0.0, 1.0)
		var color_end := Color(pow(clampf(end_height_ratio, 0.0, 1.0), 2.2) * 0.18, variation, 0.0, 1.0)
		_add_triangle(surface, p0, p1, p2, color_start, color_end, color_end)
		_add_triangle(surface, p0, p2, p3, color_start, color_end, color_start)


func _add_leaf_clump(
	surface: SurfaceTool,
	centre: Vector3,
	dimensions: Vector3,
	rotation: Basis,
	phase: float,
	variation: float
) -> void:
	var rings := 6
	var segments := 12
	for ring in rings:
		var latitude_a := -PI * 0.5 + PI * float(ring) / float(rings)
		var latitude_b := -PI * 0.5 + PI * float(ring + 1) / float(rings)
		for segment in segments:
			var longitude_a := TAU * float(segment) / float(segments)
			var longitude_b := TAU * float(segment + 1) / float(segments)
			var p0 := _leaf_vertex(centre, dimensions, rotation, latitude_a, longitude_a, phase)
			var p1 := _leaf_vertex(centre, dimensions, rotation, latitude_b, longitude_a, phase)
			var p2 := _leaf_vertex(centre, dimensions, rotation, latitude_b, longitude_b, phase)
			var p3 := _leaf_vertex(centre, dimensions, rotation, latitude_a, longitude_b, phase)
			var colour_a := _leaf_color(p0, variation, float(segment) / float(segments))
			var colour_b := _leaf_color(p1, variation, float(segment + ring) / float(segments + rings))
			var colour_c := _leaf_color(p2, variation, float(segment + 1) / float(segments))
			var colour_d := _leaf_color(p3, variation, float(segment + ring + 1) / float(segments + rings))
			_add_triangle(surface, p0, p1, p2, colour_a, colour_b, colour_c)
			_add_triangle(surface, p0, p2, p3, colour_a, colour_c, colour_d)


func _leaf_vertex(
	centre: Vector3,
	dimensions: Vector3,
	rotation: Basis,
	latitude: float,
	longitude: float,
	phase: float
) -> Vector3:
	var direction := Vector3(
		cos(latitude) * cos(longitude),
		sin(latitude),
		cos(latitude) * sin(longitude)
	)
	var irregularity := 1.0
	irregularity += sin(longitude * 3.0 + phase) * 0.105
	irregularity += sin(latitude * 4.0 - phase * 0.7) * 0.06
	return centre + rotation * (direction * dimensions * irregularity)


func _leaf_color(vertex: Vector3, variation: float, local_variation: float) -> Color:
	var height_mask := smoothstep(tree_height * 0.34, tree_height * 1.08, vertex.y)
	var radial_mask := clampf(Vector2(vertex.x, vertex.z).length() / (canopy_radius * 1.4), 0.0, 1.0)
	var wind_mask := clampf(0.45 + height_mask * 0.38 + radial_mask * 0.17, 0.0, 1.0)
	return Color(wind_mask, fmod(variation * 0.72 + local_variation * 0.28, 1.0), 1.0, 1.0)


func _add_triangle(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	color_a: Color,
	color_b: Color,
	color_c: Color
) -> void:
	surface.set_color(color_a)
	surface.add_vertex(a)
	surface.set_color(color_b)
	surface.add_vertex(b)
	surface.set_color(color_c)
	surface.add_vertex(c)
