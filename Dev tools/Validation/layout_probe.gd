extends Node
## DEVELOPMENT. Checks the lawn-obstacle LAYOUTS added in generation version 6.
##
## Everything here is composed through `ACAProperty.make_features()`, the same
## static entry point the game builds a property's features from - so this
## cannot quietly measure a property the game does not generate.
##
## What it is actually asking:
##
##   VARIETY        do different seeds produce different arrangements, or has
##                  one weight swallowed the table?
##   ROUTE          do the arrangements actually differ in SHAPE? Measured as
##                  the spread of the obstacles about their own centre, which is
##                  what an island and a perimeter disagree about.
##   SAFETY         is every rule the scatter obeyed still obeyed - inside the
##                  lawn, clear of the arrival corridor, and never two obstacles
##                  closer together than the widest machine.
##   DETERMINISM    does a seed rebuild the identical property?
##   SAVES          does a property generated before layouts existed still get
##                  the scatter it was built with?

const SEEDS := 60
const SIZES: Array[int] = [96, 144, 192]

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("\n============ LAYOUT PROBE ============")
	_variety()
	_maps()
	_shape()
	_safety()
	_determinism()
	_legacy_saves()
	print("[LAYOUT PROBE] %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _features(property_seed: int, size: int) -> ACAFeatureSet:
	var params := ACAPropertyParams.for_seed(property_seed, size)
	return ACAProperty.make_features(params, Vector2.ZERO)


func _obstacles_of(set: ACAFeatureSet) -> ACALawnObstacles:
	for f in set.features():
		if f is ACALawnObstacles:
			return f as ACALawnObstacles
	return null


# ==================================================================== variety

func _variety() -> void:
	print("\n-- arrangements over %d seeds --" % SEEDS)
	for size in SIZES:
		var counts := {}
		var total := 0
		for i in SEEDS:
			var obstacles := _obstacles_of(_features(90000 + i * 7717, size))
			if obstacles == null:
				continue
			var name := obstacles.layout_name()
			counts[name] = int(counts.get(name, 0)) + 1
			total += 1
		var line := ""
		for key in counts:
			line += "%s %d  " % [key, counts[key]]
		print("  %d x %d : %s" % [size, size, line])

		if size >= ACALawnObstacles.LAYOUT_MIN_LAWN:
			_check("%d: more than one arrangement appears" % size, counts.size() >= 4)
			var most := 0
			for key in counts:
				most = maxi(most, int(counts[key]))
			_check("%d: no arrangement swallows the table" % size,
				float(most) / maxf(float(total), 1.0) < 0.45)
		else:
			_check("%d: a small lawn is never given a full arrangement" % size,
				not counts.has("Island") and not counts.has("Gauntlet")
					and not counts.has("Avenue") and not counts.has("Perimeter"))


# ======================================================================= maps
##
## One example of each arrangement, drawn. The numbers below say the shapes
## differ; this is what they look like. `#` is an obstacle, `~` the pond, `>`
## the corner the machine arrives from.

func _maps() -> void:
	print("
-- one property of each arrangement, 144 x 144 --")
	var seen := {}
	for i in SEEDS * 4:
		var property_seed := 90000 + i * 7717
		var set := _features(property_seed, 144)
		var obstacles := _obstacles_of(set)
		if obstacles == null:
			continue
		var name := obstacles.layout_name()
		if seen.has(name):
			continue
		seen[name] = true
		print("
  %s (seed %d, %d obstacles)"
			% [name, property_seed, obstacles.count()])
		_draw(obstacles.obstacles(), 72.0)
		if seen.size() >= ACALawnObstacles.LAYOUT_NAMES.size():
			break


## 24 columns across the lawn, halved vertically because a console character is
## about twice as tall as it is wide.
func _draw(list: Array[Dictionary], half: float) -> void:
	const COLUMNS := 24
	const ROWS := 12
	var grid: Array[PackedStringArray] = []
	for r in ROWS:
		var row := PackedStringArray()
		for c in COLUMNS:
			row.append(".")
		grid.append(row)
	for o in list:
		var at: Vector2 = o["position"]
		var c := clampi(int((at.x + half) / (half * 2.0) * COLUMNS), 0, COLUMNS - 1)
		var r := clampi(int((at.y + half) / (half * 2.0) * ROWS), 0, ROWS - 1)
		grid[r][c] = "#"
	# The machine arrives off the -X edge at the lawn centre line.
	grid[ROWS / 2][0] = ">"
	for r in ROWS:
		print("    |%s|" % "".join(grid[r]))


# ====================================================================== shape
##
## Do the arrangements differ in the way that matters - the SHAPE of the route
## they ask for? Three numbers, all as a fraction of the lawn, averaged per
## arrangement over every seed that produced it:
##
##   REACH    mean distance of an obstacle from the middle of the lawn. An
##            island sits low; a perimeter sits high.
##   PULL     how far the group's centre of mass is from the middle. Corners
##            pull hard to one side; a scatter averages out to nothing.
##   LINE     how much more the group is spread along its own principal axis
##            than across it. An avenue is a line; a scatter is a blob.

func _shape() -> void:
	print("
-- the shape of the route each arrangement asks for --")
	var totals := {}
	for size in SIZES:
		if size < ACALawnObstacles.LAYOUT_MIN_LAWN:
			continue
		var span := float(size) * 0.5
		for i in SEEDS:
			var obstacles := _obstacles_of(_features(90000 + i * 7717, size))
			if obstacles == null or obstacles.count() < 3:
				continue
			var name := obstacles.layout_name()
			if not totals.has(name):
				totals[name] = {"reach": 0.0, "pull": 0.0, "line": 0.0, "n": 0}
			var m: Dictionary = totals[name]
			var stats := _measure(obstacles.obstacles(), span)
			m["reach"] += stats.x
			m["pull"] += stats.y
			m["line"] += stats.z
			m["n"] = int(m["n"]) + 1

	print("  arrangement   reach   pull    line")
	var reach := {}
	var pull := {}
	var line := {}
	for name in totals:
		var m: Dictionary = totals[name]
		var n := maxf(float(m["n"]), 1.0)
		reach[name] = float(m["reach"]) / n
		pull[name] = float(m["pull"]) / n
		line[name] = float(m["line"]) / n
		print("  %-13s %-7.2f %-7.2f %-7.2f" % [name, reach[name], pull[name],
			line[name]])

	_check("an island keeps to the middle and a perimeter to the edge",
		float(reach.get("Island", 1.0)) < float(reach.get("Perimeter", 0.0)) - 0.15)
	_check("corners pull to one side and a scatter does not",
		float(pull.get("Corners", 0.0)) > float(pull.get("Scatter", 1.0)) + 0.15)
	_check("an avenue is a line and a scatter is a blob",
		float(line.get("Avenue", 0.0)) > float(line.get("Scatter", 9.0)) + 0.4)


## Returns (reach, pull, line) for one property, all normalised by the lawn.
func _measure(list: Array[Dictionary], span: float) -> Vector3:
	var centroid := Vector2.ZERO
	for o in list:
		centroid += o["position"] as Vector2
	centroid /= float(list.size())

	var reach := 0.0
	for o in list:
		reach += (o["position"] as Vector2).length()
	reach /= float(list.size()) * span

	# Spread along the principal axis against spread across it, from the 2x2
	# covariance. No matrix library needed for two dimensions.
	var xx := 0.0
	var yy := 0.0
	var xy := 0.0
	for o in list:
		var d := (o["position"] as Vector2) - centroid
		xx += d.x * d.x
		yy += d.y * d.y
		xy += d.x * d.y
	var n := float(list.size())
	xx /= n
	yy /= n
	xy /= n
	var mean := (xx + yy) * 0.5
	var gap := sqrt(maxf(((xx - yy) * 0.5) * ((xx - yy) * 0.5) + xy * xy, 0.0))
	var major := mean + gap
	var minor := maxf(mean - gap, 0.0001)
	return Vector3(reach, centroid.length() / span, sqrt(major / minor))


# ===================================================================== safety
##
## The arrangements only OFFER positions. Every rule the scatter obeyed is still
## enforced by `_acceptable()`, and this is what proves it on the real output.

func _safety() -> void:
	print("\n-- every rule the scatter obeyed --")
	var worst_gap := INF
	var worst_edge := INF
	var worst_arrival := INF
	var shortfall := 0
	var checked := 0

	for size in SIZES:
		var half := float(size) * 0.5
		var arrival := Vector2(-half, 0.0)
		for i in SEEDS:
			var obstacles := _obstacles_of(_features(90000 + i * 7717, size))
			if obstacles == null:
				continue
			var list := obstacles.obstacles()
			checked += 1
			if list.size() < ACALawnObstacles.MIN_OBSTACLES:
				shortfall += 1
			for a in list.size():
				var at: Vector2 = list[a]["position"]
				var radius: float = list[a]["radius"]
				worst_edge = minf(worst_edge,
					half - maxf(absf(at.x), absf(at.y)) - radius)
				worst_arrival = minf(worst_arrival,
					at.distance_to(arrival) - radius)
				for b in range(a + 1, list.size()):
					var other: Vector2 = list[b]["position"]
					worst_gap = minf(worst_gap, at.distance_to(other)
						- radius - float(list[b]["radius"]))

	print("  tightest gap between two obstacles : %.2f (limit %.2f)"
		% [worst_gap, ACALawnObstacles.MOWER_CLEARANCE])
	print("  closest any obstacle gets to the edge : %.2f (limit %.2f)"
		% [worst_edge, ACALawnObstacles.EDGE_INSET])
	print("  closest any obstacle gets to the arrival : %.2f (limit %.2f)"
		% [worst_arrival, ACALawnObstacles.SPAWN_CLEAR])

	_check("no gap is narrower than the widest machine",
		worst_gap >= ACALawnObstacles.MOWER_CLEARANCE - 0.001)
	_check("nothing is jammed against the boundary",
		worst_edge >= ACALawnObstacles.EDGE_INSET - 0.001)
	_check("the arrival is clear on every property",
		worst_arrival >= ACALawnObstacles.SPAWN_CLEAR - 0.001)
	_check("every property still fills its quota",
		shortfall == 0, "%d of %d fell short" % [shortfall, checked])


# ================================================================ determinism

func _determinism() -> void:
	print("\n-- a seed is still a promise --")
	var identical := true
	for i in SEEDS:
		var first := _obstacles_of(_features(90000 + i * 7717, 144))
		var second := _obstacles_of(_features(90000 + i * 7717, 144))
		if first == null or second == null:
			continue
		if first.layout() != second.layout():
			identical = false
			break
		var a := first.obstacles()
		var b := second.obstacles()
		if a.size() != b.size():
			identical = false
			break
		for k in a.size():
			if not (a[k]["position"] as Vector2).is_equal_approx(b[k]["position"]) \
					or a[k]["kind"] != b[k]["kind"]:
				identical = false
				break
	_check("the same seed rebuilds the identical property", identical)


# ================================================================ legacy saves

func _legacy_saves() -> void:
	print("\n-- a save written before layouts existed --")
	var all_scatter := true
	var any_arranged := false
	for i in SEEDS:
		var params := ACAPropertyParams.for_seed(90000 + i * 7717, 144)
		var arranged := ACAProperty.make_features(params, Vector2.ZERO)
		if _obstacles_of(arranged) != null \
				and _obstacles_of(arranged).layout() != ACALawnObstacles.Layout.SCATTER:
			any_arranged = true

		# The same property as a version 5 save would restore it.
		var legacy := ACAPropertyParams.for_seed(90000 + i * 7717, 144)
		legacy.generation_version = 5
		var old := _obstacles_of(ACAProperty.make_features(legacy, Vector2.ZERO))
		if old != null and old.layout() != ACALawnObstacles.Layout.SCATTER:
			all_scatter = false
	_check("a version 5 property is still scattered", all_scatter)
	_check("a version 6 property is arranged", any_arranged)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passes += 1
		print("[LAYOUT PROBE] %s: PASS" % label)
	else:
		_failures += 1
		printerr("[LAYOUT PROBE] %s: FAIL %s" % [label, detail])
