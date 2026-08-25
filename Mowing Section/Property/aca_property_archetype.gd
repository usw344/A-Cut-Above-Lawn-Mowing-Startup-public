class_name ACAPropertyArchetype
extends RefCounted
## ROLE
## What KIND of place a contract is, and how that changes the property the
## generator builds.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## Every generated property used to be the same kind of place: an open rural
## lawn in a clearing, with a treeline round it and hills behind. The seed moved
## the trees, the pond and the rocks about, and it moved them well - but a
## player mowing a "Riverside Bungalow" and then a "Clinic Grounds" was looking
## at the same countryside twice, because the only thing that had ever differed
## between two contracts was the seed.
##
## The Job System has ALWAYS known what kind of property each contract is. Eight
## property types, on every job, shown on every card - and the mowing scene
## never read one of them. `ACAPropertyParams.for_job()` took the seed and the
## grid size and threw the rest away.
##
## This is the file that stops throwing it away.
##
## ---------------------------------------------------------------------------
## HOW IT CHANGES A PROPERTY, AND WHAT IT DOES NOT TOUCH
## ---------------------------------------------------------------------------
## There is still ONE generator. An archetype does not build a lawn; it
## RESHAPES the numbers the one generator already draws:
##
##   * a suburban lawn is graded flatter, its treeline is closer and thinner,
##     its grass is greener and its pond is smaller, because it is a garden;
##   * a rural lawn keeps everything the generator has always done, with a
##     little more land and a little more weather in it;
##   * a park is open and gently rolling with trees in real groves rather than
##     in a belt;
##   * a landscaped property is the flattest and the tidiest, with the
##     treeline held well back and the least dry grass on it.
##
## And it decides two things the generator could not decide before: what kind of
## EDGE the property has, and what stands OUTSIDE that edge - see
## `ACAPropertyBoundary` and `ACAPropertySurrounds`.
##
## ---------------------------------------------------------------------------
## RESHAPING, NOT REDRAWING
## ---------------------------------------------------------------------------
## `apply()` never draws a random number. Every value it changes was ALREADY
## drawn by `ACAPropertyParams.for_seed()`, and all it does is move that value
## into the range this archetype uses, keeping where in the range the seed put
## it. Two consequences, both of which are the point:
##
##   * the draw ORDER is untouched, so no existing property moves;
##   * the seed still decides everything WITHIN an archetype, so two Residential
##     contracts are two different gardens rather than one garden twice.
##
## PUBLIC API
##   ACAPropertyArchetype.for_property_type(type, seed) -> Kind
##   ACAPropertyArchetype.apply(params)                 -> reshape in place
##   ACAPropertyArchetype.name_of(kind) -> String       for diagnostics
##   ACAPropertyArchetype.description_of(kind) -> String  one player-facing line
##   ACAPropertyArchetype.short_description_of(kind) -> String   three words
##   ACAPropertyArchetype.has_surrounds(kind) -> bool
##
## SIGNALS: None.
##
## INVARIANTS
##   * `apply()` is PURE with respect to randomness. Same params in, same params
##     out, every time, on every machine.
##   * It must be idempotent: applying it twice is applying it once. Every
##     remap goes from a KNOWN source range to the archetype range rather than
##     scaling whatever is already there.
##
## PERSISTENCE OWNERSHIP
##   None directly. `ACAPropertyParams` saves the chosen Kind as an int so a
##   resumed contract rebuilds the same kind of place.

enum Kind {
	## The generator's original character: open country, a real treeline, hills.
	RURAL,
	## A garden in a neighbourhood. Graded flat, framed close, houses beyond it.
	SUBURBAN,
	## A public green. Open, gently rolling, trees in groves, planted beds.
	PARK,
	## Grounds rather than a garden: a building, a car park, clipped edges.
	LANDSCAPED,
}

const NAMES := {
	Kind.RURAL: "rural",
	Kind.SUBURBAN: "suburban",
	Kind.PARK: "park",
	Kind.LANDSCAPED: "landscaped",
}

## One line a job card or a contract introduction can print. Descriptive of the
## PLACE, never of the difficulty, because the archetype does not change pay.
const DESCRIPTIONS := {
	Kind.RURAL: "Open country. Room to work and a treeline for company.",
	Kind.SUBURBAN: "A garden in a neighbourhood, with the house right there.",
	Kind.PARK: "A public green. Wide open, with planting to work around.",
	Kind.LANDSCAPED: "Managed grounds. Tidy edges and a building to mow up to.",
}


## THE SAME THING IN THREE WORDS, for a job card, where a sentence does not fit
## and a right-aligned value has to stay short.
const SHORT_DESCRIPTIONS := {
	Kind.RURAL: "Open country",
	Kind.SUBURBAN: "House and garden",
	Kind.PARK: "Public green",
	Kind.LANDSCAPED: "Managed grounds",
}


