extends Node3D

# Attach this to your "Custom GridMap" Node3D.
# It generates chunked MultiMeshInstance3D nodes around a central playable area.
# Replace the placeholder mesh paths in ASSET_DEFS with your own resources.
#
# Important:
# 1. Your terrain must have collision, since placement uses raycasts.
# 2. For imported scenes, you can point mesh_path at either a Mesh resource
#    or a .tscn/.glb scene. If it is a scene, this script grabs the first MeshInstance3D mesh it finds.
# 3. The center play area is left empty. Everything is generated OUTSIDE it.

@export var generate_on_ready: bool = true
@export var clear_previous_generation: bool = true

# Central playable area in local X/Z units.
# If your center plane is 200 x 200, leave this as (200, 200).
@export var play_area_size: Vector2 = Vector2(200.0, 200.0)
@export var play_area_center_local: Vector3 = Vector3.ZERO

# Outer forest generation settings.
# outer_ring_count * chunk_size = total forest depth outward from the playable area.
@export var outer_ring_count: int = 4
@export var chunk_size: float = 50.0

# Raycast placement settings.
# The terrain MUST be on terrain_collision_mask and have collision.
@export_flags_3d_physics var terrain_collision_mask: int = 1
@export var terrain_root_path: NodePath
@export var raycast_start_height: float = 500.0
@export var raycast_end_height: float = -500.0

# Randomization
@export var seed: int = 1337
@export var placement_attempt_multiplier: int = 5

const GENERATED_ROOT_NAME := "GeneratedOuterForest"

# Replace these with your actual asset paths.
# You can point mesh_path at a Mesh resource OR a .tscn/.glb scene.
# If you use a scene, only the first MeshInstance3D mesh is extracted.
const ASSET_DEFS: Array[Dictionary] = [
	{
		"name": "TreeLarge",
		"mesh_path": "res://PLACEHOLDER/trees/tree_large.tscn",
		"density_per_m2": 0.008,
		"scale_min": 0.90,
		"scale_max": 1.35,
		"y_offset": 0.0,
		"max_slope_degrees": 32.0,
		"align_to_normal": true,
		"normal_align_strength": 0.35,
		"random_yaw": true,
		"min_spacing": 5.5
	},
	{
		"name": "TreeSmall",
		"mesh_path": "res://PLACEHOLDER/trees/tree_small.tscn",
		"density_per_m2": 0.010,
		"scale_min": 0.80,
		"scale_max": 1.15,
		"y_offset": 0.0,
		"max_slope_degrees": 35.0,
		"align_to_normal": true,
		"normal_align_strength": 0.35,
		"random_yaw": true,
		"min_spacing": 4.5
	},
	{
		"name": "Shrub",
		"mesh_path": "res://PLACEHOLDER/shrubs/shrub_01.tscn",
		"density_per_m2": 0.020,
		"scale_min": 0.85,
		"scale_max": 1.20,
		"y_offset": 0.0,
		"max_slope_degrees": 40.0,
		"align_to_normal": true,
		"normal_align_strength": 0.60,
		"random_yaw": true,
		"min_spacing": 2.0
	}
]


func _ready() -> void:
	if generate_on_ready:
		call_deferred("regenerate_outer_forest")


func regenerate_outer_forest() -> void:
	if outer_ring_count <= 0 or chunk_size <= 0.0:
		push_warning("Outer forest generation skipped: outer_ring_count and chunk_size must be greater than 0.")
		return

	if clear_previous_generation:
		_clear_generated_root()

	var generated_root := _get_or_create_generated_root()
	var terrain_root: Node = get_node_or_null(terrain_root_path)

	var chunk_regions := _build_chunk_regions()
	for region in chunk_regions:
		for asset_def in ASSET_DEFS:
			var multimesh_instance := _build_multimesh_for_region(region, asset_def, terrain_root)
			if multimesh_instance != null:
				generated_root.add_child(multimesh_instance)


