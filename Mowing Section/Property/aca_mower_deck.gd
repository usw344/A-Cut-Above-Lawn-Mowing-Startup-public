class_name ACAMowerDeck
extends RefCounted
## ROLE
## The cutting footprint of one machine, in world units, and the one place that
## works out what that footprint is.
##
## THE DECK IS A GAMEPLAY PROPERTY, NOT A VISUAL ONE. It is declared in WORLD
## units on each mower controller, so re-scaling a mower model to look better
## can never quietly change how fast a lawn gets cut, how long a contract takes
## or whether a tank of fuel is enough to finish one.
##
## Every canonical mower declares its own, because they are not the same machine
## and approximating all three as one circle would make the rider pointless.
##
## PUBLIC API
##   ACAMowerDeck.for_mower(node) -> ACAMowerDeck
##   half_width / half_length / forward_offset   (world units)
##   corners(transform) -> PackedVector2Array    the deck outline on XZ
##
## SIGNALS: None.
##
## INVARIANTS
##   * Units are WORLD units and never scaled by the mower node's transform.
##   * `half_length` is along the machine's local +Z, which is forward for every
##     canonical mower.
##
## PERSISTENCE OWNERSHIP
##   None.

## Used when a mower declares nothing and carries no box collision either. Wide
## enough to cut, narrow enough to be obviously a fallback in a screenshot.
const FALLBACK_WIDTH := 4.6
const FALLBACK_LENGTH := 2.2

## When a deck has to be derived from a chassis collision box, the housing
## reaches past the wheels by this much. Only used for mowers that declare
## nothing.
const CHASSIS_TO_DECK := 1.35

var half_width: float = FALLBACK_WIDTH * 0.5
var half_length: float = FALLBACK_LENGTH * 0.5
## Offset along the machine's local +Z. Positive puts the deck in front.
var forward_offset: float = 0.0


static func make(width: float, length: float, forward: float = 0.0) -> ACAMowerDeck:
	var deck := ACAMowerDeck.new()
	deck.half_width = maxf(width, 0.1) * 0.5
	deck.half_length = maxf(length, 0.1) * 0.5
	deck.forward_offset = forward
	return deck


## Resolve a machine's deck. Declared constants win; a chassis box is the
## fallback; the constant above is the last resort.
static func for_mower(mower: Node) -> ACAMowerDeck:
	if mower == null:
		return make(FALLBACK_WIDTH, FALLBACK_LENGTH)

	var script: Script = mower.get_script() as Script
	if script != null:
		var constants: Dictionary = script.get_script_constant_map()
		if constants.has("DECK_WIDTH") and constants.has("DECK_LENGTH"):
			return make(
				float(constants["DECK_WIDTH"]),
				float(constants["DECK_LENGTH"]),
				float(constants.get("DECK_FORWARD", 0.0)))

	var box := _find_chassis_box(mower)
	if box != Vector3.ZERO:
		return make(box.x * CHASSIS_TO_DECK, box.z * 0.5, 0.0)

	return make(FALLBACK_WIDTH, FALLBACK_LENGTH)


## The largest box collision shape on the machine, in world units.
static func _find_chassis_box(mower: Node) -> Vector3:
	var best := Vector3.ZERO
	var scale := Vector3.ONE
	if mower is Node3D:
		scale = (mower as Node3D).transform.basis.get_scale()
	for node in mower.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		var box := shape_node.shape as BoxShape3D
		if box == null:
			continue
		var size: Vector3 = box.size * scale
		if size.x * size.z > best.x * best.z:
			best = size
	return best


## The deck outline on the XZ plane for a given machine transform, in world
## space, ordered around the rectangle.
func corners(machine: Transform3D) -> PackedVector2Array:
	var forward := machine.basis.z
	var right := machine.basis.x
	var f := Vector2(forward.x, forward.z)
	var r := Vector2(right.x, right.z)
	if f.length_squared() < 0.000001:
		f = Vector2(0.0, 1.0)
	if r.length_squared() < 0.000001:
		r = Vector2(1.0, 0.0)
	f = f.normalized()
	r = r.normalized()
	var centre := Vector2(machine.origin.x, machine.origin.z) + f * forward_offset
	var out := PackedVector2Array()
	out.append(centre + r * half_width + f * half_length)
	out.append(centre - r * half_width + f * half_length)
	out.append(centre - r * half_width - f * half_length)
	out.append(centre + r * half_width - f * half_length)
	return out
