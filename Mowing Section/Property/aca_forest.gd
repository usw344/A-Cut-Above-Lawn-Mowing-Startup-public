class_name ACAForest
extends Node3D
## ROLE
## The wood around the property, and the rocks and shrubs that dress it. It
## decides where things grow and renders them; it owns no game state.
##
## ---------------------------------------------------------------------------
## FORESTINESS IS NOT A TREE COUNT
## ---------------------------------------------------------------------------
## Turning one number up and getting proportionally more evenly scattered trees
## produces tree soup, not woodland. `forestiness` here moves three things at
## once:
##
##   * the BELT - how close to the property the trees are allowed to come, and
##     how quickly they thicken behind that line;
##   * the CLUSTERS - a low-frequency field that gathers trees into groves, so
##     the wood has edges and the edges have shape;
##   * the OPENINGS - a second field that cuts clearings through the clusters,
##     so a dense wood still has depth and broken sightlines rather than a wall.
##
## The mowable rectangle is never a candidate at any setting. A contract that
## cannot be finished because a tree grew on it is not a harder contract.
##
## ---------------------------------------------------------------------------
## DISTANCE
## ---------------------------------------------------------------------------
## The player never leaves the property, so distance from the PROPERTY CENTRE
## and distance from the camera are within a few dozen units of each other. That
## turns level of detail into a placement decision made once at build time
## instead of a per-frame switch, which is why nothing here pops: a tree is
## authored into the band it belongs to and stays there.
##
##   near   real geometry, the trees around the lawn
##   mid    simplified stand-ins, the body of the wood
##   far    coarse stand-ins on the hills, read as silhouette and colour
##
## PUBLIC API
##   build(params, terrain, lawn, features)
##   statistics() / instance_count() / node_count()
##
## SIGNALS: None.
##
## ---------------------------------------------------------------------------
## EVERYTHING HERE IS SCENERY, AND SCENERY IS OUTSIDE THE FENCE
## ---------------------------------------------------------------------------
## Not one instance this class places has a physics body, and none ever did.
## That was a problem while the machine could reach them: a tree the mower
## drives straight through is worse than no tree. It is not a problem now,
## because `ACAPropertyBoundary` holds the player inside the playable rectangle
## and every tree, shrub and rock is planted OUTSIDE it.
##
## The single exception is the pond bank, which is inside the lawn rectangle on
## ground the lawn has already marked unmowable, and which the pond's own
## shoreline collision keeps the machine away from.
##
## So the property costs two physics bodies in total - the ground and the
## boundary - and its several thousand plants cost none.
##
## INVARIANTS
##   * Placement is a pure function of the property seed and position.
##   * Nothing is placed on the mowable lawn, on excluded ground, on a slope too
##     steep to stand on, or INSIDE THE PLAYABLE BOUNDARY.
##   * Nothing here is saved.
##
## PERSISTENCE OWNERSHIP: None.

# ---------------------------------------------------------------- the assets
## ---------------------------------------------------------------------------
## THREE TREE FAMILIES, ONE PACK
## ---------------------------------------------------------------------------
## The KayKit Forest Nature Pack spans nearly nine to one in mesh size - its
## smallest tree is 8 KB of buffer and its largest is 71 KB - and EVERY ONE OF
## THEM SHARES THE SAME PALETTE TEXTURE. That is what makes quality tiers
## possible here without a second art direction: Low and High are the same
## artist, the same atlas, the same faceted look, drawn at different densities
## of geometry. High is not a different game with more polygons in it.
##
##   LOW      the cheap end of the pack. Six species, mean buffer about 14 KB,
##            chosen for SILHOUETTE rather than for canopy structure, because at
##            the distance most of a wood is seen the silhouette is all there is.
##   MEDIUM   the balanced middle, and what the game shipped before this pass
##            (less the two trees below).
##   HIGH     the rich end - fuller canopies, better trunks, the pack's biggest
##            conifer - plus the understory species Medium already used, because
##            small trees under a canopy are what stops a wood being a wall.
##
## THE TWO SMOOTH PINES WERE RETIRED, for two reasons at once and either would
## have been enough. They are from a DIFFERENT PACK, with their own bark and
## needle textures and smooth shading, and beside twelve faceted KayKit trees
## sharing one atlas they read as a different game - which is exactly the
## mismatch this pass was asked to look for. And `Credits/` has no record of
## where they came from: the Foilage credits cover KayKit and Quaternius, and
## `SM_Pine_A2`/`SM_Pine_A3`/`SM_Bush_A1` are neither. An asset whose provenance
## cannot be established does not go in the build.
##
## `Tree_3_C` - the pack's largest conifer, and the one asset here chosen for
## exactly this job - takes over the "occasional landmark" role at High.
##
## `weight` is how often a species is drawn relative to the others.

const TREE_SOURCES_LOW := [
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_2_A_Color1.gltf",
		"height": 19.0, "kind": "broadleaf", "weight": 4},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_2_B_Color1.gltf",
		"height": 18.0, "kind": "broadleaf", "weight": 3},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_1_A_Color1.gltf",
		"height": 23.0, "kind": "broadleaf", "weight": 3},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_2_C_Color1.gltf",
		"height": 17.0, "kind": "broadleaf", "weight": 3, "understory": true},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_4_A_Color1.gltf",
		"height": 15.0, "kind": "broadleaf", "weight": 3, "understory": true},
	# ONE CONIFER, kept at a low weight rather than dropped. The pack has no
	# cheap conifer at all, and a wood with no conical crown in it loses the
	# thing that reads at distance - which is the one thing Low cannot afford
	# to lose.
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_3_B_Color1.gltf",
		"height": 28.0, "kind": "conifer", "weight": 2},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_Bare_1_B_Color1.gltf",
		"height": 18.0, "kind": "broadleaf", "weight": 1},
]

const TREE_SOURCES_MEDIUM := [
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_1_A_Color1.gltf",
		"height": 23.0, "kind": "broadleaf", "weight": 3},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_1_B_Color1.gltf",
		"height": 21.0, "kind": "broadleaf", "weight": 3},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_2_A_Color1.gltf",
		"height": 19.0, "kind": "broadleaf", "weight": 3},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_2_B_Color1.gltf",
		"height": 18.0, "kind": "broadleaf", "weight": 2},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_2_C_Color1.gltf",
		"height": 17.0, "kind": "broadleaf", "weight": 3, "understory": true},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_2_D_Color1.gltf",
		"height": 20.0, "kind": "broadleaf", "weight": 2},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_3_A_Color1.gltf",
		"height": 25.0, "kind": "conifer", "weight": 3},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_3_B_Color1.gltf",
		"height": 28.0, "kind": "conifer", "weight": 2},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_4_A_Color1.gltf",
		"height": 15.0, "kind": "broadleaf", "weight": 2, "understory": true},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_4_C_Color1.gltf",
		"height": 16.0, "kind": "broadleaf", "weight": 2, "understory": true},
	# One standing dead tree in about thirty. A wood with nothing but healthy
	# canopies reads as a texture; a single bare crown against the sky is what
	# makes the same treeline read as a place.
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_Bare_2_A_Color1.gltf",
		"height": 22.0, "kind": "broadleaf", "weight": 1},
]

