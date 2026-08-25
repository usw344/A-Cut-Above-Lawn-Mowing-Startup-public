class_name ACAMowerClearance
extends RefCounted
## ROLE
## How much clear ground a SOLID feature has to leave around itself so that the
## machine can finish mowing right up against it.
##
## ---------------------------------------------------------------------------
## THE PROBLEM THIS EXISTS TO SOLVE
## ---------------------------------------------------------------------------
## A rock's collision is a sphere of radius r. Its grass used to stop at
## r + 0.5. But the thing that touches the rock is not the deck - it is the
## CHASSIS, and on two of the three canonical machines the chassis is wider than
## the deck. Those machines stop with a strip of standing grass still in front
## of the blades, and that strip counted towards a completion the player could
## never reach.
##
## The same applies to the pond's shoreline collision ring, and to anything else
## the machine can hit.
##
## ---------------------------------------------------------------------------
## THE DERIVATION, AND WHY IT IS A CONSTANT
## ---------------------------------------------------------------------------
## For one machine and one approach direction:
##
##     shortfall = how far the chassis reaches past the deck
##
## The player chooses the approach, so the shortfall that actually matters is
## the SMALLEST over the directions available - a machine that cannot nose into
## a rock can still drive past it sideways. For a convex obstacle every heading
## is available, so what matters per machine is
##
##     min(sideways shortfall, head-on shortfall)
##
## and what matters for the GAME is the worst of those across every machine the
## player can own, because a property is generated without knowing which one
## turns up to mow it.
##
## Measured from the canonical scenes and the deck constants they declare:
##
## | machine   | chassis X/2 | chassis Z/2 | deck W/2 | deck fwd+L/2 | sideways | head-on | min   |
## |-----------|------------:|------------:|---------:|-------------:|---------:|--------:|------:|
## | Push      |       3.225 |       1.573 |     2.30 |         1.35 |    0.925 |   0.223 | 0.223 |
## | Non-rider |       3.414 |       3.187 |     2.60 |         1.60 |    0.814 |   1.587 | 0.814 |
## | Rider     |       2.060 |       2.501 |     2.80 |         1.60 |   -0.740 |   0.901 |-0.740 |
##
## The worst is the non-rider's 0.814. `SAFETY` covers what the table cannot:
## the lawn is quantised to one-unit cells, the ground is not level, and a
## player steering along a curved shoreline does not shave it perfectly.
##
## THIS IS A CONSTANT RATHER THAN A LOOKUP because it is part of how a property
## is generated, and generation has to give the same answer every time a save is
## resumed - including on a save written while the player owned a different
## machine. `Property Test` re-derives it from the real scenes and fails if the
## table above has drifted, so the constant cannot go stale quietly.
##
## PUBLIC API
##   ACAMowerClearance.REQUIRED            the number features should use
##   ACAMowerClearance.WORST_SHORTFALL     the measured part of it
##   ACAMowerClearance.SAFETY              the judged part of it
##   ACAMowerClearance.measure_scenes()    re-derive it, for the test
##
## SIGNALS: None.
##
## INVARIANTS
##   * `REQUIRED` is in WORLD units and never scaled by anything.
##   * It is a property of the FLEET, not of the machine currently in play.
##
## PERSISTENCE OWNERSHIP
##   None. It is baked into the generated property, never serialised.

## The canonical machines, and the only place this file names them.
const MOWER_SCENES := [
	"res://Assets/Vehicles and Mowers/Mowers/Push Mower.tscn",
	"res://Assets/Vehicles and Mowers/Mowers/Non Rider Mower.tscn",
	"res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn",
]

## The worst per-machine shortfall in the table above, rounded up a little.
const WORST_SHORTFALL := 0.82

## One-unit lawn cells, uneven ground and imperfect steering. Judged, not
## measured, and deliberately named so it reads as judged.
const SAFETY := 0.60

## WHAT A SOLID FEATURE SHOULD ADD to its own collision footprint.
const REQUIRED := WORST_SHORTFALL + SAFETY

## How far `measure_scenes()` may drift from `WORST_SHORTFALL` before the test
## should complain. A tenth of a unit is about two and a half centimetres.
const DRIFT_TOLERANCE := 0.10


## Re-derive the worst-case shortfall from the real mower scenes. Used by
## `Property Test`; nothing in generation calls it.
##
## Returns { shortfall: float, machines: Array[Dictionary], ok: bool }.
static func measure_scenes() -> Dictionary:
	var machines: Array[Dictionary] = []
	var worst := -INF
	for path in MOWER_SCENES:
		var entry := _measure_one(String(path))
		if entry.is_empty():
			continue
		machines.append(entry)
		worst = maxf(worst, float(entry["shortfall"]))
	return {
		"shortfall": worst if worst > -INF else 0.0,
		"machines": machines,
		"ok": not machines.is_empty()
			and absf(worst - WORST_SHORTFALL) <= DRIFT_TOLERANCE,
	}


static func _measure_one(path: String) -> Dictionary:
	var packed := load(path) as PackedScene
	if packed == null:
		return {}
	var machine := packed.instantiate()
	if machine == null:
		return {}
	var chassis := _chassis_half_extents(machine)
	var deck := ACAMowerDeck.for_mower(machine)
	machine.free()
	if chassis == Vector2.ZERO or deck == null:
		return {}
	var sideways: float = chassis.x - deck.half_width
	var head_on: float = chassis.y - (deck.forward_offset + deck.half_length)
	return {
		"path": path,
		"chassis_half_x": chassis.x,
		"chassis_half_z": chassis.y,
		"deck_half_width": deck.half_width,
		"deck_reach": deck.forward_offset + deck.half_length,
		"sideways": sideways,
		"head_on": head_on,
		# The player picks the approach, so the machine is only as blocked as
		# its BEST direction.
		"shortfall": minf(sideways, head_on),
	}


## Half the largest box collision shape on a machine, on XZ, in world units.
## The same shape `ACAMowerDeck` falls back to, read the same way.
static func _chassis_half_extents(machine: Node) -> Vector2:
	var best := Vector2.ZERO
	var node_scale := Vector3.ONE
	if machine is Node3D:
		node_scale = (machine as Node3D).transform.basis.get_scale()
	for node in machine.find_children("*", "CollisionShape3D", true, false):
		var box := (node as CollisionShape3D).shape as BoxShape3D
		if box == null:
			continue
		var size := box.size * node_scale
		if size.x * size.z > best.x * best.y * 4.0:
			best = Vector2(size.x, size.z) * 0.5
	return best
