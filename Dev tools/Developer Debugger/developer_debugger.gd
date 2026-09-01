class_name ACADeveloperDebugger
extends CanvasLayer
## DEVELOPMENT ONLY. The SUPER DEBUGGER, opened with H while playing.
##
## Replaces the legacy MVP HUD as the normal developer interface. It exists so
## the current build can be explored without grinding money, waiting for the
## weather schedule to come round to the sky being tested, playing to day forty
## or driving forty contracts to see what opens after them.
##
## ONE implementation, mounted by `ACAPauseLayer`, which both the Town Screen
## and the mowing Gameplay UI already use. That is why the same overlay is
## available on both screens without either of them knowing about it.
##
## IT OWNS NO STATE. Every control reads and writes the existing authority:
##
##   money       GameSession  - money() / add_money() / try_spend(). There is no
##                              second balance here, and nothing writes _money.
##   weather     WorldClock   - WEATHER_PRESETS for the buttons, set_weather()
##                              to change one, so the scene and environment
##                              adapters react through the signal they already
##                              listen to.
##   day         WorldClock   - advance_days() / set_day_index(), which are
##                              `advance_minutes()` called a whole number of
##                              times. No second day variable, and `day_changed`
##                              fires once per day crossed, so Business,
##                              Agreements, Clippings and the Economy move
##                              exactly as they do when the days are lived.
##   contracts   GameSession  - dev_add_completed_contracts(), which finishes
##                              real contracts through the production path.
##                              `Business.contracts_completed()` is the count;
##                              nothing here writes a total.
##   cursor      AppUI        - a named mouse hold, never Input.mouse_mode.
##
## Nothing here is persisted: the values it changes are the real ones, so a
## save afterwards stores them through the ordinary save path.
##
## SCOPE. Four things: weather, money, day, completed contracts. Deliberately
## not a free camera, a save editor, a console, a variable inspector or an asset
## browser - this is a way to reach a game state quickly, not a second
## application.

## The cursor hold taken while the overlay is open. Mowing captures the cursor,
## so without this the panel could not be clicked.
const MOUSE_HOLD := &"developer_debugger"

## Drawn above every gameplay and pause layer in the project.
const OVERLAY_LAYER := 100

const QUICK_AMOUNTS: Array[int] = [100, 1000, -100]

## Day jumps offered as buttons. The exact setter covers everything else.
const QUICK_DAYS: Array[int] = [1, 7]

## Contract batches offered as buttons.
const QUICK_CONTRACTS: Array[int] = [1, 5, 10, 25]

var _current_weather: Label
var _balance: Label
var _amount_field: LineEdit
var _weather_buttons: Dictionary = {}
var _day: Label
var _day_field: LineEdit
var _day_note: Label
var _contracts: Label
var _contract_note: Label


func _ready() -> void:
	layer = OVERLAY_LAYER
	# Usable whether or not something has paused the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false

	GameSession.money_changed.connect(_on_money_changed)
	WorldClock.weather_changed.connect(_on_weather_changed)
	WorldClock.day_changed.connect(_on_day_changed)
	# The company's books tell the panel a contract landed. Nothing here counts.
	Business.review_posted.connect(_on_review_posted)


## Defensive: a screen can be torn down with the overlay still open, and the
## hold belongs to this node.
func _exit_tree() -> void:
	if visible:
		AppUI.release_mouse(MOUSE_HOLD)


# =================================================================== toggling

func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	visible = true
	AppUI.hold_mouse(MOUSE_HOLD)
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	AppUI.release_mouse(MOUSE_HOLD)


# ====================================================================== money
##
## GameSession stays the single authority. An exact balance is reached by
## asking it for the difference through its own public API rather than by
## writing a number into it, and it can never be taken below zero because
## `try_spend()` refuses what is not there.

func set_balance(target: int) -> void:
	var wanted := maxi(0, target)
	var current: int = GameSession.money()
	if wanted > current:
		GameSession.add_money(wanted - current)
	elif wanted < current:
		GameSession.try_spend(current - wanted)


func adjust_balance(delta: int) -> void:
	set_balance(GameSession.money() + delta)


# ==================================================================== weather

func set_weather(preset: String) -> void:
	WorldClock.set_weather(preset)


# ======================================================================== day
##
## WorldClock stays the single authority, and both of these are its own
## `advance_minutes()` called a whole number of times - so the season, the
## weather schedule and every `day_changed` listener move exactly as they do
## when the days are played through, one at a time.
##
## FORWARD ONLY, and the panel says so rather than silently doing nothing: the
## clock's consumers all early-return on a day they have already seen, so
## running it backwards would leave a world whose books are ahead of its
## calendar.

func advance_days(days: int) -> void:
	WorldClock.advance_days(days)


