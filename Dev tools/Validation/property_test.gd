extends SceneTree
## DEVELOPMENT ONLY. Headless tests for the procedural property: the terrain
## height field, the lawn's compact mowing state, the mower footprint, the
## generic exclusion interface, the pond, and the save round trip.
##
##   godot --headless --path . --script "res://Dev tools/Validation/property_test.gd"
##
## Nothing here judges how anything LOOKS. That is what the rendered probes are
## for; see project-docs/validation-and-dev-tools.md.
##
## PUBLIC API: None.

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== PROPERTY TEST ===")
	_test_mesh_winding()
	_test_terrain_determinism()
	_test_terrain_queries()
	_test_playable_gentleness()
	_test_pond_carves_terrain()
	_test_lawn_layout()
	_test_deck_mowing()
	_test_every_mower_reaches_one_hundred()
	_test_pond_property_completes()
	_test_every_property_has_a_pond()
	_test_obstacles_are_fair()
	_test_boundary_contains_the_property()
	_test_obstacle_property_completes()
	_test_clearance_matches_the_machines()
	_test_no_mowable_cell_is_trapped()
	_test_cut_state_round_trip()
	_test_legacy_migration()
	_report_terrain_cost()
	_report_lawn_cost()
	print("===========================================")
	print("[PROPERTY TEST] %d passed, %d failed" % [_passed, _failed])
	print("===========================================")
	quit(1 if _failed > 0 else 0)


# ================================================================== the tests

## The index order the terrain uses must produce upward-facing triangles under
## Godot's own winding rule, or the ground renders inside out. Asserted rather
## than assumed, because the rule is easy to get backwards and the symptom is an
## invisible world.
func _test_mesh_winding() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# One flat quad, laid out exactly as ACATerrain lays out a cell.
	var v := [
		Vector3(0, 0, 0),  # i00
		Vector3(1, 0, 0),  # i10
		Vector3(0, 0, 1),  # i01
		Vector3(1, 0, 1),  # i11
	]
	for p in v:
		st.add_vertex(p)
	# i00, i10, i11 then i00, i11, i01 -- exactly ACATerrain's order.
	for i in [0, 1, 3, 0, 3, 2]:
		st.add_index(i)
	st.generate_normals()
	var arrays := st.commit_to_arrays()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	_check("winding: the terrain index order faces upward",
		normals.size() > 0 and normals[0].y > 0.9,
		"got %s" % (normals[0] if normals.size() > 0 else Vector3.ZERO))


## Same parameters, same ground. This is the whole reason a property does not
## have to be saved as geometry.
func _test_terrain_determinism() -> void:
	var params := ACAPropertyParams.for_seed(4242, 96)
	var a := _make_terrain(params)
	var b := _make_terrain(params.duplicate_params())

	var worst := 0.0
	for i in 400:
		var x := randf_range(-200.0, 200.0)
		var z := randf_range(-200.0, 200.0)
		worst = maxf(worst, absf(a.height_at(x, z) - b.height_at(x, z)))
	_check("terrain: two builds from equal parameters agree exactly",
		worst == 0.0, "worst difference %.6f" % worst)

	var other := _make_terrain(ACAPropertyParams.for_seed(4243, 96))
	var difference := 0.0
	for i in 200:
		var x := randf_range(-120.0, 120.0)
		var z := randf_range(-120.0, 120.0)
		difference = maxf(difference, absf(a.height_at(x, z) - other.height_at(x, z)))
	_check("terrain: a different seed makes different ground",
		difference > 0.25, "largest difference %.3f" % difference)

	# The parameter derivation itself must be stable.
	var p1 := ACAPropertyParams.for_seed(991, 144)
	var p2 := ACAPropertyParams.for_seed(991, 144)
	_check("params: for_seed is deterministic",
		is_equal_approx(p1.forestiness, p2.forestiness)
			and p1.pond_enabled == p2.pond_enabled
			and p1.pond_offset.is_equal_approx(p2.pond_offset),
		"forestiness %.4f vs %.4f" % [p1.forestiness, p2.forestiness])

	a.free()
	b.free()
	other.free()


