class_name MinimapPanel
extends Control
## The mowing minimap: a plan of the property the player is standing on.
##
## ============================================================
## PUBLIC API
## ============================================================
##
##   set_property_rect(rect: Rect2)     the PLAYABLE rectangle, world XZ
##   set_lawn_rect(rect: Rect2)         the mowable rectangle, world XZ
##   set_cut_mask(texture, centre, size)  the lawn's own cut texture
##   set_pond(points: PackedVector2Array)  world-space shoreline
##   set_obstacles(list)                [{position: Vector2, radius: float}]
##   set_protected_zones(list)          [{position, radius, squash, yaw}]
##   set_mower(position: Vector2, heading: float)   world XZ, radians
##   set_progress(value: float)         0 - 1, drawn as a caption
##   set_caption(text: String)
##   clear_property()
##
## Signals: none. Nothing on it is clickable.
##
## ============================================================
## IT IS NOT A SECOND COPY OF THE PROPERTY
## ============================================================
##
## Everything drawn here is handed in by the host, and every one of those things
## is the SAME object the game is using: the playable rectangle comes from
## `ACAPropertyBoundary`, the pond outline is the shoreline that the pond's own
## collision ring was built from, the obstacles are the list the exclusion
## queries read, and the cut area is `ACALawn`'s cut mask texture - the very
## texture the grass shader samples.
##
## That is the whole design. A minimap that kept its own idea of where the pond
## was would eventually be wrong, and a minimap that is wrong is worse than none.
##
## ============================================================
## STYLE
## ============================================================
##
## A SURVEY DRAWN ON THE SAME PAPER AS THE REST OF THE HUD. The panel is warm
## cream with a green header, the property is a block of lawn green on it, the
## cut ground is the paler green of mown grass, and the boundary is a drawn line
## rather than a glow.
##
## It used to be a dark slate panel, which was correct against the old HUD and
## wrong against the new one - the map was the last charcoal box in the corner
## of a cream interface. Everything here is the same five colours the job card
## uses.
##
## Not a satellite photograph and not a radar. If a shrub is not something the
## player has to drive around, it is not on here.

## World units of padding drawn around the property rectangle.
const WORLD_PADDING := 6.0

## The mower marker, in pixels.
const MARKER_LENGTH := 13.0
const MARKER_WIDTH := 9.0

## How fast the marker catches up to the machine. The mower's real transform
## jitters at 576 Hz; interpolating is what keeps the marker from buzzing.
const MARKER_SMOOTHING := 14.0

const CUT_SHADER := "res://UI/Minimap/minimap_cut.gdshader"

# ------------------------------------------------------------------- palette
## THE MAP'S FIVE COLOURS, and they are here rather than inline because a map is
## a diagram and a diagram's colours are a legend whether one is drawn or not.
##
##   PAGE      the ground beyond the fence. Dry, quiet, not part of the job.
##   PLAYABLE  inside the boundary. Where the machine can go.
##   UNCUT     the contract itself, standing.
##   CUT       drawn over it by the shader, from the lawn's own mask.
##   EDGE      the boundary line: the one thing on here the player cannot cross.
const PAGE_COLOUR := Color(0.847, 0.827, 0.749)
const PLAYABLE_COLOUR := Color(0.639, 0.694, 0.494)
const UNCUT_COLOUR := Color(0.361, 0.502, 0.290)
const CUT_COLOUR := Color(0.612, 0.749, 0.443)
const EDGE_COLOUR := Color(0.310, 0.271, 0.196)
const POND_COLOUR := Color(0.412, 0.616, 0.639)
const POND_EDGE_COLOUR := Color(0.243, 0.416, 0.451)
const OBSTACLE_COLOUR := Color(0.541, 0.514, 0.451)
## PROTECTED PLANTING. A warm flowering tone against the map's greens, with a
## dashed edge, because the one thing this has to communicate is that the line
## means something different from a fence or a pond - it is ground the machine
## CAN cross and must not.
const PROTECTED_COLOUR := Color(0.847, 0.741, 0.365, 0.55)
const PROTECTED_EDGE_COLOUR := Color(0.647, 0.494, 0.196)

