class_name ACARegionalContext
extends RefCounted
## WHAT A REGION DOES TO A PROPERTY AND TO THE AIR OVER IT.
##
## `ACAServiceTerritory` decides WHERE a contract is. This decides what that
## means when the player is standing on it: how open the ground is, how much
## wood is around it, how far the land goes before it stops, and how much air is
## between the machine and the horizon.
##
## Without this, a region is a tab on the job board. With it, a Rural contract
## has a horizon on it and a Medium City one does not, and a player can tell
## which market they are working in without reading anything.
##
## ---------------------------------------------------------------------------
## IT RESHAPES. IT NEVER DRAWS.
## ---------------------------------------------------------------------------
## Exactly the rule `ACAPropertyArchetype` and `ACAPropertyCondition` are built
## on, and for exactly the same reason: `ACAPropertyParams.for_seed()` takes a
## fixed sequence of draws from the seed, THE DRAW ORDER IS THE SAVE FORMAT, and
## anything that consumed a random number here would move every property that
## already exists.
##
## So this multiplies and clamps values the generator has already drawn, after
## the archetype and before the condition. A save written before regions existed
## reloads with its properties exactly as they were, because the region it is in
## was always implicit in what the contract was.
##
## ---------------------------------------------------------------------------
## THE AIR IS NOT A SECOND WEATHER SYSTEM
## ---------------------------------------------------------------------------
## `AIR` is a small standing modifier on the composed environment - more haze
## over a regional centre, less over open country - applied through the
## environment package's PLACE layer. It does not change with the sky, it cannot
## make it rain, and `ACAWorldClock` remains the one authority on what the
## weather is. Two players in two regions at the same moment are under the same
## sky; one of them can see further through it.
##
## PUBLIC API
##   static apply(params, region) -> void          reshape a property
##   static air_layer(region) -> Dictionary        the sky's place layer
##   static blurb(region) -> String

## ---------------------------------------------------------------------------
## THE PROPERTY RESHAPE
## ---------------------------------------------------------------------------
## Multipliers on what the seed drew, then clamped to the generator's own
## ranges. Everything is close to 1.0 on purpose: this is the difference between
## two lawns in two counties, not between two games.
##
##   `forest`     how much wood stands beyond the boundary.
##   `openness`   how much clear ground the lawn has around it.
##   `relief`     how much the playable ground moves.
##   `distance`   how tall the distant hills are - the horizon, in one number.
##   `scrub`      shrubs and rocks.
##   `meadow`     rough grass and wildflower.
const SHAPE := {
	# SMALL TOWN. Close, green and enclosed: hedges and trees between the
	# properties, a horizon you cannot see because there is a street in the way.
	ACAServiceTerritory.Region.HOME_TOWN: {
		"forest": 1.06, "openness": 0.94, "relief": 0.92,
		"distance": 0.82, "scrub": 1.05, "meadow": 1.0,
	},
	# MEDIUM CITY. Flatter and barer. Grounds here were levelled before they
	# were planted, and what is beyond them is built rather than grown.
	ACAServiceTerritory.Region.COMMERCIAL_DISTRICT: {
		"forest": 0.72, "openness": 1.04, "relief": 0.74,
		"distance": 0.70, "scrub": 0.85, "meadow": 0.80,
	},
	# BIG TOWN. The flattest ground in the game and the least of anything
	# growing, with a horizon that is far away and full of buildings.
	ACAServiceTerritory.Region.HOSPITALITY_STRIP: {
		"forest": 0.62, "openness": 1.10, "relief": 0.66,
		"distance": 0.92, "scrub": 0.78, "meadow": 0.72,
	},
	# RURAL HIGHWAY. The strongest contrast in the game: real land, real
	# treelines, and a horizon a long way off.
	ACAServiceTerritory.Region.RURAL_HIGHWAY: {
		"forest": 1.24, "openness": 1.18, "relief": 1.22,
		"distance": 1.30, "scrub": 1.20, "meadow": 1.25,
	},
	# COUNTRY PARKS. The most open ground anywhere, groves rather than
	# hedgerows, rough grass everywhere it is not cut, and the biggest horizon.
	ACAServiceTerritory.Region.CIVIC_PARK: {
		"forest": 1.14, "openness": 1.30, "relief": 1.10,
		"distance": 1.38, "scrub": 1.10, "meadow": 1.40,
	},
}