func set_day_number(player_facing_day: int) -> void:
	var target := maxi(player_facing_day, 1) - 1
	if target <= WorldClock.day_index():
		_day_note.text = "Forward only - day %d has passed." % (target + 1)
		_refresh_day()
		return
	WorldClock.set_day_index(target)
	_day_note.text = ""


# ================================================================= contracts
##
## GameSession finishes real contracts through the production path; Business
## counts them. Nothing here writes a total, and no money is paid - the balance
## has its own controls above.

func add_completed_contracts(count: int) -> void:
	var settled := GameSession.dev_add_completed_contracts(count)
	if settled < count:
		_contract_note.text = "Settled %d of %d - the market had no more work." 			% [settled, count]
	else:
		_contract_note.text = ""
	_refresh_contracts()


# =================================================================== readouts

func _refresh() -> void:
	_refresh_money()
	_refresh_weather()
	_refresh_day()
	_refresh_contracts()


func _refresh_money() -> void:
	var amount: int = GameSession.money()
	_balance.text = "Balance: %s" % UITheme.format_money(amount)
	if not _amount_field.has_focus():
		_amount_field.text = str(amount)


func _refresh_weather() -> void:
	var preset: String = WorldClock.weather_preset()
	_current_weather.text = "Current: %s" % preset
	for key in _weather_buttons:
		var button: Button = _weather_buttons[key]
		button.set_pressed_no_signal(String(key) == preset)


func _refresh_day() -> void:
	_day.text = "Day %d  -  %s" % [WorldClock.day_number(),
		WorldClock.timestamp_text()]
	if not _day_field.has_focus():
		_day_field.text = str(WorldClock.day_number())


func _refresh_contracts() -> void:
	_contracts.text = "Completed: %d" % Business.contracts_completed()


func _on_money_changed(_amount: int) -> void:
	_refresh_money()


func _on_weather_changed(_preset: String) -> void:
	_refresh_weather()


func _on_day_changed(_day_index: int) -> void:
	if visible:
		_refresh_day()


func _on_review_posted(_review: Dictionary) -> void:
	if visible:
		_refresh_contracts()


# =================================================================== the panel
##
## Built in code and deliberately plain: a slate developer panel, not a screen
## the player will ever see. It borrows UITheme only for the colours and the
## money formatter so it does not invent a second look.

func _build() -> void:
	var root := PanelContainer.new()
	root.name = "Panel"
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(24, 24)
	root.custom_minimum_size = Vector2(330, 0)
	root.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.PANEL_SOLID, UITheme.RADIUS_PANEL, 1.0,
			UITheme.HAIRLINE, 16.0, 14.0))
	add_child(root)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	root.add_child(column)

	UITheme.label(column, "Title", "SUPER DEBUGGER",
		UITheme.FONT_SUBHEAD, UITheme.INK)
	UITheme.label(column, "Hint", "H - Close", UITheme.FONT_MICRO, UITheme.INK_FAINT)

	# WORLD, then PROGRESSION, then ECONOMY. The order is how often a state is
	# reached FOR: what day it is and what the sky is doing come before how many
	# contracts are behind the business, which comes before the balance.
	_build_group(column, "WORLD")
	_build_day_section(column)
	_build_weather_section(column)
	_build_group(column, "PROGRESSION")
	_build_contracts_section(column)
	_build_group(column, "ECONOMY")
	_build_money_section(column)


## A section band. Cheap: a rule and a heading, which is all the grouping this
## panel needs - collapsible sections would be a second UI project.
func _build_group(column: VBoxContainer, title: String) -> void:
	column.add_child(_rule())
	UITheme.label(column, "%s Group" % title, title,
		UITheme.FONT_LABEL, UITheme.ACCENT_BRIGHT)


