class_name ACAPropertyBoundary
extends Node3D
## ROLE
## THE edge of the playable property: the collision that stops the machine, and
## the fence that tells the player why it stopped.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## The world around a contract is scenery. It has hills, a treeline and a
## horizon three kilometres out, and none of it is anywhere the player is meant
## to drive. Before this class, nothing said so: the machine could leave the
## lawn, cross the yard, drive through the wood - the trees are MultiMeshes and
## have never had collision - and eventually run off the edge of the terrain
## collision at forty-four units past the lawn, where the world simply stops.
##
## A boundary here is what makes the rest of the collision model honest. Once
## the player physically cannot reach the scenery, the scenery does not need
## physics bodies, and this property keeps exactly the one it always had (the
## terrain heightmap) plus this one.
##
## ---------------------------------------------------------------------------
## ONE RECTANGLE, DERIVED, NEVER DUPLICATED
## ---------------------------------------------------------------------------
## The boundary is the lawn rectangle grown by `ACAPropertyParams.boundary_margin()`
## and nothing else. It is not a second description of the property that could
## drift out of step with the first: change the lawn size and the fence moves,
## reload a save and it rebuilds in the same place, because the only inputs are
## the parameters the save already stores.
##
## `ACAForest` asks the same question through the same method, which is why no
## tree, shrub or rock is ever planted on the wrong side of the fence.
##
## PUBLIC API
##   build(params, terrain, lawn)
##   half_extent() / centre() / rect()
##   contains(x, z) / distance_outside(x, z)
##   treatment() / statistics()
##
## SIGNALS: None.
##
## INVARIANTS
##   * The collision is ONE StaticBody3D. Segments are collision SHAPES on it,
##     not bodies of their own.
##   * The wall spans from below the lowest ground under it to well above the
##     highest, so no slope inside the property can be used to drive over it.
##   * Nothing here is saved. It is rebuilt from ACAPropertyParams.
##
## PERSISTENCE OWNERSHIP: None.

## Spacing between fence posts, in world units. This world is about four times
## life size, so five units is a bit under a metre and a half of real fence.
const POST_SPACING := 5.0
## Post cross-section and height, in world units.
const POST_THICKNESS := 0.30
const POST_HEIGHT := 3.9
## Rail cross-section. Rails run post to post at the heights below.
const RAIL_THICKNESS := 0.16
const RAIL_DEPTH := 0.24
const RAIL_HEIGHTS := [3.15, 1.85]
## The single rail a `low_rail` property gets.
const LOW_RAIL_HEIGHTS := [2.0]

## Collision segment length. Shorter follows the ground more closely and costs
## one more shape; five units matches the post spacing, so a segment and a fence
## bay are the same span and the wall can never be seen to disagree with the
## fence in front of it.
const SEGMENT_LENGTH := 5.0
## How thick the invisible wall is, in world units. Thin enough to hide behind
## a fence post, thick enough that a machine at speed cannot tunnel it -
## the mower moves a small fraction of this per physics step at 576 Hz.
const WALL_THICKNESS := 0.9
## How far the wall rises above the highest ground under its segment, and drops
## below the lowest. Generous vertically because it costs nothing: a box is a
## box whatever its height.
const WALL_RISE := 5.0
const WALL_SINK := 4.0

## Weathered cedar. No texture: the whole property is flat-shaded low poly and a
## wood grain on a fence would be the only mapped surface in the frame.
const POST_COLOUR := Color(0.404, 0.310, 0.216)
const RAIL_COLOUR := Color(0.478, 0.376, 0.263)

## The visual treatments a property edge can be given. Every one of them puts
## POSTS on the line, because a boundary the player cannot see is a boundary the
## player thinks is a bug. What varies is how much fence is between them.
enum Treatment {
	## Posts and two rails the whole way round. The classic rural property line.
	RUSTIC_RAIL,
	## Posts and one low rail. More open, and lets the wood behind it read.
	LOW_RAIL,
	## Posts only, at a wider spacing, with the wood and the shrubs behind them
	## closing the gaps. A property whose edge is a treeline rather than a fence.
	MARKER_POSTS,
}