var _property := Rect2()
var _lawn := Rect2()
var _pond := PackedVector2Array()
var _obstacles: Array[Dictionary] = []
## `{ position: Vector2, radius: float, squash: float, yaw: float }`, world XZ.
var _protected: Array[Dictionary] = []
var _mower_world := Vector2.ZERO
var _mower_heading := 0.0
var _drawn_world := Vector2.ZERO
var _drawn_heading := 0.0
var _has_mower := false
var _progress := 0.0

var _cut_mask: Texture2D = null
var _cut_centre := Vector2.ZERO
var _cut_size := 1.0

## Three drawing layers rather than one, because the cut mask needs a shader of
## its own and a material belongs to a whole CanvasItem rather than to one draw
## call. Base, then the cut, then everything that has to sit on top of it.
var _map: Control = null
var _cut_layer: Control = null
var _overlay: Control = null
var _caption: Label = null
var _progress_label: Label = null
var _built := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(238, 238)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",
		UITheme.hud_panel(UITheme.RADIUS_PANEL, 10.0, 8.0))
	add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	var mark := UIGlyph.make(UIGlyph.Kind.MAP, 13.0, UITheme.HUD_GREEN)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(mark)
	header.add_theme_constant_override("separation", 7)
	_caption = UITheme.label(header, "Caption", "PROPERTY", UITheme.FONT_MICRO,
		UITheme.PAPER_INK_DIM)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(gap)
	_progress_label = UITheme.label(header, "Progress", "0%",
		UITheme.FONT_MICRO, UITheme.HUD_GREEN)

	_map = Control.new()
	_map.name = "Map"
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.custom_minimum_size = Vector2(0, 190)
	_map.clip_contents = true
	_map.draw.connect(_draw_base)
	column.add_child(_map)

	_cut_layer = Control.new()
	_cut_layer.name = "Cut"
	_cut_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cut_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var cut_shader := load(CUT_SHADER) as Shader
	if cut_shader != null:
		var cut_material := ShaderMaterial.new()
		cut_material.shader = cut_shader
		cut_material.set_shader_parameter("cut_colour", CUT_COLOUR)
		_cut_layer.material = cut_material
	_cut_layer.draw.connect(_draw_cut)
	_map.add_child(_cut_layer)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	_map.add_child(_overlay)


func _process(delta: float) -> void:
	# The cut layer is redrawn every frame regardless of the machine, because
	# the texture behind it changes as the player mows and nothing signals that.
	if _cut_layer != null:
		_cut_layer.queue_redraw()
	if not _has_mower:
		return
	# Exponential catch-up, frame-rate independent.
	var blend: float = 1.0 - exp(-MARKER_SMOOTHING * delta)
	_drawn_world = _drawn_world.lerp(_mower_world, blend)
	_drawn_heading = _drawn_heading + angle_difference(_drawn_heading, _mower_heading) * blend
	if _overlay != null:
		_overlay.queue_redraw()


# ==================================================================== the data

func set_property_rect(rect: Rect2) -> void:
	_build()
	_property = rect
	_redraw()


func set_lawn_rect(rect: Rect2) -> void:
	_build()
	_lawn = rect
	_redraw()


## THE LAWN'S OWN TEXTURE, not a copy of it. One texel per world unit, red where
## a cell has been cut. `centre` and `size` are the world rectangle it covers.
func set_cut_mask(texture: Texture2D, centre: Vector2, size: float) -> void:
	_build()
	_cut_mask = texture
	_cut_centre = centre
	_cut_size = maxf(size, 1.0)
	_redraw()


func set_pond(points: PackedVector2Array) -> void:
	_build()
	_pond = points
	_redraw()


## `list` entries: { position: Vector2 (world XZ), radius: float (world units) }.
func set_obstacles(list: Array) -> void:
	_build()
	_obstacles.clear()
	for entry in list:
		if entry is Dictionary and (entry as Dictionary).has("position"):
			_obstacles.append(entry as Dictionary)
	_redraw()


## PROTECTED PLANTING, from `ACAConservationZone.zones()`. Empty on the great
## majority of contracts, which is why nothing has to check for it: an empty
## list draws nothing.
##
## It has to be OBVIOUS. A conservation objective the player fails because they
## could not see the boundary is not a challenge, it is a trap - so the zones
## are drawn filled, edged, and over the cut layer rather than under it.
func set_protected_zones(list: Array) -> void:
	_build()
	_protected.clear()
	for entry in list:
		if entry is Dictionary and (entry as Dictionary).has("position"):
			_protected.append(entry as Dictionary)
	_redraw()


