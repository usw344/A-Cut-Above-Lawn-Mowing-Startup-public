class_name ACAPropertySurrounds
extends ACAPropertyFeature
## ROLE
## What stands OUTSIDE the fence on a suburban or a landscaped property: the
## house, the neighbours, the street, the driveway, the car park.
##
## ---------------------------------------------------------------------------
## BACKGROUND, NOT PLAYABLE, AND THE DIFFERENCE IS ABSOLUTE
## ---------------------------------------------------------------------------
## Everything this class builds is on the far side of `ACAPropertyBoundary`.
## The machine cannot reach any of it, ever, because the boundary is a solid
## wall the whole way round. So:
##
##   * NOTHING here has a collision body. Not one. A house the player cannot
##     drive to does not need to be able to stop them.
##   * Nothing here counts towards anything. It is not in the mowing
##     denominator, it does not change the pay, and it does not change how long
##     a contract takes.
##
## What it changes is the only thing that matters here, which is what the
## property LOOKS like from the seat. A residential contract that is a lawn in a
## clearing is a rural contract with a different name on the card. A residential
## contract with a house at the end of the garden, a fence between it and next
## door, and a street beyond that, is a residential contract.
##
## ---------------------------------------------------------------------------
## IT IS A FEATURE, WHICH IS HOW IT KEEPS THE TREES OUT OF THE HOUSES
## ---------------------------------------------------------------------------
## The obvious first version of this was a plain Node3D that placed some
## buildings. That version put trees through the roof of every house, because
## `ACAForest` plants the whole band outside the boundary and had no way to know
## a house was there.
##
## So this is an `ACAPropertyFeature` instead, and it answers the interface the
## forest already asks:
##
##   blocks_foliage()  TRUE   - no tree is planted through a wall
##   blocks_grass()    TRUE   - no lawn tufts under a driveway
##   blocks_mowing()   FALSE  - it is outside the lawn, and if a footprint ever
##                              did clip the lawn it must NOT quietly remove
##                              ground the player is being paid to cut
##   is_solid()        FALSE  - no collision, so it owes the deck no clearance
##
## The layout is decided in `for_params()`, which is pure and runs before the
## terrain exists; the nodes are built in `build_nodes()`, which runs after, so
## every building can be stood on ground that was measured rather than assumed.
##
## PUBLIC API
##   ACAPropertySurrounds.for_params(params, property_centre)
##   plots() -> Array[Dictionary]     what was laid out, for diagnostics
##   count()
##   plus the whole ACAPropertyFeature interface
##
## SIGNALS: None.
##
## INVARIANTS
##   * Every plot is entirely OUTSIDE `params.boundary_half_extent()`.
##   * The -X side is left clear: `ACAProperty.mower_start_transform()` brings
##     the machine in from there, and a house in the arrival view is a house the
##     player drives at.
##   * Layout is a pure function of the seed, the lawn size and the archetype.
##
## PERSISTENCE OWNERSHIP
##   None. Rebuilt from ACAPropertyParams.

## ---------------------------------------------------------------------------
## THE MODEL SET
## ---------------------------------------------------------------------------
## A SMALL RUNTIME SUBSET, chosen from the Quaternius building pack in the asset
## dump. `_Mat` variants: they carry their own material colours in an .mtl and
## need no texture, which is what makes them safe to stand next to the
## flat-shaded low-poly world without importing a palette to go with them.
##
## `width` is the target width in WORLD units, not a scale factor - a world unit
## is about a quarter of a metre, so a thirty-unit house is about seven and a
## half metres across, which is a house.
const HOUSES := [
	{"path": "res://Assets/Buildings/Low Poly/1Story_GableRoof_Mat.obj", "width": 30.0},
	{"path": "res://Assets/Buildings/Low Poly/2Story_GableRoof_Mat.obj", "width": 31.0},
	{"path": "res://Assets/Buildings/Low Poly/1Story_Mat.obj", "width": 28.0},
	{"path": "res://Assets/Buildings/Low Poly/2Story_Sidehouse_Mat.obj", "width": 42.0},
	{"path": "res://Assets/Buildings/Low Poly/1Story_RoundRoof_Mat.obj", "width": 26.0},
]
## Bigger, plainer blocks for grounds rather than gardens.
const INSTITUTIONS := [
	{"path": "res://Assets/Buildings/Low Poly/4Story_Wide_2Doors_Mat.obj", "width": 78.0},
	{"path": "res://Assets/Buildings/Low Poly/2Story_Wide_Mat.obj", "width": 58.0},
	{"path": "res://Assets/Buildings/Low Poly/3Story_Small_Mat.obj", "width": 40.0},
]

