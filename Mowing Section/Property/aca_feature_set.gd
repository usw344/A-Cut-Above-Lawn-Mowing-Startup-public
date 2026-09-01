class_name ACAFeatureSet
extends RefCounted
## ROLE
## The collection of landscape features on one property, and the single place
## that answers "is this world position available?".
##
## It exists so the lawn, the grass placer and the foliage placer hold ONE
## reference each instead of a list they have to iterate correctly, and so the
## broad-phase rejection is written once. An empty set answers "clear" to
## everything at close to no cost, which is the common case.
##
## PUBLIC API
##   add(feature) / features() / is_empty() / count()
##   prepare(base_height)                 -> let features resolve reference ground
##   terrain_offset_at(x, z)              -> summed ground displacement
##   mowing_exclusion_at(x, z, ground_y)  -> 0 .. 1
##   grass_exclusion_at(x, z, ground_y)   -> 0 .. 1
##   foliage_exclusion_at(x, z, ground_y) -> 0 .. 1
##   is_mowable(x, z, ground_y)           -> bool
##   build_nodes(parent, terrain, params)
##
## SIGNALS: None.
##
## INVARIANTS
##   * Every query is pure and frame-independent.
##   * Exclusions COMBINE by maximum, not by sum, so two overlapping features
##     cannot push a value past 1.0.
##   * Callers pass the FINAL terrain height as `ground_y`.
##
## PERSISTENCE OWNERSHIP
##   None. Rebuilt from ACAPropertyParams every time.

var _features: Array[ACAPropertyFeature] = []
## Cached XZ rectangles, so the common "nothing near here" answer costs four
## float comparisons per feature and no virtual call.
var _rects: Array[Rect2] = []


func add(feature: ACAPropertyFeature) -> void:
	if feature == null:
		return
	_features.append(feature)
	var b := feature.bounds()
	_rects.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))


func features() -> Array[ACAPropertyFeature]:
	return _features


func is_empty() -> bool:
	return _features.is_empty()


func count() -> int:
	return _features.size()


func prepare(base_height: Callable) -> void:
	for f in _features:
		f.prepare(base_height)
	# Bounds can only be final once a feature has resolved its reference ground.
	_rects.clear()
	for f in _features:
		var b := f.bounds()
		_rects.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))


## Summed vertical displacement of every feature at a point. Summed rather than
## maxed because two features digging the same ground should dig it twice; the
## generator does not place overlapping ones.
func terrain_offset_at(x: float, z: float) -> float:
	if _features.is_empty():
		return 0.0
	var total := 0.0
	var point := Vector2(x, z)
	for i in _features.size():
		if not _rects[i].has_point(point):
			continue
		total += _features[i].terrain_offset_at(x, z)
	return total


func mowing_exclusion_at(x: float, z: float, ground_y: float) -> float:
	return _exclusion(x, z, ground_y, 0)


func grass_exclusion_at(x: float, z: float, ground_y: float) -> float:
	return _exclusion(x, z, ground_y, 1)


func foliage_exclusion_at(x: float, z: float, ground_y: float) -> float:
	return _exclusion(x, z, ground_y, 2)


## THE question the lawn asks, and the only one it needs.
func is_mowable(x: float, z: float, ground_y: float) -> bool:
	return mowing_exclusion_at(x, z, ground_y) < ACAPropertyFeature.EXCLUDED_THRESHOLD


## ...and the second one, asked only of ground that is already unavailable: is
## it PROTECTED VEGETATION? See `ACAPropertyFeature.is_protected_vegetation()`.
##
## Answered by whether a protecting feature is the one taking this ground, so a
## rock standing inside a wildflower strip is still a rock: the feature with the
## strongest claim on the point decides what the point is.
func is_protected(x: float, z: float, ground_y: float) -> bool:
	if _features.is_empty():
		return false
	var point := Vector2(x, z)
	var best := 0.0
	var protecting := false
	for i in _features.size():
		if not _rects[i].has_point(point):
			continue
		var f := _features[i]
		if not f.blocks_mowing():
			continue
		var value := f.exclusion_at(x, z, ground_y)
		if value < ACAPropertyFeature.EXCLUDED_THRESHOLD or value < best:
			continue
		best = value
		protecting = f.is_protected_vegetation()
	return protecting


## Every protecting feature on this property. The minimap asks, so it can draw
## the zones a contract must not touch.
func protected_features() -> Array[ACAPropertyFeature]:
	var out: Array[ACAPropertyFeature] = []
	for f in _features:
		if f.is_protected_vegetation():
			out.append(f)
	return out


func build_nodes(parent: Node3D, terrain: Node3D, params: ACAPropertyParams) -> void:
	for f in _features:
		f.build_nodes(parent, terrain, params)


## `kind`: 0 mowing, 1 grass, 2 foliage.
func _exclusion(x: float, z: float, ground_y: float, kind: int) -> float:
	if _features.is_empty():
		return 0.0
	var worst := 0.0
	var point := Vector2(x, z)
	for i in _features.size():
		if not _rects[i].has_point(point):
			continue
		var f := _features[i]
		var applies := true
		match kind:
			0: applies = f.blocks_mowing()
			1: applies = f.blocks_grass()
			2: applies = f.blocks_foliage()
		if not applies:
			continue
		worst = maxf(worst, f.exclusion_at(x, z, ground_y))
		if worst >= 1.0:
			return 1.0
	return worst
