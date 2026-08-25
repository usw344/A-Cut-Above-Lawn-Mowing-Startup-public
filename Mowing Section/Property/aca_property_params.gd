class_name ACAPropertyParams
extends Resource
## ROLE
## The COMPLETE description of one mowing property, as compact data. Terrain
## shape, lawn size, forest character, foliage density and the pond are all
## decided here; nothing downstream invents anything of its own.
##
## Two properties built from equal parameters are identical, down to the
## position of every tree. That is what makes a property cheap to save: the
## save file stores THIS, not a mesh and not forty thousand transforms.
##
## PUBLIC API
##   ACAPropertyParams.for_job(job)        -> params derived from a contract
##   ACAPropertyParams.for_seed(s, size)   -> the same derivation without a job
##   ACAPropertyParams.preset(name)        -> a development preset
##   PRESET_NAMES                          -> the development preset names
##   to_dictionary() / from_dictionary()   -> save round trip
##   duplicate_params()                    -> an independent copy
##   lawn_half_extent() / near_extent()    -> the two sizes everything derives from
##
## SIGNALS: None.
##
## INVARIANTS
##   * `seed` alone decides every random draw. Changing the ORDER of draws in
##     for_seed() changes existing properties, so bump GENERATION_VERSION when
##     that happens.
##   * `lawn_size` is in WORLD UNITS and is also the logical mowing cell count
##     per side, because a mowing cell is exactly one world unit.
##   * Distances are world units. This world is roughly four times life size:
##     a riding mower deck is about five units wide.
##
## PERSISTENCE OWNERSHIP
##   Serialised inside the mowing save block, written by SaveService. This
##   resource never touches a file itself.

## Bump when the MEANING of a parameter changes or the order of generator draws
## moves. A save carrying an older version is rebuilt with its own version's
## rules where practical, and reported when it cannot be.
## Version 2 widened the pond bank and raised its water line. Both are ordinary
## draws in the same place in the sequence, and every pond field round trips
## through the save, so a contract already in progress keeps the pond it was
## generated with. A NEW contract on an old seed gets the new one.
## Version 3 made a pond COMPULSORY and added the lawn obstacle field. Neither
## moved an existing draw: the two rolls that used to decide whether a property
## got a pond are still taken, in their old places, and now decide how generous
## the pond is instead; the obstacles come from a separate stream keyed off the
## same seed. A property that already had a pond therefore rebuilds with exactly
## the pond it had, and every other parameter of every seed is untouched. What a
## version 2 save DOES gain when it is reloaded is the obstacles, which is safe:
## a cell that has become unmowable simply stops counting, and `ACALawn` masks
## the restored cut state with the mowable flag rather than trusting it.
const GENERATION_VERSION := 4

# ------------------------------------------------------------------ identity
## The one number every deterministic draw comes from.
@export var seed: int = 0
@export var generation_version: int = GENERATION_VERSION

## WHAT KIND OF PLACE THIS IS. See `ACAPropertyArchetype`.
##
## Not drawn from the seed: it comes from the contract's own property type,
## which the Job System has always known and the mowing scene used to ignore.
## Saved, so a contract resumed tomorrow is the same kind of place it was.
##
## A save written before archetypes existed has no value for this and loads as
## RURAL, which is exactly the property it was played on - rural was the only
## kind the generator could make.
@export var archetype: int = ACAPropertyArchetype.Kind.RURAL

# ---------------------------------------------------------------- lawn sizes
## Side length of the mowable rectangle, in world units. Also the number of
## logical mowing cells per side. Job sizes are 96 / 144 / 192.
@export var lawn_size: int = 96

## How much surrounding ground is walkable and fully detailed, beyond the lawn
## edge. The tree belt, shrubs and rocks live in this band.
@export var near_margin: float = 44.0

