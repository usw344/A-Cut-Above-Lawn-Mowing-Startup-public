class_name UIGlyph
extends Control
## A small drawn mark, for the places the interface wants a picture rather than
## a word.
##
## ============================================================
## WHY THESE ARE DRAWN AND NOT IMPORTED
## ============================================================
##
## The interface wanted the illustrated rustic accents the visual direction asks
## for - a leaf beside a job site, a drop beside the fuel, a sun beside the
## clock. The alternatives were an icon font (a new dependency, a new licence,
## and a whole file of glyphs for the six marks actually used) or a folder of
## PNGs (six imports, six import settings, and a resolution to argue about).
##
## Six polygons of a dozen points each cost neither, scale to any size, and take
## their colour from whatever is around them. They are deliberately SIMPLE:
## these are accents at twelve to twenty pixels, and detail at that size is
## noise.
##
## ============================================================
## PUBLIC API
## ============================================================
##
##   UIGlyph.make(kind, size, colour) -> UIGlyph      build one
##   set_kind(kind) / set_colour(colour)
##
## `kind` is one of the Kind enum below.
##
## Signals: none. Nothing here is interactive; `mouse_filter` is IGNORE.
##
## ============================================================
## SCENE / RESOURCE REFERENCES
## ============================================================
##
## None. No scene, no texture, no font.

enum Kind {
	## A single leaf. The game's mark - it stands beside a property's name.
	LEAF,
	## Sun. Clear weather, and the time of day.
	SUN,
	## Cloud. Overcast, fog and rain all borrow it.
	CLOUD,
	## Rain: a cloud with three falling strokes.
	RAIN,
	## A fuel drop.
	DROP,
	## A folded map. The minimap's header.
	MAP,
	## Three stacked cut stripes. The mowing objective.
	STRIPES,
	## A rounded stone. Obstacles on the contract.
	STONE,
	## A ripple. The pond.
	WATER,
}

var _kind: Kind = Kind.LEAF
var _colour: Color = Color(0.157, 0.180, 0.153)


## THE constructor. `size` is the square the mark is drawn in, in pixels.
static func make(kind: Kind, size: float = 16.0,
		colour: Color = Color(0.157, 0.180, 0.153)) -> UIGlyph:
	var g := UIGlyph.new()
	g._kind = kind
	g._colour = colour
	g.custom_minimum_size = Vector2(size, size)
	g.size = Vector2(size, size)
	return g


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_kind(kind: Kind) -> void:
	_kind = kind
	queue_redraw()


func set_colour(colour: Color) -> void:
	_colour = colour
	queue_redraw()


func colour() -> Color:
	return _colour


func _draw() -> void:
	# EVERY mark is authored in a unit square and scaled here, so one of them can
	# be adjusted without arithmetic and none of them can be the wrong size.
	var side: float = minf(size.x, size.y)
	if side < 2.0:
		return
	var origin := (size - Vector2(side, side)) * 0.5
	match _kind:
		Kind.LEAF: _draw_leaf(origin, side)
		Kind.SUN: _draw_sun(origin, side)
		Kind.CLOUD: _draw_cloud(origin, side, false)
		Kind.RAIN: _draw_cloud(origin, side, true)
		Kind.DROP: _draw_drop(origin, side)
		Kind.MAP: _draw_map(origin, side)
		Kind.STRIPES: _draw_stripes(origin, side)
		Kind.STONE: _draw_stone(origin, side)
		Kind.WATER: _draw_water(origin, side)


# ======================================================================= marks

## Two mirrored quadratic arcs meeting at the tip and the stem, with a midrib.
func _draw_leaf(o: Vector2, s: float) -> void:
	var tip := o + Vector2(0.84, 0.14) * s
	var base := o + Vector2(0.14, 0.86) * s
	# The control points are pushed WELL off the midrib. Pulled closer, the two
	# arcs meet almost as a straight line and the mark reads as a brush stroke.
	var points := PackedVector2Array()
	points.append_array(_arc(base, o + Vector2(1.02, 0.66) * s, tip, 9))
	points.append_array(_arc(tip, o + Vector2(-0.02, 0.34) * s, base, 9))
	draw_colored_polygon(points, _colour)
	draw_line(base, tip, _colour.darkened(0.25), maxf(s * 0.055, 1.0), true)


func _draw_sun(o: Vector2, s: float) -> void:
	var centre := o + Vector2(0.5, 0.5) * s
	draw_circle(centre, s * 0.235, _colour)
	var width: float = maxf(s * 0.075, 1.0)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(centre + direction * s * 0.33, centre + direction * s * 0.47,
			_colour, width, true)


