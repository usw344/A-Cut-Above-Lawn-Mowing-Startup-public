extends Control
class_name ControlsHelp

# ============================================================
# PUBLIC API
# ============================================================
#
# Host project should call:
#
#   open()
#   close()
#   is_open() -> bool
#
#   set_title(value: String)                 # default "MOWER CONTROLS"
#   set_bindings(rows: PackedStringArray)    # replace the whole list
#
# Signals emitted:
#
#   closed        # CLOSE pressed, Escape pressed, or backdrop clicked
#
# THE BINDINGS FORMAT - one string per row, key and description split by
# a single "|":
#
#   "W / S|Drive Forward / Reverse"
#   "MOUSE|Steer & Look"
#   "ESC|Pause"
#
# A row with no "|" is drawn as a section heading:
#
#   "MOWING"
#
# The default list is the DEFAULT_BINDINGS constant a few lines below.
# Edit it there for a permanent change, or call set_bindings() at runtime
# to swap in gamepad prompts. Rows rebuild immediately.
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# This script preloads nothing. Rows are built from code at runtime,
# so there is no row scene to keep in sync.
#
# Controls Help.tscn references exactly one external resource:
#
#   res://UI/Theme/Game UI.theme.tres   (root node theme property)
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# This overlay does NOT read InputMap and does NOT know the host's real
# key bindings. It is a readable reference card. If the production game
# gains rebindable controls, feed the real bindings in with
# set_bindings() rather than making this component query InputMap.
#
# Two normal entry points:
#   - from the Settings screen (its controls_requested signal)
#   - once at the start of a job, so a first-time player has a chance
#
# The root is a full-rect Control with mouse_filter STOP and its own dim
# layer. process_mode is ALWAYS, so it works over a paused tree.
#
# ============================================================


signal closed()

## Row format: "KEY|Description", or a bare string for a section heading.
const DEFAULT_BINDINGS: PackedStringArray = [
	"MOWING",
	"W / S|Drive Forward / Reverse",
	"A / D|Steer Left / Right",
	"MOUSE|Look Around",
	"SHIFT|Boost",
	"GENERAL",
	"ESC|Pause",
	"TAB|Job Details",
	"F|Refuel At Trailer",
]

## Clicking the dimmed area outside the card closes the overlay.
@export var close_on_click_outside: bool = true

@onready var _holder: Control = %CardHolder
@onready var _scrim_button: Button = %ScrimButton
@onready var _title: Label = %Title
@onready var _rows: VBoxContainer = %Rows
@onready var _close_button: Button = %CloseButton

var _open: bool = false
var _tween: Tween


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_close_button.pressed.connect(close)
	_scrim_button.pressed.connect(func() -> void:
		if close_on_click_outside:
			close())
	set_bindings(DEFAULT_BINDINGS)


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ============================================================ open / close

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_animate(1.0, 14.0, 0.0)
	_close_button.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	_animate(0.0, 0.0, 8.0)
	closed.emit()


func is_open() -> bool:
	return _open


# ================================================================ contents

func set_title(value: String) -> void:
	_title.text = value.to_upper()


## Rebuilds the whole list. See the format note in the header.
func set_bindings(rows: PackedStringArray) -> void:
	for child in _rows.get_children():
		child.queue_free()
	for row in rows:
		if row.contains("|"):
			_add_binding_row(row)
		else:
			_add_section_row(row)


func _add_section_row(text: String) -> void:
	# Sections after the first get breathing room above them.
	if _rows.get_child_count() > 0:
		var gap := Control.new()
		gap.name = "SectionGap"
		gap.custom_minimum_size = Vector2(0, 14)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(gap)

	var heading := Label.new()
	heading.name = "Section"
	heading.text = text.to_upper()
	heading.add_theme_font_size_override("font_size", UITheme.FONT_MICRO)
	heading.add_theme_color_override("font_color", UITheme.ACCENT)
	_rows.add_child(heading)


func _add_binding_row(row: String) -> void:
	var parts := row.split("|", true, 1)
	var key_text := parts[0].strip_edges()
	var description := parts[1].strip_edges() if parts.size() > 1 else ""

	var line := HBoxContainer.new()
	line.name = "Row"
	line.add_theme_constant_override("separation", 16)
	_rows.add_child(line)

	# The key chip: fixed width so every description starts on the same
	# column, however long the key name is.
	var chip := PanelContainer.new()
	chip.name = "KeyChip"
	chip.custom_minimum_size = Vector2(132, 0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CHIP_BG, UITheme.RADIUS_BUTTON, 1.0,
			UITheme.HAIRLINE, 12, 6))
	line.add_child(chip)

	var key_label := Label.new()
	key_label.name = "Key"
	key_label.text = key_text
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", UITheme.FONT_META)
	key_label.add_theme_color_override("font_color", UITheme.INK)
	chip.add_child(key_label)

	var desc_label := Label.new()
	desc_label.name = "Description"
	desc_label.text = description
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	desc_label.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
	desc_label.add_theme_color_override("font_color", UITheme.INK_DIM)
	line.add_child(desc_label)


func _animate(target_alpha: float, from_offset: float, to_offset: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_holder.position.y = from_offset
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", target_alpha, UITheme.FADE)
	_tween.tween_property(_holder, "position:y", to_offset, UITheme.FADE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if target_alpha <= 0.0:
		_tween.set_parallel(false)
		_tween.tween_callback(func() -> void: visible = false)
