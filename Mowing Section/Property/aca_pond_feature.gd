class_name ACAPondFeature
extends ACAPropertyFeature
## ROLE
## A pond as a landscape feature: it digs the terrain, refuses grass below the
## water line, removes submerged cells from the mowing total, and contributes a
## water surface.
##
## THE SHAPE IS NOT REDEFINED HERE. Every geometric answer comes from
## `ACAPondCarver`, the experimental prototype's shape function, so the carved
## heightfield, its collision, the shoreline, the grass exclusion and the mowing
## exclusion are all the same curve. The prototype carved a copy of an existing
## mesh; a procedurally generated terrain has no mesh to copy yet, so the same
## displacement is applied while the height is being generated instead. That is
## the only difference, and it is why there is no second pond shape in the
## project.
##
## ---------------------------------------------------------------------------
## THE MOWER DOES NOT GET IN
## ---------------------------------------------------------------------------
## A pond dug into a heightfield is a hole with water drawn across it. Nothing
## about that stops a machine driving down the bank, through the water plane and
## on to the bed, where it sits in a bowl it cannot climb out of.
##
## So the pond contributes a SHORELINE COLLISION RING: one static body carrying
## a short wall per shoreline segment, traced from the real carved ground at the
## height the water reaches. It is invisible, it follows the same irregular
## outline as everything else about this pond, and it is a ring rather than a
## lid - there is no surface over the water for a machine to drive across.
##
## PUBLIC API
##   ACAPondFeature.from_params(property_params, centre_world)
##   carver_params()        -> the ACAPondCarver.Params in use
##   water_world_height()   -> the water surface height, world Y
##   centre() / radius()
##   shoreline_points(terrain) -> the traced water line, for the minimap
##   plus the whole ACAPropertyFeature interface
##
## SIGNALS: None.
##
## INVARIANTS
##   * `prepare()` must run before `water_world_height()`, `bounds()` or
##     `exclusion_at()` mean anything: the water line is measured from the
##     UN-carved ground at the pond centre, so it is stable and level.
##   * Coordinates are world space. The property is built at the origin.
##
## PERSISTENCE OWNERSHIP
##   None. Rebuilt from the pond fields of ACAPropertyParams.

const WATER_SHADER := "res://Mowing Section/Experimental/Pond/pond_water.gdshader"

## How many points the shoreline is traced at. The ring's segments and the
## minimap's outline both come from this one trace, so the two can never
## disagree about where the water is.
const SHORE_SAMPLES := 48
## How far ABOVE the water line the collision ring stands, in world units. Small
## on purpose: the machine should be able to run its deck right down to the
## damp ground the way a real operator trims a bank, and be stopped only where
## the next wheel-turn would put it in the water.
const SHORE_STOP_HEIGHT := 0.30
## Ring wall thickness, and how far it reaches above and below the water line.
## It only has to stop a ground vehicle, and it is never seen.
const RING_THICKNESS := 0.7
const RING_RISE := 3.2
const RING_DROP := 3.2

## How wide the band is over which grass thins out to nothing, measured
## HORIZONTALLY along the ground, outward from where the clearance band ends.
## It stops the shoreline from being a hard ring.
##
## THIS USED TO BE A HEIGHT, and that was the bug. A pond's grass stopped a
## fixed distance ABOVE the water; how far out along the ground that landed
## depended entirely on how steep the bank happened to be. On a shallow bank it
## was generous. On the steepest bank the generator can roll it was about a
## quarter of a unit - well inside the collision ring - and the last ring of
## grass around the water was visible, counted towards completion, and
## unreachable, because the ring stops the CHASSIS and the deck sits inside it.
const SHORE_FADE := 1.1

var _params: ACAPondCarver.Params = null
var _noise: FastNoiseLite = null
## Water surface height RELATIVE to the un-carved ground, exactly as the
## prototype defines `ACAPond.water_level`.
var _water_level_offset: float = -0.55
var _water_y: float = 0.0
var _prepared: bool = false
var _water: MeshInstance3D = null
var _ring: StaticBody3D = null
## The traced water line, in world XZ. Empty until `build_nodes()` has run.
var _shoreline := PackedVector2Array()
## The collision ring's radius per angle, anticlockwise from +X, resolved in
## `prepare()`. THE reference every exclusion is measured from.
var _ring_radii := PackedFloat32Array()
## The same ring as the closed polygon the collision walls are built along.
## Cached because the exclusion measures distance to it rather than to a radius:
## on a wandering shoreline the two are not the same number, and it is the
## polygon the machine actually hits.
var _ring_polygon := PackedVector2Array()