## ---------------------------------------------------------------------------
## HOUSE COLOURS
## ---------------------------------------------------------------------------
## The Quaternius pack's own palette is a dark, desaturated blue-teal - handsome
## in isolation, and against a bright green lawn under a warm sun it renders as
## a row of unlit silhouettes. The first render of this class was five black
## houses at the end of a garden.
##
## Each building is therefore given a seeded tint, MULTIPLIED over the model's
## own material colours rather than replacing them. That matters: multiplying
## keeps the relationship between a wall, its roof, its door and its windows, so
## a tinted house is still a house with a darker roof. Replacing them would give
## five monochrome boxes.
##
## Five house tints and two building tints, all warm, all above one on every
## channel because the source is dark.
const HOUSE_TINTS := [
	Color(2.35, 2.05, 1.62),
	Color(1.62, 1.98, 1.55),
	Color(2.55, 1.78, 1.34),
	Color(1.92, 2.00, 1.96),
	Color(2.48, 2.24, 1.58),
]
## PUSHED HARDER THAN THE HOUSES. The institutional models are the darkest in
## the pack - a four storey office rendered at the pack's own values is a black
## slab on the skyline, which is what the first render of a landscaped property
## showed. Bright channels clip to white, and a pale stone building is meant to.
const INSTITUTION_TINTS := [
	Color(2.65, 2.60, 2.42),
	Color(2.35, 2.45, 2.30),
]

## Surfaces. Flat boxes rather than planes, because a plane exactly on a
## generated terrain fights it for depth on any slope at all.
const SURFACE_THICKNESS := 0.5
const ROAD_COLOUR := Color(0.208, 0.208, 0.216)
const KERB_COLOUR := Color(0.639, 0.627, 0.588)
const DRIVE_COLOUR := Color(0.541, 0.529, 0.494)
const LOT_COLOUR := Color(0.184, 0.188, 0.196)
const LINE_COLOUR := Color(0.855, 0.847, 0.804)

## How far past the fence the nearest built thing starts. Enough that a house
## does not appear to be leaning on the boundary.
const SETBACK := 9.0
## How much ground each plot reserves around itself, for the foliage exclusion.
## Generous: a tree half inside a wall is worse than a gap.
const PLOT_MARGIN := 4.0

enum PlotKind { HOUSE, INSTITUTION, ROAD, DRIVE, LOT, KERB, LINE }

var _plots: Array[Dictionary] = []
var _bounds := AABB()
var _nodes := 0


## THE constructor. Returns a surrounds with no plots at all for the two
## archetypes that do not have any, which costs the feature set one empty
## rectangle and nothing else.
static func for_params(params: ACAPropertyParams,
		property_centre: Vector2) -> ACAPropertySurrounds:
	var f := ACAPropertySurrounds.new()
	if params != null and ACAPropertyArchetype.has_surrounds(params.archetype):
		f._lay_out(params, property_centre)
	return f


func feature_id() -> StringName:
	return &"surrounds"


func count() -> int:
	return _plots.size()


func plots() -> Array[Dictionary]:
	return _plots.duplicate(true)


# ==================================================================== layout

