class_name NewGameScreen
extends Control
## The NEW GAME difficulty choice.
##
## ============================================================
## PUBLIC API
## ============================================================
##
##   open()                     fade in, focus the default option
##   close()                    fade out
##   is_open() -> bool
##   set_options(list)          [{id, name, description, characteristics}]
##   select(id)                 move the selection without confirming
##   selected() -> StringName
##
## Signals:
##
##   difficulty_chosen(id: StringName)   START was pressed
##   back_requested()                    BACK was pressed, or Escape
##
## ============================================================
## HOST INTEGRATION NOTES
## ============================================================
##
## Presentation only, like every other component in `res://UI/`. It does not
## know what a difficulty DOES, it does not start a game, and it does not read
## `ACADifficulty` - the host passes the list in and acts on the signal. That is
## why it can be opened by the UI smoke test with nothing else loaded.
##
## ============================================================
## WHY THE LAYOUT IS IN CODE
## ============================================================
##
## Three cards, laid out from a list whose length is a data decision. Authoring
## that as a fixed scene would mean a fourth difficulty could not be added
## without opening the editor, and would put the same eleven nodes in the file
## three times. The rest of `res://UI/` is generated from GDScript for the same
## reason; this one skips the generation step and builds itself.

signal difficulty_chosen(id: StringName)
signal back_requested()

## Which card starts selected, by id. The host sets this through `select()`.
const CARD_MIN_WIDTH := 300.0
const CARD_MAX_WIDTH := 360.0

var _options: Array[Dictionary] = []
var _selected: StringName = &""
var _cards: Dictionary = {}
var _row: HBoxContainer = null
var _start: Button = null
var _built := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	modulate.a = 0.0


func _build() -> void:
	if _built:
		return
	_built = true

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = UITheme.SCRIM_HEAVY
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(column)

	UITheme.label(column, "Title", "START A NEW BUSINESS",
		UITheme.FONT_TITLE, UITheme.INK)
	var blurb := UITheme.label(column, "Blurb",
		"How hard is the season going to be? This sets the money side of the "
		+ "game and it stays with this save.", UITheme.FONT_BODY,
		UITheme.INK_DIM, true)
	blurb.custom_minimum_size = Vector2(0, 0)

	var gap := Control.new()
	gap.name = "Gap"
	gap.custom_minimum_size = Vector2(0, 18)
	column.add_child(gap)

	_row = HBoxContainer.new()
	_row.name = "Options"
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 18)
	# The cards HUG their content rather than filling the screen. Stretched to
	# the full height they were two thirds empty cream, which reads as an
	# unfinished layout rather than as a card.
	_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_child(_row)

	var gap2 := Control.new()
	gap2.name = "Gap2"
	gap2.custom_minimum_size = Vector2(0, 20)
	column.add_child(gap2)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	column.add_child(buttons)

	var back := Button.new()
	back.name = "Back"
	back.text = "BACK"
	back.custom_minimum_size = Vector2(190, 46)
	UITheme.style_button(back, false, 46, UITheme.FONT_SUBHEAD)
	back.pressed.connect(func() -> void: back_requested.emit())
	buttons.add_child(back)

	_start = Button.new()
	_start.name = "Start"
	_start.text = "START"
	_start.custom_minimum_size = Vector2(230, 46)
	UITheme.style_accent_button(_start, 46, UITheme.FONT_SUBHEAD)
	_start.pressed.connect(func() -> void:
		if _selected != &"":
			difficulty_chosen.emit(_selected))
	buttons.add_child(_start)


# ===================================================================== options

## `list` entries: { id: StringName, name: String, description: String,
## characteristics: Array[String] }. Anything missing is simply not drawn.
func set_options(list: Array) -> void:
	_build()
	_options.clear()
	for entry in list:
		if entry is Dictionary:
			_options.append(entry as Dictionary)
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_cards.clear()
	for option in _options:
		_add_card(option)
	if _selected == &"" and not _options.is_empty():
		select(StringName(String(_options[0].get("id", ""))))


## THE CARD. A cream PAPER surface, because what the player is reading is a
## description of a job market rather than part of the game world.
func _add_card(option: Dictionary) -> void:
	var id := StringName(String(option.get("id", "")))
	var card := Button.new()
	card.name = "Card %s" % id
	card.toggle_mode = true
	card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_FILL
	card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 300)
	card.focus_mode = Control.FOCUS_ALL
	card.pressed.connect(func() -> void: select(id))
	_row.add_child(card)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# A short mower-orange rule at the top of the card, so the selected one is
	# marked by a SHAPE as well as by a colour. See the accessibility note in
	# `UITheme`: nothing here is carried by colour alone.
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = UITheme.ORANGE
	rule.custom_minimum_size = Vector2(0, 4)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	column.add_child(spacer)

	UITheme.label(column, "Name", String(option.get("name", String(id))).to_upper(),
		UITheme.FONT_HEADING, UITheme.PAPER_INK)
	UITheme.label(column, "Description", String(option.get("description", "")),
		UITheme.FONT_BODY, UITheme.PAPER_INK_DIM, true)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	column.add_child(spacer2)

	for point in (option.get("characteristics", []) as Array):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(row)
		var dot := UITheme.label(row, "Dot", "-", UITheme.FONT_BODY, UITheme.ACCENT)
		dot.custom_minimum_size = Vector2(10, 0)
		var text := UITheme.label(row, "Text", String(point), UITheme.FONT_LABEL,
			UITheme.PAPER_INK_DIM, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_cards[id] = card
	_style_card(card, false)


## Selected cards are raised, ruled in forest green and CAPTIONED as selected;
## unselected ones sit back. Three differences, so the state survives being
## looked at by somebody who cannot tell the two greens apart.
func _style_card(card: Button, is_selected: bool) -> void:
	var background: Color = UITheme.PAPER_BG2 if is_selected else UITheme.PAPER_BG
	var border: float = 3.0 if is_selected else 1.0
	var border_colour: Color = UITheme.ACCENT if is_selected else UITheme.PAPER_RULE
	for state in ["normal", "hover", "pressed", "focus"]:
		var bg := background
		if state == "hover" and not is_selected:
			bg = UITheme.PAPER_BG2
		var edge := border_colour
		var width := border
		if state == "focus":
			edge = UITheme.ACCENT_BRIGHT
			width = maxf(border, 3.0)
		card.add_theme_stylebox_override(state,
			UITheme.stylebox(bg, UITheme.RADIUS_CARD, width, edge, 0.0, 0.0))
	var rule := card.get_node_or_null(^"Margin/Column/Rule") as ColorRect
	if rule != null:
		rule.color = UITheme.ORANGE if is_selected else UITheme.PAPER_RULE


func select(id: StringName) -> void:
	if not _cards.has(id):
		return
	_selected = id
	for key in _cards:
		var card: Button = _cards[key]
		var chosen: bool = key == id
		card.button_pressed = chosen
		_style_card(card, chosen)


func selected() -> StringName:
	return _selected


# ================================================================== visibility

func open() -> void:
	_build()
	visible = true
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, UITheme.FADE)
	if _cards.has(_selected):
		(_cards[_selected] as Button).grab_focus()
	elif _start != null:
		_start.grab_focus()


func close() -> void:
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, UITheme.FADE)
	t.tween_callback(func() -> void: visible = false)


func is_open() -> bool:
	return visible and modulate.a > 0.01


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.is_echo() \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		back_requested.emit()
		get_viewport().set_input_as_handled()