static func from_params(property_params: ACAPropertyParams,
		centre_world: Vector2) -> ACAPondFeature:
	var f := ACAPondFeature.new()
	var p := ACAPondCarver.Params.new()
	p.centre = Vector3(centre_world.x, 0.0, centre_world.y)
	p.radius = property_params.pond_radius
	p.ellipse_ratio = property_params.pond_ellipse_ratio
	p.depth = property_params.pond_depth
	p.bank_fraction = property_params.pond_bank_fraction
	p.irregularity = property_params.pond_irregularity
	p.seed = property_params.pond_seed
	f._params = p
	f._noise = ACAPondCarver.make_shape_noise(p)
	f._water_level_offset = property_params.pond_water_level
	# A sensible answer before prepare(), so a caller that forgets does not get
	# a pond at world zero.
	f._water_y = property_params.pond_water_level
	return f


func feature_id() -> StringName:
	return &"pond"


func carver_params() -> ACAPondCarver.Params:
	return _params


func centre() -> Vector2:
	return Vector2(_params.centre.x, _params.centre.z)


func radius() -> float:
	return _params.radius


func water_world_height() -> float:
	return _water_y


## The water line is taken from the ground BEFORE this pond dug into it, at the
## pond centre. Measuring it from the carved ground would put the surface at the
## bottom of the hole; measuring it per point would make it a slope.
func prepare(base_height: Callable) -> void:
	var base: float = float(base_height.call(_params.centre.x, _params.centre.z))
	# `pond_water_level` is relative to the un-carved ground, exactly as the
	# prototype defines it.
	_water_y = base + _water_level_offset
	# The ring can only be found once the water line is known, and everything
	# downstream measures from the ring, so it is resolved here rather than
	# lazily.
	_trace_ring(base_height)
	_prepared = true


func is_prepared() -> bool:
	return _prepared


## GENEROUS ON PURPOSE. This is the rectangle `ACAFeatureSet` uses to reject
## points without a virtual call, so anything it leaves out is silently NOT
## excluded. It has to cover the whole clearance band and the fade beyond it, or
## the grass comes back in a ring exactly where the fix was meant to remove it.
func bounds() -> AABB:
	var margin: float = clearance() + SHORE_FADE + 1.0
	var half_x: float = _params.radius * _params.ellipse_ratio * (1.0 + _params.irregularity) + margin
	var half_z: float = _params.radius * (1.0 + _params.irregularity) + margin
	return AABB(
		Vector3(_params.centre.x - half_x, _water_y - _params.depth - 4.0,
			_params.centre.z - half_z),
		Vector3(half_x * 2.0, _params.depth + 16.0, half_z * 2.0))


func terrain_offset_at(x: float, z: float) -> float:
	return ACAPondCarver.depth_offset_at(Vector3(x, 0.0, z), _params, _noise)


## ---------------------------------------------------------------------------
## WHERE THE GRASS STOPS, AND WHY IT IS MEASURED FROM THE COLLISION RING
## ---------------------------------------------------------------------------
## The machine is stopped by the shoreline ring. The ring stops its CHASSIS, and
## on most of the fleet the chassis reaches further than the deck does - so the
## last band of ground before the ring can be seen, is counted, and cannot be
## cut. Grass therefore stops `ACAMowerClearance.REQUIRED` OUTSIDE the ring
## rather than at the water, and fades out over `SHORE_FADE` beyond that.
##
## THIS USED TO BE A HEIGHT TEST, and the height was the wrong question. Grass
## stopped a fixed distance ABOVE the water; how far out along the ground that
## landed depended entirely on how steep the bank happened to be, and on the
## steepest bank the generator rolls it landed INSIDE the ring.
##
## The radius the band is measured from is the ring's own, resolved in
## `prepare()` from the same carved ground the terrain bakes and the collision
## ring is traced on. Not an approximation of it: the same two functions added
## together.
func exclusion_at(x: float, z: float, _ground_y: float) -> float:
	if _ring_polygon.size() < 3:
		return 0.0
	var dx := x - _params.centre.x
	var dz := z - _params.centre.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist <= _ring_radius_at(dx, dz):
		# The water, and the damp bank the ring stands on.
		return 1.0
	# DISTANCE TO THE RING ITSELF, not to the radius on this ray. Where the
	# shoreline wanders inward the two differ by more than the clearance band is
	# wide, and it is the ring the machine meets.
	var gap: float = _distance_to_ring(Vector2(x, z))
	var clear: float = clearance()
	if gap <= clear:
		return 1.0
	if gap >= clear + SHORE_FADE:
		return 0.0
	return 1.0 - (gap - clear) / SHORE_FADE