var _params: ACAPropertyParams = null
var _terrain: ACATerrain = null
var _centre := Vector3.ZERO
var _half := 0.0
var _treatment: int = Treatment.RUSTIC_RAIL
var _body: StaticBody3D = null
var _stats := {}


# ======================================================================= build

func build(params: ACAPropertyParams, terrain: ACATerrain, lawn: ACALawn) -> void:
	_params = params
	_terrain = terrain
	_centre = lawn.lawn_centre() if lawn != null else global_position
	_half = params.lawn_half_extent() + params.boundary_margin()
	_treatment = _roll_treatment(params)
	_clear()

	var t0 := Time.get_ticks_usec()
	var segments := _build_collision()
	var t_collision := Time.get_ticks_usec()
	var posts := _build_fence()
	var t_fence := Time.get_ticks_usec()

	_stats = {
		"half_extent": _half,
		"margin": params.boundary_margin(),
		"treatment": treatment_name(_treatment),
		"segments": segments,
		"posts": posts,
		"bodies": 1,
		"collision_ms": float(t_collision - t0) / 1000.0,
		"fence_ms": float(t_fence - t_collision) / 1000.0,
	}


## The treatment is a pure function of the property seed AND of what kind of
## place this is, so the same address always has the same fence and the fence
## always suits the address. It is NOT a new generator draw: taking it from a
## hash of the seed rather than from `for_seed()`'s RandomNumberGenerator is
## what keeps every existing property exactly where it was.
##
## THE EDGE IS HOW A PROPERTY EXPLAINS ITS OWN WALL. The playable boundary is
## the same invisible line whatever is drawn on it, and the player should never
## meet it as a surprise - so each archetype gets the edge its kind of place
## would really have:
##
##   suburban    a real fence, always. A garden has a boundary, and the
##               neighbouring gardens are right behind it.
##   landscaped  a fence at every post but a LOW one: managed grounds are
##               edged rather than fenced in, and the building behind wants to
##               be seen over the top of it.
##   park        posts, mostly. A public green is edged with planting and a
##               path, not walled, and the shrub belt does the closing.
##   rural       whatever the seed says, exactly as before. A rural property is
##               the one that might genuinely be a treeline.
static func _roll_treatment(params: ACAPropertyParams) -> int:
	# A NEGLECTED PROPERTY'S FENCE HAS GONE. `boundary_condition` is 1.0 on every
	# ordinary contract, so this branch is not taken on any of them; below a
	# half it means the rails are down and only the posts are left, which is
	# what a boundary nobody has maintained looks like.
	if params.boundary_condition < 0.35:
		return Treatment.MARKER_POSTS
	if params.boundary_condition < 0.75:
		return Treatment.LOW_RAIL
	match params.archetype:
		ACAPropertyArchetype.Kind.SUBURBAN:
			return Treatment.RUSTIC_RAIL
		ACAPropertyArchetype.Kind.LANDSCAPED:
			return Treatment.LOW_RAIL
		ACAPropertyArchetype.Kind.PARK:
			var park_hash: float = fposmod(
				float(hash(Vector2i(params.seed, 7717))) * 0.000000119, 1.0)
			return Treatment.MARKER_POSTS if park_hash < 0.72 else Treatment.LOW_RAIL
		_:
			pass
	var h: float = fposmod(float(hash(Vector2i(params.seed, 7717))) * 0.000000119, 1.0)
	# A denser wood is more likely to be left to close its own edge; an open
	# property has nothing else to mark the line with, so it gets real fence.
	var marker_chance: float = lerpf(0.10, 0.42, clampf(params.forestiness, 0.0, 1.0))
	if h < marker_chance:
		return Treatment.MARKER_POSTS
	if h < marker_chance + 0.30:
		return Treatment.LOW_RAIL
	return Treatment.RUSTIC_RAIL


static func treatment_name(value: int) -> String:
	match value:
		Treatment.LOW_RAIL:
			return "low_rail"
		Treatment.MARKER_POSTS:
			return "marker_posts"
		_:
			return "rustic_rail"


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_body = null


# ================================================================== collision