const TREE_SOURCES_HIGH := [
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_1_B_Color1.gltf",
		"height": 21.0, "kind": "broadleaf", "weight": 2},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_1_C_Color1.gltf",
		"height": 25.0, "kind": "broadleaf", "weight": 3},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_2_D_Color1.gltf",
		"height": 20.0, "kind": "broadleaf", "weight": 3},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_2_E_Color1.gltf",
		"height": 22.0, "kind": "broadleaf", "weight": 3},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_3_A_Color1.gltf",
		"height": 25.0, "kind": "conifer", "weight": 2},
	# THE LANDMARK. The pack's largest conifer, and what replaced the smooth
	# pine that used to play this part from another pack entirely.
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_3_C_Color1.gltf",
		"height": 30.0, "kind": "conifer", "weight": 2},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_4_C_Color1.gltf",
		"height": 16.0, "kind": "broadleaf", "weight": 2, "understory": true},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_4_B_Color1.gltf",
		"height": 16.0, "kind": "broadleaf", "weight": 2, "understory": true},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_2_C_Color1.gltf",
		"height": 17.0, "kind": "broadleaf", "weight": 2, "understory": true},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_Bare_1_C_Color1.gltf",
		"height": 24.0, "kind": "broadleaf", "weight": 1},
	{"path": "res://Assets/Foilage/Low Poly/Trees/Tree_Bare_2_C_Color1.gltf",
		"height": 21.0, "kind": "broadleaf", "weight": 1},
]

## Canopies are all one green if nothing varies them, and one green over a
## hundred trees is the single loudest signal that a wood was generated. Each
## tree draws a tint between these two, mostly from a slow field so neighbours
## agree, partly from its own position so neighbours are not identical.
const CANOPY_COOL := Color(0.82, 0.97, 0.94)
const CANOPY_WARM := Color(1.12, 1.02, 0.74)

## SHRUBS, on the same principle and with a far wider spread: the pack's
## smallest bush is a KILOBYTE of buffer and its largest is twenty-eight. Low
## uses the one-kilobyte end, which is why shrub density can stay high there
## without costing anything.
##
## `SM_Bush_A1` was retired with the two pines, for the same two reasons.
const SHRUB_SOURCES_LOW := [
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_2_A_Color1.gltf", "height": 1.4},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_4_A_Color1.gltf", "height": 2.0},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_4_B_Color1.gltf", "height": 1.6},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_1_A_Color1.gltf", "height": 3.0},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_2_C_Color1.gltf", "height": 2.2},
]

const SHRUB_SOURCES_MEDIUM := [
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_1_A_Color1.gltf", "height": 3.0},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_1_C_Color1.gltf", "height": 2.6},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_2_C_Color1.gltf", "height": 2.2},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_3_A_Color1.gltf", "height": 1.7},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_4_A_Color1.gltf", "height": 2.0},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_4_D_Color1.gltf", "height": 1.5},
]

const SHRUB_SOURCES_HIGH := [
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_1_C_Color1.gltf", "height": 2.6},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_1_E_Color1.gltf", "height": 3.2},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_1_F_Color1.gltf", "height": 3.0},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_2_E_Color1.gltf", "height": 2.8},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_3_A_Color1.gltf", "height": 1.7},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_3_C_Color1.gltf", "height": 2.4},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_4_D_Color1.gltf", "height": 1.5},
]

## Tall grass clumps. They are not lawn and they are not shrubs: they are what
## a bank, a fence line and the foot of a wood actually look like, and they are
## the cheapest way to stop a hard line between two surfaces.
const REED_SOURCES := [
	{"path": "res://Assets/Foilage/Low Poly/Grass/Grass_1_A_Color1.gltf", "height": 2.2},
	{"path": "res://Assets/Foilage/Low Poly/Grass/Grass_1_D_Color1.gltf", "height": 2.6},
	{"path": "res://Assets/Foilage/Low Poly/Grass/Grass_2_A_Color1.gltf", "height": 1.9},
	{"path": "res://Assets/Foilage/Low Poly/Grass/Grass_2_C_Color1.gltf", "height": 2.4},
]

## Heights are WORLD units in a world about four times life size, so a boulder
## that reads at the mower's scale is a few units tall. The pack's stone is a
## cool grey; at this size against saturated grass it picks up the sky and
## reads blue, so it is warmed through ROCK_TINT below.
## SCENERY ROCKS ONLY. The rocks the machine can HIT are placed by
## `ACALawnObstacles`, they have collision, and they are deliberately NOT tiered
## - see the note on collision in `_sources_for_quality()`.
##
## Heights are WORLD units in a world about four times life size, so a boulder
## that reads at the mower's scale is a few units tall.
const ROCK_SOURCES_LOW := [
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_2_A_Color1.gltf", "height": 1.4},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_2_B_Color1.gltf", "height": 2.2},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_1_C_Color1.gltf", "height": 2.4},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_2_D_Color1.gltf", "height": 2.1},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_3_C_Color1.gltf", "height": 2.6},
]

const ROCK_SOURCES_MEDIUM := [
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_1_C_Color1.gltf", "height": 2.4},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_1_F_Color1.gltf", "height": 1.5},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_1_J_Color1.gltf", "height": 1.8},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_2_B_Color1.gltf", "height": 2.2},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_2_D_Color1.gltf", "height": 2.1},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_3_C_Color1.gltf", "height": 2.6},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_3_G_Color1.gltf", "height": 2.9},
]

const ROCK_SOURCES_HIGH := [
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_1_F_Color1.gltf", "height": 1.5},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_1_J_Color1.gltf", "height": 1.8},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_1_K_Color1.gltf", "height": 2.8},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_2_G_Color1.gltf", "height": 2.5},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_3_G_Color1.gltf", "height": 2.9},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_3_Q_Color1.gltf", "height": 3.1},
]

## Multiplies the pack's own albedo, so the texture is kept and only its cast
## changes. The pack's stone is a cool grey; at this size against saturated grass
## it picks up the sky and reads blue, so it is warmed here.
const ROCK_TINT := Color(1.05, 0.90, 0.70)

## The bush textures are considerably lighter than this game's greens, and a
## thicket of them reads as a blown-out patch beside the lawn. Same treatment.
const SHRUB_TINT := Color(0.74, 0.86, 0.62)

## Reeds sit against water and against mown grass, so they are pulled the other
## way from the shrubs: a little yellower and a little lighter than the lawn, so
## the bank reads as a different plant rather than as taller turf.
const REED_TINT := Color(0.90, 0.94, 0.58)