func has_protected_zones() -> bool:
	return not _protected.is_empty()


func set_mower(position: Vector2, heading: float) -> void:
	_build()
	if not _has_mower:
		_drawn_world = position
		_drawn_heading = heading
	_has_mower = true
	_mower_world = position
	_mower_heading = heading


func set_progress(value: float) -> void:
	_build()
	_progress = clampf(value, 0.0, 1.0)
	_progress_label.text = UITheme.percent_text(_progress)


func set_caption(text: String) -> void:
	_build()
	_caption.text = text.to_upper()


func clear_property() -> void:
	_build()
	_property = Rect2()
	_lawn = Rect2()
	_pond = PackedVector2Array()
	_obstacles.clear()
	_cut_mask = null
	_has_mower = false
	_redraw()


# ==================================================================== drawing

## World XZ to panel pixels. NORTH IS UP AND THE MAP DOES NOT ROTATE: a plan the
## player can build a mental model of beats one that is always correct and never
## the same twice.
func _to_map(world: Vector2, view: Rect2, scale: float, origin: Vector2) -> Vector2:
	return origin + (world - view.position) * scale


func _redraw() -> void:
	if _map == null:
		return
	_map.queue_redraw()
	_cut_layer.queue_redraw()
	_overlay.queue_redraw()


## Where the property sits in panel pixels. All three layers derive their
## placement from this one function, so they cannot drift apart by a pixel.
## Empty when there is nothing to draw yet.
func _view() -> Dictionary:
	var size := _map.size if _map != null else Vector2.ZERO
	if size.x < 8.0 or size.y < 8.0 or _property.size.x <= 0.0:
		return {}
	var view := _property.grow(WORLD_PADDING)
	var scale: float = minf(size.x / view.size.x, size.y / view.size.y)
	return {
		"view": view,
		"scale": scale,
		"origin": (size - view.size * scale) * 0.5,
		"size": size,
	}


func _draw_base() -> void:
	var v := _view()
	if v.is_empty():
		return
	var view: Rect2 = v["view"]
	var scale: float = v["scale"]
	var origin: Vector2 = v["origin"]
	var size: Vector2 = v["size"]

	# THE PAGE: the ground outside the fence, which is scenery.
	_map.draw_rect(Rect2(Vector2.ZERO, size), PAGE_COLOUR)

	# The playable ground, and its edge - which is the single most useful thing
	# on here, because it is the line the machine cannot cross. Two strokes: a
	# pale one outside a dark one, so the boundary reads as a drawn fence line
	# rather than as the edge of a coloured block.
	var property_rect := Rect2(
		_to_map(_property.position, view, scale, origin), _property.size * scale)
	_map.draw_rect(property_rect, PLAYABLE_COLOUR)
	_map.draw_rect(property_rect.grow(1.5), EDGE_COLOUR.lightened(0.55), false, 3.0)
	_map.draw_rect(property_rect, EDGE_COLOUR, false, 2.0)

	# The contract itself, uncut, under the cut mask.
	var lawn_rect := Rect2(
		_to_map(_lawn.position, view, scale, origin), _lawn.size * scale)
	_map.draw_rect(lawn_rect, UNCUT_COLOUR)


## WHAT HAS BEEN CUT, straight from the lawn's own mask. See `minimap_cut.gdshader`
## for why this cannot be an ordinary modulated texture.
func _draw_cut() -> void:
	if _cut_mask == null:
		return
	var v := _view()
	if v.is_empty():
		return
	var scale: float = v["scale"]
	var mask_rect := Rect2(
		_to_map(_cut_centre - Vector2(_cut_size, _cut_size) * 0.5,
			v["view"], scale, v["origin"]),
		Vector2(_cut_size, _cut_size) * scale)
	_cut_layer.draw_texture_rect(_cut_mask, mask_rect, false)


