class_name ACAMowerAttachment
extends Node3D
## WHAT IS BOLTED ON, AS GEOMETRY. The visible half of `ACAAttachments`.
##
## An upgrade in this game is a number. An attachment is a thing, and the point
## of making it a thing rather than a number is that the player can see what
## they bought on the machine they bought it for.
##
## ---------------------------------------------------------------------------
## BUILT, NOT IMPORTED
## ---------------------------------------------------------------------------
## The asset library has no bagger, no chute, no roller and no tow-behind
## sweeper, and none of the four is more than a handful of boxes and a cylinder
## at the size they are seen from. So they are built here from primitives in the
## project's own palette, and the SHAPE of the code is what matters: each one is
## a small function returning a node, and swapping any of them for a real model
## later is a change to that one function.
##
## ---------------------------------------------------------------------------
## IT NEVER TOUCHES GAMEPLAY
## ---------------------------------------------------------------------------
## No collision, no physics, no mass and no effect on the deck. What an
## attachment DOES lives in `ACAAttachments` and `ACAEquipment`; this is the
## picture of it. A machine with this node removed plays identically.
##
## PUBLIC API
##   static fit_to(mower: Node3D, fitted: Array) -> ACAMowerAttachment
##   rebuild(fitted: Array) -> void
##   visible_count() -> int
##
## SIGNALS: None.
##
## INVARIANTS
##   * NO COLLISION SHAPES, ever. What stops the machine is its chassis, and
##     `ACAMowerClearance` is derived from the chassis of the three canonical
##     machines - an attachment that could be hit would invalidate the clear
##     ground every solid feature on every property reserves.
##   * Everything is parented to the machine, so it travels with it and is
##     freed with it.

## ---------------------------------------------------------------------------
## EVERYTHING HERE IS A PROPORTION OF THE DECK, AND THE DECK IS WORLD UNITS
## ---------------------------------------------------------------------------
## `ACAMowerDeck` declares the cutting rectangle in WORLD units on each mower
## controller - the rider's is 5.6 by 2.4 - and every canonical machine is
## parented at scale one, so a proportion of that is a proportion of the real
## thing.
##
## THE DECK IS NOT THE MACHINE, and the first render of these showed exactly
## what happens when it is treated as one: a catcher sized off the deck's full
## WIDTH came out 6.4 units across and 2.4 tall, which is wider than the mower
## and half as tall again as its seat - a wall bolted to the back of a garden
## tractor. A catcher is about as wide as the BODY, which is a little under half
## the deck; a striping roller and a tow-behind sweeper are about as wide as the
## cut, because that is the job they are doing.
##
## The numbers below are those relationships, written down.

## Catcher: body-width, waist-high, and a little over half the deck deep.
const CATCHER_WIDTH := 0.42     ## of the deck's full width
const CATCHER_HEIGHT := 0.95    ## world units
const CATCHER_DEPTH := 1.25
## Gap between the back of the deck and the front of whatever is behind it.
const HITCH_GAP := 0.45

## Side chute: a short shroud clear of the deck's right-hand edge.
const CHUTE_LENGTH := 0.95
const CHUTE_HEIGHT := 0.42
const CHUTE_DEPTH := 1.05

## Striping roller: a drum across most of the cut, dragged just behind it.
const ROLLER_WIDTH := 0.82      ## of the deck's full width
const ROLLER_RADIUS := 0.34

## Tow-behind sweeper: as wide as the cut, on a drawbar of its own.
const SWEEPER_WIDTH := 0.92     ## of the deck's full width
const SWEEPER_HEIGHT := 0.9
const SWEEPER_DEPTH := 1.35
## The drawbar, from the back of the machine to the front of the hopper. Short:
## the first render measured the hitch off the machine's real geometry and then
## added a metre and a half to it, which parked the sweeper the best part of two
## machine-lengths behind the mower towing it.
const SWEEPER_BAR := 0.75

## The project's palette, so a bolt-on reads as part of the same fleet as the
## machine it is on.
const METAL := Color(0.404, 0.435, 0.412)
const DARK := Color(0.176, 0.196, 0.180)
const CANVAS := Color(0.325, 0.376, 0.298)
const ORANGE := Color(0.851, 0.478, 0.169)

var _built: Array[StringName] = []


## THE constructor. Hangs the visible pieces of `fitted` on the machine and
## returns the node holding them, or null when nothing fitted is visible.
static func fit_to(mower: Node3D, fitted: Array) -> ACAMowerAttachment:
	if mower == null:
		return null
	var node := ACAMowerAttachment.new()
	node.name = "Attachments"
	mower.add_child(node)
	node.rebuild(fitted)
	return node