# ------------------------------------------------------------------- terrain
@export_group("Terrain")
## Overall vertical scale of the near-field landscape, in world units.
@export_range(0.0, 40.0, 0.1) var terrain_amplitude: float = 7.0
## Weight of the broad, low-frequency roll. This is the shape read as
## "the land tilts that way".
@export_range(0.0, 2.0, 0.01) var broad_hill_strength: float = 1.0
## Weight of the medium-frequency unevenness. Keep it modest or the lawn stops
## being pleasant to steer on.
@export_range(0.0, 1.0, 0.01) var fine_variation: float = 0.28
## Very small surface relief, so the ground is never a perfect plane.
@export_range(0.0, 1.0, 0.02) var micro_relief: float = 0.34
## How strongly the mowable rectangle is levelled. 1.0 is dead flat; 0.0 leaves
## the lawn as hilly as the surroundings.
@export_range(0.0, 1.0, 0.01) var playable_flatness: float = 0.86
## How far past the lawn edge the levelling fades out, in world units.
@export_range(4.0, 120.0, 1.0) var flatten_falloff: float = 34.0

@export_group("Distant landscape")
## Height of the scenic hills beyond the playable area. These are allowed to be
## far more dramatic than anything the mower drives on.
@export_range(0.0, 400.0, 1.0) var distant_hill_strength: float = 110.0
## Horizontal size of those hills. Larger reads as further away.
@export_range(80.0, 2000.0, 10.0) var distant_hill_scale: float = 620.0
## Where the distant hills begin to rise, measured from the property centre.
@export_range(80.0, 1200.0, 5.0) var distant_hill_start: float = 190.0
## How far the ground is built out before the sky takes over.
@export_range(400.0, 8000.0, 50.0) var landscape_radius: float = 3600.0

# -------------------------------------------------------------------- forest
@export_group("Vegetation")
## THE landscape character control. 0 is an open field with a few trees; 1 is a
## property embedded in woodland. It changes clustering and belt depth, not just
## a multiplier on a tree count.
@export_range(0.0, 1.0, 0.01) var forestiness: float = 0.5
## How much the trees gather into groves rather than spreading evenly.
@export_range(0.0, 1.0, 0.01) var tree_cluster_strength: float = 0.62
## How far back the trees are held from the lawn edge, in world units. Higher
## means a more open property.
@export_range(0.0, 60.0, 0.5) var lawn_openness: float = 12.0
@export_range(0.0, 2.0, 0.01) var shrub_density: float = 0.8
@export_range(0.0, 2.0, 0.01) var rock_density: float = 0.55
## Density of the tall wild grass in the band between lawn and treeline.
@export_range(0.0, 2.0, 0.01) var meadow_density: float = 1.0

# ------------------------------------------------------------------ features
@export_group("Features")
## Chance that a generated property gets any landscape feature at all.
@export_range(0.0, 1.0, 0.01) var feature_probability: float = 0.5
## Of the properties that get a feature, the chance it is a pond.
@export_range(0.0, 1.0, 0.01) var pond_probability: float = 0.6

@export_group("Pond")
@export var pond_enabled: bool = false
## Centre relative to the property centre, on the XZ plane.
@export var pond_offset: Vector2 = Vector2.ZERO
@export_range(3.0, 60.0, 0.1) var pond_radius: float = 15.0
@export_range(0.4, 3.0, 0.01) var pond_ellipse_ratio: float = 1.3
@export_range(0.0, 0.6, 0.01) var pond_irregularity: float = 0.2
@export_range(0.5, 12.0, 0.05) var pond_depth: float = 3.6
## Fraction of the radius given over to the sloping bank. Low values dig a
## bathtub; this is a cozy garden pond, so it wants a wide one.
@export_range(0.1, 1.0, 0.01) var pond_bank_fraction: float = 0.74
## Water surface height relative to the UN-carved ground.
@export_range(-8.0, 2.0, 0.01) var pond_water_level: float = -0.95
@export var pond_seed: int = 0

# ---------------------------------------------------------------- appearance
@export_group("Appearance")
## Wind direction on the XZ plane. Shared by grass and trees.
@export var wind_direction: Vector2 = Vector2(0.86, 0.51)
@export_range(0.0, 2.0, 0.01) var wind_speed: float = 0.62
## Seeded colour drift, so two properties are not the same green.
@export_range(-1.0, 1.0, 0.01) var lawn_colour_bias: float = 0.0
## How much dry, late-summer yellow is mixed into the grass.
@export_range(0.0, 1.0, 0.01) var dryness: float = 0.24