# ------------------------------------------------------------------ the bands
## Where real tree geometry stops and stand-ins begin, measured from the
## property centre.
const NEAR_RADIUS := 190.0
const MID_RADIUS := 560.0
const FAR_RADIUS := 1500.0

## Candidate lattice spacing per band, in world units.
const NEAR_SPACING := 6.4
const MID_SPACING := 16.0
const FAR_SPACING := 24.0

const SHRUB_SPACING := 5.2
const ROCK_SPACING := 5.4
const REED_SPACING := 2.6
const DETAIL_RADIUS := 150.0
## Reeds are a close-range accent. Nothing past this is close enough for a
## clump of grass to be worth a draw.
const REED_RADIUS := 118.0

## How deep the wood thickens behind its front edge.
const BELT_DEPTH := 30.0
## How far from the property a real tree still casts a shadow. Past this its
## shadow falls on ground the player never looks at closely.
const TREE_SHADOW_RADIUS := 115.0

## Steeper than this and nothing takes root.
const MAX_TREE_SLOPE := 0.55
const MAX_PROP_SLOPE := 0.72

## How much clear ground is left between the fence and the first thing growing
## behind it, in world units. Without it the wood grows tight against the rails
## and the fence stops reading as a boundary and starts reading as a hedge.
const BOUNDARY_CLEARANCE := 2.5

var _params: ACAPropertyParams = null
var _terrain: ACATerrain = null
var _lawn: ACALawn = null
var _features: ACAFeatureSet = null
## The playable edge. Everything is planted outside it. Null only when a caller
## builds the wood without a property around it, in which case the lawn
## rectangle is fallen back on and the old behaviour is kept.
var _boundary: ACAPropertyBoundary = null

var _cluster_noise: FastNoiseLite = null
## Weighted species lookup, rebuilt each time the trees are placed.
var _tree_picks := PackedInt32Array()
## The subset of that lookup which is small enough to stand under a canopy.
var _understory_picks := PackedInt32Array()
var _opening_noise: FastNoiseLite = null
## How TALL the wood is here, as a slow field. Scaling every tree by its own
## random number gives an even canopy made of uneven trees; scaling a whole
## stand together gives a canopy line that rises and falls, which is what reads
## as depth from the lawn.
var _stand_noise: FastNoiseLite = null
## The same idea applied to colour.
var _tint_noise: FastNoiseLite = null

var _stats := {}
var _instances := 0
var _nodes := 0

## ---------------------------------------------------------------------------
## GRAPHICS QUALITY
## ---------------------------------------------------------------------------
## `GameSettings` is the authority and this is a READER of it, exactly as
## `preset_manager.gd` is. There is no second quality setting, no second menu
## and nothing here is saved: the level is resolved once per property build and
## a property rebuilds whenever a contract starts.
##
## COLLISION IS NOT TIERED, AND CANNOT BE. Nothing this class places has a
## physics body at all - the whole wood costs zero colliders, which is stated
## as an invariant at the top of this file. The rocks the machine can hit are
## `ACALawnObstacles`, which is a different class, is inside the fence, and
## does not read this. So a player cannot hit something on High that is not
## there on Low, because the two settings do not reach the same objects.
##
## What quality DOES change here: which family of meshes is used, and how dense
## the decorative planting is. Both are presentation.
##
## `ultra` maps to High. This project's Settings screen offers four labels and
## has three environment profiles behind them; matching that is better than
## inventing a fourth vegetation family nobody asked for.
var _quality: StringName = &"medium"

## Decorative density per level, as a multiplier on the candidate lattice.
## TREES ARE NOT IN HERE. Thinning the wood is how a lower setting stops
## looking like the same place, and the wood is the place - so Low pays for
## itself with cheaper MESHES and a shorter shadow radius, and keeps its trees.
const DENSITY_FOR_QUALITY := {
	&"low": 0.62, &"medium": 1.0, &"high": 1.0,
}

## How much of the MID AND FAR wood a level plants. The near band - the trees
## beside the lawn, the ones the player is actually looking at - is never
## thinned, at any level. The bands behind it are read as silhouette and colour
## rather than as individual trees, and they hold nine tenths of the instances,
## so this is where a lower setting can take real weight out without the place
## looking different.
const DISTANT_TREES_FOR_QUALITY := {
	&"low": 0.70, &"medium": 1.0, &"high": 1.0,
}

## Shadow radius per level. The shadow map is the expensive part of a near-field
## tree, and halving the radius that has to be covered is the cheapest real
## saving available to a lower setting.
const SHADOW_RADIUS_FOR_QUALITY := {
	&"low": 0.45, &"medium": 1.0, &"high": 1.0,
}


## Resolved once per build. Falls back to `medium` when GameSettings is absent,
## which is how the tests and the property tooling build a wood.
func _resolve_quality() -> void:
	_quality = &"medium"
	var settings := get_node_or_null(^"/root/GameSettings")
	if settings == null:
		return
	var level := String(settings.call(&"graphics_quality")).to_lower()
	match level:
		"low":
			_quality = &"low"
		"high", "ultra":
			_quality = &"high"
		_:
			_quality = &"medium"


func _tree_sources() -> Array:
	match _quality:
		&"low":
			return TREE_SOURCES_LOW
		&"high":
			return TREE_SOURCES_HIGH
	return TREE_SOURCES_MEDIUM


func _shrub_sources() -> Array:
	match _quality:
		&"low":
			return SHRUB_SOURCES_LOW
		&"high":
			return SHRUB_SOURCES_HIGH
	return SHRUB_SOURCES_MEDIUM


func _rock_sources() -> Array:
	match _quality:
		&"low":
			return ROCK_SOURCES_LOW
		&"high":
			return ROCK_SOURCES_HIGH
	return ROCK_SOURCES_MEDIUM


## Candidate spacing widened at Low, so the same placement rules produce fewer
## props without any of them moving somewhere different.
func _spacing(base: float) -> float:
	var density: float = float(DENSITY_FOR_QUALITY.get(_quality, 1.0))
	return base / maxf(density, 0.05)


func graphics_quality() -> StringName:
	return _quality


# ======================================================================= build