## Replace what is hanging on the machine. Cheap enough to call whenever the
## loadout changes, which in practice is once per contract.
func rebuild(fitted: Array) -> void:
	for child in get_children():
		child.queue_free()
	_built.clear()

	# ---------------------------------------------------------------------
	# WHERE THE BACK OF THE MACHINE IS, MEASURED
	# ---------------------------------------------------------------------
	# The DECK is a cutting rectangle, not a machine: the rider's is 2.4 long
	# and the rider itself is well over twice that, because the model carries a
	# rear housing of its own. Hanging a bagger a deck-length behind the origin
	# therefore put it INSIDE the machine, which is exactly what the first
	# render showed - a catcher that had disappeared and a roller poking out
	# from under a wheel.
	#
	# So the hitch point is taken from the machine's own drawn geometry: the
	# back of every mesh it has, in its own local space. That is measured rather
	# than tabulated, so it is right for all three canonical machines and stays
	# right if any of them is ever re-modelled.
	var deck := ACAMowerDeck.for_mower(get_parent())
	var deck_half_width: float = deck.half_width if deck != null else 1.4
	var deck_half_length: float = deck.half_length if deck != null else 1.2
	var body := _machine_extent(get_parent())
	# BOUNDED AGAINST THE DECK. See `_machine_extent()` for both halves of why.
	var half_length: float = clampf(absf(float(body["back"])),
		deck_half_length * 1.15, deck_half_length * 3.2)
	var half_width: float = maxf(float(body["half_width"]), deck_half_width * 0.45)

	for entry: Variant in fitted:
		var id := StringName(String(entry))
		var visual := ACAAttachments.visual_id(id)
		if String(visual).is_empty():
			continue
		var piece: Node3D = null
		match String(visual):
			"bagger":
				piece = _bagger(half_length, half_width)
			"chute":
				# The chute hangs off the DECK's edge, because that is what it
				# is shrouding.
				piece = _chute(deck_half_width, half_width)
			"roller":
				piece = _roller(half_length, deck_half_width)
			"sweeper":
				piece = _sweeper(half_length, deck_half_width)
		if piece == null:
			continue
		piece.name = String(id).capitalize()
		add_child(piece)
		_built.append(id)


func visible_count() -> int:
	return _built.size()


## THE BACK OF THE MACHINE, in its own local space.
##
## Measured from what the machine DRAWS, and then bounded against the deck - and
## both halves of that are there because a render showed why:
##
##   MEASURED    the deck is a cutting rectangle, not a machine. The rider's is
##               2.4 long and the rider is well over twice that, so hanging a
##               towed attachment a deck-length behind the origin put it inside
##               the machine.
##   BOUNDED     a walk-behind's mesh includes its HANDLEBARS, which reach a
##               long way back and are not part of the machine in any sense a
##               drawbar cares about. Unbounded, that parked the sweeper the
##               best part of three metres off the back.
##
## Returns `{ back, half_width, top }`; `back` is already bounded. A machine
## with no meshes falls back to a value an attachment will not vanish inside.
static func _machine_extent(machine: Node) -> Dictionary:
	var fallback := {"back": -1.8, "half_width": 1.1, "top": 1.4}
	if machine == null or not (machine is Node3D):
		return fallback
	var root_transform: Transform3D = (machine as Node3D).global_transform.affine_inverse()
	var found := false
	var box := AABB()
	for node in machine.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		# Into the MACHINE's space, not the mesh's own: a model is usually a
		# child of a child, and its transform is part of where it really is.
		var local: Transform3D = root_transform * mesh_node.global_transform
		var piece: AABB = local * mesh_node.mesh.get_aabb()
		box = piece if not found else box.merge(piece)
		found = true
	if not found:
		return fallback
	return {
		"back": box.position.z,
		"half_width": maxf(box.size.x * 0.5, 0.6),
		"top": box.position.y + box.size.y,
	}


# ====================================================================== pieces

