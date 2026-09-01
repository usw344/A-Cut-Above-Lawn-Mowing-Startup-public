class_name ACABusinessYard
extends Node3D
## ROLE
## The business's own premises in the Town, and the one place the company's
## growth is a THING rather than a number on a dashboard.
##
## ---------------------------------------------------------------------------
## IT IS DRIVEN BY WHAT THE BUSINESS HAS ALREADY EARNED
## ---------------------------------------------------------------------------
## `ACABusiness` decides which of four states the premises are in, from money
## taken over the company's lifetime, how it is regarded, and how many machines
## it owns. THIS node only draws that. There is no separate level, no experience
## number and no yard currency: a bigger yard is what having done the work looks
## like.
##
##   STARTER      a shed, a work truck, and one machine on the ground
##   ESTABLISHED  a garage door, a trailer, and somewhere to put the clippings
##   GROWING      more machines parked, a compost bay, a van
##   LEADING      the whole yard in use, and a sign on it
##
## Each state ADDS to the one before it rather than replacing it, so the player
## sees the same yard they have always had with more in it. Nothing is ever
## taken away: the premises are what the business has built, and a quiet month
## does not demolish a garage.
##
## ---------------------------------------------------------------------------
## NO PEOPLE
## ---------------------------------------------------------------------------
## Machines, vehicles, a shed and a fence. Nobody works here, because nobody
## works anywhere in this game.
##
## PUBLIC API
##   apply_tier(tier: int)
##   tier() -> int
##
## SIGNALS: None.
##
## INVARIANTS
##   * NO COLLISION and NO PHYSICS. It is scenery on a fixed isometric camera
##     that nothing can walk into.
##   * Everything is built once, in `_ready()`, and then shown or hidden. A tier
##     change is `visible = true` on a handful of nodes rather than a rebuild.
##
## PERSISTENCE OWNERSHIP: None. `ACABusiness` owns the tier.

const TRUCK := "res://Assets/Vehicles and Mowers/Work Vehicles/truck.glb"
const TRAILER := "res://Assets/Vehicles and Mowers/Work Vehicles/truck-flat.glb"
const VAN := "res://Assets/Vehicles and Mowers/Work Vehicles/van.glb"
const MOWER := "res://Main Area/ACA_BusinessTown/Generated/Mower.tscn"
const CRATE := "res://Main Area/ACA_BusinessTown/Assets/Props/box_A.gltf"
const BIN := "res://Main Area/ACA_BusinessTown/Assets/Props/dumpster.gltf"
const FENCE := "res://Main Area/ACA_BusinessTown/Generated/SiteFence.tscn"

## THE TOWN'S CARS AND THE YARD'S TRUCK COME FROM DIFFERENT PACKS, and they are
## not authored at the same size. The Town parks KayKit cars at scale 1 and they
## are about a unit long; the Kenney truck is about two, so scaling it to 1 puts
## a pickup in the yard twice the length of the cars on the street outside it -
## which is what the first render showed.
##
## 1.2, against a yard scaled to 0.38 in the scene, lands the truck at about
## half a unit longer than a town car. That is the right relationship: a pickup
## IS bigger than a hatchback, and only by a bit.
const VEHICLE_SCALE := 1.2

## Materials the Town already uses, so the yard is made of the same town.
const CONCRETE := "res://Main Area/ACA_BusinessTown/Materials/concrete.tres"
const ASPHALT := "res://Main Area/ACA_BusinessTown/Materials/asphalt.tres"
const WOOD := "res://Main Area/ACA_BusinessTown/Materials/wood.tres"
const METAL := "res://Main Area/ACA_BusinessTown/Materials/metal_light.tres"

var _tier: int = -1
## `{ tier: [nodes that appear AT that tier] }`.
var _by_tier: Dictionary = {}


func _ready() -> void:
	_build()
	var business := get_node_or_null(^"/root/Business")
	if business != null:
		apply_tier(int(business.call(&"yard_tier")))
		business.connect(&"yard_tier_changed", apply_tier)
	else:
		apply_tier(ACABusiness.Yard.STARTER)