## The machine hits the shoreline ring, so the pond owes the deck clear ground.
func is_solid() -> bool:
	return true


## The ring's radius on the ray through a point, interpolated between the
## samples `prepare()` measured. Zero before `prepare()` has run, which reads as
## "excludes nothing" - the honest answer for a pond that does not know where
## its own water is yet.
func _ring_radius_at(dx: float, dz: float) -> float:
	var count := _ring_radii.size()
	if count == 0:
		return 0.0
	var angle := atan2(dz, dx)
	if angle < 0.0:
		angle += TAU
	var position := angle / TAU * float(count)
	var index := int(floor(position))
	var blend := position - float(index)
	var a: float = _ring_radii[index % count]
	var b: float = _ring_radii[(index + 1) % count]
	return lerpf(a, b, blend)


## Walk out from the centre on `SHORE_SAMPLES` rays and find, on each, the
## radius at which the CARVED ground rises to the height the collision ring
## stands at.
##
## The ground here is `base_height + depth_offset_at`, which is precisely what
## `ACATerrain` bakes, so this line and the traced collision ring describe one
## circle rather than two that nearly agree. The alternative - solving the bank
## profile analytically - assumes the land under the pond is level, and the
## first version of this fix did exactly that and left forty-five cells of a
## hundred and thirty thousand sitting inside the ring on sloping ground.
func _trace_ring(base_height: Callable) -> void:
	_ring_radii.clear()
	var target := _water_y + SHORE_STOP_HEIGHT
	var far: float = _params.radius * maxf(_params.ellipse_ratio, 1.0) * (1.0 + _params.irregularity) + 4.0
	for i in SHORE_SAMPLES:
		var angle := TAU * float(i) / float(SHORE_SAMPLES)
		var dir := Vector2(cos(angle), sin(angle))
		var low := 0.0
		var high := far
		for _step in 12:
			var mid := (low + high) * 0.5
			var at := Vector2(_params.centre.x, _params.centre.z) + dir * mid
			if _carved_height(base_height, at) < target:
				low = mid
			else:
				high = mid
		_ring_radii.append(high)
	_ring_polygon = PackedVector2Array()
	var centre := Vector2(_params.centre.x, _params.centre.z)
	for i in _ring_radii.size():
		var a := TAU * float(i) / float(_ring_radii.size())
		_ring_polygon.append(centre + Vector2(cos(a), sin(a)) * _ring_radii[i])


## Shortest distance from a point to the ring polygon, in world units.
func _distance_to_ring(at: Vector2) -> float:
	var best := INF
	var count := _ring_polygon.size()
	for i in count:
		var a := _ring_polygon[i]
		var b := _ring_polygon[(i + 1) % count]
		var span := b - a
		var length_squared := span.length_squared()
		if length_squared < 0.000001:
			best = minf(best, at.distance_to(a))
			continue
		var t: float = clampf((at - a).dot(span) / length_squared, 0.0, 1.0)
		best = minf(best, at.distance_to(a + span * t))
	return best


func _carved_height(base_height: Callable, at: Vector2) -> float:
	var offset := ACAPondCarver.depth_offset_at(Vector3(at.x, 0.0, at.y), _params, _noise)
	return float(base_height.call(at.x, at.y)) + offset


## The 0-to-1 shore factor the carver uses, exposed for composition: rocks and
## shrubs want to gather NEAR the water rather than avoid it.
func shore_factor_at(x: float, z: float) -> float:
	return ACAPondCarver.shore_factor_with(Vector3(x, 0.0, z), _params, _noise)


# ====================================================================== water

## How far above the water line the ground still reads as damp, in world units.
## The ground shader draws the band; this is the number it draws it with.
const WET_BAND := 0.85


