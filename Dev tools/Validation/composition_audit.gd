extends SceneTree
## DEVELOPMENT ONLY. Measures the PROPERTY GENERATOR across hundreds of seeds and
## reports the distribution, so a systemic problem is found as a number rather
## than by somebody happening to look at the seed that shows it.
##
##   godot --headless --path . --script "res://Dev tools/Validation/composition_audit.gd" \
##     -- "--audit-seeds=200"
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS ALONGSIDE THE RENDERS
## ---------------------------------------------------------------------------
## Renders answer "is this property nice to look at". They cannot answer "do one
## property in forty come out with the pond touching the fence", because nobody
## renders forty properties and counts. Both are needed, and this is the half
## that scales: it builds the real terrain, the real lawn and the real feature
## set for every seed and reports what came out.
##
## It prints tables and NEVER fails a build. Judging a distribution is a design
## decision; `Property Test` is where the rules that must always hold live.
##
## PUBLIC API: None.

const SIZES := [96, 144, 192]
const DEFAULT_SEEDS := 160


func _init() -> void:
	var count := DEFAULT_SEEDS
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--audit-seeds="):
			count = maxi(arg.trim_prefix("--audit-seeds=").to_int(), 8)

	print("=== COMPOSITION AUDIT === %d seeds per size" % count)
	for size in SIZES:
		_audit_size(int(size), count)
	print("=== COMPOSITION AUDIT DONE ===")
	quit()


func _audit_size(size: int, count: int) -> void:
	var forestiness := PackedFloat64Array()
	var pond_share := PackedFloat64Array()
	var pond_radius := PackedFloat64Array()
	var boundary := PackedFloat64Array()
	var obstacles := PackedFloat64Array()
	var excluded := PackedFloat64Array()
	var openness := PackedFloat64Array()

	var beds := PackedFloat64Array()

	var no_pond := 0
	var pond_over_fence := 0
	var pond_off_lawn := 0
	var thin_obstacle_gap := 0
	var treatment_counts := {}
	var archetype_counts := {}

	for i in count:
		var seed_value := 7919 * (i + 1) + size * 131
		# THE ARCHETYPE CYCLES. Auditing only the rural default would leave the
		# three kinds of property the seed can no longer produce on its own
		# entirely unmeasured, which is where the pond, the obstacles and the
		# beds are most likely to disagree with each other.
		var kind: int = i % ACAPropertyArchetype.NAMES.size()
		var params := ACAPropertyParams.for_seed(seed_value, size, kind)
		var half := params.lawn_half_extent()
		var kind_name := ACAPropertyArchetype.name_of(kind)
		archetype_counts[kind_name] = int(archetype_counts.get(kind_name, 0)) + 1

		forestiness.append(params.forestiness)
		openness.append(params.lawn_openness)
		boundary.append(params.boundary_margin())

		if not params.pond_enabled:
			no_pond += 1
		else:
			pond_radius.append(params.pond_radius)
			var area: float = PI * params.pond_radius * params.pond_radius \
				* params.pond_ellipse_ratio
			pond_share.append(area / (float(size) * float(size)))
			# The furthest the outline can reach from the property centre.
			var reach: float = params.pond_offset.length() \
				+ params.pond_radius * maxf(params.pond_ellipse_ratio, 1.0) \
					* (1.0 + params.pond_irregularity)
			if reach > params.boundary_half_extent():
				pond_over_fence += 1
			if reach > half + 4.0:
				pond_off_lawn += 1

		var treatment := ACAPropertyBoundary.treatment_name(
			ACAPropertyBoundary._roll_treatment(params))
		treatment_counts[treatment] = int(treatment_counts.get(treatment, 0)) + 1

		var features := ACAProperty.make_features(params, Vector2.ZERO)
		var field: ACALawnObstacles = null
		for f in features.features():
			if f is ACALawnObstacles:
				field = f
		obstacles.append(float(field.count()) if field != null else 0.0)

		# THE COMPLETION DENOMINATOR, measured rather than assumed. A property
		# where features have taken a big share of the contract is a property the
		# player is paid the same for and does less work on.
		var terrain := ACATerrain.new()
		terrain.build(params, features)
		var lawn := ACALawn.new()
		lawn.build(params, terrain, features)
		var cells := lawn.cell_count() * lawn.cell_count()
		excluded.append(1.0 - float(lawn.total_item_count()) / float(maxi(cells, 1)))
		lawn.free()
		terrain.free()

		for feature in features.features():
			if feature is ACALawnBeds:
				beds.append(float((feature as ACALawnBeds).count()))

		if field != null:
			var list := field.obstacles()
			for a in list.size():
				for b in range(a + 1, list.size()):
					var gap: float = (list[a]["position"] as Vector2).distance_to(
						list[b]["position"] as Vector2) \
						- float(list[a]["radius"]) - float(list[b]["radius"])
					if gap < ACALawnObstacles.MOWER_CLEARANCE - 0.01:
						thin_obstacle_gap += 1

	print("")
	print("-- lawn %d ------------------------------------------------" % size)
	_report("forestiness", forestiness)
	_report("lawn_openness", openness)
	_report("boundary margin", boundary)
	_report("pond radius", pond_radius)
	_report("pond share of lawn", pond_share, 100.0, "%")
	_report("obstacles", obstacles)
	_report("excluded share of lawn", excluded, 100.0, "%")
	_report("planted beds", beds)
	print("   properties with no pond      : %d" % no_pond)
	print("   ponds reaching past the fence: %d" % pond_over_fence)
	print("   ponds reaching off the lawn  : %d" % pond_off_lawn)
	print("   obstacle pairs too close     : %d" % thin_obstacle_gap)
	var treatments := PackedStringArray()
	for key in treatment_counts:
		treatments.append("%s %d" % [key, treatment_counts[key]])
	print("   fence treatments             : %s" % ", ".join(treatments))
	var kinds := PackedStringArray()
	for key in archetype_counts:
		kinds.append("%s %d" % [key, archetype_counts[key]])
	print("   archetypes                   : %s" % ", ".join(kinds))


func _report(label: String, values: PackedFloat64Array, scale: float = 1.0,
		suffix: String = "") -> void:
	if values.is_empty():
		print("   %-29s: none" % label)
		return
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += v
	print("   %-29s: min %6.2f%s  p10 %6.2f%s  median %6.2f%s  p90 %6.2f%s  max %6.2f%s  mean %6.2f%s" % [
		label,
		sorted[0] * scale, suffix,
		sorted[int(sorted.size() * 0.1)] * scale, suffix,
		sorted[sorted.size() / 2] * scale, suffix,
		sorted[mini(int(sorted.size() * 0.9), sorted.size() - 1)] * scale, suffix,
		sorted[sorted.size() - 1] * scale, suffix,
		(total / float(sorted.size())) * scale, suffix])
