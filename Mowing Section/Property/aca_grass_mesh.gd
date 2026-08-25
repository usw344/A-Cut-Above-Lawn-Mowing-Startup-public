class_name ACAGrassMesh
extends RefCounted
## ROLE
## Builds the grass tuft meshes, procedurally, at runtime.
##
## WHY NOT THE OLD MESH. The lawn this replaces used a single imported blade
## cluster about three world units tall, drawn at every position on a two unit
## lattice. It read as a crop, not as a lawn: identical, upright, taller than the
## machine cutting it, and with nothing for a wind or a cut to act on.
##
## A generated mesh solves the parts a mesh has to solve:
##   * UV.y carries the HEIGHT FRACTION along each blade, so the shader can bend
##     a blade from its tip while its root stays planted;
##   * UV.x carries a per-blade identifier, so blades inside one tuft can move
##     apart from each other instead of as a rigid bunch;
##   * COLOR.rg carries the AXIS of the leaf - where the middle of that leaf sits
##     horizontally, relative to the tuft's origin - so the shader can straighten
##     a leaf without also narrowing it. Cutting has to shorten a blade and pull
##     its tip back in; without this the only handle available is the whole XZ
##     position, and pulling that in tapers every cut leaf to a needle;
##   * blades lean and twist by construction, so no two look stamped;
##   * it is opaque. No alpha cutout, no depth prepass, no sorting - which is
##     what makes a dense lawn affordable.
##
## PUBLIC API
##   ACAGrassMesh.build_tuft(blades, segments, height, width, spread, seed)
##   ACAGrassMesh.near_tuft() / mid_tuft() / far_tuft()   cached shared meshes
##
## SIGNALS: None.
##
## INVARIANTS
##   * A tuft is authored ONE world unit tall and roughly one unit across, and
##     is scaled per instance. Nothing downstream should assume otherwise.
##   * The origin sits at the ROOT of the tuft, on the ground.
##   * COLOR.rg encodes the leaf axis over the range -1 .. 1, as `axis * 0.5 +
##     0.5`. `AXIS_RANGE` below is the encoding, and the grass shader decodes it
##     with the same constant.
##
## PERSISTENCE OWNERSHIP: None.

## How the leaf axis stored in COLOR.rg is scaled into 0 .. 1. A leaf never
## reaches a world unit from the tuft centre, so one unit either way is room to
## spare and keeps the eight bits a vertex colour gets where they are useful.
## The grass shader decodes with this same number.
const AXIS_RANGE := 1.0

static var _near: ArrayMesh = null
static var _mid: ArrayMesh = null
static var _far: ArrayMesh = null


## The lawn a player is looking down at. Enough blades to read as turf -
## including MOWN turf, which is the harder half: a short lawn shows the ground
## between its leaves, so the near tuft carries more of them, and each is finer.
static func near_tuft() -> ArrayMesh:
	if _near == null:
		# THREE SEGMENTS, not two. A blade that is now most of twice as tall
		# bends over a longer arc, and two quads make that arc a hinge: the
		# top half of a tall leaf swings as one straight piece, which reads as
		# a wire rather than as grass. The third segment is the cheapest thing
		# that fixed it.
		#
		# The leaves are also a little WIDER than they were. Width is what makes
		# a lawn cover the ground, and stretching the old width over the new
		# height turned the standing lawn into a bed of needles.
		_near = build_tuft(10, 3, 1.0, 0.037, 0.33, 1201)
	return _near


## A few dozen metres out. Fewer leaves and one segment fewer than the near
## tuft, but the SAME KIND OF SHAPE: a handful of narrow leaves fanning out of
## one root. That matters more than the triangle count. The band this replaces
## used the far clump, which is four broad paddles, and the crossover between
## the two read as the lawn changing material halfway across the property.
static func mid_tuft() -> ArrayMesh:
	if _mid == null:
		# ONE SEGMENT, still. The mid band starts forty-six units out; a hinge
		# in a blade at that range is smaller than a pixel, and the near tuft's
		# third segment was measured costing frames rather than guessed at.
		_mid = build_tuft(5, 1, 1.0, 0.079, 0.36, 5507)
	return _mid


## Distant clumps. Three broad blades that read as a patch of grass rather than
## as individual leaves, because at that range nothing else does.
static func far_tuft() -> ArrayMesh:
	if _far == null:
		_far = build_tuft(4, 1, 1.0, 0.105, 0.36, 9109)
	return _far


## Build a tuft.
##
## `blades`   how many leaves
## `segments` how many quads up each leaf; more bends more smoothly
## `height`   authored height, always 1.0 for the shared meshes
## `width`    half width at the base of a leaf
## `spread`   how far leaves stand from the tuft centre
static func build_tuft(blades: int, segments: int, height: float, width: float,
		spread: float, tuft_seed: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()

	var rng := RandomNumberGenerator.new()
	rng.seed = tuft_seed

	for blade in blades:
		# Leaves fan out around the tuft rather than sharing an axis, and the
		# golden angle keeps them from lining up even at three blades.
		var yaw: float = float(blade) * 2.39996 + rng.randf_range(-0.35, 0.35)
		var direction := Vector3(cos(yaw), 0.0, sin(yaw))
		var root: Vector3 = direction * spread * rng.randf_range(0.25, 1.0)
		var blade_height: float = height * rng.randf_range(0.68, 1.0)
		# How far the tip leans out. A blade that stands perfectly upright is
		# the single strongest cause of the crop-row look.
		var lean: float = rng.randf_range(0.18, 0.52)
		var half_width: float = width * rng.randf_range(0.8, 1.15)
		var blade_id: float = (float(blade) + 0.5) / float(blades)

		var base_index := vertices.size()
		for s in segments + 1:
			var t := float(s) / float(segments)
			# Taper towards a blunt tip, and curve rather than tilt: the base
			# stays vertical and the lean accumulates towards the top. A blade
			# tapered to a needle reads as a thorn, not as grass.
			var taper: float = 1.0 - t * 0.62
			var offset: Vector3 = direction * (lean * t * t * blade_height)
			var centre: Vector3 = root + offset + Vector3(0.0, blade_height * t, 0.0)
			var side := Vector3(-direction.z, 0.0, direction.x) * half_width * taper
			vertices.append(centre - side)
			vertices.append(centre + side)
			uvs.append(Vector2(blade_id, t))
			uvs.append(Vector2(blade_id, t))
			# The leaf's own axis, so a shader can move the leaf without
			# touching how wide it is. Both edge vertices carry the same value:
			# it describes the leaf, not the vertex.
			var axis := Color(
				centre.x / AXIS_RANGE * 0.5 + 0.5,
				centre.z / AXIS_RANGE * 0.5 + 0.5,
				0.0, 1.0)
			colours.append(axis)
			colours.append(axis)
			# The normal is nearly VERTICAL, not perpendicular to the leaf. A
			# lawn is read as a surface catching the sky; blades lit by their
			# own faces turn every gap between them black.
			var facing := Vector3(-direction.z, 0.0, direction.x).cross(
				Vector3(0.0, 1.0, 0.0)).normalized()
			var n := (facing * 0.16 + Vector3.UP).normalized()
			normals.append(n)
			normals.append(n)

		for s in segments:
			var i := base_index + s * 2
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + 3)
			indices.append(i)
			indices.append(i + 3)
			indices.append(i + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# A tuft leans, so its real extent is wider than its authored footprint.
	mesh.custom_aabb = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 1.4, 2.0))
	return mesh
