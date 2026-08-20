class_name ACABusinessServices
extends Control
## THE THREE REAL TOWN SERVICES: the Supply Store, the Business office and the
## Mower workshop.
##
## Replaces the "Coming Soon" placeholder for `supply_store`, `business_hq` and
## `mower_dealer`. `future_lot` still gets the placeholder, because there really
## is nothing there yet.
##
## Built in code rather than authored as a scene. Three panels of stacked rows
## is exactly the kind of UI that is quicker to READ as a script than to trace
## through a `.tscn`, and it keeps every string next to the logic that decides
## when to show it.
##
## ---------------------------------------------------------------------------
## OWNERSHIP
## ---------------------------------------------------------------------------
##
## This panel owns NOTHING. It reads `Economy`, `MowerUpgrades`, `MowerFuel` and
## `GameSession`, and it asks them to do things. Every price comes from
## `Economy`; every payment goes through `GameSession.try_spend()`. There is no
## number in this file that is not either a layout constant or a label.

signal closed()

const FADE_TIME := 0.18

enum Service { NONE, SUPPLY, BUSINESS, MOWERS }

var _service: int = Service.NONE
var _mower_id: String = "rider"

var _scrim: ColorRect
var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _body: VBoxContainer
var _back: Button
var _tween: Tween


func _ready() -> void:
	# ANCHORS ALONE ARE NOT ENOUGH under a CanvasLayer. `set_anchors_preset()`
	# leaves the offsets where they were, so the panel kept its zero-size rect
	# and everything inside it stacked into the top-left corner of the screen.
	# The offsets have to be set too.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	modulate.a = 0.0
	_build()

	# Anything that can change a price or a balance refreshes what is on screen.
	# Polling a shop every frame to notice a recession would be silly.
	Economy.prices_changed.connect(_refresh)
	MowerUpgrades.upgrades_changed.connect(_refresh)
	GameSession.money_changed.connect(func(_a: int) -> void: _refresh())
	MowerFuel.fuel_changed.connect(func(_f: float) -> void:
		if _service == Service.SUPPLY:
			_refresh())


# ======================================================================= build

