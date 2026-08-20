extends Control
class_name LoadGameScreen

# ============================================================
# PUBLIC API
# ============================================================
#
#   set_saves(entries: Array[Dictionary])   # rebuild the list
#   open()  /  close()  /  is_open() -> bool
#
# Each entry uses the keys SaveService.list_saves() produces:
#   slot, saved_at_text, day, money, valid
#
# Signals emitted:
#
#   load_requested(slot_name: String)
#   delete_requested(slot_name: String)
#   back_requested()
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# Presentation only. It does not read or write save files, and it does not
# change scenes. The host supplies the list and acts on the signals.
#
# Built from script rather than authored as a scene so it always matches
# UITheme; there is no .tscn to re-point if the palette changes.
#
# ============================================================

signal load_requested(slot_name: String)
signal delete_requested(slot_name: String)
signal back_requested()

const ROW_HEIGHT := 66.0

var _card: PanelContainer
var _list: VBoxContainer
var _empty: Label
var _open: bool = false
var _tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	modulate.a = 0.0
	_build()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = UITheme.SCRIM_HEAVY
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_card = PanelContainer.new()
	_card.name = "Card"
	_card.custom_minimum_size = Vector2(620, 0)
	_card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.PANEL_SOLID, UITheme.RADIUS_PANEL, 0.0,
			UITheme.HAIRLINE, 0.0, 0.0))
	centre.add_child(_card)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	_card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var accent := ColorRect.new()
	accent.color = UITheme.ACCENT
	accent.custom_minimum_size = Vector2(46, 3)
	column.add_child(accent)

	UITheme.label(column, "Title", "LOAD GAME", UITheme.FONT_TITLE, UITheme.INK)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	_empty = UITheme.label(column, "Empty",
		"No saved games yet.\nStart a new game and save from the pause menu.",
		UITheme.FONT_BODY, UITheme.INK_FAINT, true)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var back := Button.new()
	back.text = "BACK"
	UITheme.style_button(back, false, 42.0)
	back.pressed.connect(func() -> void: back_requested.emit())
	column.add_child(back)


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed(&"ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


# ==================================================================== content

func set_saves(entries: Array) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	_empty.visible = entries.is_empty()

	for entry in entries:
		_list.add_child(_make_row(entry))


func _make_row(entry: Dictionary) -> Control:
	var slot := String(entry.get("slot", ""))
	var valid := bool(entry.get("valid", false))

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD, 0.0,
			UITheme.HAIRLINE, 14.0, 10.0))

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	row.add_child(line)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 2)
	line.add_child(text_column)

	UITheme.label(text_column, "Slot", slot.to_upper(),
		UITheme.FONT_SUBHEAD, UITheme.INK)

	var detail := "Unreadable save"
	if valid:
		detail = "Day %d   %s   saved %s" % [
			int(entry.get("day", 0)),
			UITheme.format_money(int(entry.get("money", 0))),
			String(entry.get("saved_at_text", "")),
		]
	UITheme.label(text_column, "Detail", detail,
		UITheme.FONT_META, UITheme.INK_DIM if valid else UITheme.URGENT)

	var load_button := Button.new()
	load_button.text = "LOAD"
	load_button.custom_minimum_size = Vector2(110, 0)
	UITheme.style_button(load_button, true, 38.0)
	load_button.disabled = not valid
	load_button.pressed.connect(func() -> void: load_requested.emit(slot))
	line.add_child(load_button)

	var delete_button := Button.new()
	delete_button.text = "DELETE"
	delete_button.custom_minimum_size = Vector2(110, 0)
	UITheme.style_danger_button(delete_button, 38.0)
	delete_button.pressed.connect(func() -> void: delete_requested.emit(slot))
	line.add_child(delete_button)

	return row


# =============================================================== open / close

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_animate(1.0)


func close() -> void:
	if not _open:
		return
	_open = false
	_animate(0.0)


func is_open() -> bool:
	return _open


func _animate(target: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"modulate:a", target, UITheme.FADE)
	if target <= 0.0:
		_tween.tween_callback(func() -> void: visible = false)