func build(params: ACAPropertyParams, terrain: ACATerrain, lawn: ACALawn,
		features: ACAFeatureSet,
		boundary: ACAPropertyBoundary = null) -> void:
	_params = params
	_terrain = terrain
	_lawn = lawn
	_features = features if features != null else ACAFeatureSet.new()
	_boundary = boundary
	var t0 := Time.get_ticks_usec()
	_clear()
	_resolve_quality()

	_cluster_noise = _noise(params.seed + 41, 1.0 / 95.0, 2)
	_opening_noise = _noise(params.seed + 73, 1.0 / 58.0, 2)
	_stand_noise = _noise(params.seed + 137, 1.0 / 118.0, 2)
	_tint_noise = _noise(params.seed + 211, 1.0 / 74.0, 2)

	var trees := _build_trees()
	var t_trees := Time.get_ticks_usec()
	var shrubs := _build_shrubs()
	var reeds := _build_reeds()
	var rocks := _build_rocks()

	_instances = trees + shrubs + reeds + rocks
	_stats = {
		"build_ms": float(Time.get_ticks_usec() - t0) / 1000.0,
		"tree_ms": float(t_trees - t0) / 1000.0,
		"trees": trees,
		"shrubs": shrubs,
		"reeds": reeds,
		"rocks": rocks,
		"instances": _instances,
		"nodes": _nodes,
		"quality": String(_quality),
	}


func statistics() -> Dictionary:
	return _stats.duplicate()


func instance_count() -> int:
	return _instances


func node_count() -> int:
	return _nodes


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_nodes = 0
	_instances = 0


# ======================================================================= trees

func _build_trees() -> int:
	var sources: Array[Dictionary] = []
	# One entry per unit of weight, so a species is picked by drawing uniformly
	# from this list. Cheaper than a running total and just as controllable.
	_tree_picks = PackedInt32Array()
	_understory_picks = PackedInt32Array()
	for entry in _tree_sources():
		var mesh := _load_mesh(String(entry["path"]))
		if mesh == null:
			continue
		var index := sources.size()
		sources.append({
			"mesh": mesh,
			"scale": _normalising_scale(mesh, float(entry["height"])),
			"kind": String(entry["kind"]),
		})
		for w in maxi(int(entry.get("weight", 1)), 1):
			_tree_picks.append(index)
		if bool(entry.get("understory", false)):
			_understory_picks.append(index)
	if sources.is_empty():
		push_warning("[FOREST] no tree meshes loaded")
		return 0

	# Near band: the real trees, split into tiles so the frustum can reject most
	# of them in one test.
	var near_tiles: Dictionary = {}
	var mid_batches: Dictionary = {}
	var far_batches: Dictionary = {}

	var placed := 0
	placed += _scatter_trees(sources, 0.0, NEAR_RADIUS, NEAR_SPACING, 0, near_tiles, 1.0)
	placed += _scatter_trees(sources, NEAR_RADIUS, MID_RADIUS, MID_SPACING, 1,
		mid_batches, 1.45 * DISTANT_TREES_FOR_QUALITY.get(_quality, 1.0))
	# The far band is READ AS TEXTURE, not as individual trees. It needs to be
	# dense enough to close the hillsides, or a wooded landscape ends in a
	# scattering of specks along the ridge. Raised again once the band stopped
	# floating: trees that now sit correctly on a hillside also disappear behind
	# it, and a mass has to be thick enough to survive that.
	placed += _scatter_trees(sources, MID_RADIUS, FAR_RADIUS, FAR_SPACING, 2,
		far_batches, 2.3 * DISTANT_TREES_FOR_QUALITY.get(_quality, 1.0))

	for key in near_tiles:
		var batch: Dictionary = near_tiles[key]
		_commit_batch("Tree", batch["mesh"], batch["transforms"],
			_vertex_tinted(batch["mesh"]), batch["colours"])
	for key in mid_batches:
		var batch: Dictionary = mid_batches[key]
		_commit_batch("Tree Mid", batch["mesh"], batch["transforms"],
			ACATreeProxy.material(), batch["colours"])
	for key in far_batches:
		var batch: Dictionary = far_batches[key]
		_commit_batch("Tree Far", batch["mesh"], batch["transforms"],
			ACATreeProxy.material(), batch["colours"])
	placed += _build_understory(sources)
	return placed


## Walk a jittered lattice over one annulus and accept candidates against the
## density field. `detail` picks real geometry, a medium stand-in or a coarse
## one, and also decides how batches are grouped.
func _scatter_trees(sources: Array[Dictionary], inner: float, outer: float,
		spacing: float, detail: int, batches: Dictionary,
		density_scale: float = 1.0) -> int:
	var steps: int = int(ceil(outer * 2.0 / spacing))
	var origin := -outer
	var placed := 0
	var lawn_centre := _lawn.lawn_centre()

	for gz in steps:
		for gx in steps:
			var jitter_x := _hash2(float(gx) * 1.37 + inner, float(gz) * 2.11)
			var jitter_z := _hash2(float(gz) * 3.19 + inner, float(gx) * 1.73)
			# Nearly the whole cell. A lattice read through a narrow jitter is
			# still a lattice, and evenly spaced trees are the other half of
			# what makes a generated wood look generated.
			var x: float = origin + (float(gx) + 0.04 + jitter_x * 0.92) * spacing
			var z: float = origin + (float(gz) + 0.04 + jitter_z * 0.92) * spacing
			var radius := sqrt(x * x + z * z)
			if radius < inner or radius >= outer:
				continue

			var density := _tree_density(x, z, lawn_centre) * density_scale
			if density <= 0.0:
				continue
			if _hash2(x * 0.53, z * 0.61) > density:
				continue

			# The height of the surface that is DRAWN, not of the height
			# function. Past the lattice the two disagree by more than a tree,
			# and taking the wrong one is what left the far band floating.
			var ground := _terrain.surface_height_at(x, z)
			if _terrain.slope_at(x, z) > MAX_TREE_SLOPE:
				continue
			if _features.foliage_exclusion_at(x, z, ground) >= 0.5:
				continue

			var slot: int = clampi(int(_hash2(x * 7.1, z * 5.9) * float(_tree_picks.size())),
				0, _tree_picks.size() - 1)
			var pick: int = _tree_picks[slot]
			var source: Dictionary = sources[pick]
			var kind := String(source["kind"])

			# Trees further from the lawn stand taller, which layers the wood
			# instead of making it a hedge of identical trunks.
			var out_distance := _rect_distance(x, z, lawn_centre)
			var height_gain: float = 1.0 + clampf(out_distance / 260.0, 0.0, 1.0) * 0.28
			# Stand-ins read as a mass rather than as trees, and a mass has to be
			# a little larger than the sum of its parts to close a hillside.
			if detail == 2:
				height_gain *= 1.45
			# The STAND decides most of the height and the tree decides the rest.
			# Reversing those two - a wide random range per tree over a flat
			# field - produces a canopy that is uneven everywhere and therefore
			# level overall, which is exactly the ceiling this is trying to break.
			var stand: float = _stand_noise.get_noise_2d(x, z) * 0.5 + 0.5
			var maturity: float = lerpf(0.70, 1.36, smoothstep(0.12, 0.88, stand))
			var variation: float = 0.84 + _hash2(x * 2.3, z * 4.7) * 0.34
			var scale: float = float(source["scale"]) * variation * maturity * height_gain
			var yaw: float = _hash2(x * 8.9, z * 6.3) * TAU
			# A slight tilt away from vertical stops a stand of trees reading as
			# a row of posts.
			var tilt: float = (_hash2(x * 3.7, z * 9.1) - 0.5) * 0.11
			var basis := Basis(Vector3.UP, yaw)
			basis = basis.rotated(Vector3(cos(yaw), 0.0, sin(yaw)), tilt)
			basis = basis.scaled(Vector3(scale, scale, scale))
			var transform := Transform3D(basis, Vector3(x, ground - 0.15, z))

			var mesh: Mesh
			var key: String
			if detail == 0:
				mesh = source["mesh"]
				key = "%d|%d|%d" % [pick, int(x / 120.0), int(z / 120.0)]
			else:
				mesh = ACATreeProxy.conifer(detail) if kind == "conifer" \
					else ACATreeProxy.broadleaf(detail)
				key = "%s|%d|%d" % [kind, detail, _sector(x, z)]

			if not batches.has(key):
				batches[key] = {
					"mesh": mesh,
					"transforms": PackedFloat32Array(),
					"colours": PackedFloat32Array(),
				}
			_append(batches[key]["transforms"], transform)
			_append_colour(batches[key]["colours"], _canopy_tint(x, z))
			placed += 1
	return placed