func _build_chunk_regions() -> Array[Dictionary]:
	var regions: Array[Dictionary] = []

	var cx := play_area_center_local.x
	var cz := play_area_center_local.z
	var half_x := play_area_size.x * 0.5
	var half_z := play_area_size.y * 0.5
	var outer_depth := float(outer_ring_count) * chunk_size

	# North band (includes corners)
	_append_chunk_grid(
		regions,
		"North",
		cx - half_x - outer_depth,
		cx + half_x + outer_depth,
		cz - half_z - outer_depth,
		cz - half_z
	)

	# South band (includes corners)
	_append_chunk_grid(
		regions,
		"South",
		cx - half_x - outer_depth,
		cx + half_x + outer_depth,
		cz + half_z,
		cz + half_z + outer_depth
	)

	# West band
	_append_chunk_grid(
		regions,
		"West",
		cx - half_x - outer_depth,
		cx - half_x,
		cz - half_z,
		cz + half_z
	)

	# East band
	_append_chunk_grid(
		regions,
		"East",
		cx + half_x,
		cx + half_x + outer_depth,
		cz - half_z,
		cz + half_z
	)

	return regions


func _append_chunk_grid(
	out_regions: Array[Dictionary],
	prefix: String,
	x_min: float,
	x_max: float,
	z_min: float,
	z_max: float
) -> void:
	var ix := 0
	var x := x_min

	while x < x_max - 0.001:
		var width = min(chunk_size, x_max - x)

		var iz := 0
		var z := z_min
		while z < z_max - 0.001:
			var depth = min(chunk_size, z_max - z)

			out_regions.append({
				"name": "%s_%d_%d" % [prefix, ix, iz],
				"min_x": x,
				"max_x": x + width,
				"min_z": z,
				"max_z": z + depth,
				"size": Vector2(width, depth),
				"center": Vector3(x + width * 0.5, 0.0, z + depth * 0.5)
			})

			z += depth
			iz += 1

		x += width
		ix += 1


func _build_multimesh_for_region(region: Dictionary, asset_def: Dictionary, terrain_root: Node) -> MultiMeshInstance3D:
	var mesh: Mesh = _load_mesh_from_resource(String(asset_def["mesh_path"]))
	if mesh == null:
		push_warning("Skipping asset '%s': could not resolve mesh from %s" % [
			String(asset_def["name"]),
			String(asset_def["mesh_path"])
		])
		return null

	var region_size: Vector2 = region["size"]
	var area := region_size.x * region_size.y
	var density := float(asset_def.get("density_per_m2", 0.0))
	var desired_count = max(roundi(area * density), 0)

	if desired_count <= 0:
		return null

	var transforms := _sample_transforms_for_region(region, asset_def, terrain_root, desired_count)
	if transforms.is_empty():
		return null

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.custom_aabb = _make_region_aabb(region)
	multimesh.instance_count = transforms.size()
	multimesh.visible_instance_count = transforms.size()

	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_%s" % [String(region["name"]), String(asset_def["name"])]
	mmi.multimesh = multimesh
	return mmi


func _sample_transforms_for_region(
	region: Dictionary,
	asset_def: Dictionary,
	terrain_root: Node,
	desired_count: int
) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var space_state := get_world_3d().direct_space_state

	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|%s|%s" % [seed, String(region["name"]), String(asset_def["name"])]).hash()

	var min_x: float = region["min_x"]
	var max_x: float = region["max_x"]
	var min_z: float = region["min_z"]
	var max_z: float = region["max_z"]

	var max_attempts = max(desired_count * placement_attempt_multiplier, desired_count)

	for _attempt in range(max_attempts):
		if transforms.size() >= desired_count:
			break

		var local_x := rng.randf_range(min_x, max_x)
		var local_z := rng.randf_range(min_z, max_z)

		var hit := _raycast_terrain(space_state, terrain_root, local_x, local_z)
		if hit.is_empty():
			continue

		var hit_position: Vector3 = hit["position"]
		var hit_normal: Vector3 = hit["normal"]

		if not _passes_slope_limit(hit_normal, float(asset_def.get("max_slope_degrees", 90.0))):
			continue

		var up := Vector3.UP
		if bool(asset_def.get("align_to_normal", true)):
			var align_strength = clamp(float(asset_def.get("normal_align_strength", 1.0)), 0.0, 1.0)
			up = Vector3.UP.lerp(hit_normal.normalized(), align_strength).normalized()

		var yaw := 0.0
		if bool(asset_def.get("random_yaw", true)):
			yaw = rng.randf_range(0.0, TAU)

		var scale_min := float(asset_def.get("scale_min", 1.0))
		var scale_max := float(asset_def.get("scale_max", 1.0))
		var uniform_scale := rng.randf_range(scale_min, scale_max)

		var local_origin := to_local(hit_position) + up * float(asset_def.get("y_offset", 0.0))
		var min_spacing := float(asset_def.get("min_spacing", 0.0))
		if min_spacing > 0.0 and _too_close_to_existing(transforms, local_origin, min_spacing):
			continue

		var basis := _make_basis_from_up(up, yaw, uniform_scale)
		transforms.append(Transform3D(basis, local_origin))

	return transforms


