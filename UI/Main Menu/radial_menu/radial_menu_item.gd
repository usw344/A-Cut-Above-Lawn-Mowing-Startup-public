class_name RadialMenuItem
extends Button

var option_id: StringName = &""
var display_name := ""

var _direction := Vector2.UP
var _design_scale := 1.0
var _label: Label
var _node_fill := Color("2f433a")
var _node_inner_fill := Color("1d2d27")
var _node_outline := Color(0.73, 0.82, 0.70, 0.62)
var _icon_colour := Color("f2f5ea")
var _label_colour := Color("b9cab3")
var _highlight_colour := Color("abcc91")
var _hover_icon_colour := Color("1d2d27")
var _primary_text_colour := Color("f2f5ea")
var _visual_diameter := 84.0
var _highlight_amount := 0.0
var _mouse_hovered := false
var _keyboard_selected := false
var _disabled_state := false
var _activation_progress := 0.0
var _highlight_tween: Tween


func _init() -> void:
	flat = true
	text = ""
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = false

	_label = Label.new()
	_label.name = "Label"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", _label_colour)
	add_child(_label)


func setup(new_option_id: StringName, new_display_name: String) -> void:
	option_id = new_option_id
	display_name = new_display_name
	_label.text = display_name
	tooltip_text = display_name.capitalize()


func set_colour_scheme(scheme: Resource) -> void:
	if scheme == null:
		return
	_node_fill = scheme.get(&"node_fill")
	_node_inner_fill = scheme.get(&"node_inner_fill")
	_node_outline = scheme.get(&"outline")
	_icon_colour = scheme.get(&"primary_text")
	_label_colour = scheme.get(&"secondary_text")
	_highlight_colour = scheme.get(&"highlight")
	_hover_icon_colour = scheme.get(&"node_inner_fill")
	_primary_text_colour = scheme.get(&"primary_text")
	_update_label_colour()
	queue_redraw()


func apply_geometry(diameter: float, direction: Vector2, scale_factor: float) -> void:
	_direction = direction
	_design_scale = scale_factor
	_visual_diameter = diameter
	var hit_diameter := diameter + 16.0 * _design_scale
	custom_minimum_size = Vector2.ONE * hit_diameter
	size = Vector2.ONE * hit_diameter
	pivot_offset = size * 0.5
	_layout_label()
	queue_redraw()


func set_mouse_hovered(is_hovered: bool) -> void:
	if is_hovered and _disabled_state:
		return
	if _mouse_hovered == is_hovered:
		return
	_mouse_hovered = is_hovered
	_refresh_interaction_state()


func set_keyboard_selected(is_selected: bool) -> void:
	if is_selected and _disabled_state:
		return
	if _keyboard_selected == is_selected:
		return
	_keyboard_selected = is_selected
	_refresh_interaction_state()


func set_disabled_state(is_disabled: bool) -> void:
	if _disabled_state == is_disabled:
		return
	_disabled_state = is_disabled
	disabled = is_disabled
	mouse_default_cursor_shape = (
		Control.CURSOR_ARROW if is_disabled else Control.CURSOR_POINTING_HAND
	)
	if is_disabled:
		_mouse_hovered = false
		_keyboard_selected = false
	_refresh_interaction_state()
	_update_label_colour()
	queue_redraw()


func prepare_for_transition(is_activating: bool) -> void:
	if _highlight_tween != null and _highlight_tween.is_valid():
		_highlight_tween.kill()
	_mouse_hovered = false
	_activation_progress = 0.0
	z_index = 20 if is_activating else 0
	_label.modulate = Color.WHITE
	queue_redraw()


func set_activation_progress(progress: float) -> void:
	_activation_progress = clampf(progress, 0.0, 1.0)
	_label.modulate = Color(1.0, 1.0, 1.0, 1.0 - _activation_progress)
	queue_redraw()


func reset_transition_visuals() -> void:
	modulate = Color.WHITE
	_label.modulate = Color.WHITE
	_activation_progress = 0.0
	z_index = 5 if _mouse_hovered or _keyboard_selected else 0
	_refresh_interaction_state()
	queue_redraw()


func _refresh_interaction_state() -> void:
	var active := _mouse_hovered or _keyboard_selected
	z_index = 5 if active else 0

	if _highlight_tween != null and _highlight_tween.is_valid():
		_highlight_tween.kill()

	var target_amount := 0.0
	var target_scale := Vector2.ONE
	if _mouse_hovered:
		target_amount = 1.0
		target_scale = Vector2.ONE * 1.08
	elif _keyboard_selected:
		target_amount = 0.58
		target_scale = Vector2.ONE * 1.03
	_highlight_tween = create_tween()
	_highlight_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_highlight_tween.tween_method(
		_set_highlight_amount,
		_highlight_amount,
		target_amount,
		0.16
	)
	_highlight_tween.parallel().tween_property(self, "scale", target_scale, 0.16)


func _set_highlight_amount(amount: float) -> void:
	_highlight_amount = amount
	_update_label_colour()
	queue_redraw()


func _update_label_colour() -> void:
	var current_colour := _label_colour.lerp(_primary_text_colour, _highlight_amount)
	if _disabled_state:
		current_colour.a *= 0.38
	_label.add_theme_color_override("font_color", current_colour)


