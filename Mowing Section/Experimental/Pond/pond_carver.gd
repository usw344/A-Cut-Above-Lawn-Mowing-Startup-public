class_name ACAPondCarver
extends RefCounted
## EXPERIMENTAL. Carves a pond-shaped depression into a COPY of a mesh.
##
## NOT part of job generation, and nothing in gameplay calls it. It exists so
## that when the mowing grid is overhauled there is a working, tested pond tool
## to integrate rather than a blank page. See `Pond Demo.tscn`.
##
## ---------------------------------------------------------------------------
## NON-DESTRUCTIVE, ABSOLUTELY
## ---------------------------------------------------------------------------
##
## The source mesh is READ and never written. Every call builds a NEW ArrayMesh.
## This matters more than it sounds: an imported `.glb` mesh or a `PlaneMesh` is
## a shared resource, and deforming it in place would silently deform every
## other instance in the project — including ones in scenes nobody had open.
##
## ---------------------------------------------------------------------------
## THE SHAPE
## ---------------------------------------------------------------------------
##
## A perfect circular crater reads as a crater. Real ponds have a wandering
## shoreline and banks that slope in, so:
##
##   * the radius at any angle is perturbed by seeded 2D noise, giving a
##     coherent irregular outline rather than a wobble per vertex;
##   * the depth profile is flat in the middle with a smoothstep BANK, so the
##     ground walks down into the water instead of falling off a wall;
##   * an ellipse ratio lets a pond be longer than it is wide.
##
## ---------------------------------------------------------------------------
## THE INPUT REQUIREMENT
## ---------------------------------------------------------------------------
##
## Deformation moves EXISTING vertices. It cannot invent them. A pond carved
## into a mesh with four vertices under it is a three-triangle pit, and that is
## worse than no pond at all — so `analyse()` measures the density first and
## `carve()` refuses rather than producing something ugly. Subdividing an
## arbitrary mesh is a remesher, and a remesher is not this prototype's job.

## The result of a carve. `ok` false means nothing was built and `message`
## explains why.
class Result extends RefCounted:
	var ok: bool = false
	var message: String = ""
	var mesh: ArrayMesh = null
	## Vertices that were actually moved.
	var affected_vertices: int = 0
	## Vertices found inside the pond footprint, moved or not.
	var vertices_in_footprint: int = 0
	## Deepest displacement applied, in local units.
	var max_drop: float = 0.0
	## World-space AABB of the carved depression.
	var bounds: AABB = AABB()


## How a pond is specified. Plain data so a caller can build one without
## touching this class.
class Params extends RefCounted:
	## Centre, in the SOURCE MESH'S LOCAL SPACE.
	var centre: Vector3 = Vector3.ZERO
	var radius: float = 8.0
	## >1 stretches along X, <1 along Z.
	var ellipse_ratio: float = 1.0
	var depth: float = 2.0
	## Fraction of the radius given over to the sloping bank. 1.0 is a bowl with
	## no flat bottom at all; 0.35 is a pond with a floor.
	var bank_fraction: float = 0.42
	## How far the shoreline wanders, as a fraction of the radius.
	var irregularity: float = 0.18
	var seed: int = 0

	func duplicate_params() -> Params:
		var p := Params.new()
		p.centre = centre
		p.radius = radius
		p.ellipse_ratio = ellipse_ratio
		p.depth = depth
		p.bank_fraction = bank_fraction
		p.irregularity = irregularity
		p.seed = seed
		return p


## Fewest vertices that may sit inside the footprint before the result stops
## being a pond and starts being a dent.
const MIN_VERTICES_IN_FOOTPRINT := 24
## And enough of them must actually move, or the mesh is dense at the edges and
## empty in the middle.
const MIN_AFFECTED_VERTICES := 12


## Measure whether `source_mesh` can carry a pond of these parameters. Cheap,
## and safe to call before committing to anything.
static func analyse(source_mesh: Mesh, params: Params) -> Dictionary:
	if source_mesh == null:
		return {"ok": false, "message": "No source mesh.", "in_footprint": 0}
	if source_mesh.get_surface_count() == 0:
		return {"ok": false, "message": "Source mesh has no surfaces.", "in_footprint": 0}

	var noise := _make_noise(params)
	var in_footprint := 0
	var total := 0
	for surface in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += verts.size()
		for v in verts:
			if _shore_factor(v, params, noise) > 0.0:
				in_footprint += 1

	var ok := in_footprint >= MIN_VERTICES_IN_FOOTPRINT
	var message := ""
	if not ok:
		message = ("Only %d vertices fall inside the pond footprint (need %d). "
			+ "The source mesh is too coarse here: subdivide it, or use a "
			+ "smaller pond.") % [in_footprint, MIN_VERTICES_IN_FOOTPRINT]
	return {
		"ok": ok,
		"message": message,
		"in_footprint": in_footprint,
		"total_vertices": total,
	}


