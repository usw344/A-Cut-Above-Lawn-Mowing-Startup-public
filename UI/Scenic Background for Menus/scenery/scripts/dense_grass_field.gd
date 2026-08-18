@tool
class_name DenseGrassField
extends Node3D

## Deterministic high-density scenery grass. MultiMesh keeps the mowing-game
## meadow inexpensive while the saved wind materials preserve breeze motion.

const GRASS_A1_SCENE := preload("res://UI/Scenic Background for Menus/Assets/SM_Grass_A1.glb")
const GRASS_A2_SCENE := preload("res://UI/Scenic Background for Menus/Assets/SM_Grass_A2.glb")
const GRASS_A1_MATERIAL := preload("res://UI/Scenic Background for Menus/scenery_wind/materials/grass_a1_wind.tres")
const GRASS_A2_MATERIAL := preload("res://UI/Scenic Background for Menus/scenery_wind/materials/grass_a2_wind.tres")

const EXCLUSIONS := [
	Vector3(4.15, -2.8, 0.8),
	Vector3(8.6, 2.0, 0.9),
	Vector3(-6.15, 1.2, 0.9),
	Vector3(-4.2, -0.8, 0.7),
	Vector3(-0.15, -3.0, 0.65),
	Vector3(6.8, -5.4, 0.65),
	Vector3(5.6, 3.1, 1.2),
	Vector3(2.7, -3.7, 0.75),
	Vector3(8.1, -4.9, 0.85),
	Vector3(-4.7, 2.7, 0.68),
	Vector3(-4.02, 3.18, 0.4),
	Vector3(-2.8, 1.95, 0.42),
	Vector3(0.75, -1.15, 0.38),
	Vector3(9.65, -1.45, 0.62),
	Vector3(5.25, -8.0, 0.38),
	Vector3(-1.65, 2.8, 0.76),
	Vector3(0.05, 2.2, 0.58),
	Vector3(-0.32, -0.1, 0.46),
]

@export var field_size := Vector2(32.0, 27.0):
	set(value):
		field_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_queue_rebuild()

@export var field_center := Vector2(1.5, -1.5):
	set(value):
		field_center = value
		_queue_rebuild()

@export_range(0.45, 2.0, 0.01) var spacing := 0.68:
	set(value):
		spacing = maxf(value, 0.45)
		_queue_rebuild()

@export_range(0.0, 1.0, 0.01) var density := 0.86:
	set(value):
		density = clampf(value, 0.0, 1.0)
		_queue_rebuild()

@export_range(0.1, 2.0, 0.01) var minimum_scale := 0.44:
	set(value):
		minimum_scale = maxf(value, 0.1)
		_queue_rebuild()

@export_range(0.1, 2.5, 0.01) var maximum_scale := 0.78:
	set(value):
		maximum_scale = maxf(value, minimum_scale)
		_queue_rebuild()

@export var random_seed := 82471:
	set(value):
		random_seed = value
		_queue_rebuild()

@export_group("Mown Lane")
@export var mown_lane_enabled := true:
	set(value):
		mown_lane_enabled = value
		_queue_rebuild()

@export_range(0.4, 3.0, 0.05) var mown_lane_half_width := 0.9:
	set(value):
		mown_lane_half_width = maxf(value, 0.4)
		_queue_rebuild()

@export_range(0.05, 0.5, 0.01) var mown_height_ratio := 0.16:
	set(value):
		mown_height_ratio = clampf(value, 0.05, 0.5)
		_queue_rebuild()