func _layout_label() -> void:
	var gap := 15.0 * _design_scale
	var label_size := Vector2(152.0, 28.0) * _design_scale
	var vertical_nudge := _direction.y * 18.0 * _design_scale
	var centre := size * 0.5
	var visual_radius := _visual_diameter * 0.5
	_label.size = label_size
	_label.add_theme_font_size_override("font_size", maxi(11, roundi(15.0 * _design_scale)))

	if _direction.y < -0.75:
		_label.position = Vector2(
			centre.x - label_size.x * 0.5,
			centre.y - visual_radius - gap - label_size.y
		)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif _direction.y > 0.75:
		_label.position = Vector2(
			centre.x - label_size.x * 0.5,
			centre.y + visual_radius + gap
		)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif _direction.x > 0.0:
		_label.position = Vector2(
			centre.x + visual_radius + gap,
			centre.y - label_size.y * 0.5 + vertical_nudge
		)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		_label.position = Vector2(
			centre.x - visual_radius - gap - label_size.x,
			centre.y - label_size.y * 0.5 + vertical_nudge
		)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _draw() -> void:
	var centre := size * 0.5
	var outer_radius := _visual_diameter * 0.5 - 1.0
	var inner_radius := _visual_diameter * 0.29
	var visual_amount := maxf(_highlight_amount, _activation_progress)
	var outline_width := maxf(1.0, (1.4 + visual_amount * 0.8) * _design_scale)
	var outer_fill := _node_fill.lerp(_highlight_colour, visual_amount * 0.24)
	var inner_fill := _node_inner_fill.lerp(_highlight_colour, visual_amount)
	var outline_colour := _node_outline.lerp(_highlight_colour, visual_amount)
	var icon_colour := _icon_colour.lerp(_hover_icon_colour, visual_amount)
	if _disabled_state:
		outer_fill = outer_fill.darkened(0.18)
		outer_fill.a *= 0.52
		inner_fill = inner_fill.darkened(0.20)
		inner_fill.a *= 0.48
		outline_colour.a *= 0.34
		icon_colour.a *= 0.34

	if visual_amount > 0.001 and not _disabled_state:
		var halo_colour := _highlight_colour
		var halo_strength := 1.0 if _mouse_hovered else 0.22
		if _activation_progress > 0.0:
			halo_strength = 0.70 + _activation_progress * 0.30
		halo_colour.a = 0.16 * visual_amount * halo_strength
		draw_circle(
			centre,
			outer_radius + (
				10.0 * visual_amount + 18.0 * _activation_progress
			) * _design_scale,
			halo_colour
		)

	draw_circle(centre, outer_radius, outer_fill)
	draw_circle(centre, inner_radius, inner_fill)
	draw_arc(centre, outer_radius, 0.0, TAU, 64, outline_colour, outline_width, true)
	if _keyboard_selected and not _disabled_state:
		var focus_colour := _highlight_colour
		focus_colour.a = 0.56
		draw_arc(
			centre,
			outer_radius + 5.0 * _design_scale,
			0.0,
			TAU,
			64,
			focus_colour,
			maxf(1.0, 1.2 * _design_scale),
			true
		)
	_draw_icon(centre, icon_colour)


func _draw_icon(centre: Vector2, icon_colour: Color) -> void:
	var icon_scale := _design_scale
	var stroke_width := maxf(1.5, 1.8 * icon_scale)

	match option_id:
		&"continue":
			var play_points := PackedVector2Array([
				centre + Vector2(-5.5, -9.0) * icon_scale,
				centre + Vector2(8.0, 0.0) * icon_scale,
				centre + Vector2(-5.5, 9.0) * icon_scale,
				centre + Vector2(-5.5, -9.0) * icon_scale,
			])
			draw_polyline(play_points, icon_colour, stroke_width, true)
		&"new_game":
			draw_line(
				centre + Vector2(-9.0, 0.0) * icon_scale,
				centre + Vector2(9.0, 0.0) * icon_scale,
				icon_colour,
				stroke_width,
				true
			)
			draw_line(
				centre + Vector2(0.0, -9.0) * icon_scale,
				centre + Vector2(0.0, 9.0) * icon_scale,
				icon_colour,
				stroke_width,
				true
			)
		&"load_game":
			var folder_points := PackedVector2Array([
				centre + Vector2(-11.0, -7.0) * icon_scale,
				centre + Vector2(-3.0, -7.0) * icon_scale,
				centre + Vector2(0.5, -3.5) * icon_scale,
				centre + Vector2(11.0, -3.5) * icon_scale,
				centre + Vector2(11.0, 8.0) * icon_scale,
				centre + Vector2(-11.0, 8.0) * icon_scale,
				centre + Vector2(-11.0, -7.0) * icon_scale,
			])
			draw_polyline(folder_points, icon_colour, stroke_width, true)
		&"options":
			var knob_positions := [-4.5, 5.0, -1.5]
			for line_index: int in 3:
				var y := (-7.0 + float(line_index) * 7.0) * icon_scale
				draw_line(
					centre + Vector2(-10.0 * icon_scale, y),
					centre + Vector2(10.0 * icon_scale, y),
					icon_colour,
					stroke_width,
					true
				)
				draw_circle(
					centre + Vector2(knob_positions[line_index] * icon_scale, y),
					2.2 * icon_scale,
					icon_colour
				)
		&"credits":
			draw_circle(centre + Vector2(0.0, -7.0) * icon_scale, 1.8 * icon_scale, icon_colour)
			draw_line(
				centre + Vector2(0.0, -1.5) * icon_scale,
				centre + Vector2(0.0, 9.0) * icon_scale,
				icon_colour,
				stroke_width,
				true
			)
		&"quit":
			draw_arc(
				centre + Vector2(0.0, 1.5) * icon_scale,
				9.0 * icon_scale,
				-PI * 0.25,
				PI * 1.25,
				28,
				icon_colour,
				stroke_width,
				true
			)
			draw_line(
				centre + Vector2(0.0, -11.0) * icon_scale,
				centre + Vector2(0.0, 0.5) * icon_scale,
				icon_colour,
				stroke_width,
				true
			)