## 0 where nothing may grow, 1 where the wood is at its thickest.
func _tree_density(x: float, z: float, lawn_centre: Vector3) -> float:
	var out_distance := _rect_distance(x, z, lawn_centre)
	# The lawn and its clearing are off limits at every setting. A denser wood
	# comes closer, but never on to the contract - and never inside the fence,
	# whatever the seed drew for `lawn_openness`, because a tree the player can
	# reach is a tree the player expects to hit.
	var openness: float = maxf(
		_params.lawn_openness * lerpf(1.35, 0.75, _params.forestiness),
		_params.boundary_margin() + BOUNDARY_CLEARANCE + 1.5)
	if out_distance <= openness:
		return 0.0

	# The FRONT of the wood wanders. Without this the treeline traces the lawn
	# rectangle at a constant offset, which reads as a hedge planted round a
	# field rather than as a property cut out of a wood.
	var wander: float = _opening_noise.get_noise_2d(x * 0.42, z * 0.42) * 17.0
	# A second, shorter wave on the same edge. The long one decides where the
	# wood swings in and out; this one decides whether that swing arrives as a
	# smooth curve or as a broken margin with spurs and bays in it.
	wander += _cluster_noise.get_noise_2d(x * 2.1, z * 2.1) * 6.5
	out_distance = maxf(out_distance + wander, 0.0)
	if out_distance <= openness * 0.55:
		return 0.0

	var belt: float = smoothstep(openness, openness + BELT_DEPTH, out_distance)
	var base: float = 0.10 + 0.85 * _params.forestiness

	var cluster: float = _cluster_noise.get_noise_2d(x, z) * 0.5 + 0.5
	# At high cluster strength the wood is groves and gaps; at low it is even.
	var clustered: float = lerpf(0.72, smoothstep(0.30, 0.72, cluster),
		_params.tree_cluster_strength)

	# Clearings. Kept even in a dense wood so sightlines break rather than close.
	var opening: float = _opening_noise.get_noise_2d(x, z) * 0.5 + 0.5
	var clearing: float = smoothstep(0.16, 0.46, opening)
	clearing = lerpf(clearing, 1.0, _params.forestiness * 0.35)

	return clampf(belt * base * clustered * clearing, 0.0, 1.0)


## The layer between the shrubs and the canopy.
##
## A wood drawn as one row of full-grown trees behind one row of bushes has two
## depths and reads as a backdrop. Young trees along the front of the belt give
## it a third, and they are the layer the eye actually uses to judge how far
## away the wood is: they overlap the trunks behind them, so the trunks stop
## reading as a fence.
##
## They are placed on the SAME density field as the wood, so they never appear
## in a clearing the wood was told to leave open, and never on the contract.
const UNDERSTORY_SPACING := 8.2
const UNDERSTORY_RADIUS := 165.0


func _build_understory(sources: Array[Dictionary]) -> int:
	if _understory_picks.is_empty() or sources.is_empty():
		return 0
	var batches: Dictionary = {}
	var placed := 0
	var lawn_centre := _lawn.lawn_centre()
	var steps: int = int(ceil(UNDERSTORY_RADIUS * 2.0 / UNDERSTORY_SPACING))
	var origin := -UNDERSTORY_RADIUS

	for gz in steps:
		for gx in steps:
			var x: float = origin + (float(gx) + 0.05
				+ _hash2(float(gx) * 6.7 + 31.0, float(gz) * 2.3) * 0.9) * UNDERSTORY_SPACING
			var z: float = origin + (float(gz) + 0.05
				+ _hash2(float(gz) * 5.1 + 17.0, float(gx) * 3.9) * 0.9) * UNDERSTORY_SPACING
			if not _terrain.contains(x, z):
				continue
			if _tree_density(x, z, lawn_centre) <= 0.0:
				continue

			# Densest along the first twenty units of the wood and gone by the
			# time the canopy has closed over it, which is where a young tree
			# would actually find the light.
			var out_distance := _rect_distance(x, z, lawn_centre)
			var front: float = smoothstep(0.0, 9.0, out_distance) * (1.0 - smoothstep(22.0, 74.0, out_distance))
			if _hash2(x * 4.13, z * 6.29) > front * 0.44:
				continue

			var ground := _terrain.height_at(x, z)
			if _terrain.slope_at(x, z) > MAX_TREE_SLOPE:
				continue
			if _features.foliage_exclusion_at(x, z, ground) >= 0.5:
				continue

			var slot: int = clampi(
				int(_hash2(x * 3.3, z * 9.7) * float(_understory_picks.size())),
				0, _understory_picks.size() - 1)
			var source: Dictionary = sources[_understory_picks[slot]]
			var scale: float = float(source["scale"]) * lerpf(0.24, 0.80, _hash2(x * 7.9, z * 1.3))
			var yaw: float = _hash2(x * 2.7, z * 11.9) * TAU
			var tilt: float = (_hash2(x * 8.1, z * 4.3) - 0.5) * 0.16
			var basis := Basis(Vector3.UP, yaw)
			basis = basis.rotated(Vector3(cos(yaw), 0.0, sin(yaw)), tilt)
			basis = basis.scaled(Vector3(scale, scale, scale))

			var key := "Sapling|%d" % _understory_picks[slot]
			if not batches.has(key):
				batches[key] = {
					"mesh": source["mesh"],
					"transforms": PackedFloat32Array(),
					"colours": PackedFloat32Array(),
				}
			_append(batches[key]["transforms"],
				Transform3D(basis, Vector3(x, ground - 0.10, z)))
			# Young growth is lighter than the canopy over it. Half a step is
			# enough; a full one turns the front of the wood into a highlight.
			_append_colour(batches[key]["colours"],
				_canopy_tint(x, z) * Color(1.06, 1.10, 1.00, 1.0))
			placed += 1

	for key in batches:
		var batch: Dictionary = batches[key]
		_commit_batch("Sapling", batch["mesh"], batch["transforms"],
			_vertex_tinted(batch["mesh"]), batch["colours"])
	return placed


