@tool
class_name ACAPond
extends Node3D
## EXPERIMENTAL. A carved pond: deformed ground, a water surface, and the
## queries a future object-placement system will need.
##
## **NOT PART OF JOB GENERATION.** Nothing in gameplay builds one of these. The
## mowing grid is due a larger overhaul, and this exists so that when it happens
## there is a working, tested pond tool to integrate. See `Pond Demo.tscn`.
##
## ---------------------------------------------------------------------------
## WHAT IT PRODUCES
## ---------------------------------------------------------------------------
##
##     source MeshInstance3D  (read only, never modified)
##              |
##       ACAPondCarver.carve()
##              |
##     +--------+---------+------------------+
##     |                  |                  |
##  carved terrain    water surface    exclusion queries
##  (a NEW mesh)      (plane + shader)  (contains_world_point, ...)
##
## The source is left exactly as it was. `carve()` hides it and shows the copy;
## `restore_source()` puts everything back.
##
## ---------------------------------------------------------------------------
## THE EXCLUSION API IS THE POINT
## ---------------------------------------------------------------------------
##
## The pond itself is the easy half. What the grid overhaul will actually need
## is a way to ask "is this where I was about to plant grass?" — so
## `contains_world_point()`, `get_exclusion_bounds()` and
## `get_exclusion_polygon()` are the API this prototype exists to prove, and
## they answer using EXACTLY the function that carved the geometry.

signal carved(result_message: String)

@export_group("Source")
## The ground to carve. READ ONLY — this node never writes to its mesh.
@export var source_path: NodePath
## Re-carve when a parameter changes in the editor.
@export var live_update: bool = true

@export_group("Shape")
@export var pond_centre: Vector3 = Vector3.ZERO: set = _set_centre
@export_range(0.5, 200.0, 0.1) var radius: float = 8.0: set = _set_radius
@export_range(0.2, 5.0, 0.01) var ellipse_ratio: float = 1.25: set = _set_ratio
@export_range(0.1, 30.0, 0.05) var depth: float = 2.0: set = _set_depth
## Fraction of the radius given to the sloping bank. Low values dig a bathtub.
@export_range(0.05, 1.0, 0.01) var bank_fraction: float = 0.45: set = _set_bank
@export_range(0.0, 0.6, 0.01) var irregularity: float = 0.18: set = _set_irregularity
@export var pond_seed: int = 20260820: set = _set_seed

@export_group("Water")
## Height of the water surface RELATIVE to the un-carved ground.
@export_range(-10.0, 2.0, 0.01) var water_level: float = -0.35: set = _set_water_level
@export var water_material: Material = null
## Subdivisions per side of the water plane. The waves are computed from world
## position, so this only decides how smoothly the vertex displacement reads.
@export_range(4, 128, 1) var water_subdivisions: int = 48

@export_group("Collision")
## Build a `ConcavePolygonShape3D` from the carved mesh, so things can stand in
## the pond. Static geometry only — this is not a water volume.
@export var generate_collision: bool = true

# --------------------------------------------------------------------- state
var _terrain: MeshInstance3D = null
var _water: MeshInstance3D = null
var _body: StaticBody3D = null
var _collision: CollisionShape3D = null
var _source: MeshInstance3D = null
var _last_result: ACAPondCarver.Result = null
var _built: bool = false


func _ready() -> void:
	carve()


# ======================================================================= build

func params() -> ACAPondCarver.Params:
	var p := ACAPondCarver.Params.new()
	p.centre = pond_centre
	p.radius = radius
	p.ellipse_ratio = ellipse_ratio
	p.depth = depth
	p.bank_fraction = bank_fraction
	p.irregularity = irregularity
	p.seed = pond_seed
	return p


func source() -> MeshInstance3D:
	if _source != null and is_instance_valid(_source):
		return _source
	if source_path.is_empty():
		return null
	_source = get_node_or_null(source_path) as MeshInstance3D
	return _source