## Half the side length of the mowable rectangle, in world units.
func lawn_half_extent() -> float:
	return float(lawn_size) * 0.5


## Half the side length of the fully detailed near field: lawn plus margin.
## Terrain collision, grass tiles and the detailed ground all stop here.
##
## This is NOT the playable area. The player is held inside `boundary_margin()`,
## which is a good deal smaller; the band between the two is the near half of the
## scenery, drawn at full detail because it is what the player looks at over the
## fence.
func near_extent() -> float:
	return lawn_half_extent() + near_margin


## THE PLAYABLE PROPERTY EDGE, as a distance out from the lawn rectangle.
##
## Everything that has to agree about where the property stops - the boundary
## collision, the fence, the foliage placer, the minimap - asks THIS. There is
## no second copy of the number and no magic constant anywhere downstream.
##
## `lawn_openness` already describes how much room this property leaves around
## its lawn, so the yard is derived from it rather than from a new draw: the
## generator's draw ORDER does not move, every existing seed keeps every value
## it had, and `GENERATION_VERSION` does not have to change.
##
## The floor is what the mower needs. `ACAProperty.ARRIVAL_SETBACK` puts the
## machine seven units off the lawn edge, and a machine that arrives already
## touching the fence behind it is a machine that cannot reverse.
func boundary_margin() -> float:
	return clampf(lawn_openness, MIN_BOUNDARY_MARGIN, MAX_BOUNDARY_MARGIN)


## The yard is never tighter than this, whatever the seed drew, because the
## mower arrives inside it and has to be able to turn around.
const MIN_BOUNDARY_MARGIN := 15.0
## ...and never wider than this, because past it the yard stops reading as part
## of the property and starts reading as a field the fence happens to be in.
const MAX_BOUNDARY_MARGIN := 26.0


## Half the side length of the PLAYABLE rectangle, in world units.
func boundary_half_extent() -> float:
	return lawn_half_extent() + boundary_margin()


## Carries `archetype` with everything else; a duplicate that lost it would
## rebuild the same seed as a different kind of place.
func duplicate_params() -> ACAPropertyParams:
	return duplicate(true) as ACAPropertyParams


# =========================================================== job integration

## THE narrow integration point with the Job System.
##
## A contract already carries a stable `seed` and a lawn size. Everything about
## the property is derived from those two, so accepting the same contract twice
## always drives to the same place, and no new field has to be added to ACAJob.
## THE CONTRACT'S PROPERTY TYPE IS NOW READ. It decides the archetype, which
## reshapes everything the seed drew - see `ACAPropertyArchetype`. The seed and
## the grid size are still the only things that DRAW anything.
static func for_job(job: ACAJob) -> ACAPropertyParams:
	if job == null:
		return preset(&"default")
	var size: int = job.grid_size.x if job.grid_size.x > 0 else 96
	return for_seed(job.seed, size,
		ACAPropertyArchetype.for_property_type(job.property_type, job.seed))