static func short_description_of(kind: int) -> String:
	return String(SHORT_DESCRIPTIONS.get(kind, SHORT_DESCRIPTIONS[Kind.RURAL]))


## THE MAPPING, from the Job System's own property types.
##
## Two of the eight are deliberately not one-to-one. A Community contract is a
## village hall as often as it is a green, and a Hospitality one is a pub garden
## as often as it is hotel grounds, so both are split on the seed - which means
## the split is stable for a given contract and varied across a save.
static func for_property_type(property_type: int, property_seed: int) -> Kind:
	match property_type:
		ACAJobEnums.PropertyType.RESIDENTIAL:
			return Kind.SUBURBAN
		ACAJobEnums.PropertyType.RURAL:
			return Kind.RURAL
		ACAJobEnums.PropertyType.PUBLIC:
			return Kind.PARK
		ACAJobEnums.PropertyType.COMMUNITY:
			return Kind.PARK if _coin(property_seed, 3181) else Kind.SUBURBAN
		ACAJobEnums.PropertyType.COMMERCIAL:
			return Kind.LANDSCAPED
		ACAJobEnums.PropertyType.INSTITUTIONAL:
			return Kind.LANDSCAPED
		ACAJobEnums.PropertyType.INDUSTRIAL:
			return Kind.LANDSCAPED
		ACAJobEnums.PropertyType.HOSPITALITY:
			return Kind.LANDSCAPED if _coin(property_seed, 9043) else Kind.PARK
		_:
			return Kind.RURAL


static func name_of(kind: int) -> String:
	return String(NAMES.get(kind, "rural"))


static func description_of(kind: int) -> String:
	return String(DESCRIPTIONS.get(kind, DESCRIPTIONS[Kind.RURAL]))


## Whether this kind of place has anything standing beyond its boundary. Rural
## and Park do not: their context is the land itself, which the forest and the
## distant hills already build.
static func has_surrounds(kind: int) -> bool:
	return kind == Kind.SUBURBAN or kind == Kind.LANDSCAPED


## Reshape a set of already-drawn parameters into this archetype's ranges.
##
## `params.archetype` is read, not taken as an argument, so there is one place
## the decision lives and no way to build a property as one kind and dress it as
## another.
static func apply(params: ACAPropertyParams) -> void:
	if params == null:
		return
	match params.archetype:
		Kind.SUBURBAN: _apply_suburban(params)
		Kind.PARK: _apply_park(params)
		Kind.LANDSCAPED: _apply_landscaped(params)
		_: _apply_rural(params)


# ================================================================ the shaping

## RURAL is the generator as it was, nudged. The land is allowed to be a little
## more uneven and the wood a little deeper than the default draw, because this
## is the archetype that is meant to feel like country rather than like a lawn
## with trees at the end of it.
static func _apply_rural(p: ACAPropertyParams) -> void:
	p.forestiness = _remap(p.forestiness, 0.22, 0.92, 0.34, 0.95)
	p.lawn_openness = _remap(p.lawn_openness, 8.0, 22.0, 12.0, 26.0)
	p.terrain_amplitude = _remap(p.terrain_amplitude, 4.5, 9.5, 5.5, 10.5)
	p.meadow_density = _remap(p.meadow_density, 0.75, 1.25, 0.95, 1.35)
	p.rock_density = _remap(p.rock_density, 0.25, 0.9, 0.4, 1.0)


## SUBURBAN is a GARDEN, and every number here is trying to say so. The ground
## has been graded, so it is flat and the surrounding land is calm. The treeline
## is close and thin, because a suburban plot is bounded by other plots rather
## than by woodland. The grass is watered, so it is green rather than dry.
static func _apply_suburban(p: ACAPropertyParams) -> void:
	# THE LOWEST OF THE FOUR, and lower than the first attempt's 0.16 - 0.42.
	# The render of that range put four thousand trees round a suburban garden,
	# which is a house in a forest clearing rather than a house in a street.
	p.forestiness = _remap(p.forestiness, 0.22, 0.92, 0.07, 0.24)
	p.tree_cluster_strength = _remap(p.tree_cluster_strength, 0.4, 0.85, 0.30, 0.55)
	# CLOSE. The trees in a suburb are in the neighbours' gardens, a few strides
	# past the fence, not at the far side of a field.
	p.lawn_openness = _remap(p.lawn_openness, 8.0, 22.0, 5.0, 11.0)
	p.terrain_amplitude = _remap(p.terrain_amplitude, 4.5, 9.5, 2.6, 5.0)
	p.broad_hill_strength = _remap(p.broad_hill_strength, 0.75, 1.25, 0.5, 0.85)
	p.playable_flatness = _remap(p.playable_flatness, 0.8, 0.92, 0.93, 0.97)
	p.distant_hill_strength = _remap(p.distant_hill_strength, 70.0, 165.0, 40.0, 95.0)
	p.shrub_density = _remap(p.shrub_density, 0.5, 1.2, 0.7, 1.4)
	p.rock_density = _remap(p.rock_density, 0.25, 0.9, 0.10, 0.35)
	p.meadow_density = _remap(p.meadow_density, 0.75, 1.25, 0.35, 0.7)
	p.dryness = _remap(p.dryness, 0.08, 0.42, 0.05, 0.22)
	# A garden pond, and a garden pond only. The share-of-lawn clamp in
	# `_roll_pond` already stops it being a lake; this stops it being a feature.
	p.pond_radius *= 0.72
	p.pond_depth *= 0.85
	# NOTE ON near_margin: it is deliberately LEFT ALONE. The obvious move for a
	# suburban plot is to pull the detailed ground in tight, and the first
	# version did - but `ACAPropertySurrounds` stands the house and the street
	# beyond the fence, and they need real ground under them. `boundary_margin()`
	# already gives suburban the tightest yard in the game, because it derives
	# from `lawn_openness` and that is now the lowest of the four.