## Build a carved COPY. The source is not modified.
static func carve(source_mesh: Mesh, params: Params) -> Result:
	var result := Result.new()
	var check := analyse(source_mesh, params)
	result.vertices_in_footprint = int(check["in_footprint"])
	if not bool(check["ok"]):
		result.message = String(check["message"])
		return result

	var noise := _make_noise(params)
	var out := ArrayMesh.new()
	var affected := 0
	var deepest := 0.0
	var min_point := Vector3.INF
	var max_point := -Vector3.INF

	for surface in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		# A COPY of the vertex buffer. The source array is left untouched.
		var moved := PackedVector3Array()
		moved.resize(verts.size())

		for i in range(verts.size()):
			var v := verts[i]
			var factor := _shore_factor(v, params, noise)
			if factor <= 0.0:
				moved[i] = v
				continue
			var drop := params.depth * factor
			var nv := Vector3(v.x, v.y - drop, v.z)
			moved[i] = nv
			affected += 1
			deepest = maxf(deepest, drop)
			min_point = min_point.min(nv)
			max_point = max_point.max(nv)

		arrays[Mesh.ARRAY_VERTEX] = moved
		# Normals are now WRONG - they describe the flat ground that used to be
		# here. Regenerating is not optional; a pond lit as though it were still
		# level reads as a painted texture.
		arrays[Mesh.ARRAY_NORMAL] = null
		arrays[Mesh.ARRAY_TANGENT] = null

		var st := SurfaceTool.new()
		st.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
		st.generate_normals()
		st.generate_tangents()
		st.commit(out)

	if affected < MIN_AFFECTED_VERTICES:
		result.message = ("Only %d vertices actually moved (need %d). The mesh "
			+ "has vertices near the pond but not across it.") % [
				affected, MIN_AFFECTED_VERTICES]
		return result

	result.ok = true
	result.mesh = out
	result.affected_vertices = affected
	result.max_drop = deepest
	if min_point.x < INF:
		result.bounds = AABB(min_point, max_point - min_point)
	result.message = "Carved %d of %d vertices in the footprint, deepest %.2f." % [
		affected, result.vertices_in_footprint, deepest]
	return result


# ==================================================================== the shape

## 0.0 outside the pond, rising to 1.0 at full depth. THE one function that
## defines the pond's outline, and the same one `ACAPond.contains_world_point()`
## asks — so the exclusion query and the geometry can never disagree.
static func _shore_factor(v: Vector3, params: Params, noise: FastNoiseLite) -> float:
	var dx := (v.x - params.centre.x) / maxf(params.ellipse_ratio, 0.01)
	var dz := v.z - params.centre.z
	var dist := sqrt(dx * dx + dz * dz)

	# The shoreline wanders. Sampled by POSITION rather than by angle, so
	# neighbouring vertices agree and the outline is smooth rather than spiky.
	var wobble := 0.0
	if params.irregularity > 0.0 and noise != null:
		wobble = noise.get_noise_2d(v.x, v.z) * params.irregularity
	var edge := params.radius * (1.0 + wobble)
	if edge <= 0.001 or dist >= edge:
		return 0.0

	# Banks slope; the middle is flat. `bank_fraction` of the radius is bank.
	var bank := clampf(params.bank_fraction, 0.02, 1.0)
	var inward := (edge - dist) / (edge * bank)
	return smoothstep(0.0, 1.0, clampf(inward, 0.0, 1.0))


## Public so `ACAPond` can answer containment questions with exactly the
## geometry that was carved.
static func shore_factor_at(v: Vector3, params: Params) -> float:
	return _shore_factor(v, params, _make_noise(params))


## The seeded noise this shape uses. Build it ONCE and hand it to
## `shore_factor_with()` when sampling thousands of points; `shore_factor_at()`
## rebuilds it per call, which is fine for a handful of queries and wasteful for
## a terrain bake.
static func make_shape_noise(params: Params) -> FastNoiseLite:
	return _make_noise(params)


## `shore_factor_at()` with the noise supplied by the caller.
static func shore_factor_with(v: Vector3, params: Params, noise: FastNoiseLite) -> float:
	return _shore_factor(v, params, noise)


## Vertical displacement this pond applies at a point, in local units. Negative
## means the ground drops.
##
## `carve()` moves a vertex by exactly this amount, and the procedural terrain
## adds exactly this amount to its generated height. One function, so a
## generated heightfield, its collision, the water line and every exclusion
## query can never disagree about where the hole is.
static func depth_offset_at(v: Vector3, params: Params, noise: FastNoiseLite = null) -> float:
	var n: FastNoiseLite = noise if noise != null else _make_noise(params)
	return -params.depth * _shore_factor(v, params, n)


static func _make_noise(params: Params) -> FastNoiseLite:
	if params.irregularity <= 0.0:
		return null
	var noise := FastNoiseLite.new()
	noise.seed = params.seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Low frequency: a few big lobes around the shore, not a crinkled edge.
	noise.frequency = 1.2 / maxf(params.radius, 0.5)
	noise.fractal_octaves = 2
	return noise