func _build() -> void:
	_scrim = ColorRect.new()
	_scrim.color = UITheme.SCRIM_HEAVY
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.PANEL_SOLID, UITheme.RADIUS_PANEL, 1.0, UITheme.HAIRLINE))
	_panel.custom_minimum_size = Vector2(680, 0)
	centre.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	_title = UITheme.label(column, "Title", "", UITheme.FONT_TITLE, UITheme.INK)
	_subtitle = UITheme.label(column, "Subtitle", "", UITheme.FONT_BODY, UITheme.INK_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var rule := ColorRect.new()
	rule.color = UITheme.HAIRLINE
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	column.add_child(_body)

	_back = Button.new()
	_back.text = "BACK TO TOWN"
	UITheme.style_button(_back, false, 42.0)
	_back.pressed.connect(close)
	column.add_child(_back)


# ======================================================================= open

func open_service(building_id: StringName) -> bool:
	match String(building_id):
		"supply_store": _open(Service.SUPPLY)
		"business_hq": _open(Service.BUSINESS)
		"mower_dealer": _open(Service.MOWERS)
		_: return false
	return true


## Which building ids this panel handles. The town asks, so the list lives in
## one place rather than being repeated in the routing.
static func handles(building_id: StringName) -> bool:
	return String(building_id) in ["supply_store", "business_hq", "mower_dealer"]


func _open(service: int) -> void:
	_service = service
	visible = true
	_refresh()
	_fade(1.0)
	_back.grab_focus()


func close() -> void:
	if not visible:
		return
	_service = Service.NONE
	_fade(0.0)
	closed.emit()


func is_open() -> bool:
	return visible and modulate.a > 0.5


func _fade(target: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"modulate:a", target, FADE_TIME)
	if target <= 0.0:
		_tween.tween_callback(func() -> void: visible = false)


# ==================================================================== refresh

func _refresh() -> void:
	if _service == Service.NONE or not is_instance_valid(_body):
		return
	for child in _body.get_children():
		child.queue_free()
	match _service:
		Service.SUPPLY: _build_supply()
		Service.BUSINESS: _build_business()
		Service.MOWERS: _build_mowers()


# -------------------------------------------------------------- supply store

func _build_supply() -> void:
	_title.text = "SUPPLY STORE"
	_subtitle.text = "Fuel, priced at whatever the market says this morning."

	var fuel := MowerFuel.fuel()
	var capacity := MowerFuel.capacity()
	var missing := maxf(capacity - fuel, 0.0)
	var price := Economy.fuel_price_per_unit()
	var cost := Economy.fuel_cost_for_units(missing)

	_stat_row("Current fuel", "%.0f / %.0f units" % [fuel, capacity])

	var bar := ProgressBar.new()
	bar.max_value = capacity
	bar.value = fuel
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	UITheme.style_progress(bar, UITheme.ACCENT if fuel > capacity * 0.25 else UITheme.WARN)
	_body.add_child(bar)

	_stat_row("Fuel price", "$%.2f / unit" % price, _fuel_price_colour())
	_stat_row("Your funds", UITheme.format_money(GameSession.money()), UITheme.MONEY)

	_spacer(6)

	if missing <= 0.01:
		var full := UITheme.label(_body, "Full", "The tank is already full.",
			UITheme.FONT_BODY, UITheme.INK_DIM)
		full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return

	_stat_row("Cost to fill", UITheme.format_money(cost),
		UITheme.MONEY if GameSession.can_afford(cost) else UITheme.URGENT)

	var buy := Button.new()
	buy.text = "REFUEL TO FULL   %s" % UITheme.format_money(cost)
	UITheme.style_button(buy, true, 46.0)
	buy.disabled = not GameSession.can_afford(cost)
	buy.pressed.connect(_purchase_fuel)
	_body.add_child(buy)

	if not GameSession.can_afford(cost):
		# Partial refuel, so being short of a full tank is not the same as being
		# unable to buy fuel at all.
		var affordable := floorf(float(GameSession.money()) / maxf(price, 0.01))
		if affordable >= 1.0:
			var part_cost := Economy.fuel_cost_for_units(affordable)
			var part := Button.new()
			part.text = "BUY %.0f UNITS   %s" % [affordable, UITheme.format_money(part_cost)]
			UITheme.style_button(part, false, 42.0)
			part.pressed.connect(func() -> void: _purchase_fuel_units(affordable))
			_body.add_child(part)
		else:
			var poor := UITheme.label(_body, "Poor",
				"Not enough for even one unit.", UITheme.FONT_META, UITheme.URGENT)
			poor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _fuel_price_colour() -> Color:
	var index := Economy.fuel_index()
	if index >= 1.12:
		return UITheme.URGENT
	if index <= 0.92:
		return UITheme.ACCENT_BRIGHT
	return UITheme.INK


func _purchase_fuel() -> void:
	_purchase_fuel_units(maxf(MowerFuel.capacity() - MowerFuel.fuel(), 0.0))


## The one transaction. Money out FIRST, and only then fuel in — so a failed
## payment can never leave the player with free fuel.
func _purchase_fuel_units(units: float) -> void:
	if units <= 0.0:
		return
	var cost := Economy.fuel_cost_for_units(units)
	if not GameSession.try_spend(cost):
		AppUI.notify_warning("Not enough money", "That costs %s."
			% UITheme.format_money(cost))
		return
	var added := MowerFuel.refuel(units)
	AppUI.notify_money("Fuel purchased",
		"%.0f units for %s" % [added, UITheme.format_money(cost)])
	_refresh()


# ------------------------------------------------------------- business office

func _build_business() -> void:
	_title.text = "BUSINESS OFFICE"
	var s := Economy.summary()
	_subtitle.text = String(s["condition_blurb"])

	var days := int(s["condition_days_remaining"])
	_stat_row("Economy", "%s   (about %d day%s left)"
		% [s["condition_name"], days, "" if days == 1 else "s"], _condition_colour())
	_stat_row("Job market", ACAEconomyManager.format_index(s["job_index"]),
		_index_colour(s["job_index"], true))
	_stat_row("Fuel", "$%.2f / unit   %s"
		% [s["fuel_price"], ACAEconomyManager.format_index(s["fuel_index"])],
		_index_colour(s["fuel_index"], false))
	_stat_row("Equipment prices",
		ACAEconomyManager.format_index(s["equipment_index"]),
		_index_colour(s["equipment_index"], false))

	_spacer(6)

	if bool(s["has_event"]):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel",
			UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD, 1.0, UITheme.WARN))
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 4)
		var pad := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			pad.add_theme_constant_override("margin_" + side, 14)
		pad.add_child(inner)
		card.add_child(pad)
		UITheme.label(inner, "EventName", "%s — %d day%s remaining"
			% [s["event_name"], s["event_days_remaining"],
				"" if int(s["event_days_remaining"]) == 1 else "s"],
			UITheme.FONT_SUBHEAD, UITheme.WARN)
		var blurb := UITheme.label(inner, "EventBlurb", String(s["event_blurb"]),
			UITheme.FONT_META, UITheme.INK_DIM)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(card)
	else:
		var quiet := UITheme.label(_body, "NoEvent",
			"No special conditions in the market right now.",
			UITheme.FONT_META, UITheme.INK_FAINT)
		quiet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_spacer(4)
	_stat_row("Funds", UITheme.format_money(GameSession.money()), UITheme.MONEY)