## ONE body, with a box shape per segment of each side. A segment sits at the
## MIDDLE of the ground beneath it and is tall enough to cover the ends, so a
## wall following a slope has no gap at the joins and no lip to climb.
func _build_collision() -> int:
	_body = StaticBody3D.new()
	_body.name = "Boundary Collision"
	add_child(_body)

	var span := _half * 2.0
	var count: int = maxi(int(ceil(span / SEGMENT_LENGTH)), 1)
	var step := span / float(count)
	var made := 0
	# Four sides. Each is walked in its own axis; the corners are covered
	# because each side runs the FULL width, so the two walls overlap there.
	for side in 4:
		for i in count:
			var t := -_half + step * (float(i) + 0.5)
			var half_len := step * 0.5
			var pos: Vector3
			var size: Vector3
			match side:
				0:  # -Z edge, running along X
					pos = Vector3(_centre.x + t, 0.0, _centre.z - _half)
					size = Vector3(step, 1.0, WALL_THICKNESS)
				1:  # +Z edge
					pos = Vector3(_centre.x + t, 0.0, _centre.z + _half)
					size = Vector3(step, 1.0, WALL_THICKNESS)
				2:  # -X edge, running along Z
					pos = Vector3(_centre.x - _half, 0.0, _centre.z + t)
					size = Vector3(WALL_THICKNESS, 1.0, step)
				_:  # +X edge
					pos = Vector3(_centre.x + _half, 0.0, _centre.z + t)
					size = Vector3(WALL_THICKNESS, 1.0, step)
			var ground := _ground_range(pos, size, half_len)
			var low: float = ground.x - WALL_SINK
			var high: float = ground.y + WALL_RISE
			size.y = high - low
			pos.y = (low + high) * 0.5

			var shape := BoxShape3D.new()
			shape.size = size
			var node := CollisionShape3D.new()
			node.name = "Wall %d-%d" % [side, i]
			node.shape = shape
			node.position = pos - global_position
			_body.add_child(node)
			made += 1
	return made


## Lowest and highest ground under one segment, sampled at its two ends and its
## middle. Three samples is enough: the property is levelled under the lawn and
## the margin band beyond it is gentle by construction.
func _ground_range(centre: Vector3, size: Vector3, half_len: float) -> Vector2:
	var along := Vector3(1.0, 0.0, 0.0) if size.x > size.z else Vector3(0.0, 0.0, 1.0)
	var low := INF
	var high := -INF
	for f: float in [-1.0, 0.0, 1.0]:
		var p: Vector3 = centre + along * (half_len * f)
		var h: float = _terrain.height_at(p.x, p.z) if _terrain != null else 0.0
		low = minf(low, h)
		high = maxf(high, h)
	return Vector2(low, high)


# ====================================================================== fence