## A flat surface a little wider than the shoreline. The terrain rises above it
## outside the pond and hides the overhang, and the shader fades the last
## centimetres against the bed so the waterline is soft rather than a cut edge.
##
## The bank is handed to the GROUND material at the same time. A pond that only
## contributes water is a puddle on a lawn: what makes it read as a pond is that
## the ground around it knows the water is there.
func build_nodes(parent: Node3D, terrain: Node3D, params: ACAPropertyParams) -> void:
	if parent == null:
		return
	_apply_shore_to_ground(terrain)
	_build_shore_collision(parent, terrain)
	var plane := PlaneMesh.new()
	plane.size = Vector2(
		_params.radius * _params.ellipse_ratio * 2.0 * 1.22,
		_params.radius * 2.0 * 1.22)
	plane.subdivide_width = 40
	plane.subdivide_depth = 40

	_water = MeshInstance3D.new()
	_water.name = "Pond Water"
	_water.mesh = plane
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water.material_override = _make_water_material(params)
	parent.add_child(_water)
	_water.global_position = Vector3(_params.centre.x, _water_y, _params.centre.z)


func water_node() -> MeshInstance3D:
	return _water


func shore_collision_body() -> StaticBody3D:
	return _ring


## The water line in world XZ, anticlockwise from +X. The minimap draws this;
## nothing recomputes a second outline of its own.
func shoreline_points(terrain: Node3D = null) -> PackedVector2Array:
	if _shoreline.is_empty():
		_shoreline = _trace_shoreline(terrain)
	return _shoreline


# ======================================================== shoreline collision

## THE water line, as points, from the ONE trace `prepare()` took.
##
## This used to walk the baked height field a second time, and the second walk
## did not quite agree with the first: a lattice with linear interpolation
## between its samples is not the continuous function the samples came from, and
## the two answers differed by up to about a quarter of a unit on sloping
## ground. That is small, and it was enough to leave a couple of mowable cells
## per thousand properties sitting INSIDE the collision ring - which is the
## whole class of bug this pass exists to remove.
##
## So there is now one curve. The collision ring is built on it, the grass
## exclusion is measured from it, and the minimap draws it. They cannot disagree
## because there is nothing for them to disagree about.
##
## The height-field walk survives below as the fallback for a caller that
## somehow asks before `prepare()` has run.
func _trace_shoreline(terrain: Node3D) -> PackedVector2Array:
	if not _ring_polygon.is_empty():
		return _ring_polygon
	return _trace_shoreline_from_field(terrain)