## The tint one tree gets. Mostly the slow field, so a stand agrees with itself;
## partly the tree's own position, so a stand is not a single flat colour.
func _canopy_tint(x: float, z: float) -> Color:
	var field: float = _tint_noise.get_noise_2d(x, z) * 0.5 + 0.5
	var own: float = _hash2(x * 4.91, z * 7.37)
	var t: float = clampf(field * 0.72 + own * 0.28, 0.0, 1.0)
	var tint := CANOPY_COOL.lerp(CANOPY_WARM, t)
	# A little light and shade on top, so two trees of the same tint still read
	# as two trees.
	# Weighted a little under one on average. The pack's canopies are lighter
	# than this game's greens, and a wood that out-values the lawn in front of
	# it pulls the eye off the thing the player is actually doing.
	var value: float = lerpf(0.79, 1.03, _hash2(z * 2.13, x * 5.77))
	return Color(tint.r * value, tint.g * value, tint.b * value, 1.0)


# =============================================================== shrubs, rocks

## Shrubs live where the wood meets the lawn and along the pond bank: the places
## a bare transition would otherwise show.
func _build_shrubs() -> int:
	var sources := _prepare(_shrub_sources())
	if sources.is_empty():
		return 0
	var batches: Dictionary = {}
	var placed := 0
	var lawn_centre := _lawn.lawn_centre()
	var spacing := _spacing(SHRUB_SPACING)
	var steps: int = int(ceil(DETAIL_RADIUS * 2.0 / spacing))
	var origin := -DETAIL_RADIUS

	for gz in steps:
		for gx in steps:
			var x: float = origin + (float(gx) + 0.2
				+ _hash2(float(gx) * 5.3, float(gz) * 1.9) * 0.6) * spacing
			var z: float = origin + (float(gz) + 0.2
				+ _hash2(float(gz) * 4.1, float(gx) * 2.7) * 0.6) * spacing
			if not _terrain.contains(x, z):
				continue
			var out_distance := _rect_distance(x, z, lawn_centre)
			var ground := _terrain.height_at(x, z)
			if not _plantable(x, z, ground, 1.5):
				continue

			if _features.foliage_exclusion_at(x, z, ground) >= 1.0:
				continue
			if _terrain.slope_at(x, z) > MAX_PROP_SLOPE:
				continue

			# Densest in the band just outside the lawn, thinning as the trees
			# take over -- but gathered into thickets rather than laid as a
			# hedge. An even band of shrubs all the way round a property reads
			# as a garden border, which is exactly what a wooded lot does not
			# have.
			var edge_weight: float = smoothstep(2.5, 12.0, out_distance) \
				* (1.0 - smoothstep(20.0, 64.0, out_distance) * 0.8)
			var thicket: float = _cluster_noise.get_noise_2d(x * 2.4, z * 2.4) * 0.5 + 0.5
			thicket = smoothstep(0.34, 0.74, thicket)
			var bank_weight := _shore_weight(x, z)
			var chance: float = _params.shrub_density * maxf(
				edge_weight * thicket * 0.6, bank_weight * 0.7)
			if _hash2(x * 1.31, z * 1.79) > chance:
				continue

			# Bank planting is kept SHORT. A shrub at its full size on the water's
			# edge hides the one thing on the property worth standing still to
			# look at, and a player who drives down to the pond ends up inside it.
			placed += _place(sources, batches, x, z, ground, 0.6,
				lerpf(1.65, 0.95, bank_weight), "Shrub")
	_commit_all(batches, "Shrub")
	return placed


## Tall grass at the water's edge and at the foot of the wood.
##
## THIS IS THE POND'S BEST FEATURE and it is not the water. What made the pond
## read as a hole with water in it was that mown turf ran straight into the
## surface with nothing growing between the two. A metre of reeds is what a real
## bank has, and it is also what hides the seam where the water plane meets the
## ground.
##
## Placement is by HEIGHT ABOVE THE WATER, taken from the feature's own
## exclusion curve: a reed may stand anywhere the pond has not already claimed,
## which is the damp band and no further. Nothing is ever placed under water,
## and nothing is placed on the contract.
func _build_reeds() -> int:
	var sources := _prepare(REED_SOURCES)
	if sources.is_empty():
		return 0
	var batches: Dictionary = {}
	var placed := 0
	var lawn_centre := _lawn.lawn_centre()
	var spacing := _spacing(REED_SPACING)
	var steps: int = int(ceil(REED_RADIUS * 2.0 / spacing))
	var origin := -REED_RADIUS

	for gz in steps:
		for gx in steps:
			var x: float = origin + (float(gx) + 0.05
				+ _hash2(float(gx) * 3.7 + 8.0, float(gz) * 9.1) * 0.9) * spacing
			var z: float = origin + (float(gz) + 0.05
				+ _hash2(float(gz) * 6.3 + 4.0, float(gx) * 5.5) * 0.9) * spacing
			if not _terrain.contains(x, z):
				continue
			var out_distance := _rect_distance(x, z, lawn_centre)
			var ground := _terrain.height_at(x, z)
			if not _plantable(x, z, ground, 1.0):
				continue

			var bank := _shore_weight(x, z)
			# Away from a bank, the ordinary rule: nothing where a feature has
			# taken the ground outright. ON a bank, `_shore_weight` has already
			# said how deep the water is, and a reed standing ankle deep in it
			# is the point.
			if bank <= 0.0 and _features.foliage_exclusion_at(x, z, ground) >= 1.0:
				continue
			if _terrain.slope_at(x, z) > MAX_PROP_SLOPE:
				continue

			# Along the wood, thinly, and gathered rather than laid as a fringe.
			var thicket: float = _cluster_noise.get_noise_2d(x * 2.9, z * 2.9) * 0.5 + 0.5
			var edge: float = smoothstep(2.0, 9.0, out_distance) \
				* (1.0 - smoothstep(14.0, 44.0, out_distance))
			# A FRINGE, NOT A CROP. The first pass at this filled the pond in:
			# the bank weight was near one all the way round, so every candidate
			# on a two unit lattice took, and a pond the player is meant to look
			# at came back as a wall of leaves with a little water behind it.
			var chance: float = maxf(
				bank * 0.30,
				edge * smoothstep(0.40, 0.80, thicket) * 0.30 * _params.shrub_density)
			if _hash2(x * 5.17, z * 2.83) > chance:
				continue

			placed += _place(sources, batches, x, z, ground - 0.12, 0.34, 0.86, "Reed")
	_commit_all(batches, "Reed")
	return placed