func _lay_out(params: ACAPropertyParams, centre: Vector2) -> void:
	# A SEPARATE stream, keyed off the property seed, so surrounds could be
	# added without moving a single draw in `ACAPropertyParams.for_seed()`.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(params.seed, 88413))
	var half := params.boundary_half_extent()
	if params.archetype == ACAPropertyArchetype.Kind.SUBURBAN:
		_lay_out_suburban(rng, centre, half)
	else:
		_lay_out_landscaped(rng, centre, half)
	_recompute_bounds()


## ---------------------------------------------------------------------------
## SUBURBAN: a garden with a house on it, in a street of houses
## ---------------------------------------------------------------------------
## Read outward from the lawn on the +X side, which is the side the machine did
## NOT arrive from:
##
##   the fence  |  the house  |  the front garden  |  the pavement  |  the road
##
## and then the neighbours, one either side across their own fences, and a row
## of houses facing back across the road. That row is what turns a house at the
## end of a garden into a NEIGHBOURHOOD, and it is three buildings.
func _lay_out_suburban(rng: RandomNumberGenerator, centre: Vector2,
		half: float) -> void:
	var house_x: float = centre.x + half + SETBACK + 16.0
	var road_x: float = house_x + 44.0
	var road_width := 26.0

	# THE HOUSE. Turned to face the lawn, so what the player sees over the fence
	# is a front elevation with windows in it rather than a blank gable.
	_add_building(HOUSES, rng, Vector2(house_x, centre.y + rng.randf_range(-14.0, 14.0)),
		-PI * 0.5, PlotKind.HOUSE, 1.0)

	# The drive, from the house down to the road - and STOPPING at the kerb.
	# The first version ran it twelve units past the road's centre line, so on
	# every suburban property the driveway crossed the street and came out the
	# far side.
	var drive_far: float = road_x - road_width * 0.5
	var drive_length: float = drive_far - house_x
	_add_surface(PlotKind.DRIVE,
		Vector2((house_x + drive_far) * 0.5, centre.y + 20.0),
		Vector2(drive_length, 13.0), 0.0)

	# The road, and a pavement on the near side of it.
	_add_surface(PlotKind.ROAD, Vector2(road_x, centre.y),
		Vector2(road_width, half * 2.6), 0.0)
	_add_surface(PlotKind.KERB, Vector2(road_x - road_width * 0.5 - 5.0, centre.y),
		Vector2(10.0, half * 2.6), 0.0)
	# The centre line, in dashes, because an unbroken white stripe on a
	# residential street reads as a runway.
	var dash_count := int(half * 2.2 / 18.0)
	for i in dash_count:
		var z: float = centre.y - half * 1.1 + 18.0 * (float(i) + 0.5)
		_add_surface(PlotKind.LINE, Vector2(road_x, z), Vector2(1.2, 8.0), 0.0)

	# The neighbours, one on each side of the garden.
	for side in [-1.0, 1.0]:
		_add_building(HOUSES, rng,
			Vector2(centre.x + rng.randf_range(-half * 0.35, half * 0.35),
				centre.y + side * (half + SETBACK + 19.0)),
			PI if side < 0.0 else 0.0, PlotKind.HOUSE, 0.92)

	# The row across the road. Facing back this way, so the street has two sides.
	for i in 3:
		_add_building(HOUSES, rng,
			Vector2(road_x + road_width * 0.5 + 24.0,
				centre.y + (float(i) - 1.0) * 46.0 + rng.randf_range(-6.0, 6.0)),
			PI * 0.5, PlotKind.HOUSE, rng.randf_range(0.86, 1.02))


