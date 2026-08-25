class_name ACAProperty
extends Node3D
## ROLE
## One generated mowing property: the ground, the landscape around it, the lawn,
## the features on it and everything growing. It is the single node the mowing
## scene owns, and the single thing anything outside asks for a lawn.
##
## It composes; it does not implement. Terrain shape lives in ACATerrain, mowing
## state in ACALawn, exclusion in ACAFeatureSet, vegetation in ACALawnGrass and
## ACAForest. This class decides the ORDER, which matters: features are chosen
## before the ground is generated so the ground can be dug, the lawn is laid out
## after the ground exists so it knows what is under water, and nothing is
## planted until the lawn knows what it is allowed to have.
##
## PUBLIC API
##   build(params)                 -> generate the whole property
##   build_for_job(job)            -> the same, from an accepted contract
##   params() / terrain() / lawn() / features()
##   mower_start_transform()       -> where the machine arrives
##   ground_height_at(x, z)        -> terrain height, for anything placing itself
##   lawn_bounds() / property_bounds()
##   boundary()                    -> the playable edge: collision and fence
##   statistics()                  -> build timings and counts
##   set_time_scale_hint(...)      -> nothing yet; reserved
##   dev_skip_grass / dev_skip_foliage   DEVELOPMENT ONLY, see below
##
## SIGNALS
##   built()   emitted once the property is complete and safe to query
##
## INVARIANTS
##   * A property is generated around this node's own origin, and must not be
##     moved afterwards: the terrain lattice and the lawn grid are both anchored
##     where they were built.
##   * `build()` is synchronous. Every query is valid the moment it returns.
##   * Nothing generated here is saved. ACAPropertyParams is the save.
##
## PERSISTENCE OWNERSHIP
##   Owns the property half of the mowing save block: the parameters. The cut
##   state belongs to ACALawn.

signal built()

## The machine arrives just off the lawn edge, facing across it, the way a
## contractor pulls up to a property rather than materialising in the middle of
## one.
const ARRIVAL_SETBACK := 7.0
const ARRIVAL_CLEARANCE := 0.35

## DEVELOPMENT ONLY. Set either of these before `build()` and that subsystem is
## not generated at all, so the large-lawn stress scene can ask what a size
## costs with the grass or the wood taken out of the answer. Nothing in the game
## writes them: both default to false, and a build with both false is byte for
## byte the build the game has always done.
##
## They are here rather than in the stress scene because the ORDER of the build
## is this class's business. A debug scene that composed ACATerrain, ACALawn and
## ACAForest itself to skip one of them would be measuring its own copy of that
## order, and would drift away from the real one the first time it changed.
var dev_skip_grass := false
var dev_skip_foliage := false

var _params: ACAPropertyParams = null
var _features: ACAFeatureSet = null
var _terrain: ACATerrain = null
var _lawn: ACALawn = null
var _grass: ACALawnGrass = null
var _forest: ACAForest = null
var _boundary: ACAPropertyBoundary = null
var _stats := {}
var _built := false


# ======================================================================= build

## Generate a property from an accepted contract. The contract's own seed and
## lawn size are the only inputs, which is the whole of the Job System
## integration.
func build_for_job(job: ACAJob) -> void:
	build(ACAPropertyParams.for_job(job))


func build(params: ACAPropertyParams) -> void:
	_params = params if params != null else ACAPropertyParams.preset(&"default")
	var t0 := Time.get_ticks_usec()

	_features = _make_features()
	var t_features := Time.get_ticks_usec()

	_terrain = _ensure(_terrain, ACATerrain.new(), "Terrain") as ACATerrain
	_terrain.build(_params, _features)
	var t_terrain := Time.get_ticks_usec()

	_lawn = _ensure(_lawn, ACALawn.new(), "Lawn") as ACALawn
	_lawn.build(_params, _terrain, _features)
	_terrain.set_lawn_mask(_lawn.cut_mask(),
		Vector2(_lawn.lawn_centre().x, _lawn.lawn_centre().z),
		_lawn.lawn_half_extent() * 2.0)
	var t_lawn := Time.get_ticks_usec()

	# Features contribute their own nodes only once the ground they sit in
	# exists, so a water surface can be placed at a height that was measured
	# rather than guessed.
	_features.build_nodes(self, _terrain, _params)
	var t_feature_nodes := Time.get_ticks_usec()

	# THE PLAYABLE EDGE, before anything is planted. The foliage placer asks the
	# boundary where the property stops, so the boundary has to exist first;
	# that ordering is the whole reason nothing is ever planted on the wrong
	# side of the fence.
	_boundary = _ensure(_boundary, ACAPropertyBoundary.new(), "Boundary") as ACAPropertyBoundary
	_boundary.build(_params, _terrain, _lawn)
	var t_boundary := Time.get_ticks_usec()

	if not dev_skip_grass:
		_grass = _ensure(_grass, ACALawnGrass.new(), "Grass") as ACALawnGrass
		_grass.build(_params, _terrain, _lawn, _features)
		# The player's graphics setting trims the grass draw distance, and keeps
		# trimming it if they change the setting mid-contract.
		_grass.bind_to_settings()
	var t_grass := Time.get_ticks_usec()

	if not dev_skip_foliage:
		_forest = _ensure(_forest, ACAForest.new(), "Foliage") as ACAForest
		_forest.build(_params, _terrain, _lawn, _features, _boundary)
	var t_forest := Time.get_ticks_usec()

	_stats = {
		"features_ms": float(t_features - t0) / 1000.0,
		"terrain_ms": float(t_terrain - t_features) / 1000.0,
		"lawn_ms": float(t_lawn - t_terrain) / 1000.0,
		"feature_nodes_ms": float(t_feature_nodes - t_lawn) / 1000.0,
		"boundary_ms": float(t_boundary - t_feature_nodes) / 1000.0,
		"grass_ms": float(t_grass - t_boundary) / 1000.0,
		"foliage_ms": float(t_forest - t_grass) / 1000.0,
		"total_ms": float(t_forest - t0) / 1000.0,
		"terrain": _terrain.statistics(),
		"boundary": _boundary.statistics(),
		"grass": _grass.statistics() if _grass != null else {},
		"foliage": _forest.statistics() if _forest != null else {},
		"lawn_cells": _lawn.cell_count() * _lawn.cell_count(),
		"lawn_mowable": _lawn.total_item_count(),
	}
	_built = true
	built.emit()