## Rocks are accents. They gather on slopes, at the pond bank and inside tree
## clusters, and they stay off the lawn, where they would only make the mowing
## harder to read.
func _build_rocks() -> int:
	var sources := _prepare(_rock_sources())
	if sources.is_empty():
		return 0
	var batches: Dictionary = {}
	var placed := 0
	var lawn_centre := _lawn.lawn_centre()
	var spacing := _spacing(ROCK_SPACING)
	var steps: int = int(ceil(DETAIL_RADIUS * 2.0 / spacing))
	var origin := -DETAIL_RADIUS

	for gz in steps:
		for gx in steps:
			var x: float = origin + (float(gx) + 0.2
				+ _hash2(float(gx) * 2.9, float(gz) * 6.1) * 0.6) * spacing
			var z: float = origin + (float(gz) + 0.2
				+ _hash2(float(gz) * 3.3, float(gx) * 7.7) * 0.6) * spacing
			if not _terrain.contains(x, z):
				continue
			var ground := _terrain.height_at(x, z)
			if not _plantable(x, z, ground, 2.5):
				continue
			if _features.foliage_exclusion_at(x, z, ground) >= 1.0:
				continue

			# Rocks go where ground CHANGES: a break of slope, the pond bank, or
			# the floor of a thicket. A small even scatter underneath keeps the
			# open ground from being empty without making it a quarry.
			var slope_weight: float = smoothstep(0.07, 0.30, _terrain.slope_at(x, z))
			var bank_weight := _shore_weight(x, z)
			var cluster: float = _cluster_noise.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5
			var chance: float = _params.rock_density * (
				0.05
				+ slope_weight * 0.55
				# The bank is the one place on a property where a stone reads as
				# deliberate rather than as debris, so it is weighted well above
				# everything else and thinned much less.
				+ bank_weight * 1.90
				+ smoothstep(0.46, 0.78, cluster) * 0.35)
			if _hash2(x * 2.71, z * 3.11) > chance * 0.35:
				continue

			# A stone at the water is HALF BURIED and no larger than one dropped
			# in a thicket. Two earlier attempts made bank stones bigger, on the
			# reasoning that a stone at the water is a deliberate accent; both
			# came back as pale blocks sitting on the surface, because this pack
			# has flat-topped stones and the bank is the one place they are seen
			# side-on against water rather than end-on against grass.
			var sunk: float = lerpf(0.25, 1.25, bank_weight)
			var biggest: float = lerpf(1.5, 0.80, bank_weight)
			placed += _place(sources, batches, x, z, ground - sunk, 0.6, biggest, "Rock")
	_commit_all(batches, "Rock")
	return placed


## How far above the water is measured, in world units, before a point stops
## counting as bank at all.
const BANK_HEIGHT := 2.6

## How far into the water the bank still counts, in world units.
const WADE_DEPTH := 0.15


## How strongly a point wants to be pond bank: 1 at the water line, falling away
## as the ground climbs out of it, and zero under water or away from a pond.
##
## Measured by HEIGHT rather than by the shape function. The two agree while the
## bank is a fixed slope, and stop agreeing the moment the bank shape changes -
## which it did. Height is also what the eye is reading: a plant grows near the
## water because the ground there is wet, not because it is a certain fraction
## of the way in from an outline.
func _shore_weight(x: float, z: float) -> float:
	var best := 0.0
	for feature in _features.features():
		var pond := feature as ACAPondFeature
		if pond == null:
			continue
		if pond.shore_factor_at(x, z) <= 0.0:
			continue
		var above := _terrain.height_at(x, z) - pond.water_world_height()
		# Reeds and stones stand IN the shallows, not only beside them.
		if above < -WADE_DEPTH:
			continue
		best = maxf(best, 1.0 - smoothstep(0.0, BANK_HEIGHT, maxf(above, 0.0)))
	return best


## May anything be planted at this point?
##
## THE POND BANK IS INSIDE THE CONTRACT RECTANGLE. Every prop pass here used to
## begin by refusing any point within a metre or two of the mowable rectangle,
## which sounds like "stay off the lawn" and is in fact "stay away from the
## pond", because a pond dug into the middle of a lawn is surrounded by lawn on
## every side. That one line is why the bank had no shrubs, no reeds and almost
## no stones on it however hard the bank was weighted.
##
## The right question is not where the rectangle is, it is what the LAWN SAYS.
## A cell the lawn has marked unmowable is ground a feature has already taken,
## and nothing that grows there can cost the player a contract.
func _plantable(x: float, z: float, ground: float, margin: float) -> bool:
	var out_distance := _rect_distance(x, z, _lawn.lawn_centre())
	if out_distance <= 0.0001:
		# INSIDE the lawn rectangle. The only ground available here is ground a
		# feature has already taken - the pond and its bank - which is exactly
		# what makes the water's edge worth looking at.
		return not _lawn.is_mowable(Vector3(x, ground, z))
	# Outside the lawn: the question is no longer the lawn's, it is the
	# BOUNDARY'S. The yard between the two belongs to the player, and a shrub
	# standing in it is a shrub the machine drives through.
	return _outside_boundary(x, z) > maxf(margin, BOUNDARY_CLEARANCE)


## How far outside the PLAYABLE rectangle a point is. Falls back to the lawn
## rectangle plus the standard margin when this wood was built without a
## boundary, so the class still works on its own.
func _outside_boundary(x: float, z: float) -> float:
	if _boundary != null:
		return _boundary.distance_outside(x, z)
	var centre := _lawn.lawn_centre()
	var half := _lawn.lawn_half_extent() + _params.boundary_margin()
	var dx: float = maxf(absf(x - centre.x) - half, 0.0)
	var dz: float = maxf(absf(z - centre.z) - half, 0.0)
	return sqrt(dx * dx + dz * dz)


func _place(sources: Array[Dictionary], batches: Dictionary, x: float, z: float,
		y: float, min_scale: float, max_scale: float, prefix: String) -> int:
	var pick: int = clampi(int(_hash2(x * 9.3, z * 4.1) * float(sources.size())),
		0, sources.size() - 1)
	var source: Dictionary = sources[pick]
	var scale: float = float(source["scale"]) \
		* lerpf(min_scale, max_scale, _hash2(x * 5.7, z * 8.9))
	var yaw: float = _hash2(x * 1.9, z * 12.7) * TAU
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
	var key := "%s|%d" % [prefix, pick]
	if not batches.has(key):
		batches[key] = {"mesh": source["mesh"], "transforms": PackedFloat32Array()}
	_append(batches[key]["transforms"], Transform3D(basis, Vector3(x, y, z)))
	return 1