## ---------------------------------------------------------------------------
## LANDSCAPED: grounds in front of a building, with somewhere to park
## ---------------------------------------------------------------------------
## One large building filling the far side, a car park beside it with marked
## bays, and an access road leaving the site. The building is what tells the
## player this is a clinic or an office rather than somebody's garden, so it is
## deliberately the biggest thing on any generated property.
func _lay_out_landscaped(rng: RandomNumberGenerator, centre: Vector2,
		half: float) -> void:
	var building_x: float = centre.x + half + SETBACK + 20.0
	_add_building(INSTITUTIONS, rng, Vector2(building_x, centre.y),
		-PI * 0.5, PlotKind.INSTITUTION, 1.0)

	# The car park, off to one side of the building and squarely on the grid,
	# because a landscaped site is a site somebody drew.
	var lot_side: float = 1.0 if rng.randf() < 0.5 else -1.0
	var lot_centre := Vector2(building_x - 6.0,
		centre.y + lot_side * (half * 0.55 + 30.0))
	var lot_size := Vector2(56.0, 40.0)
	_add_surface(PlotKind.LOT, lot_centre, lot_size, 0.0)
	var bays := 5
	for i in bays:
		var x: float = lot_centre.x - lot_size.x * 0.5 \
			+ lot_size.x * (float(i) + 1.0) / float(bays + 1)
		_add_surface(PlotKind.LINE, Vector2(x, lot_centre.y),
			Vector2(1.0, lot_size.y * 0.72), 0.0)

	# The access road, running from the car park out past the building.
	_add_surface(PlotKind.ROAD,
		Vector2(building_x + 30.0, centre.y + lot_side * half * 0.25),
		Vector2(20.0, half * 1.8), 0.0)
	_add_surface(PlotKind.DRIVE,
		Vector2((lot_centre.x + building_x + 30.0) * 0.5, lot_centre.y),
		Vector2(building_x + 30.0 - lot_centre.x, 14.0), 0.0)

	# A second, smaller block on one flank, so the site reads as a campus rather
	# than as one building on a field.
	_add_building(INSTITUTIONS, rng,
		Vector2(centre.x + rng.randf_range(-half * 0.3, half * 0.2),
			centre.y - lot_side * (half + SETBACK + 26.0)),
		0.0 if lot_side > 0.0 else PI, PlotKind.INSTITUTION, 0.7)


func _add_building(catalogue: Array, rng: RandomNumberGenerator, at: Vector2,
		yaw: float, kind: PlotKind, scale: float) -> void:
	var pick: int = rng.randi() % catalogue.size()
	var entry: Dictionary = catalogue[pick]
	var width: float = float(entry["width"]) * scale
	var tints: Array = INSTITUTION_TINTS if kind == PlotKind.INSTITUTION else HOUSE_TINTS
	_plots.append({
		"kind": kind,
		"position": at,
		"yaw": yaw + rng.randf_range(-0.03, 0.03),
		"path": String(entry["path"]),
		"width": width,
		"tint": rng.randi() % tints.size(),
		# The footprint reserved from the foliage. Square and generous; the
		# exact depth of a given model is not worth resolving for a rectangle
		# whose only job is to keep a tree out.
		"extent": Vector2(width * 0.62, width * 0.62),
	})


func _add_surface(kind: PlotKind, at: Vector2, size: Vector2, yaw: float) -> void:
	_plots.append({
		"kind": kind,
		"position": at,
		"yaw": yaw,
		"size": size,
		"extent": size * 0.5,
	})


func _recompute_bounds() -> void:
	if _plots.is_empty():
		_bounds = AABB()
		return
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for plot: Dictionary in _plots:
		var at: Vector2 = plot["position"]
		# Rotation-agnostic: the extent is grown to its own diagonal so a turned
		# plot is still inside the rectangle whatever its yaw.
		var reach: float = (plot["extent"] as Vector2).length() + PLOT_MARGIN
		min_x = minf(min_x, at.x - reach)
		min_z = minf(min_z, at.y - reach)
		max_x = maxf(max_x, at.x + reach)
		max_z = maxf(max_z, at.y + reach)
	_bounds = AABB(Vector3(min_x, -400.0, min_z),
		Vector3(max_x - min_x, 800.0, max_z - min_z))


# ================================================================== interface

func bounds() -> AABB:
	return _bounds


## Surrounds sit ON the ground. Nothing here digs or raises the terrain: a
## driveway on a slope is a driveway on a slope.
func terrain_offset_at(_x: float, _z: float) -> float:
	return 0.0