## Carve, or re-carve. Safe to call repeatedly.
func carve() -> bool:
	var src := source()
	if src == null or src.mesh == null:
		_report("No source MeshInstance3D assigned.")
		return false

	var result := ACAPondCarver.carve(src.mesh, params())
	_last_result = result
	if not result.ok:
		# A refusal is reported, not swallowed. A silent no-op looks exactly
		# like a pond that did not render.
		push_warning("ACAPond: %s" % result.message)
		_report(result.message)
		return false

	_ensure_nodes()
	_terrain.mesh = result.mesh
	_inherit_materials(src, result.mesh)
	_terrain.transform = src.transform

	# The source is HIDDEN, not changed. `restore_source()` undoes this.
	src.visible = false

	_build_water(src)
	_build_collision(result)
	_built = true
	_report(result.message)
	return true


## Put the scene back the way it was found: source visible, carved copy gone.
func restore_source() -> void:
	var src := source()
	if src != null:
		src.visible = true
	if _terrain != null:
		_terrain.visible = false
	if _water != null:
		_water.visible = false
	if _body != null:
		_body.process_mode = Node.PROCESS_MODE_DISABLED
	_built = false


## The carved copy has to LOOK like the ground it was cut from, and a material
## can be attached in three different places:
##
##   1. `MeshInstance3D.material_override`      — wins over everything;
##   2. `MeshInstance3D.surface_override_material(i)` — per instance;
##   3. `Mesh.surface_get_material(i)`          — on the RESOURCE itself.
##
## Only the first was copied at first, and the demo's ground carries its
## material on the mesh — so the pond rendered as a white slab in a green field.
## All three are checked now, in the order the renderer resolves them.
func _inherit_materials(src: MeshInstance3D, carved_mesh: ArrayMesh) -> void:
	_terrain.material_override = src.material_override
	for i in range(carved_mesh.get_surface_count()):
		var material: Material = null
		if i < src.get_surface_override_material_count():
			material = src.get_surface_override_material(i)
		if material == null and src.mesh != null and i < src.mesh.get_surface_count():
			material = src.mesh.surface_get_material(i)
		if material != null:
			_terrain.set_surface_override_material(i, material)


func _ensure_nodes() -> void:
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = MeshInstance3D.new()
		_terrain.name = "Carved Terrain"
		add_child(_terrain)
	_terrain.visible = true


func _build_water(src: MeshInstance3D) -> void:
	if _water == null or not is_instance_valid(_water):
		_water = MeshInstance3D.new()
		_water.name = "Water Surface"
		_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_water)
	_water.visible = true

	# Slightly wider than the shoreline, so the shader's depth fade has bank to
	# disappear into rather than ending exactly where the geometry does.
	var span := radius * maxf(ellipse_ratio, 1.0) * 2.0 * 1.15
	var plane := PlaneMesh.new()
	plane.size = Vector2(span * maxf(ellipse_ratio, 1.0) / maxf(ellipse_ratio, 1.0), span)
	plane.size = Vector2(radius * ellipse_ratio * 2.3, radius * 2.3)
	plane.subdivide_width = water_subdivisions
	plane.subdivide_depth = water_subdivisions
	_water.mesh = plane
	_water.material_override = water_material if water_material != null else _default_water()

	_water.transform = src.transform
	_water.position = src.transform * (pond_centre + Vector3(0.0, water_level, 0.0))


func _default_water() -> Material:
	var mat := ShaderMaterial.new()
	var shader := load(
		"res://Mowing Section/Experimental/Pond/pond_water.gdshader") as Shader
	if shader == null:
		return StandardMaterial3D.new()
	mat.shader = shader
	return mat


## Collision from the CARVED mesh, so a body standing in the pond is standing on
## the bed rather than on the ground that used to be there.
##
## `create_trimesh_shape()` is static-geometry only. That is the honest limit of
## this prototype: there is no water VOLUME here, nothing floats, and nothing
## gets wet. Buoyancy belongs to the terrain overhaul.
func _build_collision(result: ACAPondCarver.Result) -> void:
	if not generate_collision:
		if _body != null:
			_body.process_mode = Node.PROCESS_MODE_DISABLED
		return
	if _body == null or not is_instance_valid(_body):
		_body = StaticBody3D.new()
		_body.name = "Carved Collision"
		_collision = CollisionShape3D.new()
		_body.add_child(_collision)
		add_child(_body)
	_body.process_mode = Node.PROCESS_MODE_INHERIT
	_body.transform = _terrain.transform
	_collision.shape = result.mesh.create_trimesh_shape()