## A PARK is the most OPEN of the four. Its trees are in real groves with grass
## between them rather than in a belt round the edge, its ground rolls gently
## because nobody graded it flat, and it is the archetype most likely to have
## planted beds in the middle of the mowing.
static func _apply_park(p: ACAPropertyParams) -> void:
	p.forestiness = _remap(p.forestiness, 0.22, 0.92, 0.24, 0.58)
	# THE HIGHEST CLUSTERING OF THE FOUR. A park's trees stand in twos and
	# threes with mown grass between them; an even scatter reads as scrub.
	p.tree_cluster_strength = _remap(p.tree_cluster_strength, 0.4, 0.85, 0.68, 0.92)
	p.lawn_openness = _remap(p.lawn_openness, 8.0, 22.0, 14.0, 24.0)
	p.terrain_amplitude = _remap(p.terrain_amplitude, 4.5, 9.5, 3.6, 6.8)
	p.playable_flatness = _remap(p.playable_flatness, 0.8, 0.92, 0.86, 0.93)
	p.shrub_density = _remap(p.shrub_density, 0.5, 1.2, 0.8, 1.5)
	p.rock_density = _remap(p.rock_density, 0.25, 0.9, 0.12, 0.4)
	p.meadow_density = _remap(p.meadow_density, 0.75, 1.25, 0.5, 0.9)
	p.dryness = _remap(p.dryness, 0.08, 0.42, 0.06, 0.26)


## LANDSCAPED is the TIDIEST and the flattest. Grounds are levelled before they
## are planted, the planting is deliberate, and the treeline is held back to
## keep the building visible - which is the whole point of the archetype, since
## the building is what tells the player where they are.
static func _apply_landscaped(p: ACAPropertyParams) -> void:
	p.forestiness = _remap(p.forestiness, 0.22, 0.92, 0.14, 0.36)
	p.tree_cluster_strength = _remap(p.tree_cluster_strength, 0.4, 0.85, 0.45, 0.7)
	p.lawn_openness = _remap(p.lawn_openness, 8.0, 22.0, 16.0, 28.0)
	p.terrain_amplitude = _remap(p.terrain_amplitude, 4.5, 9.5, 2.2, 4.4)
	p.broad_hill_strength = _remap(p.broad_hill_strength, 0.75, 1.25, 0.45, 0.8)
	p.playable_flatness = _remap(p.playable_flatness, 0.8, 0.92, 0.95, 0.985)
	p.distant_hill_strength = _remap(p.distant_hill_strength, 70.0, 165.0, 50.0, 110.0)
	p.shrub_density = _remap(p.shrub_density, 0.5, 1.2, 0.6, 1.2)
	p.rock_density = _remap(p.rock_density, 0.25, 0.9, 0.05, 0.22)
	p.meadow_density = _remap(p.meadow_density, 0.75, 1.25, 0.3, 0.6)
	p.dryness = _remap(p.dryness, 0.08, 0.42, 0.04, 0.18)
	# A landscaped pond is a DESIGNED pond: rounder, shallower, with a wide
	# planted shelf rather than a wandering bank.
	p.pond_irregularity *= 0.55
	p.pond_bank_fraction = clampf(p.pond_bank_fraction * 1.1, 0.1, 1.0)
	p.pond_depth *= 0.9


# ===================================================================== helpers

## Move `value` from the range it was drawn in into a new one, keeping its
## position within the range. Clamped on the way in, so a value that has already
## been reshaped once cannot be pushed further by a second call.
static func _remap(value: float, from_low: float, from_high: float,
		to_low: float, to_high: float) -> float:
	if absf(from_high - from_low) < 0.000001:
		return to_low
	var t: float = clampf((value - from_low) / (from_high - from_low), 0.0, 1.0)
	return lerpf(to_low, to_high, t)


## A stable coin flip from a seed and a salt. Used only where a property type
## maps to more than one archetype.
static func _coin(property_seed: int, salt: int) -> bool:
	return absi(hash(Vector2i(property_seed, salt))) % 2 == 0