func _condition_colour() -> Color:
	match Economy.condition():
		ACAEconomyManager.Condition.GROWTH: return UITheme.ACCENT_BRIGHT
		ACAEconomyManager.Condition.RECESSION: return UITheme.URGENT
		ACAEconomyManager.Condition.INFLATION: return UITheme.WARN
	return UITheme.INK


## `higher_is_better` flips the meaning: a high job index is good news, a high
## fuel index is not.
func _index_colour(index: float, higher_is_better: bool) -> Color:
	if absf(index - 1.0) < 0.02:
		return UITheme.INK
	var good := (index > 1.0) == higher_is_better
	return UITheme.ACCENT_BRIGHT if good else UITheme.URGENT


# ---------------------------------------------------------------- mower shop

func _build_mowers() -> void:
	_title.text = "MOWER WORKSHOP"
	_subtitle.text = "Upgrades are fitted per machine. Prices follow the market."

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for id: String in ACAMowerUpgrades.MOWER_IDS:
		var tab := Button.new()
		tab.text = ACAMowerUpgrades.mower_name(id)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(tab, id == _mower_id, 38.0)
		tab.pressed.connect(func() -> void:
			_mower_id = id
			_refresh())
		tabs.add_child(tab)
	_body.add_child(tabs)

	_stat_row("Your funds", UITheme.format_money(GameSession.money()), UITheme.MONEY)
	_spacer(4)

	for entry: Dictionary in MowerUpgrades.summary(_mower_id):
		_body.add_child(_upgrade_row(entry))

	if _mower_id == "push":
		var note := UITheme.label(_body, "PushNote",
			"A push mower burns no fuel, so it has no fuel system to improve.",
			UITheme.FONT_MICRO, UITheme.INK_FAINT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _upgrade_row(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	card.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	pad.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)

	var lvl := int(entry["level"])
	var max_lvl := int(entry["max_level"])
	UITheme.label(text, "Name", "%s   —   Level %d / %d"
		% [entry["name"], lvl, max_lvl], UITheme.FONT_SUBHEAD, UITheme.INK)
	var blurb := UITheme.label(text, "Blurb", String(entry["blurb"]),
		UITheme.FONT_META, UITheme.INK_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# The EFFECT, stated as a real number. An upgrade whose effect cannot be
	# written down is an upgrade nobody should be selling.
	UITheme.label(text, "Effect", _effect_text(entry),
		UITheme.FONT_META, UITheme.ACCENT_BRIGHT)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(190, 0)
	if bool(entry["maxed"]):
		buy.text = "MAX"
		UITheme.style_button(buy, false, 44.0)
		buy.disabled = true
	else:
		var cost := int(entry["next_cost"])
		buy.text = "UPGRADE   %s" % UITheme.format_money(cost)
		UITheme.style_button(buy, GameSession.can_afford(cost), 44.0)
		buy.disabled = not GameSession.can_afford(cost)
		var category := String(entry["category"])
		buy.pressed.connect(func() -> void: _purchase_upgrade(category))
	row.add_child(buy)
	return card


## Reads the stat the right way round: fuel is the one where lower is better.
func _effect_text(entry: Dictionary) -> String:
	var current := float(entry["value"])
	var is_fuel := String(entry["stat"]) == "fuel"
	var current_pct := (1.0 - current) * 100.0 if is_fuel else (current - 1.0) * 100.0
	var label := "fuel saved" if is_fuel else String(entry["unit"])
	if bool(entry["maxed"]):
		return "Now: %+.0f%% %s  (fully upgraded)" % [current_pct, label]
	var next := float(entry["next_value"])
	var next_pct := (1.0 - next) * 100.0 if is_fuel else (next - 1.0) * 100.0
	return "Now: %+.0f%% %s      Next: %+.0f%%" % [current_pct, label, next_pct]


func _purchase_upgrade(category: String) -> void:
	var cost := MowerUpgrades.next_cost(_mower_id, category)
	if MowerUpgrades.try_purchase(_mower_id, category):
		var spec: Dictionary = ACAMowerUpgrades.CATEGORIES[category]
		AppUI.notify_success("%s fitted" % spec["name"],
			"%s — %s" % [ACAMowerUpgrades.mower_name(_mower_id),
				UITheme.format_money(cost)])
	else:
		AppUI.notify_warning("Cannot fit that",
			"Not enough money, or it is already at maximum.")
	_refresh()


# ==================================================================== helpers

func _stat_row(key: String, value: String, value_colour: Color = UITheme.INK) -> void:
	var row := HBoxContainer.new()
	var k := UITheme.label(row, "Key", key, UITheme.FONT_BODY, UITheme.INK_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UITheme.label(row, "Value", value, UITheme.FONT_BODY, value_colour)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_body.add_child(row)


func _spacer(height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	_body.add_child(s)


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