## The same derivation without a contract, for probes and the standalone bench.
##
## `archetype` defaults to RURAL, which is what every caller that predates
## archetypes was implicitly asking for.
static func for_seed(property_seed: int, lawn_size_units: int,
		archetype_kind: int = ACAPropertyArchetype.Kind.RURAL) -> ACAPropertyParams:
	var p := ACAPropertyParams.new()
	p.seed = property_seed
	p.lawn_size = maxi(lawn_size_units, 16)

	var rng := RandomNumberGenerator.new()
	rng.seed = property_seed
	# DRAW ORDER IS PART OF THE FORMAT. Adding a draw in the middle changes every
	# existing property; append, or bump GENERATION_VERSION.
	p.forestiness = rng.randf_range(0.22, 0.92)
	p.tree_cluster_strength = rng.randf_range(0.4, 0.85)
	p.lawn_openness = rng.randf_range(8.0, 22.0)
	p.terrain_amplitude = rng.randf_range(4.5, 9.5)
	p.broad_hill_strength = rng.randf_range(0.75, 1.25)
	p.fine_variation = rng.randf_range(0.18, 0.4)
	p.playable_flatness = rng.randf_range(0.8, 0.92)
	p.distant_hill_strength = rng.randf_range(70.0, 165.0)
	p.distant_hill_scale = rng.randf_range(480.0, 820.0)
	p.shrub_density = rng.randf_range(0.5, 1.2)
	p.rock_density = rng.randf_range(0.25, 0.9)
	p.meadow_density = rng.randf_range(0.75, 1.25)
	p.lawn_colour_bias = rng.randf_range(-0.5, 0.5)
	p.dryness = rng.randf_range(0.08, 0.42)
	var wind_angle := rng.randf_range(0.0, TAU)
	p.wind_direction = Vector2(cos(wind_angle), sin(wind_angle))
	p.wind_speed = rng.randf_range(0.45, 0.8)

	# EVERY PROPERTY HAS A POND. It is the one landscape feature the mowing
	# systems fully understand - it digs the ground, excludes the grass, moves
	# the completion denominator and now stops the machine at its shoreline - and
	# a lawn with water on it is a lawn with a shape to it.
	#
	# THE TWO DRAWS THAT USED TO DECIDE WHETHER IT GOT ONE ARE STILL TAKEN, in
	# exactly their old positions, because the draw order IS the save format.
	# They now decide how generous the pond is: a property that would have had
	# one gets precisely the pond it had before, and a property that would not
	# gets a smaller, more modest one.
	var size_bonus: float = clampf((float(p.lawn_size) - 96.0) / 192.0, 0.0, 0.35)
	var wanted_feature := rng.randf() < p.feature_probability + size_bonus
	var wanted_pond := rng.randf() < p.pond_probability
	_roll_pond(p, rng, 1.0 if (wanted_feature and wanted_pond) else MODEST_POND_SCALE)

	# LAST, AND AFTER EVERY DRAW. The archetype reshapes what was drawn; it never
	# draws. Putting it here rather than anywhere earlier is what guarantees the
	# random sequence above is byte for byte the sequence it has always been.
	p.archetype = archetype_kind
	ACAPropertyArchetype.apply(p)
	return p


## How much smaller the pond is on a property whose seed would not have rolled
## one at all. Small enough to read as a garden pond rather than a lake, large
## enough that the shoreline is still worth mowing around.
##
## The first value tried here was 0.74, and the render showed why that was too
## low: at the bottom of the range it produced an eight unit pond on a Medium
## lawn, which from a standing player is a dark puddle in a green field rather
## than a feature to mow around.
const MODEST_POND_SCALE := 0.86


## Ponds sit OFF-CENTRE and away from the mower start corner, so a contract
## never begins with the machine facing water, and the lawn never becomes a
## ring around a hole in the middle.
static func _roll_pond(p: ACAPropertyParams, rng: RandomNumberGenerator,
		scale: float = 1.0) -> void:
	var half := p.lawn_half_extent()
	p.pond_enabled = true
	p.pond_seed = rng.randi()
	# SIZE IS BOUNDED BY THE LAWN, not only by the absolute clamp. A Small
	# contract is 96 units on a side; the old floor of 8 units was drawn for a
	# Medium and left a Small property with a pond taking a tenth of its usable
	# ground before the bank was counted. The upper bound is a share of the lawn
	# so the same rule reads sensibly at every size.
	# THE RANGE IS A SHARE OF THE LAWN at every size, with a floor that keeps a
	# pond readable on a Small contract and a ceiling that keeps it from being
	# the contract. Widened from 0.16 - 0.26 after the renders: the old range's
	# lower half did not read as water from the seat of a mower.
	p.pond_radius = clampf(half * rng.randf_range(0.19, 0.29) * scale,
		maxf(half * 0.15, 6.5), minf(half * 0.32, 34.0))
	p.pond_ellipse_ratio = rng.randf_range(1.0, 1.6)
	p.pond_irregularity = rng.randf_range(0.14, 0.3)
	p.pond_depth = rng.randf_range(2.8, 4.6)
	# WIDER BANKS AND A HIGHER WATER LINE than the first pass drew. The old
	# numbers put the surface well over a unit below the surrounding ground
	# behind a narrow, steep rim, so from a mower's seat a pond was a dark
	# depression with a patch of water at the bottom of it and the bank - the
	# part worth looking at - hidden behind its own edge. These are the same two
	# draws in the same order; only the ranges moved.
	p.pond_bank_fraction = rng.randf_range(0.62, 0.88)
	p.pond_water_level = rng.randf_range(-1.15, -0.75)

	# Somewhere in the outer half of the lawn, never in the -X half where the
	# mower is placed.
	var angle := rng.randf_range(-PI * 0.42, PI * 0.42)
	var distance: float = half * rng.randf_range(0.34, 0.5)
	p.pond_offset = Vector2(cos(angle), sin(angle)) * distance