## The query and the surface a camera sees have to be the same number, or grass
## floats, wheels sink and the pond water line is wrong.
func _test_terrain_queries() -> void:
	var params := ACAPropertyParams.for_seed(7, 96)
	var terrain := _make_terrain(params)

	var mesh: MeshInstance3D = terrain.get_node_or_null(^"Ground")
	_check("terrain: a ground mesh was built", mesh != null and mesh.mesh != null, "")
	if mesh == null or mesh.mesh == null:
		terrain.free()
		return

	# Compare height_at() against the ACTUAL triangle the point lands on, read
	# back out of the committed mesh arrays rather than out of the generator.
	var worst := 0.0
	var samples := 0
	var layout_ok := true
	var arrays := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var side := int(round(sqrt(float(vertices.size()))))
	var span: float = mesh.mesh.get_aabb().size.x
	var cell: float = span / float(side - 1)
	var origin: float = -span * 0.5
	for i in 250:
		var x := randf_range(origin + cell, -origin - cell * 2.0)
		var z := randf_range(origin + cell, -origin - cell * 2.0)
		var ix := int(floor((x - origin) / cell))
		var iz := int(floor((z - origin) / cell))
		var v00 := vertices[iz * side + ix]
		var v10 := vertices[iz * side + ix + 1]
		var v01 := vertices[(iz + 1) * side + ix]
		var v11 := vertices[(iz + 1) * side + ix + 1]
		if absf(v00.x - (origin + float(ix) * cell)) > 0.001 \
				or absf(v00.z - (origin + float(iz) * cell)) > 0.001:
			layout_ok = false
			break
		var fx := (x - v00.x) / cell
		var fz := (z - v00.z) / cell
		var expected: float
		if fz <= fx:
			expected = v00.y + (v10.y - v00.y) * fx + (v11.y - v10.y) * fz
		else:
			expected = v00.y + (v01.y - v00.y) * fz + (v11.y - v01.y) * fx
		samples += 1
		worst = maxf(worst, absf(expected - terrain.height_at(x, z)))
	_check("terrain: the ground mesh is a regular lattice", layout_ok, "")
	_check("terrain: height_at matches the rendered surface",
		samples > 200 and worst < 0.002,
		"%d samples, worst %.5f" % [samples, worst])

	# Both surfaces must face up, or the world renders inside out.
	_check("terrain: the core mesh faces upward", _faces_up(mesh.mesh), "")
	var rings: MeshInstance3D = terrain.get_node_or_null(^"Distant Landscape")
	_check("terrain: the distant rings face upward",
		rings != null and rings.mesh != null and _faces_up(rings.mesh), "")

	# Normals must point up on gentle ground and be unit length everywhere.
	var min_up := 1.0
	for i in 200:
		var n := terrain.normal_at(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
		min_up = minf(min_up, n.y)
		if absf(n.length() - 1.0) > 0.001:
			min_up = -1.0
			break
	_check("terrain: normals are unit length and upward on the lawn",
		min_up > 0.85, "lowest normal.y %.3f" % min_up)

	# Bounds have to actually contain the ground.
	var b := terrain.bounds()
	var inside := true
	for i in 100:
		var x := randf_range(-terrain.near_extent(), terrain.near_extent())
		var z := randf_range(-terrain.near_extent(), terrain.near_extent())
		var y := terrain.height_at(x, z)
		if y < b.position.y or y > b.position.y + b.size.y:
			inside = false
			break
	_check("terrain: bounds contain the near field", inside, "")

	# Collision must exist and be the same lattice.
	var body: StaticBody3D = terrain.collision_body()
	var shape_node := body.get_node_or_null(^"Shape") as CollisionShape3D if body != null else null
	var shape := shape_node.shape as HeightMapShape3D if shape_node != null else null
	_check("terrain: a height map collision shape was built",
		shape != null and shape.map_width > 2
			and shape.map_data.size() == shape.map_width * shape.map_depth,
		"shape %s" % shape)

	terrain.free()


## The mowable rectangle has to stay pleasant to steer on. Measured as a real
## slope, not asserted by reading the parameter that was meant to cause it.
func _test_playable_gentleness() -> void:
	var worst_lawn := 0.0
	var best_far := 0.0
	for property_seed in [11, 909, 30303, 777001]:
		var params := ACAPropertyParams.for_seed(property_seed, 192)
		var terrain := _make_terrain(params)
		var half := params.lawn_half_extent()
		for i in 400:
			var x := randf_range(-half, half)
			var z := randf_range(-half, half)
			worst_lawn = maxf(worst_lawn, terrain.slope_at(x, z))
		for i in 200:
			var a := randf_range(0.0, TAU)
			var r := randf_range(700.0, 1800.0)
			best_far = maxf(best_far, absf(terrain.height_at(cos(a) * r, sin(a) * r)))
		terrain.free()

	# 0.18 is about eleven degrees. Anything steeper starts to fight the mower.
	_check("terrain: the lawn never exceeds a gentle slope",
		worst_lawn < 0.18, "steepest lawn slope %.3f" % worst_lawn)
	_check("terrain: the distant landscape has real elevation",
		best_far > 30.0, "tallest distant point %.1f" % best_far)


## The pond is not a decorative plane. The ground under it must actually be
## lower, the water line must sit above the bed, and the exclusion query must
## agree with the geometry that was generated.
func _test_pond_carves_terrain() -> void:
	var params := ACAPropertyParams.preset(&"pond", 144)
	_check("pond preset: the pond is enabled", params.pond_enabled, "")

	var flat := params.duplicate_params()
	flat.pond_enabled = false

	var features := ACAFeatureSet.new()
	var pond := ACAPondFeature.from_params(params, params.pond_offset)
	features.add(pond)

	var carved := _make_terrain(params, features)
	var plain := _make_terrain(flat)

	var centre := params.pond_offset
	var drop := plain.height_at(centre.x, centre.y) - carved.height_at(centre.x, centre.y)
	_check("pond: the terrain is genuinely carved",
		drop > params.pond_depth * 0.85,
		"dropped %.2f of a %.2f pond" % [drop, params.pond_depth])

	var water := pond.water_world_height()
	var bed := carved.height_at(centre.x, centre.y)
	_check("pond: the water surface sits above the bed",
		water > bed + 1.0, "water %.2f, bed %.2f" % [water, bed])
	_check("pond: the water surface sits below the surrounding ground",
		water < plain.height_at(centre.x + params.pond_radius * 2.0, centre.y),
		"water %.2f" % water)

	# Away from the pond, nothing moved.
	var far_delta := absf(plain.height_at(-60.0, -60.0) - carved.height_at(-60.0, -60.0))
	_check("pond: ground outside the footprint is untouched",
		far_delta < 0.0001, "moved %.5f" % far_delta)

	# Exclusion and geometry must agree: every excluded point is under water,
	# and every submerged point is excluded.
	var disagreements := 0
	var submerged_found := 0
	var r := params.pond_radius * 1.6
	for i in 600:
		var x := centre.x + randf_range(-r, r)
		var z := centre.y + randf_range(-r, r)
		var ground := carved.height_at(x, z)
		var excluded: bool = features.mowing_exclusion_at(x, z, ground) >= 0.5
		var under_water: bool = ground < water
		if under_water:
			submerged_found += 1
		if under_water and not excluded:
			disagreements += 1
	_check("pond: every submerged point is excluded from mowing",
		disagreements == 0 and submerged_found > 50,
		"%d disagreements over %d submerged samples" % [disagreements, submerged_found])

	# And outside the pond nothing is excluded.
	var false_positives := 0
	for i in 300:
		var x := randf_range(-60.0, -20.0)
		var z := randf_range(-60.0, -20.0)
		if features.mowing_exclusion_at(x, z, carved.height_at(x, z)) > 0.0:
			false_positives += 1
	_check("pond: nothing far from the pond is excluded",
		false_positives == 0, "%d false exclusions" % false_positives)

	carved.free()
	plain.free()


## The lawn is a rectangle of one-unit cells over the property, and every one of
## them starts uncut and mowable when nothing is in the way.
##
## NOTHING IN THE WAY has to be arranged deliberately now. Every generated
## property has a pond and a handful of lawn obstacles on it, so an empty
## feature set is passed explicitly to test the rectangle itself; the properties
## the game actually generates are tested below.
func _test_lawn_layout() -> void:
	for size in [96, 144, 192]:
		var built := _build_lawn_with(ACAPropertyParams.for_seed(5, int(size)),
			ACAFeatureSet.new())
		var lawn: ACALawn = built["lawn"]
		_check("lawn %d: one cell per world unit" % size,
			lawn.cell_count() == size and lawn.total_item_count() == size * size,
			"%d cells, %d mowable" % [lawn.cell_count(), lawn.total_item_count()])
		_check("lawn %d: starts uncut" % size,
			lawn.mowed_item_count() == 0 and is_zero_approx(lawn.mowed_fraction()), "")
		_check("lawn %d: has no physics bodies at all" % size,
			_count_bodies(lawn) == 0, "%d bodies" % _count_bodies(lawn))
		_free(built)


## The cut is the deck's own footprint swept along the path travelled, not a
## disc and not a point sample. Both halves of that matter: a wide machine must
## cut a wide strip, and a fast one must not skip ground between updates.
func _test_deck_mowing() -> void:
	var built := _build_lawn(ACAPropertyParams.for_seed(9, 96))
	var lawn: ACALawn = built["lawn"]
	var centre := lawn.lawn_centre()
	var deck := ACAMowerDeck.make(6.0, 2.0)
	var basis := Basis(Vector3.UP, PI * 0.5)

	# One straight pass of forty units.
	var from := Vector3(centre.x - 20.0, centre.y, centre.z)
	var to := Vector3(centre.x + 20.0, centre.y, centre.z)
	var cut := lawn.mow_deck(Transform3D(basis, from), Transform3D(basis, to), deck)
	# Forty units of travel, six wide, plus the deck's own length at each end.
	var expected := 40.0 * 6.0
	_check("deck: a pass cuts about its own width times its length",
		cut > expected * 0.85 and cut < expected * 1.45,
		"cut %d cells, expected about %d" % [cut, int(expected)])

	# The same ground again cuts nothing: cells do not double count.
	var again := lawn.mow_deck(Transform3D(basis, from), Transform3D(basis, to), deck)
	_check("deck: cutting the same ground twice changes nothing", again == 0,
		"cut %d more" % again)

	# The strip really is where it was driven, and only there.
	_check("deck: the middle of the pass is cut",
		lawn.is_cut(Vector3(centre.x, centre.y, centre.z)), "")
	_check("deck: ground beside the pass is untouched",
		not lawn.is_cut(Vector3(centre.x, centre.y, centre.z + 6.0)), "")

	# A LEAP. Nothing between the two poses may be missed.
	var lawn2: ACALawn = _build_lawn(ACAPropertyParams.for_seed(9, 96))["lawn"]
	var a := Vector3(centre.x - 30.0, centre.y, centre.z + 10.0)
	var b := Vector3(centre.x + 30.0, centre.y, centre.z + 10.0)
	lawn2.mow_deck(Transform3D(basis, a), Transform3D(basis, b), deck)
	var gaps := 0
	for i in 60:
		var x: float = a.x + float(i) + 0.5
		var p := Vector3(x, centre.y, centre.z + 10.0)
		# Ground the machine is not allowed to cut does not count as a gap.
		if lawn2.is_mowable(p) and not lawn2.is_cut(p):
			gaps += 1
	_check("deck: a sixty unit leap leaves no gap behind the machine",
		gaps == 0, "%d uncut cells along the path" % gaps)
	lawn2.free()
	_free(built)


## Every canonical machine, driven over the whole lawn, finishes it. Exactly one
## hundred per cent, not ninety-nine point something.
func _test_every_mower_reaches_one_hundred() -> void:
	const MOWERS := {
		"rider": "res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn",
		"powered": "res://Assets/Vehicles and Mowers/Mowers/Non Rider Mower.tscn",
		"push": "res://Assets/Vehicles and Mowers/Mowers/Push Mower.tscn",
	}
	for key in MOWERS:
		var packed := load(MOWERS[key]) as PackedScene
		var machine := packed.instantiate()
		var deck := ACAMowerDeck.for_mower(machine)
		machine.free()
		_check("%s: declares its own cutting deck" % key,
			deck.half_width > 1.0 and deck.half_length > 0.5,
			"%.2f x %.2f" % [deck.half_width * 2.0, deck.half_length * 2.0])

		var built := _build_lawn(ACAPropertyParams.for_seed(31, 96))
		var lawn: ACALawn = built["lawn"]
		var passes := _drive_whole_lawn(lawn, deck)
		_check("%s: mowing the whole lawn reaches exactly 100%%" % key,
			lawn.mowed_fraction() >= 1.0
				and lawn.mowed_item_count() == lawn.total_item_count(),
			"%.4f after %d passes (%d of %d)" % [lawn.mowed_fraction(), passes,
				lawn.mowed_item_count(), lawn.total_item_count()])
		_free(built)


## THE pond requirement. A property with water in it must still finish, and it
## must finish without any rule anywhere that mentions ponds.
func _test_pond_property_completes() -> void:
	var params := ACAPropertyParams.preset(&"wooded_pond", 144)
	var built := _build_lawn(params)
	var lawn: ACALawn = built["lawn"]
	var cells := lawn.cell_count() * lawn.cell_count()

	_check("pond property: some cells are excluded from the total",
		lawn.total_item_count() < cells and lawn.total_item_count() > cells / 2,
		"%d mowable of %d" % [lawn.total_item_count(), cells])

	var deck := ACAMowerDeck.make(5.6, 2.4)
	_drive_whole_lawn(lawn, deck)
	_check("pond property: reaches exactly 100%",
		lawn.mowed_fraction() >= 1.0
			and lawn.mowed_item_count() == lawn.total_item_count(),
		"%.4f (%d of %d)" % [lawn.mowed_fraction(), lawn.mowed_item_count(),
			lawn.total_item_count()])

	# And the water itself was never cut, because it was never mowable.
	var pond: ACAPondFeature = null
	for feature in (built["features"] as ACAFeatureSet).features():
		pond = feature as ACAPondFeature
	var submerged_cut := 0
	if pond != null:
		var centre := pond.centre()
		for i in 400:
			var angle := randf_range(0.0, TAU)
			var r := randf_range(0.0, pond.radius() * 0.5)
			var p := Vector3(centre.x + cos(angle) * r, 0.0, centre.y + sin(angle) * r)
			p.y = (built["terrain"] as ACATerrain).height_at(p.x, p.z)
			if p.y < pond.water_world_height() and lawn.is_cut(p):
				submerged_cut += 1
	_check("pond property: nothing under the water was ever cut",
		submerged_cut == 0, "%d submerged cells cut" % submerged_cut)
	_free(built)


## A save is the cut mask, not a list of blades. It has to come back exactly.
func _test_cut_state_round_trip() -> void:
	var params := ACAPropertyParams.preset(&"pond", 96)
	var built := _build_lawn(params)
	var lawn: ACALawn = built["lawn"]
	var deck := ACAMowerDeck.make(5.6, 2.4)
	var centre := lawn.lawn_centre()
	var basis := Basis(Vector3.UP, PI * 0.5)
	for i in 6:
		var z: float = centre.z - 30.0 + float(i) * 7.0
		lawn.mow_deck(
			Transform3D(basis, Vector3(centre.x - 40.0, 0.0, z)),
			Transform3D(basis, Vector3(centre.x + 40.0, 0.0, z)), deck)
	var expected_cut := lawn.mowed_item_count()
	var expected_total := lawn.total_item_count()
	var state := lawn.cut_state()

	var text := JSON.stringify(state)
	var parsed: Variant = JSON.parse_string(text)
	_check("cut state: survives a JSON round trip", parsed is Dictionary, "")
	# A cut lawn is long runs of the same bit and the same heading, so the
	# whole block should cost a small fraction of a byte per cell.
	_check("cut state: is compact", text.length() < expected_total / 3,
		"%d characters for %d cells" % [text.length(), expected_total])

	var rebuilt := _build_lawn(params)
	var lawn2: ACALawn = rebuilt["lawn"]
	_check("cut state: restores on to a rebuilt property",
		lawn2.restore_cut_state(parsed as Dictionary), "")
	_check("cut state: the same cells are cut",
		lawn2.mowed_item_count() == expected_cut
			and lawn2.total_item_count() == expected_total,
		"%d of %d, expected %d of %d" % [lawn2.mowed_item_count(),
			lawn2.total_item_count(), expected_cut, expected_total])
	var mismatches := 0
	for i in 500:
		var p := Vector3(
			centre.x + randf_range(-46.0, 46.0), 0.0,
			centre.z + randf_range(-46.0, 46.0))
		if lawn.is_cut(p) != lawn2.is_cut(p):
			mismatches += 1
	_check("cut state: cell for cell identical", mismatches == 0,
		"%d cells differ" % mismatches)

	# A state from a different sized lawn must be refused, not half applied.
	var other := _build_lawn(ACAPropertyParams.for_seed(1, 144))
	_check("cut state: a state for a different lawn is refused",
		not (other["lawn"] as ACALawn).restore_cut_state(parsed as Dictionary), "")
	_free(other)
	_free(rebuilt)
	_free(built)


## A save written by the previous lawn stored one string per cut blade on a two
## unit lattice. Replaying it must not quietly return a quarter of the progress.
func _test_legacy_migration() -> void:
	var built := _build_lawn(ACAPropertyParams.for_seed(77, 96))
	var lawn: ACALawn = built["lawn"]

	# Rebuild what the old grid would have written for a FULLY mown lawn: every
	# chunk, every instance, in the "chunk_id,x,y,z" form it used.
	var names := PackedStringArray()
	var chunks_per_side := 96 / 4
	for chunk_id in chunks_per_side * chunks_per_side:
		for lx in [0, 2, 4, 6]:
			for lz in [0, 2, 4, 6]:
				names.append("%d,%d,0,%d," % [chunk_id, lx, lz])
	var applied := lawn.apply_legacy_mowed_items(names, 96)
	_check("legacy save: a fully mown old lawn restores as fully mown",
		lawn.mowed_fraction() > 0.985,
		"%d cells applied, %.1f%%" % [applied, lawn.mowed_fraction() * 100.0])
	_free(built)

	# And a half-mown one restores as half mown, on the correct half.
	var half := _build_lawn(ACAPropertyParams.for_seed(77, 96))
	var lawn2: ACALawn = half["lawn"]
	var partial := PackedStringArray()
	for chunk_id in chunks_per_side * chunks_per_side:
		# Chunk ids were handed out in reverse order, so the first half of the
		# ids is the far half of the lawn.
		if chunk_id >= (chunks_per_side * chunks_per_side) / 2:
			continue
		for lx in [0, 2, 4, 6]:
			for lz in [0, 2, 4, 6]:
				partial.append("%d,%d,0,%d," % [chunk_id, lx, lz])
	lawn2.apply_legacy_mowed_items(partial, 96)
	var fraction := lawn2.mowed_fraction()
	_check("legacy save: a half mown old lawn restores as about half mown",
		fraction > 0.44 and fraction < 0.56, "%.3f" % fraction)
	_free(half)


## Not an assertion: a printed table, so a change in generation cost is visible
## in the same run that proves it still works.
func _report_terrain_cost() -> void:
	print("[PROPERTY TEST] terrain generation cost")
	print("| lawn | samples | core tris | ring tris | bake ms | core ms | ring ms | total ms |")
	print("|---|---:|---:|---:|---:|---:|---:|---:|")
	for size in [96, 144, 192]:
		var terrain := _make_terrain(ACAPropertyParams.for_seed(1234, int(size)))
		var s := terrain.statistics()
		print("| %d | %d | %d | %d | %.1f | %.1f | %.1f | %.1f |" % [
			size, s["samples"], s["core_triangles"], s["ring_triangles"],
			s["bake_ms"], s["core_mesh_ms"], s["ring_mesh_ms"], s["total_ms"]])
		terrain.free()


func _report_lawn_cost() -> void:
	print("[PROPERTY TEST] lawn cost")
	print("| lawn | cells | mowable | build ms | nodes | bodies | save bytes |")
	print("|---|---:|---:|---:|---:|---:|---:|")
	for size in [96, 144, 192]:
		var built := _build_lawn(ACAPropertyParams.for_seed(1234, int(size)))
		var lawn: ACALawn = built["lawn"]
		var deck := ACAMowerDeck.make(5.6, 2.4)
		_drive_whole_lawn(lawn, deck)
		var bytes := JSON.stringify(lawn.cut_state()).length()
		print("| %d | %d | %d | %.1f | %d | %d | %d |" % [
			size, lawn.cell_count() * lawn.cell_count(), lawn.total_item_count(),
			lawn.build_milliseconds(), _count_nodes(lawn), _count_bodies(lawn), bytes])
		_free(built)


## THE CLEARANCE CONSTANT IS A COPY OF A MEASUREMENT, and this is what stops it
## becoming a copy of an out-of-date one. `ACAMowerClearance` documents a table
## derived from the canonical mower scenes and their declared decks; if either
## changes - a wider chassis, a narrower deck, a fourth machine - the constant
## the properties were generated with is quietly wrong and every lawn gains an
## uncuttable ring. So the table is re-derived from the real scenes here.
func _test_clearance_matches_the_machines() -> void:
	var measured := ACAMowerClearance.measure_scenes()
	_check("clearance: every canonical machine could be measured",
		int((measured["machines"] as Array).size()) == ACAMowerClearance.MOWER_SCENES.size(),
		"measured %d of %d" % [(measured["machines"] as Array).size(),
			ACAMowerClearance.MOWER_SCENES.size()])
	_check("clearance: the constant still matches the machines",
		bool(measured["ok"]),
		"scenes say %.3f, the constant says %.3f (tolerance %.2f)" % [
			float(measured["shortfall"]), ACAMowerClearance.WORST_SHORTFALL,
			ACAMowerClearance.DRIFT_TOLERANCE])
	for entry: Dictionary in measured["machines"]:
		print("[PROPERTY TEST]   %s: chassis %.2f x %.2f, deck %.2f wide reaching %.2f, shortfall %.3f" % [
			String(entry["path"]).get_file().get_basename(),
			float(entry["chassis_half_x"]) * 2.0, float(entry["chassis_half_z"]) * 2.0,
			float(entry["deck_half_width"]) * 2.0, float(entry["deck_reach"]),
			float(entry["shortfall"])])


## ---------------------------------------------------------------------------
## THE ONE THAT MATTERS: CAN EVERY CELL THE PLAYER IS PAID FOR BE REACHED?
## ---------------------------------------------------------------------------
## A cell counts towards completion if the feature set calls it mowable. It can
## be CUT only if the deck can be brought over it, and the deck cannot go where
## the chassis cannot follow. So for every solid feature, the band from its
## COLLISION SURFACE out to `WORST_SHORTFALL` is ground the worst machine in the
## fleet can see and never cut, and no mowable cell may sit in it.
##
## The collision surface is asked for by name rather than derived: the obstacle
## list is the one the collision spheres were built from, and the shoreline is
## the polygon the collision ring was built from. Re-deriving either would let
## the test agree with a wrong answer.
##
## It is a geometric check on the generator rather than a simulation of driving.
## Driving every machine over every seed is the deferred playability harness;
## this is the cheap thing that catches the same bug.
func _test_no_mowable_cell_is_trapped() -> void:
	var seeds := [11, 4242, 90210, 777001, 313377, 8, 65535, 1, 202020, 5150]
	var worst_intrusion := 0.0
	var trapped_total := 0
	var checked := 0
	var need: float = ACAMowerClearance.WORST_SHORTFALL
	for property_seed: int in seeds:
		var params := ACAPropertyParams.for_seed(property_seed, 144)
		var built := _build_lawn(params)
		var lawn: ACALawn = built["lawn"]
		var terrain: ACATerrain = built["terrain"]
		var features: ACAFeatureSet = built["features"]
		var discs := _collision_discs(features)
		var rings := _collision_rings(features, terrain)

		var centre := lawn.lawn_centre()
		var half := lawn.lawn_half_extent()
		var cells := int(half * 2.0)
		for iz in cells:
			var z: float = centre.z - half + float(iz) + 0.5
			for ix in cells:
				var x: float = centre.x - half + float(ix) + 0.5
				if not features.is_mowable(x, z, terrain.height_at(x, z)):
					continue
				checked += 1
				var clear: float = _distance_to_collision(Vector2(x, z), discs, rings)
				if clear < need:
					trapped_total += 1
					worst_intrusion = maxf(worst_intrusion, need - clear)
		_free(built)

	_check("clearance: no mowable cell sits inside a machine's stopping band",
		trapped_total == 0,
		"%d of %d mowable cells trapped, worst %.2f units inside" % [
			trapped_total, checked, worst_intrusion])
	print("[PROPERTY TEST]   checked %d mowable cells across %d seeds" % [
		checked, seeds.size()])

	# THE PROPERTY EDGE needs no clearance band of its own, and this is the
	# assertion that says so rather than leaving it to be assumed. The lawn stops
	# `boundary_margin()` short of the fence - fifteen units at the tightest -
	# so the machine drives PAST the last row of lawn and back, and the last pass
	# round the perimeter is never squeezed against a wall.
	var tightest := INF
	for property_seed: int in seeds:
		var params := ACAPropertyParams.for_seed(property_seed, 144)
		tightest = minf(tightest, params.boundary_margin())
	_check("clearance: the lawn stops well short of the boundary wall",
		tightest >= ACAMowerClearance.REQUIRED * 2.0,
		"tightest margin %.1f units, need %.1f" % [
			tightest, ACAMowerClearance.REQUIRED * 2.0])


## The obstacle collision spheres, as { centre, radius } on XZ.
func _collision_discs(features: ACAFeatureSet) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for feature in features.features():
		if not (feature is ACALawnObstacles):
			continue
		for o: Dictionary in (feature as ACALawnObstacles).obstacles():
			out.append({"centre": o["position"] as Vector2,
				"radius": float(o["radius"])})
	return out


## The pond's shoreline polygons, grown by half the collision ring's thickness
## because the ring is a wall standing ON the traced line and its outer face is
## what the machine actually meets.
func _collision_rings(features: ACAFeatureSet,
		terrain: ACATerrain) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for feature in features.features():
		if not (feature is ACAPondFeature):
			continue
		var points := (feature as ACAPondFeature).shoreline_points(terrain)
		if points.size() >= 3:
			out.append({"points": points,
				"grow": ACAPondFeature.RING_THICKNESS * 0.5})
	return out


## How much clear ground there is between a point and the nearest collision
## surface, in world units. Negative would mean inside one, which a mowable cell
## never is.
func _distance_to_collision(at: Vector2, discs: Array[Dictionary],
		rings: Array[Dictionary]) -> float:
	var best := INF
	for d: Dictionary in discs:
		best = minf(best, at.distance_to(d["centre"] as Vector2) - float(d["radius"]))
	for r: Dictionary in rings:
		var points: PackedVector2Array = r["points"]
		var nearest := INF
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			nearest = minf(nearest, _distance_to_segment(at, a, b))
		best = minf(best, nearest - float(r["grow"]))
	return best


static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var span := b - a
	var length_squared := span.length_squared()
	if length_squared < 0.000001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(a + span * t)


# =================================================================== helpers

## A terrain, features and a lawn, without the rendering. Everything the mowing
## logic needs and nothing it does not.
func _build_lawn(params: ACAPropertyParams) -> Dictionary:
	# THROUGH the production composer, not a copy of it. A suite that builds its
	# own feature set is a suite that stops testing the game the moment the game
	# gains a feature - which is exactly what happened when the lawn obstacles
	# arrived and this function still only knew about ponds.
	return _build_lawn_with(params, ACAProperty.make_features(params, Vector2.ZERO))


## A lawn with a feature set supplied by the caller, for the two tests that want
## to isolate the bare rectangle from anything standing on it.
func _build_lawn_with(params: ACAPropertyParams,
		features: ACAFeatureSet) -> Dictionary:
	var terrain := ACATerrain.new()
	terrain.build(params, features)
	var lawn := ACALawn.new()
	lawn.build(params, terrain, features)
	return {"terrain": terrain, "lawn": lawn, "features": features}


func _free(built: Dictionary) -> void:
	(built["lawn"] as ACALawn).free()
	(built["terrain"] as ACATerrain).free()


## Sweep the deck over every square unit of the lawn, in overlapping lanes, the
## way a player who wants to be paid actually drives.
func _drive_whole_lawn(lawn: ACALawn, deck: ACAMowerDeck) -> int:
	var centre := lawn.lawn_centre()
	var half := lawn.lawn_half_extent()
	# Lanes overlap slightly, which is also what a player does.
	var pitch: float = deck.half_width * 2.0 * 0.85
	var lanes: int = int(ceil((half * 2.0 + pitch) / pitch)) + 1
	var basis := Basis(Vector3.UP, PI * 0.5)
	# EACH LANE IS WALKED IN STRIDES NO LONGER THAN THE DECK. `mow_deck` bounds
	# one call's sweep at sixty-four stamps, which is right for a machine
	# reporting every physics frame and hopeless for a single call spanning two
	# hundred units: the stamps end up further apart than the deck is long and
	# the pass comes out as a ladder of cut and uncut rungs. That is a limit of
	# driving the lawn from a test, not of the lawn.
	var stride: float = deck.half_length * 2.0 * 0.8
	for i in lanes:
		var z: float = centre.z - half - pitch * 0.5 + float(i) * pitch
		var x: float = centre.x - half - 4.0
		var finish: float = centre.x + half + 4.0
		var previous := Transform3D(basis, Vector3(x, 0.0, z))
		while x < finish:
			x = minf(x + stride, finish)
			var current := Transform3D(basis, Vector3(x, 0.0, z))
			lawn.mow_deck(previous, current, deck)
			previous = current
	return lanes


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



## Winding check straight off the committed arrays: at least nineteen triangles
## in twenty must have an upward geometric normal for a ground surface.
func _faces_up(mesh: Mesh) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var up := 0
	var total := 0
	var step: int = maxi(3, (indices.size() / 3 / 400) * 3)
	var i := 0
	while i + 2 < indices.size():
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		# Godot's front-face normal for a triangle (a, b, c). The winding test
		# above pins this down rather than leaving it to convention.
		var n := (c - a).cross(b - a)
		if n.length_squared() > 0.0:
			total += 1
			if n.y > 0.0:
				up += 1
		i += step
	return total > 50 and float(up) / float(total) > 0.95


func _make_terrain(params: ACAPropertyParams,
		features: ACAFeatureSet = null) -> ACATerrain:
	var terrain := ACATerrain.new()
	terrain.build(params, features)
	return terrain


func _check(label: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("[PROPERTY TEST] %s: PASS" % label)
	else:
		_failed += 1
		print("[PROPERTY TEST] %s: FAIL  %s" % [label, detail])


# ===================================================== ponds, rocks and fences

## EVERY generated property has water on it, at every contract size, and the
## pond is scaled to the lawn it is on rather than to a constant.
func _test_every_property_has_a_pond() -> void:
	var sizes := [96, 144, 192]
	for size in sizes:
		var without := 0
		var worst_share := 0.0
		var smallest := INF
		for seed_value in range(1, 41):
			var params := ACAPropertyParams.for_seed(seed_value * 977, int(size))
			if not params.pond_enabled:
				without += 1
				continue
			smallest = minf(smallest, params.pond_radius)
			# Area of the ellipse against the area of the lawn.
			var area: float = PI * params.pond_radius \
				* params.pond_radius * params.pond_ellipse_ratio
			worst_share = maxf(worst_share,
				area / (float(size) * float(size)))
		_check("size %d: all 40 seeds generate a pond" % size,
			without == 0, "%d without" % without)
		# A pond may be a feature of the property. It may not BE the property.
		_check("size %d: no pond takes more than a fifth of the lawn" % size,
			worst_share < 0.20, "worst %.1f%%" % (worst_share * 100.0))
		_check("size %d: no pond is too small to read as one" % size,
			smallest >= 5.0, "smallest radius %.1f" % smallest)


## The placement rules that keep a lawn drivable. Every one of these is a rule a
## player would notice being broken.
func _test_obstacles_are_fair() -> void:
	var too_close := 0
	var off_lawn := 0
	var on_spawn := 0
	var in_pond := 0
	var empty := 0
	for size in [96, 144, 192]:
		for seed_value in range(1, 31):
			var params := ACAPropertyParams.for_seed(seed_value * 313 + 7, int(size))
			var features := ACAProperty.make_features(params, Vector2.ZERO)
			var field: ACALawnObstacles = null
			var pond: ACAPondFeature = null
			for f in features.features():
				if f is ACALawnObstacles:
					field = f
				elif f is ACAPondFeature:
					pond = f
			if field == null or field.count() == 0:
				empty += 1
				continue
			var half := params.lawn_half_extent()
			var arrival := Vector2(-half, 0.0)
			var list := field.obstacles()
			for i in list.size():
				var a: Dictionary = list[i]
				var at: Vector2 = a["position"]
				var r: float = float(a["radius"])
				if absf(at.x) + r > half or absf(at.y) + r > half:
					off_lawn += 1
				if at.distance_to(arrival) < ACALawnObstacles.SPAWN_CLEAR:
					on_spawn += 1
				if pond != null:
					# Inside the pond outline at all is too far in.
					if pond.shore_factor_at(at.x, at.y) > 0.0:
						in_pond += 1
				for j in range(i + 1, list.size()):
					var b: Dictionary = list[j]
					var gap: float = at.distance_to(b["position"]) \
						- r - float(b["radius"])
					if gap < ACALawnObstacles.MOWER_CLEARANCE - 0.01:
						too_close += 1
	_check("obstacles: every property gets some", empty == 0,
		"%d properties with none" % empty)
	_check("obstacles: none hangs over the lawn edge", off_lawn == 0,
		"%d over the edge" % off_lawn)
	_check("obstacles: none blocks the arrival", on_spawn == 0,
		"%d on the spawn" % on_spawn)
	_check("obstacles: none is in the pond", in_pond == 0,
		"%d in water" % in_pond)
	_check("obstacles: every gap fits the widest deck", too_close == 0,
		"%d pairs closer than %.1f units" % [too_close, ACALawnObstacles.MOWER_CLEARANCE])


## The playable rectangle has to contain the whole contract and the point the
## machine arrives at, and has to sit inside the ground that has collision.
func _test_boundary_contains_the_property() -> void:
	for size in [96, 144, 192]:
		var too_tight := 0
		var past_terrain := 0
		for seed_value in range(1, 41):
			var params := ACAPropertyParams.for_seed(seed_value * 641 + 3, int(size))
			var half := params.lawn_half_extent()
			var edge := params.boundary_half_extent()
			# The arrival sits `ARRIVAL_SETBACK` outside the lawn, and the
			# machine is about six units long behind that.
			if edge < half + ACAProperty.ARRIVAL_SETBACK + 6.0:
				too_tight += 1
			if edge > params.near_extent():
				past_terrain += 1
		_check("size %d: the fence leaves room for the arrival" % size,
			too_tight == 0, "%d too tight" % too_tight)
		_check("size %d: the fence is inside the ground collision" % size,
			past_terrain == 0, "%d past the terrain" % past_terrain)


## THE completion requirement, with rocks on the lawn as well as water in it.
## A property nobody can finish is a property nobody can be paid for.
func _test_obstacle_property_completes() -> void:
	for size in [96, 144, 192]:
		var params := ACAPropertyParams.for_seed(4242 + int(size), int(size))
		var built := _build_lawn(params)
		var lawn: ACALawn = built["lawn"]
		var cells := lawn.cell_count() * lawn.cell_count()
		_check("obstacle lawn %d: ground under the rocks is excluded" % size,
			lawn.total_item_count() < cells and lawn.total_item_count() > cells / 2,
			"%d mowable of %d" % [lawn.total_item_count(), cells])
		_drive_whole_lawn(lawn, ACAMowerDeck.make(5.6, 2.4))
		_check("obstacle lawn %d: still reaches exactly 100%%" % size,
			lawn.mowed_fraction() >= 1.0
				and lawn.mowed_item_count() == lawn.total_item_count(),
			"%.4f (%d of %d)" % [lawn.mowed_fraction(), lawn.mowed_item_count(),
				lawn.total_item_count()])
		_free(built)