## NO COLLISION ANYWHERE, so no clearance is owed. The boundary is what stops
## the player, and it stops them well before any of this.
func is_solid() -> bool:
	return false


## THE ONE THAT MATTERS: this must not remove ground from the mowing total.
## Every plot is outside the boundary and therefore outside the lawn, so in
## practice it never would - but a layout bug that put a driveway over the lawn
## should show up as a driveway drawn on the grass, which is obvious, rather
## than as a contract that silently finishes at ninety-four per cent, which is
## not.
func blocks_mowing() -> bool:
	return false


func exclusion_at(x: float, z: float, _ground_y: float) -> float:
	var point := Vector2(x, z)
	for plot: Dictionary in _plots:
		var local := (point - (plot["position"] as Vector2)).rotated(-float(plot["yaw"]))
		var extent: Vector2 = plot["extent"]
		if absf(local.x) <= extent.x + PLOT_MARGIN \
				and absf(local.y) <= extent.y + PLOT_MARGIN:
			return 1.0
	return 0.0


# ====================================================================== nodes

## Buildings are batched per model into one MultiMesh each; surfaces are one
## MeshInstance3D apiece, because there are a dozen of them and they are all
## different sizes.
func build_nodes(parent: Node3D, terrain: Node3D, _params: ACAPropertyParams) -> void:
	if parent == null or _plots.is_empty():
		return
	var batches: Dictionary = {}
	for i in _plots.size():
		var plot: Dictionary = _plots[i]
		var kind: int = int(plot["kind"])
		if kind == PlotKind.HOUSE or kind == PlotKind.INSTITUTION:
			_batch_building(batches, plot, terrain)
		else:
			_build_surface(parent, plot, terrain, i)
	for key in batches:
		var batch: Dictionary = batches[key]
		_commit(parent, batch["mesh"], batch["transforms"], batch["tint"] as Color)


## Batched by MODEL AND TINT together, so two houses of the same model in two
## different colours are two MultiMeshes rather than one. On a suburban property
## that is six batches at worst, which is six draw calls for a neighbourhood.
func _batch_building(batches: Dictionary, plot: Dictionary,
		terrain: Node3D) -> void:
	var path: String = String(plot["path"])
	var kind: int = int(plot["kind"])
	var tints: Array = INSTITUTION_TINTS if kind == PlotKind.INSTITUTION else HOUSE_TINTS
	var tint_index: int = int(plot.get("tint", 0)) % tints.size()
	var key := "%s|%d" % [path, tint_index]
	if not batches.has(key):
		var mesh := _load_mesh(path)
		if mesh == null:
			return
		var aabb := mesh.get_aabb()
		batches[key] = {
			"mesh": mesh,
			"tint": tints[tint_index] as Color,
			"unit_width": maxf(maxf(aabb.size.x, aabb.size.z), 0.001),
			"transforms": PackedFloat32Array(),
		}
	var batch: Dictionary = batches[key]
	var scale: float = float(plot["width"]) / float(batch["unit_width"])
	var at: Vector2 = plot["position"]
	var ground: float = float(terrain.call(&"height_at", at.x, at.y)) \
		if terrain != null and terrain.has_method(&"height_at") else 0.0
	var basis := Basis(Vector3.UP, float(plot["yaw"])) \
		.scaled(Vector3(scale, scale, scale))
	# SET SLIGHTLY IN. These models sit on y = 0 exactly, and on generated ground
	# that leaves a hairline of daylight under one corner of every wall.
	_append(batch["transforms"], Transform3D(basis, Vector3(at.x, ground - 0.35, at.y)))