func _raycast_terrain(
	space_state: PhysicsDirectSpaceState3D,
	terrain_root: Node,
	local_x: float,
	local_z: float
) -> Dictionary:
	var ray_from := to_global(Vector3(local_x, raycast_start_height, local_z))
	var ray_to := to_global(Vector3(local_x, raycast_end_height, local_z))

	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, terrain_collision_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return {}

	if terrain_root != null:
		var collider: Object = hit["collider"]
		if not _collider_matches_terrain(collider, terrain_root):
			return {}

	return hit


func _collider_matches_terrain(collider: Object, terrain_root: Node) -> bool:
	if collider == terrain_root:
		return true

	if collider is Node:
		var collider_node := collider as Node
		return terrain_root.is_ancestor_of(collider_node)

	return false


func _passes_slope_limit(normal: Vector3, max_slope_degrees: float) -> bool:
	var up_dot = clamp(normal.normalized().dot(Vector3.UP), -1.0, 1.0)
	var slope_radians := acos(up_dot)
	return rad_to_deg(slope_radians) <= max_slope_degrees


func _too_close_to_existing(existing: Array[Transform3D], point: Vector3, min_spacing: float) -> bool:
	var min_spacing_sq := min_spacing * min_spacing

	for item in existing:
		var delta := item.origin - point
		delta.y = 0.0
		if delta.length_squared() < min_spacing_sq:
			return true

	return false


func _make_basis_from_up(up: Vector3, yaw_radians: float, uniform_scale: float) -> Basis:
	var y_axis := up.normalized()

	var x_axis := Vector3.FORWARD.cross(y_axis)
	if x_axis.length_squared() < 0.00001:
		x_axis = Vector3.RIGHT.cross(y_axis)
	x_axis = x_axis.normalized()

	var z_axis := x_axis.cross(y_axis).normalized()

	var basis := Basis(x_axis, y_axis, z_axis).orthonormalized()
	basis = Basis(y_axis, yaw_radians) * basis
	basis = basis.scaled(Vector3.ONE * uniform_scale)

	return basis


func _make_region_aabb(region: Dictionary) -> AABB:
	var min_x: float = region["min_x"]
	var min_z: float = region["min_z"]
	var size: Vector2 = region["size"]

	var y_min = min(raycast_start_height, raycast_end_height)
	var y_max = max(raycast_start_height, raycast_end_height)

	return AABB(
		Vector3(min_x, y_min, min_z),
		Vector3(size.x, y_max - y_min, size.y)
	)


func _load_mesh_from_resource(resource_path: String) -> Mesh:
	if resource_path.is_empty():
		return null

	var resource := load(resource_path)
	if resource == null:
		return null

	if resource is Mesh:
		return resource as Mesh

	if resource is PackedScene:
		var temp_root := (resource as PackedScene).instantiate()
		var found_mesh := _find_first_mesh_in_node(temp_root)
		temp_root.free()
		return found_mesh

	return null


func _find_first_mesh_in_node(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			return mi.mesh

	for child in node.get_children():
		var found := _find_first_mesh_in_node(child)
		if found != null:
			return found

	return null


func _get_or_create_generated_root() -> Node3D:
	var existing := get_node_or_null(GENERATED_ROOT_NAME)
	if existing is Node3D:
		return existing as Node3D

	var root := Node3D.new()
	root.name = GENERATED_ROOT_NAME
	add_child(root)
	return root


func _clear_generated_root() -> void:
	var existing := get_node_or_null(GENERATED_ROOT_NAME)
	if existing != null:
		existing.queue_free()