var _rebuild_queued := false
var generated_instance_count := 0
var generated_cut_count := 0


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	generated_instance_count = 0
	generated_cut_count = 0
	var mesh_a1 := _find_mesh(GRASS_A1_SCENE)
	var mesh_a2 := _find_mesh(GRASS_A2_SCENE)
	if mesh_a1 == null or mesh_a2 == null:
		push_error("DenseGrassField could not resolve the supplied grass meshes.")
		return

	var transforms_a1: Array[Transform3D] = []
	var transforms_a2: Array[Transform3D] = []
	var custom_a1: Array[Color] = []
	var custom_a2: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	var columns := maxi(1, int(floor(field_size.x / spacing)))
	var rows := maxi(1, int(floor(field_size.y / spacing)))
	var start := field_center - field_size * 0.5
	for row in rows:
		for column in columns:
			if rng.randf() > density:
				continue
			var x := start.x + (float(column) + 0.5) * spacing
			var z := start.y + (float(row) + 0.5) * spacing
			x += rng.randf_range(-spacing * 0.34, spacing * 0.34)
			z += rng.randf_range(-spacing * 0.34, spacing * 0.34)
			if _inside_exclusion(Vector2(x, z)):
				continue

			var mown := mown_lane_enabled and _inside_mown_lane(Vector2(x, z))
			# Keep the lane recognizably cut while retaining a short grassy surface.
			if mown and rng.randf() > 0.42:
				continue

			var base_scale := rng.randf_range(minimum_scale, maximum_scale)
			var vertical_scale := base_scale * rng.randf_range(0.9, 1.08)
			if mown:
				vertical_scale *= mown_height_ratio
				base_scale *= 0.82
				generated_cut_count += 1

			var position := Vector3(x, terrain_height(Vector2(x, z)) + 0.015, z)
			var basis := Basis(Vector3.UP, rng.randf_range(-PI, PI))
			basis = basis.scaled(Vector3(base_scale, vertical_scale, base_scale))
			var grass_transform := Transform3D(basis, position)
			var variation := Color(rng.randf(), 1.0 if mown else 0.0, rng.randf(), 1.0)

			if (row + column) % 2 == 0:
				transforms_a1.append(grass_transform)
				custom_a1.append(variation)
			else:
				transforms_a2.append(grass_transform)
				custom_a2.append(variation)

	_build_multimesh("GrassA1Field", mesh_a1, GRASS_A1_MATERIAL, transforms_a1, custom_a1)
	_build_multimesh("GrassA2Field", mesh_a2, GRASS_A2_MATERIAL, transforms_a2, custom_a2)
	generated_instance_count = transforms_a1.size() + transforms_a2.size()


func _build_multimesh(
	node_name: StringName,
	mesh: Mesh,
	material: ShaderMaterial,
	transforms: Array[Transform3D],
	custom_data: Array[Color]
) -> void:
	var renderer := get_node_or_null(NodePath(node_name)) as MultiMeshInstance3D
	if renderer == null:
		renderer = MultiMeshInstance3D.new()
		renderer.name = node_name
		add_child(renderer, false, Node.INTERNAL_MODE_BACK)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_custom_data(index, custom_data[index])

	renderer.multimesh = multimesh
	renderer.material_override = material
	# Thousands of alpha-cut shadow casters caused long-session GPU stalls. The
	# trees/manual accents retain shadows and SSAO supplies grass contact depth.
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	renderer.extra_cull_margin = 1.0


func _find_mesh(scene: PackedScene) -> Mesh:
	var instance := scene.instantiate()
	var mesh := _find_mesh_in_node(instance)
	instance.free()
	return mesh


func _find_mesh_in_node(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var mesh := _find_mesh_in_node(child)
		if mesh != null:
			return mesh
	return null


func _inside_exclusion(point: Vector2) -> bool:
	for exclusion in EXCLUSIONS:
		if point.distance_squared_to(Vector2(exclusion.x, exclusion.y)) < exclusion.z * exclusion.z:
			return true
	return false


func _inside_mown_lane(point: Vector2) -> bool:
	var lane_centre := -1.45 + sin((point.y + 1.5) * 0.19) * 0.85
	return absf(point.x - lane_centre) < mown_lane_half_width


static func terrain_height(point: Vector2) -> float:
	var local_roll := sin(point.x * 0.105 + 0.65) * 0.24
	local_roll += cos(point.y * 0.085 - 0.55) * 0.22
	var crossing_roll := sin((point.x + point.y) * 0.045) * 0.38
	crossing_roll += cos((point.x - point.y) * 0.061) * 0.19
	var distant_rise := smoothstep(3.0, 32.0, -point.y) * 1.4
	var surface_relief := (_soil_noise(point * 0.45) - 0.5) * 0.12
	surface_relief += (_value_noise(point * 1.2 + Vector2(19.7, 19.7)) - 0.5) * 0.035
	return local_roll + crossing_roll + distant_rise + surface_relief


static func _soil_noise(point: Vector2) -> float:
	return (
		_value_noise(point) * 0.58
		+ _value_noise(point * 2.07 + Vector2(13.4, 13.4)) * 0.29
		+ _value_noise(point * 4.13 - Vector2(7.1, 7.1)) * 0.13
	)


static func _value_noise(point: Vector2) -> float:
	var cell := Vector2(floor(point.x), floor(point.y))
	var fraction := point - cell
	fraction = fraction * fraction * (Vector2(3.0, 3.0) - fraction * 2.0)
	var a := _hash21(cell)
	var b := _hash21(cell + Vector2(1.0, 0.0))
	var c := _hash21(cell + Vector2(0.0, 1.0))
	var d := _hash21(cell + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, fraction.x), lerpf(c, d, fraction.x), fraction.y)


static func _hash21(point: Vector2) -> float:
	var warped := Vector2(
		_fract(point.x * 123.34),
		_fract(point.y * 456.21)
	)
	var offset := warped.dot(warped + Vector2(45.32, 45.32))
	warped += Vector2(offset, offset)
	return _fract(warped.x * warped.y)


static func _fract(value: float) -> float:
	return value - floor(value)