# ==================================================================== plumbing

func _prepare(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		var mesh := _load_mesh(String(entry["path"]))
		if mesh == null:
			continue
		out.append({
			"mesh": mesh,
			"scale": _normalising_scale(mesh, float(entry["height"])),
		})
	return out


func _commit_all(batches: Dictionary, prefix: String) -> void:
	for key in batches:
		var batch: Dictionary = batches[key]
		var override: Material = null
		if prefix == "Rock":
			override = _tinted(batch["mesh"], ROCK_TINT)
		elif prefix == "Shrub":
			override = _tinted(batch["mesh"], SHRUB_TINT)
		elif prefix == "Reed":
			override = _tinted(batch["mesh"], REED_TINT)
		_commit_batch(prefix, batch["mesh"], batch["transforms"], override)


## A copy of a mesh's own material with its albedo multiplied. Copied rather
## than edited, because an imported mesh's material is a SHARED resource and
## writing to it would recolour every other use of that asset in the project.
func _tinted(mesh: Mesh, tint: Color) -> Material:
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var source := mesh.surface_get_material(0) as BaseMaterial3D
	if source == null:
		return null
	var copy := source.duplicate() as BaseMaterial3D
	copy.albedo_color = Color(
		source.albedo_color.r * tint.r,
		source.albedo_color.g * tint.g,
		source.albedo_color.b * tint.b,
		source.albedo_color.a)
	return copy


## A copy of an imported mesh's material that lets a MultiMesh's per-instance
## colour multiply its albedo. The mesh's own texture is kept; all this changes
## is whether the instance colour is allowed to say anything.
##
## Copied, never edited in place: an imported mesh's material is a SHARED
## resource, and writing to it would recolour every other use of that asset.
## Cached per source material, so fourteen species cost fourteen copies however
## many batches they end up split across.
static var _vertex_materials := {}


func _vertex_tinted(mesh: Mesh) -> Material:
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var source := mesh.surface_get_material(0) as BaseMaterial3D
	if source == null:
		return null
	var key := source.get_instance_id()
	if _vertex_materials.has(key):
		return _vertex_materials[key]
	var copy := source.duplicate() as BaseMaterial3D
	copy.vertex_color_use_as_albedo = true
	_vertex_materials[key] = copy
	return copy


static func _append_colour(colours: PackedFloat32Array, c: Color) -> void:
	colours.append(c.r)
	colours.append(c.g)
	colours.append(c.b)
	colours.append(c.a)


func _commit_batch(prefix: String, mesh: Mesh, transforms: PackedFloat32Array,
		override_material: Material,
		colours: PackedFloat32Array = PackedFloat32Array()) -> void:
	var count := transforms.size() / 12
	if count <= 0:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	var tinted := colours.size() == count * 4
	multimesh.use_colors = tinted
	multimesh.instance_count = count
	if tinted:
		# Godot interleaves the buffer per instance: twelve transform floats,
		# then the colour. Writing it in one assignment is the difference
		# between a property building in a fraction of a second and setting
		# nine thousand instances one call at a time.
		var buffer := PackedFloat32Array()
		buffer.resize(count * 16)
		for i in count:
			var t := i * 12
			var c := i * 4
			var w := i * 16
			for k in 12:
				buffer[w + k] = transforms[t + k]
			for k in 4:
				buffer[w + 12 + k] = colours[c + k]
		multimesh.buffer = buffer
	else:
		multimesh.buffer = transforms

	var instance := MultiMeshInstance3D.new()
	instance.name = "%s %d" % [prefix, _nodes]
	instance.multimesh = multimesh
	if override_material != null:
		instance.material_override = override_material
	# Only the trees the player can walk up to cast shadows, and only the ones
	# close enough for their shadow to fall on ground the player can see. A
	# shadow map that has to cover a thousand units of woodland costs far more
	# than the contact it adds under a distant canopy.
	# SAPLINGS ARE NOT AMONG THEM. There are hundreds of them, they are the
	# smallest thing in the wood, and putting them in the shadow map cost about
	# a third of the frame for contact nobody was going to go looking for.
	var shadow_radius: float = TREE_SHADOW_RADIUS * float(
		SHADOW_RADIUS_FOR_QUALITY.get(_quality, 1.0))
	if prefix != "Tree" or _batch_distance(transforms) > shadow_radius:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 6.0
	add_child(instance)
	_nodes += 1


## Sources are authored at whatever size their pack used. Everything is
## normalised to a target world height here, so a swapped asset never silently
## changes the composition.
func _normalising_scale(mesh: Mesh, target_height: float) -> float:
	var height := mesh.get_aabb().size.y
	if height <= 0.001:
		return 1.0
	return target_height / height


func _load_mesh(path: String) -> Mesh:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[FOREST] could not load %s" % path)
		return null
	var instance := packed.instantiate()
	var mesh := _first_mesh(instance)
	instance.free()
	return mesh


func _first_mesh(node: Node) -> Mesh:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		return mesh_instance.mesh
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _append(transforms: PackedFloat32Array, t: Transform3D) -> void:
	var b := t.basis
	var o := t.origin
	transforms.append(b.x.x)
	transforms.append(b.y.x)
	transforms.append(b.z.x)
	transforms.append(o.x)
	transforms.append(b.x.y)
	transforms.append(b.y.y)
	transforms.append(b.z.y)
	transforms.append(o.y)
	transforms.append(b.x.z)
	transforms.append(b.y.z)
	transforms.append(b.z.z)
	transforms.append(o.z)


## Mean distance of a batch from the property centre, read straight out of the
## packed transform buffer: the origin is floats 3, 7 and 11 of each instance.
static func _batch_distance(transforms: PackedFloat32Array) -> float:
	var count := transforms.size() / 12
	if count <= 0:
		return 0.0
	var sum := 0.0
	for i in count:
		var base := i * 12
		var x := transforms[base + 3]
		var z := transforms[base + 11]
		sum += sqrt(x * x + z * z)
	return sum / float(count)


## Distance from a point to the mowable rectangle, zero inside it.
func _rect_distance(x: float, z: float, lawn_centre: Vector3) -> float:
	var half := _lawn.lawn_half_extent()
	var dx: float = maxf(absf(x - lawn_centre.x) - half, 0.0)
	var dz: float = maxf(absf(z - lawn_centre.z) - half, 0.0)
	return sqrt(dx * dx + dz * dz)


## Eight wedges around the property, so a distant batch can be frustum culled
## rather than drawn whole every frame.
static func _sector(x: float, z: float) -> int:
	return int(fposmod(atan2(z, x), TAU) / TAU * 8.0)


func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


static func _hash2(x: float, z: float) -> float:
	var s := sin(Vector2(x, z).dot(Vector2(127.1, 311.7))) * 43758.5453
	return s - floor(s)