func _report(message: String) -> void:
	carved.emit(message)


# ============================================================ exclusion API
#
# What a future grass / rock / prop placer will ask. Every one of these answers
# with the SAME shape function that carved the geometry, so a query can never
# disagree with what is on screen.

## Is this world point inside the pond's footprint?
func contains_world_point(world_point: Vector3) -> bool:
	return shore_factor_world(world_point) > 0.0


## 0.0 outside, rising to 1.0 at the deepest part. Useful for FADING a
## placement density near the shore rather than cutting it off at a line.
func shore_factor_world(world_point: Vector3) -> float:
	var src := source()
	if src == null:
		return 0.0
	var local := src.to_local(world_point)
	return ACAPondCarver.shore_factor_at(local, params())


## Would this point be under water?
func is_submerged(world_point: Vector3) -> bool:
	if not contains_world_point(world_point):
		return false
	return world_point.y <= water_world_height()


func water_world_height() -> float:
	var src := source()
	if src == null:
		return global_position.y + water_level
	return (src.global_transform * (pond_centre + Vector3(0, water_level, 0))).y


## World-space AABB of the footprint, for broad-phase rejection before anyone
## bothers calling `contains_world_point()` per blade of grass.
func get_exclusion_bounds() -> AABB:
	var src := source()
	var half_x := radius * ellipse_ratio * (1.0 + irregularity)
	var half_z := radius * (1.0 + irregularity)
	var local := AABB(
		pond_centre - Vector3(half_x, depth + 0.5, half_z),
		Vector3(half_x * 2.0, depth + 1.0, half_z * 2.0))
	if src == null:
		return local
	return src.global_transform * local


## The shoreline as a world-space XZ polygon, sampled at `segments` angles.
## For a placement system that wants a 2D region rather than a per-point test.
func get_exclusion_polygon(segments: int = 32) -> PackedVector2Array:
	var out := PackedVector2Array()
	var src := source()
	var count := maxi(segments, 8)
	for i in range(count):
		var angle := TAU * float(i) / float(count)
		var direction := Vector3(cos(angle) * ellipse_ratio, 0.0, sin(angle))
		# Walk outwards until the shape function says we have left the pond.
		# Cheaper and more honest than reimplementing the noise here.
		var step := radius * (1.0 + irregularity + 0.05) / 48.0
		var found := radius
		for s in range(48, 0, -1):
			var probe := pond_centre + direction * (step * float(s))
			if ACAPondCarver.shore_factor_at(probe, params()) > 0.0:
				found = step * float(s)
				break
		var local := pond_centre + direction * found
		var world := local if src == null else src.global_transform * local
		out.append(Vector2(world.x, world.z))
	return out


# ==================================================================== reading

func is_built() -> bool:
	return _built


func last_result() -> ACAPondCarver.Result:
	return _last_result


func carved_terrain() -> MeshInstance3D:
	return _terrain


func water_surface() -> MeshInstance3D:
	return _water


# ================================================================== setters

func _rebuild_if_live() -> void:
	if live_update and is_inside_tree():
		carve()


func _set_centre(v: Vector3) -> void:
	pond_centre = v
	_rebuild_if_live()


func _set_radius(v: float) -> void:
	radius = v
	_rebuild_if_live()


func _set_ratio(v: float) -> void:
	ellipse_ratio = v
	_rebuild_if_live()


func _set_depth(v: float) -> void:
	depth = v
	_rebuild_if_live()


func _set_bank(v: float) -> void:
	bank_fraction = v
	_rebuild_if_live()


func _set_irregularity(v: float) -> void:
	irregularity = v
	_rebuild_if_live()


func _set_seed(v: int) -> void:
	pond_seed = v
	_rebuild_if_live()


func _set_water_level(v: float) -> void:
	water_level = v
	if _water != null and is_instance_valid(_water) and source() != null:
		_water.position = source().transform * (pond_centre + Vector3(0, v, 0))
