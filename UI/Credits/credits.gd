extends Control
class_name CreditsScreen

# ============================================================
# PUBLIC API
# ============================================================
#
#   open()  /  close()  /  is_open() -> bool
#   refresh()                        # re-scan the credits folder
#   entry_count() -> int
#   selected_title() -> String
#   select_index(index: int)
#   detail_text() -> String          # what the right pane is showing
#
# Signals emitted:
#
#   back_requested()
#
# ============================================================
# WHAT IT SHOWS
# ============================================================
#
# A list of credit entries on the left, the selected entry's text on the
# right, scrollable. Everything comes from ACACreditsLoader, which scans
# ONE folder - see credits_loader.gd. Adding a credit is a file copy.
#
# Licence text is displayed VERBATIM. This screen never trims, wraps
# destructively, or summarises it.
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# Presentation only. It does not change scenes; the host acts on
# back_requested(). Built from script rather than authored as a scene so
# it always matches UITheme.
#
# ============================================================

signal back_requested()

const LIST_WIDTH := 300.0

var _card: PanelContainer
var _list: VBoxContainer
var _detail_title: Label
var _detail_body: Label
var _detail_scroll: ScrollContainer
var _empty: Label

var _entries: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _selected: int = -1
var _open: bool = false
var _tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	modulate.a = 0.0
	_build()
	refresh()


# ====================================================================== build

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
	_card.custom_minimum_size = Vector2(1000, 640)
	_card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.PANEL_SOLID, UITheme.RADIUS_PANEL, 0.0,
			UITheme.HAIRLINE, 0.0, 0.0))
	centre.add_child(_card)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	_card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var accent := ColorRect.new()
	accent.color = UITheme.ACCENT
	accent.custom_minimum_size = Vector2(46, 3)
	column.add_child(accent)

	UITheme.label(column, "Title", "CREDITS", UITheme.FONT_TITLE, UITheme.INK)
	UITheme.label(column, "Subtitle",
		"Third-party software, art and audio used in A Cut Above: Mow & Grow. "
		+ "Each licence is reproduced in full.",
		UITheme.FONT_META, UITheme.INK_DIM, true)

	var panes := HBoxContainer.new()
	panes.name = "Panes"
	panes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panes.add_theme_constant_override("separation", 22)
	column.add_child(panes)

	# ------------------------------------------------------------ left: list
	var list_scroll := ScrollContainer.new()
	list_scroll.name = "ListScroll"
	list_scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panes.add_child(list_scroll)

	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	list_scroll.add_child(_list)

	# --------------------------------------------------------- right: detail
	var detail_panel := PanelContainer.new()
	detail_panel.name = "Detail"
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD, 0.0,
			UITheme.HAIRLINE, 18.0, 14.0))
	panes.add_child(detail_panel)

	var detail_column := VBoxContainer.new()
	detail_column.add_theme_constant_override("separation", 8)
	detail_panel.add_child(detail_column)

	_detail_title = UITheme.label(detail_column, "DetailTitle", "",
		UITheme.FONT_SUBHEAD, UITheme.ACCENT_BRIGHT)

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.name = "DetailScroll"
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_column.add_child(_detail_scroll)

	_detail_body = Label.new()
	_detail_body.name = "DetailBody"
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.add_theme_font_size_override("font_size", UITheme.FONT_META)
	_detail_body.add_theme_color_override("font_color", UITheme.INK_DIM)
	_detail_scroll.add_child(_detail_body)

	_empty = UITheme.label(column, "Empty",
		"No credit files found in %s." % ACACreditsLoader.CREDITS_DIRECTORY,
		UITheme.FONT_BODY, UITheme.INK_FAINT, true)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.visible = false

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "BACK"
	back.custom_minimum_size = Vector2(160, 0)
	UITheme.style_button(back, false, 42.0)
	back.pressed.connect(func() -> void: back_requested.emit())
	footer.add_child(back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)


# ==================================================================== content

## Re-scan the credits folder and rebuild the list. Called on _ready() and
## every time the screen opens, so a file added while the game is running in
## the editor shows up without a restart.
func refresh() -> void:
	_entries = ACACreditsLoader.list_entries()

	for button in _buttons:
		button.queue_free()
	_buttons.clear()
	_selected = -1

	for i in _entries.size():
		var entry := _entries[i]
		var button := Button.new()
		button.text = String(entry["title"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		# A long pack name is trimmed with an ellipsis rather than cut mid-word,
		# and the full title stays reachable as a tooltip.
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = String(entry["title"])
		UITheme.style_button(button, false, 38.0, UITheme.FONT_LABEL)
		var index := i
		button.pressed.connect(func() -> void: select_index(index))
		_list.add_child(button)
		_buttons.append(button)

	_empty.visible = _entries.is_empty()
	if _entries.is_empty():
		_detail_title.text = ""
		_detail_body.text = ""
	else:
		select_index(0)


func entry_count() -> int:
	return _entries.size()


func entry_titles() -> PackedStringArray:
	var titles := PackedStringArray()
	for entry in _entries:
		titles.append(String(entry["title"]))
	return titles


func selected_title() -> String:
	if _selected < 0 or _selected >= _entries.size():
		return ""
	return String(_entries[_selected]["title"])


## What the right-hand pane is currently showing, verbatim.
func detail_text() -> String:
	return _detail_body.text


func select_index(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	_selected = index
	var entry := _entries[index]
	_detail_title.text = String(entry["title"]).to_upper()
	var text := ACACreditsLoader.load_text(String(entry["path"]))
	_detail_body.text = text if not text.is_empty() else "(this credit file could not be read)"
	_detail_scroll.scroll_vertical = 0

	for i in _buttons.size():
		_buttons[i].add_theme_color_override(
			"font_color", UITheme.ACCENT_BRIGHT if i == index else UITheme.INK)


# =============================================================== open / close

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	refresh()
	_animate(1.0)
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	_animate(0.0)


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed(&"ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


func _animate(target: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"modulate:a", target, UITheme.FADE)
	if target <= 0.0:
		_tween.tween_callback(func() -> void: visible = false)
