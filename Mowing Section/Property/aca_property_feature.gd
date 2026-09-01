class_name ACAPropertyFeature
extends RefCounted
## ROLE
## The interface every landscape feature answers, and the ONLY thing the lawn,
## the grass placer and the foliage placer know about features.
##
## A pond, a rock cluster, a garden bed or a building footprint all present the
## same three questions: how do you change the ground, where do you take space
## away, and how big are you. Nothing downstream asks WHY an area is excluded,
## which is what keeps pond-specific conditions out of the mowing core.
##
## PUBLIC API
##   bounds()                      -> world AABB, for broad-phase rejection
##   terrain_offset_at(x, z)       -> vertical displacement of the ground
##   exclusion_at(x, z, ground_y)  -> 0 clear .. 1 fully taken
##   blocks_mowing() / blocks_grass() / blocks_foliage()
##   is_solid()                    -> does the machine physically hit this?
##   footprints()                  -> the circles it really occupies, if several
##   clearance()                   -> clear ground it owes the deck, world units
##   feature_id()                  -> a short stable name, for diagnostics
##
## SIGNALS: None.
##
## INVARIANTS
##   * Every method is PURE. Same arguments, same answer, no node access, no
##     frame dependence. That is what lets the terrain bake, the collision
##     heightmap, the grass placer and a save-time reconstruction all agree.
##   * `terrain_offset_at()` must be zero outside `bounds()`.
##   * Coordinates are WORLD space, on the XZ plane.
##
## PERSISTENCE OWNERSHIP
##   None. Features are rebuilt from ACAPropertyParams, never serialised
##   individually.

## Above this, an area counts as taken: not mowable, no grass, no props.
const EXCLUDED_THRESHOLD := 0.5


func feature_id() -> StringName:
	return &"feature"


## Whether the machine physically collides with this feature.
##
## A solid feature owes the lawn more clear ground than its own footprint: the
## thing that touches it is the CHASSIS, and on most machines the chassis
## reaches past the cutting deck. See `ACAMowerClearance` for the derivation and
## for why leaving that band mowable makes a contract impossible to finish.
##
## A feature that is only DRAWN - a garden bed, a path strip - is not solid, and
## owes nothing beyond its own edge.
func is_solid() -> bool:
	return false


## DOES THIS FEATURE NEED THE GROUND UNDER IT LEVEL?
##
## A pond does: its surface is a flat plane, so ground with a grade running
## across it either floods out of the bowl on one side or leaves the water line
## short of the bank on the other. Almost nothing else does - a rock, a bed or a
## path sits on whatever slope it is put on, the way it would in a garden.
##
## `ACATerrain` reads this once, at build, and holds the LAWN'S GRADE at this
## feature's centre across it. The grade outside is untouched, so the ground
## does not step: it simply stops falling where the water is.
func levels_ground() -> bool:
	return false


## How far past its own physical footprint this feature keeps grass out, in
## world units. Zero for anything the machine can drive over.
##
## Every solid feature answers `ACAMowerClearance.REQUIRED` unless it has a
## reason of its own, so the size of the band is decided in ONE place and by
## measurement rather than by a constant per feature.
func clearance() -> float:
	return ACAMowerClearance.REQUIRED if is_solid() else 0.0


## Called once BEFORE the terrain is baked. `base_height` is a callable taking
## (x: float, z: float) and returning the ground height with no feature offsets
## applied. A feature that has to know where the untouched ground sits - a pond
## deciding its water line - resolves it here and caches the answer.
func prepare(_base_height: Callable) -> void:
	pass


## World-space extent. Y is generous on purpose: callers use this only to reject
## points quickly on XZ.
func bounds() -> AABB:
	return AABB()


## How far this feature moves the ground at a point, in world units. Negative
## digs down. Zero outside the footprint.
func terrain_offset_at(_x: float, _z: float) -> float:
	return 0.0


## 0 where the feature takes nothing, 1 where it takes everything. Values in
## between exist so a placer can FADE density towards a shoreline or a bed edge
## rather than cutting it off at a line.
##
## `ground_y` is the FINAL terrain height at that point, offsets already
## applied, so a feature can answer with the geometry that actually exists.
func exclusion_at(_x: float, _z: float, _ground_y: float) -> float:
	return 0.0


## Whether an excluded cell stops counting towards mowing completion.
func blocks_mowing() -> bool:
	return true


## Is the ground this feature takes PROTECTED VEGETATION rather than simply
## unavailable?
##
## Both kinds are outside the contract. The difference is what happens when the
## machine goes over one: a pond cannot be cut and a wildflower meadow can, so
## protected ground is swept by the deck exactly as the lawn is and what it
## records is damage rather than progress. See `ACALawn.FLAG_PROTECTED`.
##
## A feature that answers TRUE must also answer `blocks_mowing()` TRUE: the
## player is not supposed to cut it, so it can never be part of what they are
## being asked to finish.
func is_protected_vegetation() -> bool:
	return false


## Whether excluded ground refuses lawn grass.
func blocks_grass() -> bool:
	return true


## Whether excluded ground refuses trees, shrubs and rocks.
func blocks_foliage() -> bool:
	return true


## WHERE THIS FEATURE ACTUALLY IS, as circles on the XZ plane.
##
## `bounds()` is the rectangle around EVERYTHING a feature holds, which is the
## right answer for rejecting a point quickly and the wrong one for asking
## whether a candidate collides with anything. A dozen lawn rocks scattered
## across a property have a combined bounding box that is nearly the whole
## property; a placer that treats that box as occupied ground can place nothing.
##
## So a feature made of several small things says so here, and a placer that
## needs to be exact tests against these instead. Returning an EMPTY array means
## "I am one thing, use my bounds", which is the correct answer for a pond and
## is the default.
##
## Each entry: `{ position: Vector2, radius: float }` in world space.
func footprints() -> Array[Dictionary]:
	return []


## Optional visual/collision nodes this feature contributes to the property.
## Called once during the build, after the terrain exists. The default adds
## nothing.
func build_nodes(_parent: Node3D, _terrain: Node3D, _params: ACAPropertyParams) -> void:
	pass