## Three overlapping discs on a flat base. `raining` adds the strokes.
func _draw_cloud(o: Vector2, s: float, raining: bool) -> void:
	var lift: float = 0.0 if raining else 0.06
	var top: float = (0.44 - lift) * s
	draw_circle(o + Vector2(0.34 * s, top), s * 0.19, _colour)
	draw_circle(o + Vector2(0.58 * s, top - s * 0.07), s * 0.23, _colour)
	draw_circle(o + Vector2(0.76 * s, top + s * 0.02), s * 0.17, _colour)
	draw_rect(Rect2(o + Vector2(0.20 * s, top), Vector2(0.62 * s, s * 0.20)),
		_colour)
	if not raining:
		return
	var width: float = maxf(s * 0.075, 1.0)
	for i in 3:
		var x: float = (0.32 + 0.19 * float(i)) * s
		draw_line(o + Vector2(x, s * 0.68), o + Vector2(x - s * 0.06, s * 0.90),
			_colour, width, true)


## A circle with a pointed top: the shape everyone reads as a drop.
func _draw_drop(o: Vector2, s: float) -> void:
	var centre := o + Vector2(0.5, 0.62) * s
	draw_circle(centre, s * 0.28, _colour)
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(0.50, 0.08) * s,
		o + Vector2(0.755, 0.66) * s,
		o + Vector2(0.245, 0.66) * s,
	]), _colour)


## A folded map: three panels with the folds drawn in.
func _draw_map(o: Vector2, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(0.08, 0.26) * s,
		o + Vector2(0.36, 0.14) * s,
		o + Vector2(0.64, 0.28) * s,
		o + Vector2(0.92, 0.16) * s,
		o + Vector2(0.92, 0.76) * s,
		o + Vector2(0.64, 0.88) * s,
		o + Vector2(0.36, 0.74) * s,
		o + Vector2(0.08, 0.86) * s,
	]), _colour)
	var fold := _colour.lightened(0.55)
	var width: float = maxf(s * 0.06, 1.0)
	draw_line(o + Vector2(0.36, 0.14) * s, o + Vector2(0.36, 0.74) * s,
		fold, width, true)
	draw_line(o + Vector2(0.64, 0.28) * s, o + Vector2(0.64, 0.88) * s,
		fold, width, true)


## Three mown stripes, alternating tone, which is what a finished lawn looks
## like from above and what the progress bar is counting.
func _draw_stripes(o: Vector2, s: float) -> void:
	var pale := _colour.lightened(0.45)
	for i in 3:
		var y: float = (0.20 + 0.22 * float(i)) * s
		draw_rect(Rect2(o + Vector2(0.10 * s, y), Vector2(0.80 * s, s * 0.13)),
			_colour if i % 2 == 0 else pale)


func _draw_stone(o: Vector2, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(0.16, 0.74) * s,
		o + Vector2(0.10, 0.50) * s,
		o + Vector2(0.30, 0.26) * s,
		o + Vector2(0.62, 0.22) * s,
		o + Vector2(0.88, 0.44) * s,
		o + Vector2(0.86, 0.74) * s,
	]), _colour)
	draw_line(o + Vector2(0.30, 0.26) * s, o + Vector2(0.46, 0.74) * s,
		_colour.lightened(0.4), maxf(s * 0.055, 1.0), true)


## Two ripples. Water, without drawing a whole pond.
func _draw_water(o: Vector2, s: float) -> void:
	var width: float = maxf(s * 0.085, 1.2)
	for i in 2:
		var y: float = (0.40 + 0.24 * float(i)) * s
		draw_polyline(PackedVector2Array([
			o + Vector2(0.12 * s, y),
			o + Vector2(0.34 * s, y - s * 0.09),
			o + Vector2(0.56 * s, y),
			o + Vector2(0.78 * s, y - s * 0.09),
			o + Vector2(0.90 * s, y - s * 0.03),
		]), _colour, width, true)


# ===================================================================== helpers

## A quadratic Bezier as `steps` points, start included and end excluded, so two
## arcs can be joined into one closed polygon without a duplicated vertex.
static func _arc(from: Vector2, control: Vector2, to: Vector2,
		steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps:
		var t := float(i) / float(steps)
		var inverse := 1.0 - t
		out.append(from * inverse * inverse + control * 2.0 * inverse * t
			+ to * t * t)
	return out