## The original walk over the baked height field. Kept as a fallback only.
func _trace_shoreline_from_field(terrain: Node3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	if terrain == null or not terrain.has_method(&"height_at"):
		return out
	var target := _water_y + SHORE_STOP_HEIGHT
	# Comfortably past the widest the outline can wander.
	var far: float = _params.radius * maxf(_params.ellipse_ratio, 1.0) \
		* (1.0 + _params.irregularity) + 4.0
	for i in SHORE_SAMPLES:
		var angle := TAU * float(i) / float(SHORE_SAMPLES)
		var dir := Vector2(cos(angle), sin(angle))
		var low := 0.0
		var high := far
		# Twelve halvings resolve `far` (about 40 units at the largest pond) to
		# a centimetre, which is far finer than the wall is thick.
		for _step in 12:
			var mid := (low + high) * 0.5
			var p := Vector2(_params.centre.x, _params.centre.z) + dir * mid
			if float(terrain.call(&"height_at", p.x, p.y)) < target:
				low = mid
			else:
				high = mid
		out.append(Vector2(_params.centre.x, _params.centre.z) + dir * high)
	return out


## ONE body, a box per shoreline segment. A ring, never a lid: there is no
## shape over the water, so a machine that somehow got in would still be in it
## rather than standing on an invisible floor.
func _build_shore_collision(parent: Node3D, terrain: Node3D) -> void:
	_shoreline = _trace_shoreline(terrain)
	if _shoreline.size() < 3:
		return
	_ring = StaticBody3D.new()
	_ring.name = "Pond Shore Collision"
	parent.add_child(_ring)

	var height := RING_RISE + RING_DROP
	for i in _shoreline.size():
		var a := _shoreline[i]
		var b := _shoreline[(i + 1) % _shoreline.size()]
		var span := b - a
		var length := span.length()
		if length <= 0.001:
			continue
		var mid := (a + b) * 0.5
		var shape := BoxShape3D.new()
		# A little longer than the gap it spans, so neighbouring segments
		# overlap at their ends and the ring has no seams to slip through.
		shape.size = Vector3(length + RING_THICKNESS, height, RING_THICKNESS)
		var node := CollisionShape3D.new()
		node.name = "Shore %d" % i
		node.shape = shape
		node.transform = Transform3D(
			Basis(Vector3.UP, -atan2(span.y, span.x)),
			Vector3(mid.x, _water_y + (RING_RISE - RING_DROP) * 0.5, mid.y))
		_ring.add_child(node)


## Tell the ground shader where the water line is. The band it draws is decided
## by HEIGHT, so it follows this pond's irregular outline exactly without the
## shader being told anything about the shape; the rectangle below only scopes
## the effect, so a low corner elsewhere on the property never turns to mud.
func _apply_shore_to_ground(terrain: Node3D) -> void:
	if terrain == null or not terrain.has_method(&"ground_material"):
		return
	var material := terrain.call(&"ground_material") as ShaderMaterial
	if material == null:
		return
	var half_x: float = _params.radius * _params.ellipse_ratio * (1.0 + _params.irregularity) + 1.5
	var half_z: float = _params.radius * (1.0 + _params.irregularity) + 1.5
	material.set_shader_parameter("shore_centre",
		Vector2(_params.centre.x, _params.centre.z))
	material.set_shader_parameter("shore_extent", Vector2(half_x, half_z))
	material.set_shader_parameter("shore_water_y", _water_y)
	material.set_shader_parameter("shore_wet_band", WET_BAND)


func _make_water_material(params: ACAPropertyParams) -> Material:
	var shader := load(WATER_SHADER) as Shader
	if shader == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.16, 0.38, 0.42, 0.8)
		fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# A small pond in a breeze, not open water: the ripples move with the wind
	# speed the rest of the property uses, and stay shallow.
	mat.set_shader_parameter("wave_speed", clampf(params.wind_speed * 0.9, 0.2, 1.4))
	mat.set_shader_parameter("wave_height", 0.028)
	mat.set_shader_parameter("ripple_strength", 0.16)
	# A garden pond is GREEN water over a soft bed, not a mirror. Left at the
	# prototype's defaults it reads as polished chrome against the grass, which
	# is the one thing that would make it look dropped in.
	#
	# The second correction was the SKY. Seen from a standing player almost all
	# of a small pond is at a glancing angle, so a fresnel term strong enough to
	# look right on the near edge washes the whole surface out to a flat pale
	# blue. It is pulled well down, and what it reflects is pulled towards the
	# tone of the trees on the far bank rather than towards the zenith.
	#
	# AND THE THIRD CORRECTION WAS THAT IT WAS TOO DARK. Seen at any distance
	# past a dozen units the pond was reading as a hole rather than as water:
	# the deep colour dominated almost the whole surface, and what the fresnel
	# added on top of it was the grey of a hazy sky rather than anything green.
	# The shallow tone is lifted, the deep tone is lifted further, and the depth
	# falloff is slowed so the shallow colour reaches further in.
	mat.set_shader_parameter("shallow_color", Color(0.353, 0.576, 0.451, 1.0))
	mat.set_shader_parameter("deep_color", Color(0.114, 0.267, 0.243, 1.0))
	mat.set_shader_parameter("fresnel_color", Color(0.482, 0.640, 0.588, 1.0))
	mat.set_shader_parameter("fresnel_power", 4.4)
	mat.set_shader_parameter("fresnel_amount", 0.26)
	# ROUGHER AND LESS SPECULAR THAN A MIRROR. The overhead renders of forty
	# generated properties all showed the same thing: from any angle steeper
	# than a standing player's the fresnel term is nearly zero and the albedo is
	# green, and the pond STILL came back a flat pale blue - because the
	# renderer reflects the sky through ROUGHNESS and SPECULAR whatever the
	# albedo says. Blurring that reflection and quietening it is what keeps a
	# garden pond green when it is looked down on.
	mat.set_shader_parameter("roughness_value", 0.66)
	mat.set_shader_parameter("specular_value", 0.15)
	mat.set_shader_parameter("depth_falloff", 2.4)
	# A wider fade than the bank is deep, so the last of the water disappears
	# into the damp ground the ground shader draws rather than ending on it.
	mat.set_shader_parameter("shore_fade", 2.4)
	mat.set_shader_parameter("max_alpha", 0.94)
	return mat