func tier() -> int:
	return _tier


## Show everything up to and including `value`. Additive by design: see the note
## at the top about the premises being what the business has built.
func apply_tier(value: int) -> void:
	_tier = clampi(value, ACABusiness.Yard.STARTER, ACABusiness.Yard.LEADING)
	for level: int in _by_tier:
		var shown := level <= _tier
		for node: Node3D in _by_tier[level]:
			if is_instance_valid(node):
				node.visible = shown


# ======================================================================= build

func _build() -> void:
	for level in [ACABusiness.Yard.STARTER, ACABusiness.Yard.ESTABLISHED,
			ACABusiness.Yard.GROWING, ACABusiness.Yard.LEADING]:
		_by_tier[level] = [] as Array[Node3D]

	# ---------------------------------------------------------------- starter
	# The hard standing the whole yard sits on, so the premises read as a plot
	# rather than as things left on the grass.
	_slab(Vector3(0.0, 0.02, 0.0), Vector3(9.0, 0.04, 6.0), ASPHALT,
		ACABusiness.Yard.STARTER)
	_shed(Vector3(-2.6, 0.0, -1.9), 3.4, 2.2, ACABusiness.Yard.STARTER)
	_vehicle(TRUCK, Vector3(2.2, 0.06, 1.4), 0.0, ACABusiness.Yard.STARTER)
	_prop(MOWER, Vector3(-0.2, 0.06, 1.9), 0.7, 1.0, ACABusiness.Yard.STARTER)
	_prop(CRATE, Vector3(-4.0, 0.06, 1.6), 0.2, 1.0, ACABusiness.Yard.STARTER)

	# ------------------------------------------------------------ established
	# A trailer behind the truck, a second bay on the shed, and a bin for the
	# clippings the business has started bringing home.
	_vehicle(TRAILER, Vector3(2.2, 0.06, -1.1), 0.0, ACABusiness.Yard.ESTABLISHED)
	_shed(Vector3(1.2, 0.0, -2.4), 2.6, 2.0, ACABusiness.Yard.ESTABLISHED)
	_prop(BIN, Vector3(-4.2, 0.06, -1.0), -PI * 0.5, 1.0,
		ACABusiness.Yard.ESTABLISHED)

	# ----------------------------------------------------------------- growing
	# More machines on the ground, a van, and the compost bay - three low timber
	# walls with a heap in them, which is what a yard that composts looks like.
	_prop(MOWER, Vector3(-1.1, 0.06, 2.2), -0.5, 1.0, ACABusiness.Yard.GROWING)
	_prop(MOWER, Vector3(0.7, 0.06, 2.3), 0.3, 1.0, ACABusiness.Yard.GROWING)
	_vehicle(VAN, Vector3(-3.2, 0.06, 2.4), PI * 0.5, ACABusiness.Yard.GROWING)
	_compost_bay(Vector3(3.6, 0.0, -2.2), ACABusiness.Yard.GROWING)

	# ----------------------------------------------------------------- leading
	# The plot is full, it is fenced, and it has the company's name on it - in
	# paint on a board, which is as close to a person as this game gets.
	for i in 4:
		_prop(FENCE, Vector3(-4.4 + float(i) * 2.3, 0.06, -3.0), 0.0, 1.0,
			ACABusiness.Yard.LEADING)
	_prop(CRATE, Vector3(-4.3, 0.06, 0.4), -0.3, 1.0, ACABusiness.Yard.LEADING)
	_sign(Vector3(-4.6, 0.0, 2.9), ACABusiness.Yard.LEADING)


# ======================================================================= parts

func _slab(at: Vector3, size: Vector3, material_path: String, level: int) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = "Slab"
	instance.mesh = mesh
	instance.position = at
	instance.material_override = load(material_path)
	_add(instance, level)