## THE CATCHER. A box behind the machine with a chute running into it from the
## deck, at body width rather than deck width - see the note at the top.
func _bagger(half_length: float, half_width: float) -> Node3D:
	var root := Node3D.new()
	var width: float = half_width * 2.0 * CATCHER_WIDTH
	var behind: float = -(half_length + HITCH_GAP + CATCHER_DEPTH * 0.5)
	var centre_y: float = CATCHER_HEIGHT * 0.5 + 0.35

	_box(root, Vector3(width, CATCHER_HEIGHT, CATCHER_DEPTH),
		Vector3(0.0, centre_y, behind), CANVAS)
	# The frame it sits on.
	_box(root, Vector3(width * 1.05, 0.12, CATCHER_DEPTH * 1.05),
		Vector3(0.0, centre_y - CATCHER_HEIGHT * 0.5, behind), DARK)
	# The chute, running forward from the box towards the deck's discharge side.
	_box(root, Vector3(width * 0.34, CATCHER_HEIGHT * 0.42, half_length * 0.9),
		Vector3(width * 0.32, centre_y,
			behind + CATCHER_DEPTH * 0.5 + half_length * 0.4), METAL)
	return root


## THE SIDE CHUTE. A short angled shroud off the right of the deck.
## `deck_half_width` is the DECK's, because a discharge shroud sits on the edge
## of the cut rather than on the edge of the machine.
func _chute(deck_half_width: float, _half_width: float) -> Node3D:
	var root := Node3D.new()
	var out: float = deck_half_width + CHUTE_LENGTH * 0.45
	var piece := _box(root, Vector3(CHUTE_LENGTH, CHUTE_HEIGHT, CHUTE_DEPTH),
		Vector3(out, 0.55, 0.2), METAL)
	# Angled down and back, the way a discharge shroud sits.
	piece.rotation = Vector3(0.0, 0.0, deg_to_rad(-16.0))
	return root


## THE STRIPING ROLLER. A weighted drum on two arms, dragged behind the deck.
func _roller(half_length: float, half_width: float) -> Node3D:
	var root := Node3D.new()
	var behind: float = -(half_length + HITCH_GAP * 0.8)
	var drum := CylinderMesh.new()
	drum.top_radius = ROLLER_RADIUS
	drum.bottom_radius = ROLLER_RADIUS
	drum.height = half_width * 2.0 * ROLLER_WIDTH
	drum.radial_segments = 14
	drum.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = drum
	instance.material_override = _material(DARK)
	instance.position = Vector3(0.0, ROLLER_RADIUS, behind - ROLLER_RADIUS)
	# A cylinder is authored on Y; the drum lies across the machine.
	instance.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
	root.add_child(instance)

	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.09, 0.09, HITCH_GAP + ROLLER_RADIUS * 2.0),
			Vector3(side * half_width * ROLLER_WIDTH * 0.9,
				ROLLER_RADIUS + 0.18, behind + HITCH_GAP * 0.2), METAL)
	return root


## THE TOW-BEHIND SWEEPER. A hopper on a drawbar with a brush under it and two
## wheels - the one attachment that reads as a machine of its own.
func _sweeper(half_length: float, half_width: float) -> Node3D:
	var root := Node3D.new()
	var width: float = half_width * 2.0 * SWEEPER_WIDTH
	var bar_end: float = -(half_length + HITCH_GAP + SWEEPER_BAR)
	var behind: float = bar_end - SWEEPER_DEPTH * 0.5
	var centre_y: float = SWEEPER_HEIGHT * 0.5 + 0.32

	# The drawbar, from the back of the deck to the front of the hopper.
	_box(root, Vector3(0.11, 0.11, SWEEPER_BAR),
		Vector3(0.0, 0.34, -(half_length + HITCH_GAP + SWEEPER_BAR * 0.5)), METAL)
	# The hopper.
	_box(root, Vector3(width, SWEEPER_HEIGHT, SWEEPER_DEPTH),
		Vector3(0.0, centre_y, behind), CANVAS)
	_box(root, Vector3(width * 1.03, 0.12, SWEEPER_DEPTH * 1.03),
		Vector3(0.0, centre_y - SWEEPER_HEIGHT * 0.5, behind), DARK)
	# The brush under its leading edge, and a strip of the fleet's own orange so
	# the thing reads as equipment rather than as a crate on wheels.
	_box(root, Vector3(width * 0.94, 0.24, 0.32),
		Vector3(0.0, 0.20, behind + SWEEPER_DEPTH * 0.42), ORANGE)

	for side in [-1.0, 1.0]:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.32
		wheel.bottom_radius = 0.32
		wheel.height = 0.16
		wheel.radial_segments = 12
		wheel.rings = 1
		var instance := MeshInstance3D.new()
		instance.mesh = wheel
		instance.material_override = _material(DARK)
		instance.position = Vector3(side * (width * 0.5 + 0.10), 0.32, behind)
		instance.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
		root.add_child(instance)
	return root


# ====================================================================== parts

func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _material(colour)
	parent.add_child(instance)
	return instance


func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.85
	material.metallic = 0.05
	return material