# =============================================================== dev presets

const PRESET_NAMES: Array[StringName] = [
	&"open", &"light_forest", &"wooded", &"pond", &"wooded_pond", &"default",
]


## Development presets for the visual probes. These are NOT job categories; the
## Job System still decides the lawn size and the seed.
static func preset(preset_name: StringName, lawn_size_units: int = 144) -> ACAPropertyParams:
	var p := ACAPropertyParams.new()
	p.lawn_size = lawn_size_units
	match preset_name:
		&"open":
			p.seed = 101
			p.forestiness = 0.16
			p.tree_cluster_strength = 0.35
			p.lawn_openness = 26.0
			p.shrub_density = 0.35
			p.rock_density = 0.3
			p.distant_hill_strength = 130.0
		&"light_forest":
			p.seed = 202
			p.forestiness = 0.45
			p.tree_cluster_strength = 0.6
			p.lawn_openness = 16.0
		&"wooded":
			p.seed = 303
			p.forestiness = 0.92
			p.tree_cluster_strength = 0.75
			p.lawn_openness = 10.0
			p.shrub_density = 1.2
			p.rock_density = 0.8
		&"pond":
			p.seed = 404
			p.forestiness = 0.34
			p.lawn_openness = 18.0
			_apply_demo_pond(p)
		&"wooded_pond":
			p.seed = 505
			p.forestiness = 0.86
			p.tree_cluster_strength = 0.78
			p.lawn_openness = 11.0
			p.shrub_density = 1.15
			p.rock_density = 0.9
			_apply_demo_pond(p)
		_:
			p.seed = 20260820
	return p


static func _apply_demo_pond(p: ACAPropertyParams) -> void:
	var half := p.lawn_half_extent()
	p.pond_enabled = true
	p.pond_seed = p.seed * 7919
	p.pond_radius = clampf(half * 0.22, 8.0, 34.0)
	p.pond_ellipse_ratio = 1.34
	p.pond_irregularity = 0.22
	p.pond_depth = 3.8
	p.pond_bank_fraction = 0.74
	p.pond_water_level = -0.95
	p.pond_offset = Vector2(half * 0.36, half * 0.2)


# ============================================================ save round trip

## Compact and JSON-safe. Vectors become two-element arrays because a save file
## is plain JSON.
func to_dictionary() -> Dictionary:
	return {
		"generation_version": generation_version,
		"seed": seed,
		"archetype": archetype,
		"lawn_size": lawn_size,
		"near_margin": near_margin,
		"terrain_amplitude": terrain_amplitude,
		"broad_hill_strength": broad_hill_strength,
		"fine_variation": fine_variation,
		"micro_relief": micro_relief,
		"playable_flatness": playable_flatness,
		"flatten_falloff": flatten_falloff,
		"distant_hill_strength": distant_hill_strength,
		"distant_hill_scale": distant_hill_scale,
		"distant_hill_start": distant_hill_start,
		"landscape_radius": landscape_radius,
		"forestiness": forestiness,
		"tree_cluster_strength": tree_cluster_strength,
		"lawn_openness": lawn_openness,
		"shrub_density": shrub_density,
		"rock_density": rock_density,
		"meadow_density": meadow_density,
		"feature_probability": feature_probability,
		"pond_probability": pond_probability,
		"pond_enabled": pond_enabled,
		"pond_offset": [pond_offset.x, pond_offset.y],
		"pond_radius": pond_radius,
		"pond_ellipse_ratio": pond_ellipse_ratio,
		"pond_irregularity": pond_irregularity,
		"pond_depth": pond_depth,
		"pond_bank_fraction": pond_bank_fraction,
		"pond_water_level": pond_water_level,
		"pond_seed": pond_seed,
		"wind_direction": [wind_direction.x, wind_direction.y],
		"wind_speed": wind_speed,
		"lawn_colour_bias": lawn_colour_bias,
		"dryness": dryness,
	}