## ---------------------------------------------------------------------------
## THE AIR
## ---------------------------------------------------------------------------
## `haze` scales the composed depth-fog density and the Sky3D aerial quad;
## `reach` scales how far the depth fog runs before it is total. Together they
## are "how far can I see here", and nothing else.
const AIR := {
	ACAServiceTerritory.Region.HOME_TOWN: {"haze": 1.00, "reach": 1.00},
	ACAServiceTerritory.Region.COMMERCIAL_DISTRICT: {"haze": 1.14, "reach": 0.92},
	ACAServiceTerritory.Region.HOSPITALITY_STRIP: {"haze": 1.26, "reach": 0.86},
	ACAServiceTerritory.Region.RURAL_HIGHWAY: {"haze": 0.84, "reach": 1.22},
	ACAServiceTerritory.Region.CIVIC_PARK: {"haze": 0.90, "reach": 1.30},
}

const BLURBS := {
	ACAServiceTerritory.Region.HOME_TOWN:
		"Close, green and enclosed. Somebody's garden.",
	ACAServiceTerritory.Region.COMMERCIAL_DISTRICT:
		"Levelled ground with buildings round it.",
	ACAServiceTerritory.Region.HOSPITALITY_STRIP:
		"Flat, wide grounds under a developed skyline.",
	ACAServiceTerritory.Region.RURAL_HIGHWAY:
		"Open country. The horizon is a long way off.",
	ACAServiceTerritory.Region.CIVIC_PARK:
		"Public ground, groves and rough grass, going on and on.",
}


static func shape_of(region: int) -> Dictionary:
	return SHAPE.get(region, SHAPE[ACAServiceTerritory.Region.HOME_TOWN])


static func blurb(region: int) -> String:
	return String(BLURBS.get(region, ""))


## RESHAPE A PROPERTY. Called from `ACAPropertyParams.for_seed()` after the
## archetype and before the condition; a `region` of -1 does nothing at all,
## which is what every caller that predates regions is implicitly asking for.
static func apply(params: ACAPropertyParams, region: int) -> void:
	if params == null or not SHAPE.has(region):
		return
	var s := shape_of(region)
	params.forestiness = clampf(
		params.forestiness * float(s["forest"]), 0.05, 1.0)
	params.lawn_openness = clampf(
		params.lawn_openness * float(s["openness"]), 5.0, 30.0)
	params.terrain_amplitude = clampf(
		params.terrain_amplitude * float(s["relief"]), 1.5, 14.0)
	params.broad_hill_strength = clampf(
		params.broad_hill_strength * float(s["relief"]), 0.35, 1.8)
	params.distant_hill_strength = clampf(
		params.distant_hill_strength * float(s["distance"]), 25.0, 260.0)
	params.shrub_density = clampf(
		params.shrub_density * float(s["scrub"]), 0.1, 1.8)
	params.rock_density = clampf(
		params.rock_density * float(s["scrub"]), 0.05, 1.4)
	params.meadow_density = clampf(
		params.meadow_density * float(s["meadow"]), 0.3, 2.0)


## THE SKY'S PLACE LAYER for a region, in the environment package's own
## `{ scale: {}, set: {} }` shape. Only `scale`, and only four keys: a region
## may say how far you can see and nothing else.
static func air_layer(region: int) -> Dictionary:
	var air: Dictionary = AIR.get(region, {})
	if air.is_empty():
		return {}
	var haze := float(air["haze"])
	var reach := float(air["reach"])
	if is_equal_approx(haze, 1.0) and is_equal_approx(reach, 1.0):
		return {}
	return {
		"scale": {
			"env:fog_density": haze,
			"env:fog_depth_end": reach,
			"dome:fog_density": haze,
			"dome:fog_end": reach,
		},
	}