func _draw_overlay() -> void:
	var v := _view()
	if v.is_empty():
		return
	var view: Rect2 = v["view"]
	var scale: float = v["scale"]
	var origin: Vector2 = v["origin"]

	# NORTH. The map does not rotate, which is what makes a mental model of a
	# property possible - and a plan that does not rotate has to say which way is
	# up or the player has to work it out from the fence.
	_draw_north(v["size"] as Vector2)

	# The pond, as a filled outline. Ponds are convex enough for a fan.
	if _pond.size() >= 3:
		var points := PackedVector2Array()
		for p in _pond:
			points.append(_to_map(p, view, scale, origin))
		_overlay.draw_colored_polygon(points, POND_COLOUR)
		points.append(points[0])
		_overlay.draw_polyline(points, POND_EDGE_COLOUR, 1.5, true)

	# PROTECTED PLANTING, under the obstacles and over the cut. Drawn as the oval
	# it really is - position, radius, squash and yaw are the zone's own - so the
	# shape on the plan is the shape on the ground.
	for zone: Dictionary in _protected:
		var centre: Vector2 = _to_map(zone["position"] as Vector2, view, scale, origin)
		var radius: float = maxf(float(zone.get("radius", 8.0)) * scale, 3.0)
		var squash: float = maxf(float(zone.get("squash", 1.0)), 0.05)
		var yaw: float = float(zone.get("yaw", 0.0))
		var points := PackedVector2Array()
		for step in 24:
			var angle := TAU * float(step) / 24.0
			# The map's Y is world Z, so the oval is built in world space and
			# then scaled, exactly as the zone's own exclusion test does it.
			var local := Vector2(cos(angle) * radius, sin(angle) * radius * squash)
			points.append(centre + local.rotated(yaw))
		_overlay.draw_colored_polygon(points, PROTECTED_COLOUR)
		points.append(points[0])
		_overlay.draw_polyline(points, PROTECTED_EDGE_COLOUR, 1.6, true)

	# Solid obstacles. Drawn a little larger than they are, because the thing
	# the player needs from this is "do not go there", not a survey.
	for o: Dictionary in _obstacles:
		var at: Vector2 = _to_map(o["position"] as Vector2, view, scale, origin)
		var radius: float = maxf(float(o.get("radius", 2.0)) * scale, 2.5)
		_overlay.draw_circle(at, radius + 1.0, EDGE_COLOUR.darkened(0.1))
		_overlay.draw_circle(at, radius, OBSTACLE_COLOUR)

	if not _has_mower:
		return

	# THE MACHINE. An arrow, so heading is as readable as position - which is
	# what makes this useful for deciding which way the next pass goes.
	var centre := _to_map(_drawn_world, view, scale, origin)
	var forward := Vector2(sin(_drawn_heading), cos(_drawn_heading))
	var side := Vector2(-forward.y, forward.x)
	var arrow := PackedVector2Array([
		centre + forward * MARKER_LENGTH * 0.62,
		centre - forward * MARKER_LENGTH * 0.38 + side * MARKER_WIDTH * 0.5,
		centre - forward * MARKER_LENGTH * 0.16,
		centre - forward * MARKER_LENGTH * 0.38 - side * MARKER_WIDTH * 0.5,
	])
	# A dark outline under it, so the marker reads on cut grass, uncut grass and
	# water alike rather than only on the tone it was designed against.
	var outline := PackedVector2Array()
	for p in arrow:
		outline.append(centre + (p - centre) * 1.35)
	_overlay.draw_colored_polygon(outline, Color(0.988, 0.973, 0.937, 0.92))
	_overlay.draw_colored_polygon(arrow, UITheme.ORANGE)


## A small compass mark in the top right of the plan: an arrowhead and an N.
func _draw_north(size: Vector2) -> void:
	# Inset far enough that the arrowhead and the letter under it both sit inside
	# the plan; at the panel edge the mark was half drawn and half clipped.
	var at := Vector2(size.x - 16.0, 13.0)
	_overlay.draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.0, -7.0),
		at + Vector2(4.0, 2.0),
		at + Vector2(0.0, -0.5),
		at + Vector2(-4.0, 2.0),
	]), EDGE_COLOUR)
	var font := get_theme_default_font()
	if font != null:
		_overlay.draw_string(font, at + Vector2(-3.5, 15.0), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, EDGE_COLOUR)