## Missing keys fall back to the current default, so an older save loads.
static func from_dictionary(data: Dictionary) -> ACAPropertyParams:
	var p := ACAPropertyParams.new()
	p.generation_version = int(data.get("generation_version", 1))
	p.seed = int(data.get("seed", 0))
	# RURAL for anything written before archetypes, which is the truth: it is
	# the only kind of property the generator could produce.
	p.archetype = int(data.get("archetype", ACAPropertyArchetype.Kind.RURAL))
	p.lawn_size = int(data.get("lawn_size", 96))
	p.near_margin = float(data.get("near_margin", p.near_margin))
	p.terrain_amplitude = float(data.get("terrain_amplitude", p.terrain_amplitude))
	p.broad_hill_strength = float(data.get("broad_hill_strength", p.broad_hill_strength))
	p.fine_variation = float(data.get("fine_variation", p.fine_variation))
	p.micro_relief = float(data.get("micro_relief", p.micro_relief))
	p.playable_flatness = float(data.get("playable_flatness", p.playable_flatness))
	p.flatten_falloff = float(data.get("flatten_falloff", p.flatten_falloff))
	p.distant_hill_strength = float(data.get("distant_hill_strength", p.distant_hill_strength))
	p.distant_hill_scale = float(data.get("distant_hill_scale", p.distant_hill_scale))
	p.distant_hill_start = float(data.get("distant_hill_start", p.distant_hill_start))
	p.landscape_radius = float(data.get("landscape_radius", p.landscape_radius))
	p.forestiness = float(data.get("forestiness", p.forestiness))
	p.tree_cluster_strength = float(data.get("tree_cluster_strength", p.tree_cluster_strength))
	p.lawn_openness = float(data.get("lawn_openness", p.lawn_openness))
	p.shrub_density = float(data.get("shrub_density", p.shrub_density))
	p.rock_density = float(data.get("rock_density", p.rock_density))
	p.meadow_density = float(data.get("meadow_density", p.meadow_density))
	p.feature_probability = float(data.get("feature_probability", p.feature_probability))
	p.pond_probability = float(data.get("pond_probability", p.pond_probability))
	p.pond_enabled = bool(data.get("pond_enabled", false))
	p.pond_offset = _to_vector2(data.get("pond_offset", null), p.pond_offset)
	p.pond_radius = float(data.get("pond_radius", p.pond_radius))
	p.pond_ellipse_ratio = float(data.get("pond_ellipse_ratio", p.pond_ellipse_ratio))
	p.pond_irregularity = float(data.get("pond_irregularity", p.pond_irregularity))
	p.pond_depth = float(data.get("pond_depth", p.pond_depth))
	p.pond_bank_fraction = float(data.get("pond_bank_fraction", p.pond_bank_fraction))
	p.pond_water_level = float(data.get("pond_water_level", p.pond_water_level))
	p.pond_seed = int(data.get("pond_seed", 0))
	p.wind_direction = _to_vector2(data.get("wind_direction", null), p.wind_direction)
	p.wind_speed = float(data.get("wind_speed", p.wind_speed))
	p.lawn_colour_bias = float(data.get("lawn_colour_bias", p.lawn_colour_bias))
	p.dryness = float(data.get("dryness", p.dryness))
	return p


static func _to_vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
