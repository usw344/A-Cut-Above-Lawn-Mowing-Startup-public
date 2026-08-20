extends Node
## DEV TOOL - not part of the Job System runtime.
##
## Regenerates JobCard.tscn and JobBoard.tscn from code, the same way the Town
## project builds its own HUD scenes. Run BuildJobUI.tscn in the editor (or
## headless) after changing the UI layout:
##
##     godot --headless --path <project> res://Main Area/ACA_JobSystem/tools/BuildJobUI.tscn
##
## Nothing in job_system/ or demo/ loads this file. It may be deleted from a
## shipping build without affecting anything.

const UI_DIR := "res://Main Area/ACA_JobSystem/job_system/ui/"
const CARD_PATH := UI_DIR + "JobCard.tscn"
const BOARD_PATH := UI_DIR + "JobBoard.tscn"

const S := preload("res://Main Area/ACA_JobSystem/job_system/ui/job_ui_style.gd")


func _ready() -> void:
	build_card()
	build_board()
	print("JOB UI BUILD OK")
	get_tree().quit()


# ===================================================================== JobCard

static func build_card() -> void:
	var root := PanelContainer.new()
	root.name = "JobCard"
	root.set_script(load(UI_DIR + "job_card.gd"))
	root.add_theme_stylebox_override("panel", S.stylebox(S.CARD_BG, 12, 1.0, S.HAIRLINE, 0, 0))

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var accent := ColorRect.new()
	accent.name = "AccentBar"
	accent.color = S.ACCENT
	accent.custom_minimum_size = Vector2(0, 3)
	col.add_child(accent)

	var title := S.label(col, "Title", "JOB SITE", 20, S.INK)
	title.add_theme_constant_override("line_spacing", 0)
	S.label(col, "Meta", "Property   -   Lawn", 13, S.INK_DIM)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 4)
	col.add_child(rows)

	var row_a := _kv_row(rows, "RowA", "Estimated Time", "-")
	var row_b := _kv_row(rows, "RowB", "Pay", "-")
	var row_c := _kv_row(rows, "RowC", "Progress", "0%")

	var bar := ProgressBar.new()
	bar.name = "Progress"
	bar.custom_minimum_size = Vector2(0, 6)
	bar.show_percentage = false
	bar.value = 0.0
	bar.add_theme_stylebox_override("background", S.stylebox(Color(0.075, 0.094, 0.106, 0.9), 3, 0.0, S.HAIRLINE, 0, 0))
	bar.add_theme_stylebox_override("fill", S.stylebox(S.ACCENT, 3, 0.0, S.HAIRLINE, 0, 0))
	col.add_child(bar)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)

	var footer_label := S.label(footer, "FooterLabel", "Offer expires in -", 13, S.INK_DIM)
	footer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var action := S.button(footer, "ActionButton", "ACCEPT", true, 36, 14)
	action.custom_minimum_size = Vector2(168, 36)

	root.set("accent_bar", accent)
	root.set("title_label", title)
	root.set("meta_label", col.get_node("Meta"))
	root.set("row_a_key", row_a.get_node("Key"))
	root.set("row_a_value", row_a.get_node("Value"))
	root.set("row_b_key", row_b.get_node("Key"))
	root.set("row_b_value", row_b.get_node("Value"))
	root.set("row_c", row_c)
	root.set("row_c_key", row_c.get_node("Key"))
	root.set("row_c_value", row_c.get_node("Value"))
	root.set("progress_bar", bar)
	root.set("footer", footer)
	root.set("footer_label", footer_label)
	root.set("action_button", action)

	_save(root, CARD_PATH)


static func _kv_row(parent: Node, node_name: String, key: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var k := S.label(row, "Key", key, 13, S.INK_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := S.label(row, "Value", value, 15, S.INK)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return row


# ==================================================================== JobBoard

static func build_board() -> void:
	var root := Control.new()
	root.name = "JobBoard"
	root.set_script(load(UI_DIR + "job_board.gd"))
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Leaves the host's top information bar visible and uncovered.
	root.offset_top = S.TOP_BAR_HEIGHT
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = S.DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var frame := MarginContainer.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", 28)
	frame.add_theme_constant_override("margin_right", 28)
	frame.add_theme_constant_override("margin_top", 26)
	frame.add_theme_constant_override("margin_bottom", 26)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(row)

	var left := Control.new()
	left.name = "SpacerL"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(760, 0)
	panel.size_flags_vertical = Control.SIZE_FILL
	panel.add_theme_stylebox_override("panel", S.stylebox(S.PANEL_BG, 16, 1.0, S.HAIRLINE, 0, 0))
	row.add_child(panel)

	var right := Control.new()
	right.name = "SpacerR"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	# ---- header
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	col.add_child(header)

	var head_spacer := Control.new()
	head_spacer.name = "HeadSpacer"
	head_spacer.custom_minimum_size = Vector2(110, 0)
	header.add_child(head_spacer)

	var titles := VBoxContainer.new()
	titles.name = "Titles"
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)

	var title := S.label(titles, "Title", "JOBS", 26, S.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := S.label(titles, "Subtitle", "0 offers on the board", 13, S.INK_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var close_button := S.button(header, "CloseButton", "CLOSE", false, 34, 13)
	close_button.custom_minimum_size = Vector2(110, 34)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.color = S.HAIRLINE
	divider.custom_minimum_size = Vector2(0, 1)
	col.add_child(divider)

	# ---- tabs
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	col.add_child(tabs)

	var tab_available := _tab_button(tabs, "AvailableTab", "AVAILABLE  0")
	var tab_current := _tab_button(tabs, "CurrentTab", "CURRENT  0")
	var tab_past := _tab_button(tabs, "PastTab", "PAST  0")

	# ---- transient player-facing message (e.g. current-job capacity)
	var message := S.label(col, "Message", "", 13, S.WARN, true)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.visible = false

	# ---- body: the scrolling list, with an empty state layered over it
	var body := Control.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(0, 320)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	var empty_box := CenterContainer.new()
	empty_box.name = "EmptyBox"
	empty_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	empty_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(empty_box)

	var empty := S.label(empty_box, "Empty", "", 14, S.INK_FAINT, true)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.custom_minimum_size = Vector2(420, 0)

	root.set("card_scene", load(CARD_PATH))
	root.set("title_label", title)
	root.set("subtitle_label", subtitle)
	root.set("close_button", close_button)
	root.set("available_tab_button", tab_available)
	root.set("current_tab_button", tab_current)
	root.set("past_tab_button", tab_past)
	root.set("list_container", list)
	root.set("scroll", scroll)
	root.set("empty_label", empty)
	root.set("message_label", message)

	_save(root, BOARD_PATH)


static func _tab_button(parent: Node, node_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	parent.add_child(b)
	return S.style_tab(b)


# ===================================================================== saving

static func _own(root: Node, target: Node = null) -> void:
	var node: Node = target if target != null else root
	for child in node.get_children():
		child.owner = root
		_own(root, child)


static func _save(root: Node, path: String) -> void:
	_own(root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed for %s (%d)" % [path, err])
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("save failed for %s (%d)" % [path, err])
	else:
		print("  scene  ", path)
