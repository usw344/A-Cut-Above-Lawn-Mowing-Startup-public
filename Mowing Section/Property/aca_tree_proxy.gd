class_name ACATreeProxy
extends RefCounted
## ROLE
## Builds the simplified stand-in meshes used for trees the player can see but
## will never walk up to.
##
## WHY NOT BILLBOARDS. An impostor has to be rendered, stored and re-rendered
## when the light changes, and it turns as the camera moves, which is what makes
## a distant wood shimmer. A dozen triangles of real geometry costs about the
## same, never turns, catches the real sun and casts a real silhouette against
## the hills. At four hundred units and through fog, nothing else is visible
## anyway.
##
## PUBLIC API
##   ACATreeProxy.conifer(detail) / ACATreeProxy.broadleaf(detail)
##   ACATreeProxy.material()      -> the shared vertex-coloured material
##
## `detail` 1 is the middle distance, 2 is the far band.
##
## SIGNALS: None.
##
## INVARIANTS
##   * Proxies are authored ONE unit tall with the trunk base at the origin, so
##     they scale exactly like the real trees they stand in for.
##   * Colour lives in the vertex data, so every species and both detail levels
##     share one material and one draw state.
##
## PERSISTENCE OWNERSHIP: None.

const TRUNK := Color(0.255, 0.180, 0.130)
const CONIFER_LOW := Color(0.098, 0.206, 0.113)
const CONIFER_HIGH := Color(0.174, 0.322, 0.161)
const BROADLEAF_LOW := Color(0.131, 0.239, 0.105)
const BROADLEAF_HIGH := Color(0.240, 0.374, 0.151)

static var _cache := {}
static var _material: StandardMaterial3D = null


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.95
		_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _material


static func conifer(detail: int) -> ArrayMesh:
	return _cached("conifer%d" % detail, func() -> ArrayMesh:
		var sides: int = 7 if detail <= 1 else 5
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_trunk(st, 0.055, 0.30, sides if detail <= 1 else 4)
		if detail <= 1:
			_cone(st, sides, 0.24, 0.20, 0.62, CONIFER_LOW, CONIFER_HIGH)
			_cone(st, sides, 0.19, 0.46, 0.54, CONIFER_LOW, CONIFER_HIGH)
			_cone(st, sides, 0.13, 0.70, 0.30, CONIFER_LOW, CONIFER_HIGH)
		else:
			_cone(st, sides, 0.25, 0.22, 0.82, CONIFER_LOW, CONIFER_HIGH)
		st.generate_normals()
		return st.commit())


static func broadleaf(detail: int) -> ArrayMesh:
	return _cached("broadleaf%d" % detail, func() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_trunk(st, 0.06, 0.46, 5 if detail <= 1 else 4)
		if detail <= 1:
			_blob(st, Vector3(0.0, 0.62, 0.0), 0.30, BROADLEAF_LOW, BROADLEAF_HIGH)
			_blob(st, Vector3(0.13, 0.80, -0.06), 0.20, BROADLEAF_LOW, BROADLEAF_HIGH)
			_blob(st, Vector3(-0.14, 0.74, 0.10), 0.18, BROADLEAF_LOW, BROADLEAF_HIGH)
		else:
			_blob(st, Vector3(0.0, 0.68, 0.0), 0.33, BROADLEAF_LOW, BROADLEAF_HIGH)
		st.generate_normals()
		return st.commit())


static func _cached(key: String, builder: Callable) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = builder.call()
	return _cache[key]


## A tapered prism. Cheaper than a cylinder and reads the same in silhouette.
static func _trunk(st: SurfaceTool, radius: float, height: float, sides: int) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var b1 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		var t0 := Vector3(cos(a0) * radius * 0.7, height, sin(a0) * radius * 0.7)
		var t1 := Vector3(cos(a1) * radius * 0.7, height, sin(a1) * radius * 0.7)
		_tri(st, b0, t0, t1, TRUNK)
		_tri(st, b0, t1, b1, TRUNK)


## A cone, darker at the skirt and lighter at the tip so it reads as lit foliage
## rather than as a flat green triangle.
static func _cone(st: SurfaceTool, sides: int, radius: float, base_y: float,
		height: float, low: Color, high: Color) -> void:
	var apex := Vector3(0.0, base_y + height, 0.0)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := Vector3(cos(a0) * radius, base_y, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, base_y, sin(a1) * radius)
		_tri_shaded(st, p0, p1, apex, low, low, high)


## An octahedron. Eight triangles for a whole canopy.
static func _blob(st: SurfaceTool, centre: Vector3, radius: float,
		low: Color, high: Color) -> void:
	var top := centre + Vector3(0.0, radius, 0.0)
	var bottom := centre - Vector3(0.0, radius * 0.8, 0.0)
	var ring: Array[Vector3] = []
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		ring.append(centre + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	for i in 4:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % 4]
		_tri_shaded(st, p0, p1, top, low, low, high)
		_tri_shaded(st, p1, p0, bottom, low, low, low.darkened(0.25))


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		colour: Color) -> void:
	_tri_shaded(st, a, b, c, colour, colour, colour)


static func _tri_shaded(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