## Posts in one MultiMesh, rails in another. A Large property's whole boundary
## is therefore two draw calls whatever its treatment, which is the reason the
## fence is built from boxes and instanced rather than from a scene per bay.
func _build_fence() -> int:
	var spacing: float = POST_SPACING * (1.8 if _treatment == Treatment.MARKER_POSTS else 1.0)
	var span := _half * 2.0
	var bays: int = maxi(int(round(span / spacing)), 2)
	var step := span / float(bays)

	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(POST_THICKNESS, POST_HEIGHT, POST_THICKNESS)
	var rail_mesh := BoxMesh.new()
	# A unit-long rail, stretched per instance to the bay it spans.
	rail_mesh.size = Vector3(1.0, RAIL_THICKNESS, RAIL_DEPTH)

	var heights: Array = _rail_heights()
	var post_transforms := PackedFloat32Array()
	var rail_transforms := PackedFloat32Array()

	for side in 4:
		var along: Vector3
		var normal: Vector3
		match side:
			0:
				along = Vector3(1.0, 0.0, 0.0)
				normal = Vector3(0.0, 0.0, -1.0)
			1:
				along = Vector3(1.0, 0.0, 0.0)
				normal = Vector3(0.0, 0.0, 1.0)
			2:
				along = Vector3(0.0, 0.0, 1.0)
				normal = Vector3(-1.0, 0.0, 0.0)
			_:
				along = Vector3(0.0, 0.0, 1.0)
				normal = Vector3(1.0, 0.0, 0.0)
		var corner := _centre + normal * _half - along * _half
		# The last post of a side is the first post of the next, so each side
		# stops one short and the corners are not doubled up.
		for i in bays:
			var at := corner + along * (step * float(i))
			var ground := _ground_height(at)
			# A post is set INTO the ground rather than balanced on it, so a
			# gentle slope never shows daylight under the fence line.
			var lean := (_jitter(at, 3.1) - 0.5) * 0.05
			var basis := Basis(Vector3.UP, _facing(along)) \
				.rotated(along.normalized(), lean)
			_append(post_transforms, Transform3D(basis,
				Vector3(at.x, ground + POST_HEIGHT * 0.5 - 0.35, at.z)))

			var next := corner + along * (step * float(i + 1))
			var next_ground := _ground_height(next)
			for h_value in heights:
				var height := float(h_value)
				var mid := (at + next) * 0.5
				var y := (ground + next_ground) * 0.5 + height - 0.35
				var rail_basis := Basis(Vector3.UP, _facing(along))
				# Rails follow the slope of their bay rather than stepping.
				var slope: float = atan2(next_ground - ground, step)
				rail_basis = rail_basis.rotated(
					rail_basis * Vector3(0.0, 0.0, 1.0), -slope)
				var length := sqrt(step * step
					+ (next_ground - ground) * (next_ground - ground))
				rail_basis = rail_basis.scaled(Vector3(length, 1.0, 1.0))
				_append(rail_transforms, Transform3D(rail_basis,
					Vector3(mid.x, y, mid.z)))

	_commit("Fence Posts", post_mesh, post_transforms, POST_COLOUR)
	if not rail_transforms.is_empty():
		_commit("Fence Rails", rail_mesh, rail_transforms, RAIL_COLOUR)
	return post_transforms.size() / 12


func _rail_heights() -> Array:
	match _treatment:
		Treatment.LOW_RAIL:
			return LOW_RAIL_HEIGHTS
		Treatment.MARKER_POSTS:
			return []
		_:
			return RAIL_HEIGHTS


## Yaw that turns local +X into the direction the side runs.
static func _facing(along: Vector3) -> float:
	return atan2(along.x, along.z) - PI * 0.5


func _ground_height(at: Vector3) -> float:
	return _terrain.height_at(at.x, at.z) if _terrain != null else 0.0


static func _jitter(at: Vector3, salt: float) -> float:
	return fposmod(sin(at.x * 12.9898 + at.z * 78.233 + salt) * 43758.5453, 1.0)


static func _append(into: PackedFloat32Array, t: Transform3D) -> void:
	var b := t.basis
	var o := t.origin
	into.append_array(PackedFloat32Array([
		b.x.x, b.y.x, b.z.x, o.x,
		b.x.y, b.y.y, b.z.y, o.y,
		b.x.z, b.y.z, b.z.z, o.z,
	]))


func _commit(node_name: String, mesh: Mesh, transforms: PackedFloat32Array,
		colour: Color) -> void:
	var count := transforms.size() / 12
	if count <= 0:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	multimesh.buffer = transforms

	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.94
	material.specular = 0.08

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	# The fence is a long thin thing at the edge of the frame. Its shadow adds
	# nothing the player will look at and it is in the shadow map for the whole
	# perimeter of the property, so it is left out of it.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 4.0
	add_child(instance)


# ==================================================================== reading

func half_extent() -> float:
	return _half


func centre() -> Vector3:
	return _centre


## The playable rectangle on the XZ plane. The minimap and any future feature
## placement read THIS rather than recomputing it.
func rect() -> Rect2:
	return Rect2(_centre.x - _half, _centre.z - _half, _half * 2.0, _half * 2.0)


func contains(x: float, z: float) -> bool:
	return absf(x - _centre.x) <= _half and absf(z - _centre.z) <= _half


## How far outside the playable rectangle a point is, in world units. Zero
## inside it. This is the question `ACAForest` asks before it plants anything.
func distance_outside(x: float, z: float) -> float:
	var dx: float = maxf(absf(x - _centre.x) - _half, 0.0)
	var dz: float = maxf(absf(z - _centre.z) - _half, 0.0)
	return sqrt(dx * dx + dz * dz)


func treatment() -> int:
	return _treatment


func statistics() -> Dictionary:
	return _stats.duplicate(true)