func _build_day_section(column: VBoxContainer) -> void:
	UITheme.label(column, "Day Heading", "DAY",
		UITheme.FONT_LABEL, UITheme.INK_DIM)
	_day = UITheme.label(column, "Day Current", "Day -",
		UITheme.FONT_BODY, UITheme.INK)

	var jump_row := HBoxContainer.new()
	jump_row.name = "Day Jump Row"
	jump_row.add_theme_constant_override("separation", 6)
	column.add_child(jump_row)

	for days in QUICK_DAYS:
		var button := Button.new()
		button.name = "Day +%d" % days
		button.text = "+%d DAY%s" % [days, "" if days == 1 else "S"]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(button, false, 28.0, UITheme.FONT_MICRO)
		button.pressed.connect(advance_days.bind(days))
		jump_row.add_child(button)

	var set_row := HBoxContainer.new()
	set_row.name = "Day Set Row"
	set_row.add_theme_constant_override("separation", 6)
	column.add_child(set_row)

	_day_field = LineEdit.new()
	_day_field.name = "Day Field"
	_day_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_day_field.custom_minimum_size = Vector2(90, 30)
	_day_field.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_day_field.text_submitted.connect(func(_t: String) -> void: _apply_day_field())
	set_row.add_child(_day_field)

	var set_button := Button.new()
	set_button.name = "Set Day"
	set_button.text = "SET DAY"
	UITheme.style_button(set_button, true, 30.0, UITheme.FONT_MICRO)
	set_button.pressed.connect(_apply_day_field)
	set_row.add_child(set_button)

	_day_note = UITheme.label(column, "Day Note", "",
		UITheme.FONT_MICRO, UITheme.INK_FAINT)
	_day_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_contracts_section(column: VBoxContainer) -> void:
	UITheme.label(column, "Contracts Heading", "COMPLETED CONTRACTS",
		UITheme.FONT_LABEL, UITheme.INK_DIM)
	_contracts = UITheme.label(column, "Contracts Current", "Completed: -",
		UITheme.FONT_BODY, UITheme.INK)

	var grid := GridContainer.new()
	grid.name = "Contract Buttons"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	column.add_child(grid)

	for count in QUICK_CONTRACTS:
		var button := Button.new()
		button.name = "Contracts +%d" % count
		button.text = "+%d" % count
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(button, false, 28.0, UITheme.FONT_MICRO)
		button.pressed.connect(add_completed_contracts.bind(count))
		grid.add_child(button)

	_contract_note = UITheme.label(column, "Contracts Note",
		"Settled through the real path. No payment.",
		UITheme.FONT_MICRO, UITheme.INK_FAINT)
	_contract_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_weather_section(column: VBoxContainer) -> void:
	UITheme.label(column, "Weather Heading", "WEATHER",
		UITheme.FONT_LABEL, UITheme.INK_DIM)
	_current_weather = UITheme.label(column, "Weather Current", "Current: -",
		UITheme.FONT_BODY, UITheme.ACCENT_BRIGHT)

	# Generated from the authority, so a preset added to WorldClock appears
	# here with no change to this file.
	var grid := GridContainer.new()
	grid.name = "Weather Buttons"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)

	for preset in WorldClock.WEATHER_PRESETS:
		var button := Button.new()
		button.name = preset
		button.text = preset.to_upper()
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(button, false, 30.0, UITheme.FONT_MICRO)
		button.pressed.connect(_on_weather_button_pressed.bind(preset))
		grid.add_child(button)
		_weather_buttons[preset] = button


func _build_money_section(column: VBoxContainer) -> void:
	UITheme.label(column, "Money Heading", "MONEY",
		UITheme.FONT_LABEL, UITheme.INK_DIM)
	_balance = UITheme.label(column, "Balance", "Balance: -",
		UITheme.FONT_BODY, UITheme.MONEY)

	var set_row := HBoxContainer.new()
	set_row.name = "Set Row"
	set_row.add_theme_constant_override("separation", 6)
	column.add_child(set_row)

	_amount_field = LineEdit.new()
	_amount_field.name = "Amount"
	_amount_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_field.custom_minimum_size = Vector2(110, 30)
	_amount_field.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_amount_field.text_submitted.connect(func(_text: String) -> void: _apply_field())
	set_row.add_child(_amount_field)

	var set_button := Button.new()
	set_button.name = "Set Balance"
	set_button.text = "SET BALANCE"
	UITheme.style_button(set_button, true, 30.0, UITheme.FONT_MICRO)
	set_button.pressed.connect(_apply_field)
	set_row.add_child(set_button)

	var quick_row := HBoxContainer.new()
	quick_row.name = "Quick Row"
	quick_row.add_theme_constant_override("separation", 6)
	column.add_child(quick_row)

	for amount in QUICK_AMOUNTS:
		var button := Button.new()
		button.name = "Quick %d" % amount
		button.text = "%s%s" % ["+" if amount > 0 else "-",
			UITheme.format_money(absi(amount))]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(button, false, 28.0, UITheme.FONT_MICRO)
		button.pressed.connect(adjust_balance.bind(amount))
		quick_row.add_child(button)


func _rule() -> Control:
	var line := ColorRect.new()
	line.name = "Rule"
	line.color = UITheme.HAIRLINE
	line.custom_minimum_size = Vector2(0, 1)
	return line


func _on_weather_button_pressed(preset: String) -> void:
	set_weather(preset)
	# The preset may already have been the current one, in which case WorldClock
	# emits nothing; put the toggles back the way the authority says.
	_refresh_weather()


func _apply_field() -> void:
	var text := _amount_field.text.strip_edges().replace(",", "").replace("$", "")
	if not text.is_valid_int():
		_refresh_money()
		return
	set_balance(int(text))
	_amount_field.release_focus()
	_refresh_money()


func _apply_day_field() -> void:
	var text := _day_field.text.strip_edges()
	if not text.is_valid_int():
		_refresh_day()
		return
	set_day_number(int(text))
	_day_field.release_focus()
	_refresh_day()
