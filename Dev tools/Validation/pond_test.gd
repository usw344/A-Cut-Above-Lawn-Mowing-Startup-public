extends SceneTree
## DEVELOPMENT ONLY. The EXPERIMENTAL pond carver.
##
##   godot --headless --path <project> \
##     --script "res://Dev tools/Validation/pond_test.gd"
##
## No renderer needed: everything here is mesh arithmetic. The LOOK is judged
## from `Pond Demo.tscn`'s captures, not from assertions.
##
## The guarantees this suite exists to hold:
##
##   1. the source mesh is never modified — the single most important one,
##      because an imported mesh is a SHARED resource and deforming it in place
##      would corrupt every other scene that uses it;
##   2. a mesh too coarse to carry a pond is REFUSED, not turned into a
##      three-triangle pit;
##   3. normals are regenerated, so the depression is lit as a depression;
##   4. the exclusion API agrees with the geometry that was actually carved.

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_test_non_destructive()
	_test_density_refusal()
	_test_geometry()
	_test_normals()
	_test_shape_controls()
	_test_exclusion_api()
	_test_collision()
	_test_edge_cases()

	print("[POND TEST] %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _dense_source(subdivisions: int = 90) -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	return plane


func _params(radius: float = 10.0, depth: float = 2.5) -> ACAPondCarver.Params:
	var p := ACAPondCarver.Params.new()
	p.centre = Vector3.ZERO
	p.radius = radius
	p.depth = depth
	p.ellipse_ratio = 1.3
	p.bank_fraction = 0.45
	p.irregularity = 0.18
	p.seed = 20260820
	return p


# ============================================================ non-destructive

## THE assertion that matters most. A shared mesh resource deformed in place
## would change every other instance of it in the project, silently.
func _test_non_destructive() -> void:
	var source := _dense_source()
	var before: PackedVector3Array = source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# A real copy of the buffer, not a reference to it.
	var snapshot := PackedVector3Array(before)

	var result := ACAPondCarver.carve(source, _params())
	_check("Carve: succeeded on a dense source (%s)" % result.message, result.ok)

	var after: PackedVector3Array = source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var identical := after.size() == snapshot.size()
	if identical:
		for i in range(after.size()):
			if not after[i].is_equal_approx(snapshot[i]):
				identical = false
				break
	_check("SOURCE MESH IS UNTOUCHED after carving", identical)
	_check("Carve: the result is a DIFFERENT mesh object",
		result.mesh != null and result.mesh != source)


# ================================================================== refusal

func _test_density_refusal() -> void:
	# Four vertices under a ten-unit pond is a dent, not a pond.
	var coarse := _dense_source(2)
	var analysis := ACAPondCarver.analyse(coarse, _params())
	_check("Density: a coarse mesh is REFUSED (%d in footprint)"
		% int(analysis["in_footprint"]), not bool(analysis["ok"]))
	_check("Density: the refusal explains itself",
		String(analysis["message"]).length() > 20)

	var result := ACAPondCarver.carve(coarse, _params())
	_check("Density: carving a coarse mesh returns a failure, not a bad mesh",
		not result.ok and result.mesh == null)

	var fine := ACAPondCarver.analyse(_dense_source(), _params())
	_check("Density: a dense mesh is accepted (%d in footprint)"
		% int(fine["in_footprint"]), bool(fine["ok"]))

	# The same coarse mesh CAN carry a smaller pond - the limit is density
	# relative to the pond, not an absolute rule about the mesh.
	var big := _dense_source(40)
	_check("Density: the limit is relative — a denser mesh accepts the same pond",
		bool(ACAPondCarver.analyse(big, _params())["ok"]))


# ================================================================== geometry

func _test_geometry() -> void:
	var source := _dense_source()
	var params := _params(10.0, 2.5)
	var result := ACAPondCarver.carve(source, params)
	if not result.ok:
		_check("Geometry: carve succeeded", false)
		return

	var verts: PackedVector3Array = result.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var original: PackedVector3Array = source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check("Geometry: vertex count is preserved", verts.size() == original.size())

	var lowest := 0.0
	for v in verts:
		lowest = minf(lowest, v.y)
	_check("Geometry: the pond really goes down (%.2f)" % lowest,
		lowest < -params.depth * 0.85)
	_check("Geometry: and no deeper than asked (%.2f vs %.2f)"
		% [lowest, -params.depth], lowest >= -params.depth - 0.001)
	_check("Geometry: the reported max drop matches (%.2f)" % result.max_drop,
		absf(result.max_drop - absf(lowest)) < 0.01)

	# Ground well outside the pond must be exactly where it was.
	var moved_outside := false
	for i in range(verts.size()):
		var flat := Vector2(original[i].x, original[i].z)
		if flat.length() > params.radius * 2.0 and absf(verts[i].y - original[i].y) > 0.0001:
			moved_outside = true
	_check("Geometry: ground outside the pond is not disturbed", not moved_outside)


func _test_normals() -> void:
	var result := ACAPondCarver.carve(_dense_source(), _params())
	if not result.ok:
		_check("Normals: carve succeeded", false)
		return
	var arrays := result.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	_check("Normals: the carved mesh has normals", normals.size() > 0)

	# A flat plane's normals are all straight up. If ANY normal tilted, the
	# bank was regenerated rather than inherited from the flat ground.
	var tilted := 0
	var inverted := 0
	for n in normals:
		if n.y < 0.999:
			tilted += 1
		if n.y <= 0.0:
			inverted += 1
	_check("Normals: the banks have tilted normals (%d of %d)"
		% [tilted, normals.size()], tilted > 20)
	_check("Normals: NONE are inverted (%d)" % inverted, inverted == 0)


func _test_shape_controls() -> void:
	var source := _dense_source()

	# Deeper means deeper.
	var shallow := ACAPondCarver.carve(source, _params(10.0, 1.0))
	var deep := ACAPondCarver.carve(source, _params(10.0, 4.0))
	_check("Shape: depth controls depth (%.2f < %.2f)"
		% [shallow.max_drop, deep.max_drop], deep.max_drop > shallow.max_drop * 2.0)

	# Bigger means more vertices moved.
	var small := ACAPondCarver.carve(source, _params(5.0))
	var large := ACAPondCarver.carve(source, _params(15.0))
	_check("Shape: radius controls footprint (%d < %d)"
		% [small.affected_vertices, large.affected_vertices],
		large.affected_vertices > small.affected_vertices * 2)

	# A different seed is a different shoreline; the same seed is not.
	var a := _params()
	var b := _params()
	b.seed = a.seed + 7717
	var pa := ACAPondCarver.carve(source, a)
	var pb := ACAPondCarver.carve(source, b)
	var pa2 := ACAPondCarver.carve(source, _params())
	_check("Shape: the seed changes the shoreline",
		pa.affected_vertices != pb.affected_vertices)
	_check("Shape: the same seed is reproducible",
		pa.affected_vertices == pa2.affected_vertices)

	# An ellipse is not a circle.
	var round_p := _params()
	round_p.ellipse_ratio = 1.0
	var oval := _params()
	oval.ellipse_ratio = 2.5
	var round_r := ACAPondCarver.carve(source, round_p)
	var oval_r := ACAPondCarver.carve(source, oval)
	_check("Shape: ellipse_ratio stretches the pond",
		oval_r.affected_vertices > round_r.affected_vertices)


# ============================================================== exclusion API

## The queries a future grass / rock placer will make. They must agree with the
## geometry that was actually carved, because they use the same function.
func _test_exclusion_api() -> void:
	var params := _params(10.0, 2.5)
	_check("Exclusion: the centre is inside",
		ACAPondCarver.shore_factor_at(Vector3.ZERO, params) > 0.0)
	_check("Exclusion: a far point is outside",
		ACAPondCarver.shore_factor_at(Vector3(60, 0, 60), params) == 0.0)
	_check("Exclusion: the factor is deepest at the centre",
		ACAPondCarver.shore_factor_at(Vector3.ZERO, params)
		> ACAPondCarver.shore_factor_at(Vector3(0, 0, params.radius * 0.9), params))
	_check("Exclusion: the factor is 0..1",
		ACAPondCarver.shore_factor_at(Vector3.ZERO, params) <= 1.0)

	# The query and the geometry are the SAME function, so a carved vertex must
	# be one the query also calls inside.
	var source := _dense_source()
	var result := ACAPondCarver.carve(source, params)
	var original: PackedVector3Array = source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var carved: PackedVector3Array = result.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# Compared at the SAME threshold on both sides. A vertex sitting exactly on
	# the shoreline has a shore factor of a few billionths, which is genuinely
	# "inside" and just as genuinely does not move a measurable distance —
	# comparing "moved by more than 0.0001" against "factor greater than zero"
	# would fail on arithmetic rather than on disagreement.
	var epsilon := 0.0001
	var disagreements := 0
	for i in range(original.size()):
		var moved := absf(carved[i].y - original[i].y) > epsilon
		var inside := ACAPondCarver.shore_factor_at(original[i], params) * params.depth 			> epsilon
		if moved != inside:
			disagreements += 1
	_check("Exclusion: the query agrees with the carve on every vertex (%d disagree)"
		% disagreements, disagreements == 0)


func _test_collision() -> void:
	var result := ACAPondCarver.carve(_dense_source(), _params())
	if not result.ok:
		_check("Collision: carve succeeded", false)
		return
	var shape := result.mesh.create_trimesh_shape()
	_check("Collision: a trimesh shape can be built from the carved mesh",
		shape != null and shape.get_faces().size() > 0)
	# Static geometry only. There is no water VOLUME and nothing floats; that
	# belongs to the terrain overhaul, and pretending otherwise would be worse
	# than saying so.
	_check("Collision: it is static geometry, matching the carved bed",
		shape is ConcavePolygonShape3D)


## The cases a future integrator will actually hit. None of them should crash,
## and each should either work or refuse for a stated reason — a carver that
## returns a broken mesh on a strange input is worse than one that says no.
func _test_edge_cases() -> void:
	var source := _dense_source()

	# A pond BIGGER than the ground it is cut into. Legitimate: a small lawn
	# with a large water feature. It should carve what it can reach.
	var huge := _params(60.0, 3.0)
	var huge_result := ACAPondCarver.carve(source, huge)
	_check("Edge: a pond larger than the mesh still carves (%d vertices)"
		% huge_result.affected_vertices, huge_result.ok)
	if huge_result.ok:
		var verts: PackedVector3Array = huge_result.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var finite := true
		for v in verts:
			if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
				finite = false
		_check("Edge: and produces no NaN or infinite vertices", finite)

	# A pond centred well OFF the mesh. Nothing to carve; must refuse rather
	# than return an untouched mesh that looks like a success.
	var away := _params(8.0, 2.0)
	away.centre = Vector3(400.0, 0.0, 400.0)
	var away_result := ACAPondCarver.carve(source, away)
	_check("Edge: a pond centred off the mesh is refused, not silently empty",
		not away_result.ok and away_result.mesh == null)

	# A pond straddling the EDGE of the mesh - half on, half off. This is the
	# realistic version of the case above and it must work.
	var edge := _params(12.0, 2.0)
	edge.centre = Vector3(38.0, 0.0, 0.0)
	var edge_result := ACAPondCarver.carve(source, edge)
	_check("Edge: a pond straddling the mesh boundary carves (%d vertices)"
		% edge_result.affected_vertices, edge_result.ok)

	# Zero irregularity: a clean ellipse, no noise. Must not divide by zero.
	var clean := _params(10.0, 2.0)
	clean.irregularity = 0.0
	var clean_result := ACAPondCarver.carve(source, clean)
	_check("Edge: zero irregularity gives a clean ellipse without dividing by zero",
		clean_result.ok and clean_result.affected_vertices > 0)

	# A nearly flat pond. Should carve, and should be shallow rather than
	# rounding to nothing.
	var shallow := _params(10.0, 0.15)
	var shallow_result := ACAPondCarver.carve(source, shallow)
	_check("Edge: a very shallow pond still carves (%.3f deep)"
		% shallow_result.max_drop,
		shallow_result.ok and shallow_result.max_drop > 0.1
		and shallow_result.max_drop <= 0.151)

	# A bathtub: almost no bank. Allowed, but must not produce inverted normals.
	var steep := _params(10.0, 4.0)
	steep.bank_fraction = 0.05
	var steep_result := ACAPondCarver.carve(source, steep)
	_check("Edge: a near-vertical bank still carves", steep_result.ok)
	if steep_result.ok:
		var normals: PackedVector3Array = steep_result.mesh.surface_get_arrays(
			0)[Mesh.ARRAY_NORMAL]
		var inverted := 0
		for n in normals:
			if n.y <= 0.0:
				inverted += 1
		_check("Edge: and even a bathtub has no inverted normals (%d)" % inverted,
			inverted == 0)

	# A null mesh must be handled, not crash.
	var null_result := ACAPondCarver.carve(null, _params())
	_check("Edge: a null source mesh is refused with a message",
		not null_result.ok and not null_result.message.is_empty())


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[POND] %s: PASS" % label)
	else:
		_fail += 1
		printerr("[POND] %s: FAIL" % label)