## Which features this property has. Deterministic: the parameters already say,
## because ACAPropertyParams rolled them from the seed.
##
## ORDER MATTERS HERE. The pond goes in first, the obstacles are rolled against
## the set as it already stands, and the planted beds against both - so a lawn
## rock is never dropped in the water and a flowerbed is never planted round a
## boulder. Each feature yields to the ones with the older, larger claim.
func _make_features() -> ACAFeatureSet:
	return make_features(_params, Vector2(position.x, position.z))


## STATIC, and public, so nothing has to build a second version of this. The
## validation suite and any tool that needs a lawn without a whole property
## around it compose their features THROUGH this, which is what stops a test
## quietly measuring a property the game does not generate.
static func make_features(params: ACAPropertyParams,
		property_centre: Vector2) -> ACAFeatureSet:
	var set := ACAFeatureSet.new()
	if params.pond_enabled:
		set.add(ACAPondFeature.from_params(params,
			property_centre + params.pond_offset))
	var obstacles := ACALawnObstacles.for_params(params, property_centre, set)
	if obstacles.count() > 0:
		set.add(obstacles)
	# LAST, and against everything already placed. A bed is the softest claim on
	# the ground - the machine can drive through one, so it yields to the pond
	# and to the rocks rather than the other way round.
	var beds := ACALawnBeds.for_params(params, property_centre, set)
	if beds.count() > 0:
		set.add(beds)
	# The world beyond the fence. A feature only so the forest knows not to
	# plant a tree through a house; it takes nothing from the lawn.
	var surrounds := ACAPropertySurrounds.for_params(params, property_centre)
	if surrounds.count() > 0:
		set.add(surrounds)
	return set


func _ensure(existing: Node, replacement: Node, node_name: String) -> Node:
	if existing != null and is_instance_valid(existing):
		return existing
	replacement.name = node_name
	add_child(replacement)
	return replacement


# ==================================================================== reading

func is_built() -> bool:
	return _built


func params() -> ACAPropertyParams:
	return _params


func terrain() -> ACATerrain:
	return _terrain


func lawn() -> ACALawn:
	return _lawn


func features() -> ACAFeatureSet:
	return _features


func grass() -> ACALawnGrass:
	return _grass


func foliage() -> ACAForest:
	return _forest


## The playable edge. Everything that needs to know where the property stops -
## the minimap, obstacle placement, a save-time sanity check on the machine's
## position - asks this rather than adding the margin itself.
func boundary() -> ACAPropertyBoundary:
	return _boundary


func statistics() -> Dictionary:
	return _stats.duplicate(true)


func ground_height_at(x: float, z: float) -> float:
	return _terrain.height_at(x, z) if _terrain != null else 0.0


func lawn_bounds() -> AABB:
	return _lawn.lawn_bounds() if _lawn != null else AABB()


func property_bounds() -> AABB:
	return _terrain.bounds() if _terrain != null else AABB()


## The PLAYABLE rectangle on the XZ plane, which is a good deal smaller than
## `property_bounds()`: that one is how much ground exists, this one is how much
## of it the player can drive on.
func playable_rect() -> Rect2:
	if _boundary != null:
		return _boundary.rect()
	var half: float = _params.boundary_half_extent() if _params != null else 64.0
	var c: Vector3 = _lawn.lawn_centre() if _lawn != null else global_position
	return Rect2(c.x - half, c.z - half, half * 2.0, half * 2.0)


## Where the machine starts: off the lawn's -X edge, on the ground, facing
## across the property. The height is the real terrain height, so a mower does
## not have to fall on to the world before it can be driven.
func mower_start_transform() -> Transform3D:
	var half: float = _params.lawn_half_extent() if _params != null else 48.0
	var centre: Vector3 = _lawn.lawn_centre() if _lawn != null else global_position
	var x: float = centre.x - half - ARRIVAL_SETBACK
	var z: float = centre.z
	var y: float = ground_height_at(x, z) + ARRIVAL_CLEARANCE
	# Local +Z is forward on every canonical mower, so a yaw of a quarter turn
	# points the machine along +X, across the lawn.
	var basis := Basis(Vector3.UP, PI * 0.5)
	return Transform3D(basis, Vector3(x, y, z))