## A simple open-fronted shed: two side walls, a back, and a roof. Built rather
## than instanced because the Town has no shed model and four boxes is cheaper
## than importing one.
func _shed(at: Vector3, width: float, depth: float, level: int) -> void:
	var root := Node3D.new()
	root.name = "Shed"
	root.position = at
	_add(root, level)

	var height := 1.7
	var wall := load(WOOD)
	var roof := load(METAL)

	for side in [-1.0, 1.0]:
		var panel := BoxMesh.new()
		panel.size = Vector3(0.12, height, depth)
		_piece(root, panel, wall, Vector3(side * width * 0.5, height * 0.5, 0.0))

	var back := BoxMesh.new()
	back.size = Vector3(width, height, 0.12)
	_piece(root, back, wall, Vector3(0.0, height * 0.5, -depth * 0.5))

	var top := BoxMesh.new()
	top.size = Vector3(width + 0.3, 0.12, depth + 0.3)
	_piece(root, top, roof, Vector3(0.0, height + 0.06, 0.0))


## Three low timber walls with a heap of clippings in them.
func _compost_bay(at: Vector3, level: int) -> void:
	var root := Node3D.new()
	root.name = "Compost Bay"
	root.position = at
	_add(root, level)

	var wall := load(WOOD)
	var height := 0.55
	for side in [-1.0, 1.0]:
		var panel := BoxMesh.new()
		panel.size = Vector3(0.1, height, 1.8)
		_piece(root, panel, wall, Vector3(side * 0.9, height * 0.5, 0.0))
	var back := BoxMesh.new()
	back.size = Vector3(1.9, height, 0.1)
	_piece(root, back, wall, Vector3(0.0, height * 0.5, -0.9))

	# The heap itself. A flattened sphere is a pile of grass at this distance,
	# and it is the one green thing in the yard that is not a machine.
	var heap := SphereMesh.new()
	heap.radius = 0.8
	heap.height = 0.9
	heap.radial_segments = 10
	heap.rings = 5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.33, 0.38, 0.20)
	material.roughness = 0.95
	heap.surface_set_material(0, material)
	_piece(root, heap, null, Vector3(0.0, 0.28, -0.1))


## The company's board. NO NAME ON IT beyond the game's own: the business has no
## proprietor, and inventing one would put a person in a world that has none.
func _sign(at: Vector3, level: int) -> void:
	var root := Node3D.new()
	root.name = "Yard Sign"
	root.position = at
	_add(root, level)

	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.9, 0.12)
	_piece(root, post, load(WOOD), Vector3(0.0, 0.95, 0.0))

	var board := BoxMesh.new()
	board.size = Vector3(2.2, 0.7, 0.08)
	var painted := StandardMaterial3D.new()
	painted.albedo_color = Color(0.243, 0.435, 0.278)
	painted.roughness = 0.8
	board.surface_set_material(0, painted)
	_piece(root, board, null, Vector3(0.0, 1.75, 0.0))

	var stripe := BoxMesh.new()
	stripe.size = Vector3(1.7, 0.12, 0.02)
	var cream := StandardMaterial3D.new()
	cream.albedo_color = Color(0.949, 0.925, 0.867)
	stripe.surface_set_material(0, cream)
	_piece(root, stripe, null, Vector3(0.0, 1.75, 0.06))


func _vehicle(path: String, at: Vector3, yaw: float, level: int) -> void:
	_prop(path, at, yaw, VEHICLE_SCALE, level)


func _prop(path: String, at: Vector3, yaw: float, scale: float,
		level: int) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[YARD] could not load %s" % path)
		return
	var node := packed.instantiate() as Node3D
	if node == null:
		return
	node.position = at
	node.rotation.y = yaw
	node.scale = Vector3.ONE * scale
	_add(node, level)


func _piece(parent: Node3D, mesh: Mesh, material: Material,
		at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	if material != null:
		instance.material_override = material
	parent.add_child(instance)


func _add(node: Node3D, level: int) -> void:
	add_child(node)
	node.visible = false
	(_by_tier[level] as Array[Node3D]).append(node)