## A flat box laid on the ground, following it at its centre. Roads and
## driveways here are short enough relative to the terrain's flattening that one
## height sample is not visibly wrong; the alternative is a strip mesh per
## surface, which is a lot of geometry for scenery the player cannot walk on.
func _build_surface(parent: Node3D, plot: Dictionary, terrain: Node3D,
		index: int) -> void:
	var size: Vector2 = plot["size"]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, SURFACE_THICKNESS, size.y)

	var material := StandardMaterial3D.new()
	material.albedo_color = _surface_colour(int(plot["kind"]))
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var instance := MeshInstance3D.new()
	instance.name = "Surround Surface %d" % index
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

	var at: Vector2 = plot["position"]
	var ground: float = float(terrain.call(&"height_at", at.x, at.y)) \
		if terrain != null and terrain.has_method(&"height_at") else 0.0
	# Lines sit a whisker proud of the tarmac they are painted on.
	var lift: float = 0.06 if int(plot["kind"]) == PlotKind.LINE else 0.0
	instance.transform = Transform3D(Basis(Vector3.UP, float(plot["yaw"])),
		Vector3(at.x, ground - SURFACE_THICKNESS * 0.5 + 0.08 + lift, at.y))


static func _surface_colour(kind: int) -> Color:
	match kind:
		PlotKind.ROAD:
			return ROAD_COLOUR
		PlotKind.KERB:
			return KERB_COLOUR
		PlotKind.LOT:
			return LOT_COLOUR
		PlotKind.LINE:
			return LINE_COLOUR
		_:
			return DRIVE_COLOUR


func _commit(parent: Node3D, mesh: Mesh, transforms: PackedFloat32Array,
		tint: Color) -> void:
	var count := transforms.size() / 12
	if count <= 0:
		return
	# A TINTED COPY OF THE MESH, not of its material. These models carry eight
	# surfaces with eight different materials - wall, roof, door, glass and so
	# on - and a `material_override` would collapse all eight into one flat
	# colour, which is the difference between a house and a coloured box. So the
	# mesh is rebuilt with each surface's OWN material duplicated and multiplied.
	var tinted := _tinted_mesh(mesh, tint)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = tinted
	multimesh.instance_count = count
	multimesh.buffer = transforms

	var instance := MultiMeshInstance3D.new()
	instance.name = "Surround Buildings %d" % _nodes
	instance.multimesh = multimesh
	# These DO cast shadows. A house with no shadow beside a fence that has one
	# reads as a cardboard cut-out, and the house is the whole point.
	instance.extra_cull_margin = 20.0
	parent.add_child(instance)
	_nodes += 1


## A copy of `mesh` whose every surface keeps its own material, duplicated and
## multiplied by `tint`. The source materials are SHARED resources, so they are
## duplicated rather than edited - writing to one would recolour every other use
## of that model in the project.
static func _tinted_mesh(mesh: Mesh, tint: Color) -> Mesh:
	if mesh == null:
		return null
	var out := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			mesh.surface_get_arrays(surface))
		var source := mesh.surface_get_material(surface) as BaseMaterial3D
		if source == null:
			continue
		var copy := source.duplicate() as BaseMaterial3D
		copy.albedo_color = Color(
			minf(source.albedo_color.r * tint.r, 1.0),
			minf(source.albedo_color.g * tint.g, 1.0),
			minf(source.albedo_color.b * tint.b, 1.0),
			source.albedo_color.a)
		# Flat and matte, like everything else on the property. The pack ships
		# these with a specular highlight that reads as wet plastic outdoors.
		copy.roughness = 0.95
		copy.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		out.surface_set_material(surface, copy)
	return out


static func _load_mesh(path: String) -> Mesh:
	var mesh := load(path) as Mesh
	if mesh != null:
		return mesh
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[SURROUNDS] could not load %s" % path)
		return null
	var instance := packed.instantiate()
	var found := _first_mesh(instance)
	instance.free()
	return found


static func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


static func _append(into: PackedFloat32Array, t: Transform3D) -> void:
	var b := t.basis
	var o := t.origin
	into.append_array(PackedFloat32Array([
		b.x.x, b.y.x, b.z.x, o.x,
		b.x.y, b.y.y, b.z.y, o.y,
		b.x.z, b.y.z, b.z.z, o.z,
	]))
