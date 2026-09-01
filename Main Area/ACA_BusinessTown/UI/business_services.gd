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

enum Service { NONE, SUPPLY, BUSINESS, MOWERS, DEPOT }

## The tallest the scrolling body is allowed to get. Chosen so the whole counter
## still fits a 1280x720 window with its heading, its rule and its BACK button.
const BODY_MAX_HEIGHT := 430.0
## Pixels kept clear at the right edge of the scrolling body for the scrollbar.
const SCROLLBAR_GUTTER := 14

var _service: int = Service.NONE
var _mower_id: String = "rider"
## Which part of the workshop is showing: the machines, the autonomous fleet, or
## the things that bolt on to them.
var _workshop_tab: StringName = &"machines"
## Which page of the Business Office is showing. The office is five subjects
## now - the company, its territories, its fleet, its agreements and its
## portfolio - and five pages of one counter is one interface to learn rather
## than five buildings to visit.
var _office_tab: StringName = &"company"

var _scrim: ColorRect
var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _mark: UIGlyph
var _accent: ColorRect
var _body: VBoxContainer
var _scroll: ScrollContainer
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
	# The business systems, for the same reason: a counter showing a stale
	# inventory or a stale fleet is a counter the player cannot trust.
	Clippings.inventory_changed.connect(_refresh)
	Equipment.ownership_changed.connect(_refresh)
	Equipment.autonomous_fleet_changed.connect(_refresh)
	Business.reputation_changed.connect(func(_v: float) -> void: _refresh())
	Business.customers_changed.connect(_refresh)
	# The expansion's systems, for the same reason: a counter showing a stale
	# loadout, a stale territory or a stale agreement is a counter the player
	# cannot trust.
	Equipment.loadout_changed.connect(_refresh)
	Territory.regions_changed.connect(_refresh)
	Territory.presence_changed.connect(func(_r: int) -> void: _refresh())
	Agreements.offers_changed.connect(_refresh)


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

	# THE COUNTER IS PAPER. Every one of these three screens is a transaction the
	# business is doing - a fuel receipt, a work order for an upgrade, a page of
	# the books - and the rest of the game now draws its paperwork on cream. The
	# Job Board's offers already did; this is the rest of the town catching up.
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel",
		UITheme.paper_panel(UITheme.RADIUS_PANEL, 0.0, 0.0))
	_panel.custom_minimum_size = Vector2(680, 0)
	centre.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	# EACH SERVICE GETS ITS OWN MARK AND ITS OWN ACCENT, and that is the whole of
	# the differentiation between the three. They are the same counter with the
	# same layout doing three different jobs, and dressing them as three
	# different screens would be three screens to maintain and one interface to
	# unlearn.
	_accent = ColorRect.new()
	_accent.name = "Accent"
	_accent.custom_minimum_size = Vector2(0, 3)
	column.add_child(_accent)

	var heading := HBoxContainer.new()
	heading.name = "Heading"
	heading.add_theme_constant_override("separation", 12)
	column.add_child(heading)
	_mark = UIGlyph.make(UIGlyph.Kind.LEAF, 26.0, UITheme.HUD_GREEN)
	_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(_mark)
	_title = UITheme.label(heading, "Title", "", UITheme.FONT_TITLE,
		UITheme.PAPER_INK)

	_subtitle = UITheme.label(column, "Subtitle", "", UITheme.FONT_BODY,
		UITheme.PAPER_INK_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var rule := ColorRect.new()
	rule.color = UITheme.PAPER_RULE
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	# THE BODY SCROLLS. The Business Office is a company dashboard now - a
	# reputation, a market table, a fleet and a customer book - and the three
	# counters share one layout, so the layout is the thing that has to cope
	# with a long panel. A fixed maximum height with a scroll inside it keeps
	# the counter the same size whatever is on it, which is what stops the
	# panel jumping about between services.
	var scroll := ScrollContainer.new()
	scroll.name = "BodyScroll"
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	_scroll = scroll

	# ROOM FOR THE SCROLLBAR. A ScrollContainer draws its bar INSIDE its own
	# rect, over whatever is at the right edge - and every row on these counters
	# is a label on the left and a value hard against the right. Without this the
	# bar sits on top of the prices.
	var gutter := MarginContainer.new()
	gutter.name = "Gutter"
	gutter.add_theme_constant_override("margin_right", SCROLLBAR_GUTTER)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gutter)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(_body)

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
		"service_lot": _open(Service.DEPOT)
		_: return false
	return true


## Which building ids this panel handles. The town asks, so the list lives in
## one place rather than being repeated in the routing.
static func handles(building_id: StringName) -> bool:
	return String(building_id) in [
		"supply_store", "business_hq", "mower_dealer", "service_lot",
	]


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
		Service.SUPPLY:
			_set_identity(UIGlyph.Kind.DROP, UITheme.ORANGE)
			_build_supply()
		Service.BUSINESS:
			_set_identity(UIGlyph.Kind.MAP, UITheme.HUD_GREEN)
			_build_business()
		Service.MOWERS:
			_set_identity(UIGlyph.Kind.STRIPES, UITheme.SAGE.darkened(0.35))
			_build_mowers()
		Service.DEPOT:
			_set_identity(UIGlyph.Kind.STONE, UITheme.WARN)
			_build_depot()
	# The body is composed with the shared slate palette, exactly as it always
	# was; this moves it on to the paper family in one pass rather than making
	# three build functions each remember to.
	UITheme.repaint_to_paper(_body)
	_fit_body()


## The counter is a fixed size whatever is on it: short content sits at its own
## height, long content scrolls rather than growing the panel off the screen.
func _fit_body() -> void:
	if _scroll == null:
		return
	await get_tree().process_frame
	if not is_instance_valid(_scroll) or not is_instance_valid(_body):
		return
	_scroll.custom_minimum_size = Vector2(0,
		minf(_body.get_combined_minimum_size().y + 4.0, BODY_MAX_HEIGHT))


## The mark and the accent stripe that say which counter this is.
func _set_identity(kind: UIGlyph.Kind, accent: Color) -> void:
	if _mark != null:
		_mark.set_kind(kind)
		_mark.set_colour(accent)
	if _accent != null:
		_accent.color = accent


# -------------------------------------------------------------- supply store

func _build_supply() -> void:
	_title.text = "SUPPLY STORE"
	_subtitle.text = "Fuel, priced at whatever the market says this morning."

	var fuel := MowerFuel.fuel()
	var capacity := MowerFuel.capacity()
	var missing := maxf(capacity - fuel, 0.0)
	var price := Economy.fuel_price_per_unit()
	var cost := Economy.fuel_cost_for_units(missing)

	_section_heading("FUEL")
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
		_spacer(8)
		_build_clippings()
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
	_spacer(8)
	_build_clippings()


# ------------------------------------------------------- the clipping counter

## THE RESOURCE HALF OF THE SUPPLY STORE.
##
## A separate screen was considered and rejected: the Supply Store is already
## where the business buys what it consumes, and selling what it collects across
## the same counter is one place to go rather than two. It is also the honest
## reading of the fiction - the yard is behind the shop.
func _build_clippings() -> void:
	_section_heading("CLIPPINGS")

	var fresh := Clippings.fresh_kilograms()
	var composting := Clippings.composting_kilograms()
	var compost := Clippings.compost_kilograms()
	var stored := Clippings.stored_total()
	var capacity := Clippings.store_capacity()

	_stat_row("Yard storage", "%s of %s" % [
		ACAClippings.format_kg(stored), ACAClippings.format_kg(capacity)],
		UITheme.URGENT if Clippings.store_is_full() else UITheme.INK)

	var bar := ProgressBar.new()
	bar.max_value = maxf(capacity, 1.0)
	bar.value = stored
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	UITheme.style_progress(bar,
		UITheme.WARN if Clippings.store_fraction() > 0.85 else UITheme.ACCENT)
	_body.add_child(bar)

	if stored <= 0.01:
		var empty := UITheme.label(_body, "NoClippings",
			"Nothing in the yard. Collect on a contract and unload at the truck.",
			UITheme.FONT_META, UITheme.INK_FAINT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return

	# --- fresh: sell now, or put it on the heap ---
	if fresh > 0.01:
		var value := Clippings.fresh_sale_value()
		_stat_row("Fresh clippings", "%s   ·   %s" % [
			ACAClippings.format_kg(fresh), UITheme.format_money(value)], UITheme.MONEY)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var sell := Button.new()
		sell.text = "SELL FRESH   %s" % UITheme.format_money(value)
		sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(sell, false, 42.0)
		sell.disabled = value <= 0
		sell.pressed.connect(_sell_fresh)
		row.add_child(sell)

		var heap := Button.new()
		heap.text = "COMPOST IT   %d days" % ACAClippings.COMPOST_DAYS
		heap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(heap, true, 42.0)
		heap.pressed.connect(_start_composting)
		row.add_child(heap)
		_body.add_child(row)

		# THE TRADE, STATED. Composting loses mass and takes days, and pays more
		# per kilogram at the end. The player should be able to see which is
		# worth more before choosing, rather than discovering it four days later.
		var later := fresh * ACAClippings.COMPOST_YIELD * Clippings.compost_price_per_kg()
		UITheme.label(_body, "CompostMath",
			"Composting turns %s into about %s and is worth roughly %s in %d days."
				% [ACAClippings.format_kg(fresh),
					ACAClippings.format_kg(fresh * ACAClippings.COMPOST_YIELD),
					UITheme.format_money(int(later)), ACAClippings.COMPOST_DAYS],
			UITheme.FONT_MICRO, UITheme.INK_FAINT).autowrap_mode = 				TextServer.AUTOWRAP_WORD_SMART

	if composting > 0.01:
		var days := Clippings.days_until_compost(WorldClock.day_index())
		_stat_row("On the heap", "%s   ·   ready in %d day%s" % [
			ACAClippings.format_kg(composting), days, "" if days == 1 else "s"],
			UITheme.INK_DIM)

	if compost > 0.01:
		var compost_value := Clippings.compost_sale_value()
		_stat_row("Compost", "%s   ·   %s" % [
			ACAClippings.format_kg(compost), UITheme.format_money(compost_value)],
			UITheme.MONEY)
		var sell_compost := Button.new()
		sell_compost.text = "SELL COMPOST   %s" % UITheme.format_money(compost_value)
		UITheme.style_button(sell_compost, true, 44.0)
		sell_compost.disabled = compost_value <= 0
		sell_compost.pressed.connect(_sell_compost)
		_body.add_child(sell_compost)

	_spacer(2)
	UITheme.label(_body, "Price",
		"Today: $%.2f / kg fresh, $%.2f / kg composted."
			% [Clippings.fresh_price_per_kg(), Clippings.compost_price_per_kg()],
		UITheme.FONT_MICRO, UITheme.INK_FAINT)


func _sell_fresh() -> void:
	var paid := Clippings.sell_fresh()
	if paid > 0:
		AppUI.notify_money("Clippings sold", UITheme.format_money(paid))
	_refresh()


func _sell_compost() -> void:
	var paid := Clippings.sell_compost()
	if paid > 0:
		AppUI.notify_money("Compost sold", UITheme.format_money(paid))
	_refresh()


func _start_composting() -> void:
	var amount := Clippings.start_composting(WorldClock.day_index())
	if amount > 0.0:
		AppUI.notify_info("On the heap",
			"%s will be ready in %d days." % [
				ACAClippings.format_kg(amount), ACAClippings.COMPOST_DAYS])
	_refresh()


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
	_build_office_tabs()
	match _office_tab:
		&"territories":
			_build_territories()
			return
		&"operations":
			_build_operations()
			return
		&"agreements":
			_build_agreements()
			return
		&"portfolio":
			_build_portfolio()
			return
	_build_market_and_company()


func _build_market_and_company() -> void:
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

	_spacer(10)
	_build_company()


# ------------------------------------------------------- the company dashboard

## WHAT THE BUSINESS IS, as opposed to what the market is doing.
##
## The Business Office was a market readout with the player's balance at the
## bottom. It is the company's own page now: how it is regarded, who keeps
## calling it back, who it is losing work to, how much of the district it holds
## and what its premises look like.
##
## There is NO employee list, NO payroll and NO labour market on this page, and
## there must not be. Capacity is machines.
func _build_company() -> void:
	_section_heading("THE BUSINESS")

	var band := Business.reputation_band()
	_stat_row("Reputation", "%d / 100   -   %s" % [
		int(round(Business.reputation())), band["name"]], _reputation_colour())

	var rep_bar := ProgressBar.new()
	rep_bar.max_value = ACABusiness.MAX_REPUTATION
	rep_bar.value = Business.reputation()
	rep_bar.show_percentage = false
	rep_bar.custom_minimum_size = Vector2(0, 10)
	UITheme.style_progress(rep_bar, _reputation_colour())
	_body.add_child(rep_bar)

	var band_note := UITheme.label(_body, "Band", String(band["blurb"]),
		UITheme.FONT_META, UITheme.INK_FAINT)
	band_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if Business.has_reserved_access():
		UITheme.label(_body, "Reserved",
			"Standing high enough that the large contracts are held for you rather than taken.",
			UITheme.FONT_META, UITheme.ACCENT_BRIGHT).autowrap_mode = \
				TextServer.AUTOWRAP_WORD_SMART

	var rating := Business.average_rating()
	if rating > 0.0:
		_stat_row("Customer rating", "%.1f / 5 over the last %d contracts"
			% [rating, Business.recent_reviews(99).size()], UITheme.INK)
	_stat_row("Contracts completed", str(Business.contracts_completed()), UITheme.INK)
	_stat_row("Lifetime revenue", UITheme.format_money(Business.lifetime_revenue()),
		UITheme.MONEY)

	# --- market share ---
	_spacer(8)
	_section_heading("LOCAL MARKET")
	var table := Business.market_table()
	if table.is_empty():
		var quiet := UITheme.label(_body, "NoMarket",
			"No contracts have been taken yet, by you or by anyone else.",
			UITheme.FONT_META, UITheme.INK_FAINT)
		quiet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		_stat_row("Your share", "%d%%%s" % [
			int(round(Business.market_share() * 100.0)),
			"   -   leading the district" if Business.is_market_leader() else ""],
			UITheme.ACCENT_BRIGHT if Business.is_market_leader() else UITheme.INK)
		for entry: Dictionary in table:
			_body.add_child(_share_row(entry))
		UITheme.label(_body, "ShareNote",
			"Measured by contract VALUE over the last %d contracts in the district."
				% ACABusiness.MARKET_WINDOW,
			UITheme.FONT_MICRO, UITheme.INK_FAINT).autowrap_mode = \
				TextServer.AUTOWRAP_WORD_SMART

	# --- who else is bidding ---
	_spacer(8)
	_section_heading("THE COMPETITION")
	for firm: Dictionary in ACABusiness.COMPETITORS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = firm["colour"]
		swatch.custom_minimum_size = Vector2(4, 0)
		row.add_child(swatch)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 1)
		row.add_child(text)
		UITheme.label(text, "Firm", "%s   -   %s" % [firm["name"], firm["archetype"]],
			UITheme.FONT_BODY, UITheme.INK)
		UITheme.label(text, "Blurb", String(firm["blurb"]),
			UITheme.FONT_MICRO, UITheme.INK_FAINT).autowrap_mode = \
				TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(row)

	# --- capacity ---
	_spacer(8)
	_section_heading("CAPACITY")
	_stat_row("Machines you drive", "%d of %d owned" % [
		Equipment.owned_mower_count(), ACAMowerUpgrades.MOWER_IDS.size()], UITheme.INK)
	var fleet := Equipment.fleet_summary()
	var busy := 0
	for entry: Dictionary in fleet:
		if bool(entry["busy"]):
			busy += 1
	_stat_row("Autonomous machines", "%d owned, %d working" % [fleet.size(), busy],
		UITheme.INK)
	_stat_row("Yard storage", "%s of %s" % [
		ACAClippings.format_kg(Clippings.stored_total()),
		ACAClippings.format_kg(Clippings.store_capacity())], UITheme.INK_DIM)

	# --- customers ---
	_spacer(8)
	_section_heading("CUSTOMERS")
	var customers := Business.active_customers()
	if customers.is_empty():
		var none := UITheme.label(_body, "NoCustomers",
			"No repeat customers yet. Finish a contract well and the property will call again.",
			UITheme.FONT_META, UITheme.INK_FAINT)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		var today := WorldClock.day_index()
		for i in mini(customers.size(), 5):
			var record: Dictionary = customers[i]
			var due := int(record["next_day"]) - today
			var when := "due now" if due <= 0 else "due in %d day%s" % [
				due, "" if due == 1 else "s"]
			_stat_row("%s   (%d visit%s)" % [record["site"], int(record["services"]),
				"" if int(record["services"]) == 1 else "s"],
				"%s   -   loyalty %d" % [when, int(record["loyalty"])],
				UITheme.ACCENT_BRIGHT if due <= 0 else UITheme.INK_DIM)
		if customers.size() > 5:
			UITheme.label(_body, "MoreCustomers",
				"...and %d more on the books." % (customers.size() - 5),
				UITheme.FONT_MICRO, UITheme.INK_FAINT)
	var lapsed := Business.lapsed_customers()
	if not lapsed.is_empty():
		_stat_row("Lapsed", "%d propert%s stopped calling" % [
			lapsed.size(), "y" if lapsed.size() == 1 else "ies"], UITheme.WARN)

	# --- reviews ---
	var reviews := Business.recent_reviews(3)
	if not reviews.is_empty():
		_spacer(8)
		_section_heading("RECENT REVIEWS")
		for review: Dictionary in reviews:
			var line := VBoxContainer.new()
			line.add_theme_constant_override("separation", 1)
			UITheme.label(line, "Stars", "%s   %s" % [
				_stars_text(int(review["stars"])), review["site"]],
				UITheme.FONT_META, UITheme.WARN)
			UITheme.label(line, "Text", String(review["text"]),
				UITheme.FONT_META, UITheme.INK_DIM).autowrap_mode = \
					TextServer.AUTOWRAP_WORD_SMART
			_body.add_child(line)

	# --- the yard ---
	_spacer(8)
	_section_heading("THE YARD")
	_stat_row("Premises", Business.yard_name(), UITheme.ACCENT_BRIGHT)
	var yard_note := UITheme.label(_body, "YardBlurb", Business.yard_blurb(),
		UITheme.FONT_META, UITheme.INK_DIM)
	yard_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var next_up := Business.next_yard_requirement()
	if not next_up.is_empty():
		var wants := UITheme.label(_body, "YardNext", next_up,
			UITheme.FONT_META, UITheme.INK_FAINT)
		wants.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _share_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var swatch := ColorRect.new()
	swatch.color = entry["colour"]
	swatch.custom_minimum_size = Vector2(4, 0)
	row.add_child(swatch)

	var name_label := UITheme.label(row, "Who", String(entry["name"]),
		UITheme.FONT_META,
		UITheme.INK if bool(entry["is_player"]) else UITheme.INK_DIM)
	name_label.custom_minimum_size = Vector2(190, 0)

	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = float(entry["share"])
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.style_progress(bar, entry["colour"])
	row.add_child(bar)

	var pct := UITheme.label(row, "Pct", "%d%%" % int(round(float(entry["share"]) * 100.0)),
		UITheme.FONT_META, UITheme.INK_DIM)
	pct.custom_minimum_size = Vector2(46, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return row


## Filled and empty marks rather than a number alone, and the number is always
## beside it - nothing in this interface is ever communicated by a symbol only.
static func _stars_text(stars: int) -> String:
	var out := ""
	for i in 5:
		out += "*" if i < stars else "."
	return "%s  %d/5" % [out, stars]


func _reputation_colour() -> Color:
	var value := Business.reputation()
	if value >= ACABusiness.RESERVED_ACCESS_AT:
		return UITheme.ACCENT_BRIGHT
	if value < 30.0:
		return UITheme.URGENT
	return UITheme.INK


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

	# TWO HALVES OF ONE WORKSHOP: the machines the player drives, and the ones
	# that work on their own. Same counter, same layout, one switch - rather
	# than a second building for a second kind of machine.
	var halves := HBoxContainer.new()
	halves.add_theme_constant_override("separation", 8)
	for pair in [[&"machines", "MACHINES"], [&"autonomous", "AUTONOMOUS"],
			[&"attachments", "ATTACHMENTS"]]:
		var which: StringName = pair[0]
		var tab := Button.new()
		tab.text = String(pair[1])
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(tab, _workshop_tab == which, 38.0)
		tab.pressed.connect(func() -> void:
			_workshop_tab = which
			_refresh())
		halves.add_child(tab)
	_body.add_child(halves)

	_stat_row("Your funds", UITheme.format_money(GameSession.money()), UITheme.MONEY)

	if _workshop_tab == &"autonomous":
		_build_autonomous()
		return
	if _workshop_tab == &"attachments":
		_build_attachment_shop()
		return

	_subtitle.text = "Buy a machine outright, choose which one goes to the next contract, and fit upgrades."
	_spacer(2)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for id: String in ACAMowerUpgrades.MOWER_IDS:
		var tab := Button.new()
		# A machine the business does not own is still listed, so the player can
		# see what there is to buy rather than having to guess that it exists.
		tab.text = ACAMowerUpgrades.mower_name(id)
		if not Equipment.owns(id):
			tab.text += "  (not owned)"
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(tab, id == _mower_id, 38.0)
		tab.pressed.connect(func() -> void:
			_mower_id = id
			_refresh())
		tabs.add_child(tab)
	_body.add_child(tabs)

	if not Equipment.owns(_mower_id):
		_build_mower_purchase()
		return

	_build_mower_selection()
	_spacer(4)

	for entry: Dictionary in MowerUpgrades.summary(_mower_id):
		_body.add_child(_upgrade_row(entry))

	if _mower_id == "push":
		var note := UITheme.label(_body, "PushNote",
			"A push mower burns no fuel, so it has no fuel system to improve.",
			UITheme.FONT_MICRO, UITheme.INK_FAINT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## A MACHINE THE BUSINESS DOES NOT HAVE YET. Bought outright, out of the money
## in hand - there is no financing anywhere in this game and there never will be.
func _build_mower_purchase() -> void:
	var cost := Equipment.purchase_cost(_mower_id)
	_spacer(4)
	_stat_row("Purchase price", UITheme.format_money(cost),
		UITheme.MONEY if GameSession.can_afford(cost) else UITheme.URGENT)
	_stat_row("Catcher", ACAClippings.format_kg(Equipment.rated_bag_capacity(_mower_id)),
		UITheme.INK)
	_stat_row("Fuel", "None - it is pushed" if _mower_id == "push"
		else "Runs on the tank", UITheme.INK_DIM)

	var blurb := UITheme.label(_body, "WhyBuy", _machine_case(_mower_id),
		UITheme.FONT_META, UITheme.INK_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var buy := Button.new()
	buy.text = "BUY OUTRIGHT   %s" % UITheme.format_money(cost)
	UITheme.style_button(buy, GameSession.can_afford(cost), 46.0)
	buy.disabled = not GameSession.can_afford(cost)
	var id := _mower_id
	buy.pressed.connect(func() -> void: _purchase_mower(id))
	_body.add_child(buy)

	UITheme.label(_body, "AfterBuy", _after_purchase_text(cost),
		UITheme.FONT_META,
		UITheme.WARN if _leaves_thin_reserve(cost) else UITheme.INK_FAINT)


## WHY A PLAYER WOULD WANT IT, in a sentence. Not marketing - each of these is a
## real operating difference the game models.
func _machine_case(mower_id: String) -> String:
	match mower_id:
		"push":
			return "Burns no fuel at all. On a small contract that turns the fuel line of the job into nothing, which is why the cheapest machine in the shop is not simply the worst one."
		"powered":
			return "Walks where a rider will not fit, and carries a middling catcher. The machine for a garden with things in it."
		"rider":
			return "Covers ground, and carries the largest catcher in the shop. The machine for acreage."
	return ""


func _purchase_mower(mower_id: String) -> void:
	var cost := Equipment.purchase_cost(mower_id)
	if Equipment.try_purchase_mower(mower_id):
		Equipment.select_mower(mower_id)
		AppUI.notify_success("Machine bought",
			"%s - %s" % [ACAMowerUpgrades.mower_name(mower_id),
				UITheme.format_money(cost)])
	else:
		AppUI.notify_warning("Cannot buy that", "Not enough money.")
	_refresh()


## WHICH MACHINE GOES TO THE NEXT CONTRACT. Chosen here rather than at the job
## board, because this is where the player is already looking at what they own.
func _build_mower_selection() -> void:
	var selected := String(Equipment.selected_mower()) == _mower_id
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	UITheme.label(text, "Owned", "Owned. Catcher %s."
		% ACAClippings.format_kg(Equipment.bag_capacity(_mower_id)),
		UITheme.FONT_BODY, UITheme.INK)
	var advice := UITheme.label(text, "Recommend", _recommendation_line(),
		UITheme.FONT_META, UITheme.INK_FAINT)
	advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advice.visible = not advice.text.is_empty()

	var take := Button.new()
	take.custom_minimum_size = Vector2(190, 0)
	take.text = "TAKING THIS ONE" if selected else "TAKE THIS ONE"
	UITheme.style_button(take, not selected, 44.0)
	take.disabled = selected
	var id := _mower_id
	take.pressed.connect(func() -> void:
		Equipment.select_mower(id)
		AppUI.notify_info("Loaded on the trailer",
			"%s goes to the next contract." % ACAMowerUpgrades.mower_name(id))
		_refresh())
	row.add_child(take)
	_body.add_child(row)


## What the workshop would advise for the contract the player is most likely to
## drive to next. ADVISORY ONLY: nothing anywhere refuses a machine, because a
## player who wants to push-mow a large rural contract has made a decision
## rather than a mistake.
func _recommendation_line() -> String:
	var job := GameSession.current_job()
	if job == null:
		var offers := JobManager.available_jobs()
		if offers.is_empty():
			return ""
		job = offers[0]
	var advice := Equipment.recommended_for(job)
	if String(advice["mower_id"]) == _mower_id:
		return "Suggested for %s. %s" % [job.job_site, advice["reason"]]
	return "For %s the workshop would suggest the %s." % [
		job.job_site, ACAMowerUpgrades.mower_name(String(advice["mower_id"]))]


# ------------------------------------------------------- the autonomous fleet

## MACHINES THAT WORK WITHOUT BEING DRIVEN.
##
## There is no operator to hire, no shift to fill and no wage to pay: capacity
## beyond what the player personally drives is a machine the business OWNS. That
## is the design, and it is also the art direction - this game has no people in
## it.
func _build_autonomous() -> void:
	_subtitle.text = "Machines that work a contract on their own. Owned outright; no operator, no wage."
	_spacer(2)

	var fleet := Equipment.fleet_summary()
	_section_heading("YOUR FLEET")
	if fleet.is_empty():
		var none := UITheme.label(_body, "NoFleet",
			"No autonomous machines yet. One of these can take a contract off the board while you drive to another.",
			UITheme.FONT_META, UITheme.INK_FAINT)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		for entry: Dictionary in fleet:
			_body.add_child(_fleet_row(entry))

	_spacer(6)
	_section_heading("FOR SALE")
	for tier in ACAEquipment.AUTONOMOUS_ORDER:
		_body.add_child(_autonomous_row(String(tier)))


func _fleet_row(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	card.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pad.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	UITheme.label(text, "Name", String(entry["name"]), UITheme.FONT_SUBHEAD, UITheme.INK)

	if bool(entry["busy"]):
		var job := JobManager.get_job(StringName(String(entry["job_id"])))
		UITheme.label(text, "Busy", "Working %s - %d%% through." % [
			job.job_site if job != null else "a contract",
			int(round(float(entry["progress"]) * 100.0))],
			UITheme.FONT_META, UITheme.ACCENT_BRIGHT)
	else:
		UITheme.label(text, "Idle", "Idle. Up to %s contracts, %s." % [
			ACAJobEnums.lawn_size_name(int(entry["max_size"])).to_lower(),
			"collects" if float(entry["bag_kg"]) > 0.0 else "mulches"],
			UITheme.FONT_META, UITheme.INK_DIM)

	var escort := Button.new()
	escort.custom_minimum_size = Vector2(180, 0)
	var uid := int(entry["uid"])
	if bool(entry["busy"]):
		escort.text = "ON A CONTRACT"
		UITheme.style_button(escort, false, 42.0)
		escort.disabled = true
	elif Equipment.escort_unit_uid() == uid:
		escort.text = "COMING WITH YOU"
		UITheme.style_button(escort, false, 42.0)
		escort.pressed.connect(func() -> void:
			Equipment.clear_escort_unit()
			_refresh())
	else:
		escort.text = "BRING IT ALONG"
		UITheme.style_button(escort, true, 42.0)
		escort.pressed.connect(func() -> void:
			Equipment.set_escort_unit(uid)
			AppUI.notify_info("Loaded on the trailer",
				"%s will work beside you on the next contract."
					% Equipment.unit_label(uid))
			_refresh())
	row.add_child(escort)
	return card


func _autonomous_row(tier: String) -> Control:
	var spec := ACAEquipment.tier_spec(tier)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	card.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pad.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	UITheme.label(text, "Name", String(spec["name"]), UITheme.FONT_SUBHEAD, UITheme.INK)
	var blurb := UITheme.label(text, "Blurb", String(spec["blurb"]),
		UITheme.FONT_META, UITheme.INK_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.label(text, "Rating", "Rated to %s contracts   -   catcher %s" % [
		ACAJobEnums.lawn_size_name(int(spec["max_size"])).to_lower(),
		ACAClippings.format_kg(float(spec["bag_kg"])) if float(spec["bag_kg"]) > 0.0
			else "none, it mulches"],
		UITheme.FONT_META, UITheme.ACCENT_BRIGHT)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(180, 0)
	var cost := Equipment.autonomous_cost(tier)
	if cost < 0:
		buy.text = "FLEET FULL"
		UITheme.style_button(buy, false, 44.0)
		buy.disabled = true
	else:
		buy.text = "BUY   %s" % UITheme.format_money(cost)
		UITheme.style_button(buy, GameSession.can_afford(cost), 44.0)
		buy.disabled = not GameSession.can_afford(cost)
		buy.pressed.connect(func() -> void: _purchase_autonomous(tier))
		UITheme.label(text, "After", _after_purchase_text(cost), UITheme.FONT_META,
			UITheme.WARN if _leaves_thin_reserve(cost) else UITheme.INK_FAINT)
	row.add_child(buy)
	return card


func _purchase_autonomous(tier: String) -> void:
	var cost := Equipment.autonomous_cost(tier)
	var uid := Equipment.try_purchase_autonomous(tier)
	if uid > 0:
		AppUI.notify_success("Machine bought",
			"%s - %s" % [Equipment.unit_label(uid), UITheme.format_money(cost)])
	else:
		AppUI.notify_warning("Cannot buy that",
			"Not enough money, or the fleet is full.")
	_refresh()


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
		# WHAT IS LEFT AFTERWARDS, stated before the purchase rather than
		# discovered after it. The economy study found that buying equipment
		# early is the single most reliable way to end a business, and that
		# almost every failed run in the baseline was an aggressive upgrade
		# policy running itself out of fuel money. This is not advice and it is
		# not a warning system; it is the one number the player was already
		# doing in their head, done for them.
		UITheme.label(text, "After",
			_after_purchase_text(cost), UITheme.FONT_META,
			UITheme.WARN if _leaves_thin_reserve(cost) else UITheme.INK_FAINT)
	row.add_child(buy)
	return card


## How much fuel a balance buys at today's price, so "what is left" is expressed
## in the thing the player actually needs it for.
func _after_purchase_text(cost: int) -> String:
	var remaining := GameSession.money() - cost
	if remaining < 0:
		return "You are %s short." % UITheme.format_money(-remaining)
	var price := Economy.fuel_price_per_unit()
	var tanks: float = float(remaining) / maxf(price * MowerFuel.capacity(), 1.0)
	return "Leaves %s - about %.1f tanks of fuel at today's price." % [
		UITheme.format_money(remaining), tanks]


## Under one full tank left is thin, whatever the number says. Reported by
## CHANGING THE WORDING as well as the colour, so the caution does not depend on
## being able to tell amber from grey.
func _leaves_thin_reserve(cost: int) -> bool:
	var remaining := GameSession.money() - cost
	if remaining < 0:
		return true
	return float(remaining) < Economy.fuel_price_per_unit() * MowerFuel.capacity()


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


func _____The_Office_Pages_____():
	pass

## ---------------------------------------------------------------------------
## THE BUSINESS OFFICE, IN FIVE PAGES
## ---------------------------------------------------------------------------
## The office used to be one page: the market, and the company under it. The
## company has four more subjects now - where it is allowed to work, what its
## machines are doing right now, what it has committed to, and what it has
## already done - and each of them is a page of the same counter rather than a
## building of its own.
func _build_office_tabs() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for pair in [[&"company", "COMPANY"], [&"territories", "AREAS"],
			[&"operations", "FLEET"], [&"agreements", "AGREEMENTS"],
			[&"portfolio", "WORK"]]:
		var which: StringName = pair[0]
		var tab := Button.new()
		tab.text = String(pair[1])
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_button(tab, _office_tab == which, 34.0)
		tab.pressed.connect(func() -> void:
			_office_tab = which
			_refresh())
		row.add_child(tab)
	_body.add_child(row)


## ---------------------------------------------------------------------------
## AREAS: WHERE THE BUSINESS WORKS, AND WHERE IT COULD
## ---------------------------------------------------------------------------
## The expansion screen. A lot is bought ONCE, in full, out of money the company
## has actually earned - there is no financing anywhere in this game and there
## never will be.
func _build_territories() -> void:
	_title.text = "SERVICE AREAS"
	_subtitle.text = "Where the business is allowed to work, and what it would cost to work somewhere else."
	_stat_row("Your funds", UITheme.format_money(GameSession.money()), UITheme.MONEY)
	_spacer(4)
	_body.add_child(_region_map())
	_spacer(6)

	_section_heading("OWNED")
	for region: int in Territory.owned_regions():
		_body.add_child(_owned_region_card(region))

	var available := Territory.available_regions()
	if available.is_empty():
		_spacer(6)
		var note := UITheme.label(_body, "AllOwned",
			"The business works every area on the map.",
			UITheme.FONT_META, UITheme.ACCENT_BRIGHT)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return

	_spacer(8)
	_section_heading("FOR SALE")
	for region: int in available:
		_body.add_child(_region_offer_card(region))


## ---------------------------------------------------------------------------
## THE MAP
## ---------------------------------------------------------------------------
## The five markets in progression order, as one strip: where the business is,
## what it owns, and what is still out there. It is a DIAGRAM rather than
## geography - there is no real map in this game and inventing one would be
## claiming a shape the world does not have - but a chain reads as a journey in
## a way five stacked cards never will.
##
##   SMALL TOWN - MEDIUM CITY - BIG TOWN - RURAL HIGHWAY - COUNTRY PARKS
##
## Built from `REGION_ORDER`, so it can never disagree with the cards below it.
func _region_map() -> Control:
	var frame := PanelContainer.new()
	frame.name = "RegionMap"
	frame.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.TRACK_BG, UITheme.RADIUS_CARD, 1.0,
			UITheme.HAIRLINE, 10.0, 10.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(row)

	var order := ACAServiceTerritory.REGION_ORDER
	for i in order.size():
		if i > 0:
			row.add_child(_map_link(Territory.owns(order[i])))
		row.add_child(_map_stop(order[i]))
	return frame


## One market on the strip. Owned markets are filled in their own colour; the
## one being worked out of carries the accent ring; locked ones are outlines.
func _map_stop(region: int) -> Control:
	var owned := Territory.owns(region)
	var here := Territory.active_region() == region
	var colour := ACAServiceTerritory.region_colour(region)

	var column := VBoxContainer.new()
	column.name = "Stop"
	column.add_theme_constant_override("separation", 3)
	column.custom_minimum_size = Vector2(96.0, 0.0)

	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(0.0, 20.0)
	dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", UITheme.stylebox(
		colour if owned else UITheme.CARD_BG,
		UITheme.RADIUS_CHIP,
		2.0 if here else 1.0,
		UITheme.ACCENT_BRIGHT if here else (colour if owned else UITheme.INK_FAINT),
		12.0, 2.0))
	var mark := UITheme.label(dot, "Mark",
		ACAServiceTerritory.region_short_name(region), UITheme.FONT_MICRO,
		UITheme.PAPER_INK if owned else UITheme.INK_FAINT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(dot)

	var state := "WORKING HERE" if here else ("OPEN" if owned else "LOCKED")
	var caption := UITheme.label(column, "State", state, UITheme.FONT_MICRO,
		UITheme.ACCENT_BRIGHT if here else
			(UITheme.INK_DIM if owned else UITheme.INK_FAINT))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return column


## The line between two stops. Solid once the far end is owned.
func _map_link(reached: bool) -> Control:
	var line := PanelContainer.new()
	line.name = "Link"
	line.custom_minimum_size = Vector2(26.0, 3.0)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_theme_stylebox_override("panel", UITheme.stylebox(
		UITheme.ACCENT if reached else UITheme.PAPER_RULE, 1.5, 0.0,
		UITheme.HAIRLINE, 0.0, 0.0))
	return line


func _owned_region_card(region: int) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD, 1.0,
			ACAServiceTerritory.region_colour(region)))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	pad.add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var name_label := UITheme.label(head, "Name",
		ACAServiceTerritory.region_name(region), UITheme.FONT_SUBHEAD,
		ACAServiceTerritory.region_colour(region))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var here := Territory.active_region() == region
	UITheme.label(head, "Here", "WORKING FROM HERE" if here else "OWNED",
		UITheme.FONT_MICRO, UITheme.ACCENT_BRIGHT if here else UITheme.INK_FAINT)

	var presence := Territory.presence(region)
	var bar := ProgressBar.new()
	bar.max_value = ACAServiceTerritory.PRESENCE_MAX
	bar.value = presence
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	UITheme.style_progress(bar, ACAServiceTerritory.region_colour(region))
	column.add_child(bar)

	UITheme.label(column, "Band", "%s   -   %d contracts completed here" % [
		Territory.presence_band_name(region),
		Territory.contracts_completed_in(region)],
		UITheme.FONT_META, UITheme.INK_DIM)
	var note := UITheme.label(column, "Note", Territory.presence_line(region),
		UITheme.FONT_MICRO, UITheme.INK_FAINT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return card


## WHAT A LOT COSTS AND WHAT IT BUYS, before the player commits to it.
func _region_offer_card(region: int) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	pad.add_child(column)

	UITheme.label(column, "Name", ACAServiceTerritory.region_name(region),
		UITheme.FONT_SUBHEAD, ACAServiceTerritory.region_colour(region))
	var blurb := UITheme.label(column, "Blurb",
		ACAServiceTerritory.region_blurb(region), UITheme.FONT_META, UITheme.INK_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var spec := ACAServiceTerritory.region_spec(region)
	_card_row(column, "Work there", ACAServiceTerritory.native_work_line(region))
	_card_row(column, "On the ground", ACARegionalContext.blurb(region))
	_card_row(column, "The market", String(spec["demand"]))
	_card_row(column, "Bring", String(spec["recommends"]))
	_card_row(column, "Competition", _competitor_line(region))

	var wanted := Territory.requirements(region)
	_card_row(column, "They want", "a standing of %d, and %d contracts behind you"
		% [int(round(float(wanted["reputation"]))), int(wanted["contracts"])])

	var cost := Territory.purchase_cost(region)
	var gate := Territory.can_purchase(region)
	var buy := Button.new()
	buy.text = "PURCHASE SERVICE LOT   %s" % UITheme.format_money(cost)
	UITheme.style_button(buy, bool(gate["allowed"]), 46.0)
	buy.disabled = not bool(gate["allowed"])
	if bool(gate["allowed"]):
		buy.pressed.connect(func() -> void: _purchase_lot(region))
		UITheme.label(column, "After", _after_purchase_text(cost),
			UITheme.FONT_META,
			UITheme.WARN if _leaves_thin_reserve(cost) else UITheme.INK_FAINT)
	else:
		var why := UITheme.label(column, "Why", String(gate["reason"]),
			UITheme.FONT_MICRO, UITheme.WARN)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(buy)
	return card


## Which firms are strong where, read off `ACABusiness`'s own table so there is
## one list of competitors in the game.
static func _competitor_line(region: int) -> String:
	var names := PackedStringArray()
	for firm: Dictionary in ACABusiness.COMPETITORS:
		if (firm["strong_in"] as Array).has(region):
			names.append(String(firm["name"]))
	if names.is_empty():
		return "Nobody dominates it."
	return "%s works it hard." % " and ".join(names)


func _purchase_lot(region: int) -> void:
	var cost := Territory.purchase_cost(region)
	if not Territory.try_purchase_lot(region):
		AppUI.notify_warning("Cannot buy that lot",
			String(Territory.can_purchase(region).get("reason", "")))
		_refresh()
		return
	AppUI.notify_success("Service lot purchased",
		"%s - %s. The board will start showing work there."
		% [ACAServiceTerritory.region_name(region), UITheme.format_money(cost)])
	_refresh()


## ---------------------------------------------------------------------------
## FLEET: WHAT EVERY MACHINE IS DOING RIGHT NOW
## ---------------------------------------------------------------------------
## The operations board. One row per machine the business owns, plus the player
## themselves, because the player IS one of the company's machines as far as
## capacity is concerned.
func _build_operations() -> void:
	_title.text = "OPERATIONS"
	_subtitle.text = "Everything the business has out, and where."

	_section_heading("THE COMPANY")
	_body.add_child(_operations_row("You",
		_player_operation_status(), UITheme.ACCENT_BRIGHT, _player_progress()))

	var fleet := Equipment.fleet_summary()
	if fleet.is_empty():
		var note := UITheme.label(_body, "NoFleet",
			"The business owns no autonomous machines. The workshop sells them.",
			UITheme.FONT_META, UITheme.INK_FAINT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		for entry: Dictionary in fleet:
			_body.add_child(_operations_row(String(entry["name"]),
				_unit_status(entry), UITheme.SAGE, float(entry["progress"])))

	_spacer(6)
	_stat_row("Contracts open", "%d of %d" % [
		JobManager.current_jobs().size(), JobManager.max_current_jobs()])

	_spacer(8)
	_section_heading("THE COMPETITION")
	for firm: Dictionary in Business.competitor_capacity_table():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 1)
		row.add_child(text)
		UITheme.label(text, "Name", String(firm["name"]), UITheme.FONT_BODY,
			firm["colour"])
		var strong := PackedStringArray()
		for region: Variant in firm["strong_in"]:
			strong.append(ACAServiceTerritory.region_name(int(region)))
		UITheme.label(text, "Where", "Strong in %s" % ", ".join(strong)
			if strong.size() > 0 else "Takes whatever is going",
			UITheme.FONT_MICRO, UITheme.INK_FAINT)
		var held := int(firm["held"])
		var capacity := int(firm["capacity"])
		var status := UITheme.label(row, "Held", "%d / %d in hand" % [held, capacity],
			UITheme.FONT_META, UITheme.WARN if held >= capacity else UITheme.INK_DIM)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_body.add_child(row)


func _operations_row(name_text: String, status: String, accent: Color,
		progress: float) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	pad.add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var name_label := UITheme.label(head, "Name", name_text, UITheme.FONT_BODY, accent)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status_label := UITheme.label(head, "Status", status, UITheme.FONT_META,
		UITheme.INK_DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	if progress > 0.0:
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.value = progress
		bar.custom_minimum_size = Vector2(0, 6)
		bar.show_percentage = false
		UITheme.style_progress(bar, accent)
		column.add_child(bar)
	return card


func _player_operation_status() -> String:
	var job := GameSession.current_job()
	if job == null:
		return "Available"
	return "%s - %d%%   (%s)" % [job.job_site, job.progress_percent(),
		ACAServiceTerritory.region_short_name(
			ACAServiceTerritory.region_for_job(job))]


func _player_progress() -> float:
	var job := GameSession.current_job()
	return job.progress if job != null else 0.0


func _unit_status(entry: Dictionary) -> String:
	if not bool(entry["busy"]):
		return "Available"
	var job := JobManager.get_job(StringName(String(entry["job_id"])))
	if job == null:
		return "Returning"
	return "%s - %d%%   (%s)" % [job.job_site,
		int(round(float(entry["progress"]) * 100.0)),
		ACAServiceTerritory.region_short_name(
			ACAServiceTerritory.region_for_job(job))]


## ---------------------------------------------------------------------------
## AGREEMENTS: WORK THE BUSINESS HAS COMMITTED TO
## ---------------------------------------------------------------------------
func _build_agreements() -> void:
	_title.text = "SERVICE AGREEMENTS"
	_subtitle.text = "Several properties, serviced repeatedly, for a fixed term."

	var active := Agreements.active()
	if not active.is_empty():
		_section_heading("BEING SERVED")
		for agreement: Dictionary in active:
			_body.add_child(_agreement_card(agreement, false))

	var offers := Agreements.offers()
	if not offers.is_empty():
		_spacer(6)
		_section_heading("ON THE TABLE")
		for offer: Dictionary in offers:
			_body.add_child(_agreement_card(offer, true))

	if active.is_empty() and offers.is_empty():
		var note := UITheme.label(_body, "NoAgreements",
			"Nobody has offered the business an agreement. They go to operators "
			+ "who are established in an area - do more work where you already are.",
			UITheme.FONT_META, UITheme.INK_FAINT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var history := Agreements.completed()
	if history.is_empty():
		return
	_spacer(8)
	_section_heading("SERVED OUT")
	for entry: Dictionary in history:
		_stat_row(String(entry["name"]),
			"honoured" if bool(entry.get("honoured", false)) else "dropped",
			UITheme.ACCENT_BRIGHT if bool(entry.get("honoured", false)) else UITheme.URGENT)


func _agreement_card(agreement: Dictionary, is_offer: bool) -> Control:
	var region := int(agreement["region"])
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD, 1.0,
			ACAServiceTerritory.region_colour(region)))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	pad.add_child(column)

	UITheme.label(column, "Name", String(agreement["name"]), UITheme.FONT_SUBHEAD,
		ACAServiceTerritory.region_colour(region))
	var blurb := UITheme.label(column, "Blurb", String(agreement["blurb"]),
		UITheme.FONT_META, UITheme.INK_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	for line: Dictionary in ACAServiceAgreements.summary_lines(agreement):
		_card_row(column, String(line["key"]), String(line["value"]))

	if not is_offer:
		UITheme.label(column, "Status",
			ACAServiceAgreements.status_line(agreement),
			UITheme.FONT_META, UITheme.ACCENT_BRIGHT)
		return card

	var gate := Agreements.can_accept(String(agreement["id"]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var take := Button.new()
	take.text = "SIGN THE AGREEMENT"
	take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(take, bool(gate["allowed"]), 44.0)
	take.disabled = not bool(gate["allowed"])
	if bool(gate["allowed"]):
		take.pressed.connect(func() -> void: _accept_agreement(String(agreement["id"])))
	row.add_child(take)
	var pass_button := Button.new()
	pass_button.text = "PASS"
	pass_button.custom_minimum_size = Vector2(110, 0)
	UITheme.style_button(pass_button, false, 44.0)
	pass_button.pressed.connect(func() -> void:
		Agreements.decline(String(agreement["id"]))
		_refresh())
	row.add_child(pass_button)
	column.add_child(row)

	if not bool(gate["allowed"]):
		var why := UITheme.label(column, "Why", String(gate["reason"]),
			UITheme.FONT_MICRO, UITheme.WARN)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return card


func _accept_agreement(id: String) -> void:
	if Agreements.accept(id):
		AppUI.notify_success("Agreement signed",
			"The first round of visits will be on the board tomorrow.")
	else:
		AppUI.notify_warning("Cannot take that on", "")
	_refresh()


## ---------------------------------------------------------------------------
## WORK: THE PORTFOLIO
## ---------------------------------------------------------------------------
## Before and after, from the same viewpoint, for every contract the player
## drove. The images are files under `user://portfolio/`; this only asks
## `ACAPortfolio` for them and draws what comes back. A missing photograph is a
## blank frame, never an error.
func _build_portfolio() -> void:
	_title.text = "COMPLETED WORK"
	var count := Portfolio.entry_count()
	_subtitle.text = "%d propert%s photographed, %d of them featured." % [
		count, "y" if count == 1 else "ies", Portfolio.featured_count()]

	if count <= 0:
		var note := UITheme.label(_body, "NoWork",
			"Nothing photographed yet. Every contract you drive to yourself is "
			+ "recorded here, before and after.",
			UITheme.FONT_META, UITheme.INK_FAINT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return

	for entry: Dictionary in Portfolio.entries():
		_body.add_child(_portfolio_card(entry))


func _portfolio_card(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	var featured := bool(entry.get("featured", false))
	card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD,
			1.0 if featured else 0.0, UITheme.WARN))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	pad.add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var title := UITheme.label(head, "Site", String(entry["site"]),
		UITheme.FONT_SUBHEAD, UITheme.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if featured:
		UITheme.label(head, "Featured", "FEATURED", UITheme.FONT_MICRO, UITheme.WARN)

	var frames := HBoxContainer.new()
	frames.add_theme_constant_override("separation", 8)
	frames.add_child(_portfolio_frame("BEFORE", String(entry.get("before", ""))))
	frames.add_child(_portfolio_frame("AFTER", String(entry.get("after", ""))))
	column.add_child(frames)

	UITheme.label(column, "Meta", "%s   -   %s   -   day %d" % [
		String(entry.get("property_type_name", "")),
		String(entry.get("size_name", "")), int(entry.get("day", 0))],
		UITheme.FONT_MICRO, UITheme.INK_FAINT)
	UITheme.label(column, "Detail", "%s   %s   %s   %s" % [
		UITheme.format_money(int(entry.get("payout", 0))),
		_stars_text(int(entry.get("stars", 0))),
		String(entry.get("machine", "")),
		String(entry.get("service", ""))],
		UITheme.FONT_META, UITheme.INK_DIM)

	# A PROPERTY THE BUSINESS HAS BEEN BACK TO shows its own history rather
	# than one more stranger's lawn.
	var pair := Portfolio.latest_pair_for_seed(int(entry["seed"]))
	if not pair.is_empty() and int(pair["latest"]["index"]) == int(entry["index"]):
		UITheme.label(column, "Repeat",
			"Serviced before - first visit on day %d."
			% int((pair["first"] as Dictionary).get("day", 0)),
			UITheme.FONT_MICRO, UITheme.ACCENT_BRIGHT)
	return card


func _portfolio_frame(caption: String, file_name: String) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	var label := UITheme.label(column, "Caption", caption, UITheme.FONT_MICRO,
		UITheme.INK_FAINT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var texture := Portfolio.load_image(file_name)
	if texture == null:
		var blank := PanelContainer.new()
		blank.add_theme_stylebox_override("panel",
			UITheme.stylebox(UITheme.TRACK_BG, UITheme.RADIUS_CHIP))
		blank.custom_minimum_size = Vector2(0, 92)
		var missing := UITheme.label(blank, "Missing", "no photograph",
			UITheme.FONT_MICRO, UITheme.INK_FAINT)
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		column.add_child(blank)
		return column

	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(0, 92)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	column.add_child(rect)
	return column


## A key/value line inside a card, as opposed to `_stat_row()`, which puts one
## on the counter itself.
func _card_row(parent: Node, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	var k := UITheme.label(row, "Key", key, UITheme.FONT_META, UITheme.INK_FAINT)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UITheme.label(row, "Value", value, UITheme.FONT_META, UITheme.INK_DIM)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size = Vector2(230, 0)
	parent.add_child(row)


func _____Attachment_Shop_____():
	pass

## ---------------------------------------------------------------------------
## THE ATTACHMENT SHOP, and the trailers
## ---------------------------------------------------------------------------
## Buying is here; FITTING is at the service lot, because what is bolted on is a
## decision about today's work rather than a purchase.
func _build_attachment_shop() -> void:
	_subtitle.text = "Things that bolt on to a machine, and the trailer that carries them."

	_section_heading("ATTACHMENTS")
	for id in ACAAttachments.ORDER:
		_body.add_child(_attachment_shop_row(id))

	_spacer(8)
	_section_heading("THE TRAILER")
	_stat_row("Behind the truck", Equipment.trailer_name())
	for line: Dictionary in ACAHaulage.summary_lines(Equipment.trailer_tier()):
		_stat_row(String(line["key"]), String(line["value"]))

	var next := ACAHaulage.next_tier(Equipment.trailer_tier())
	if String(next).is_empty():
		_spacer(4)
		var note := UITheme.label(_body, "TopTrailer",
			"The largest trailer the business can use.",
			UITheme.FONT_META, UITheme.ACCENT_BRIGHT)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	_spacer(4)
	_body.add_child(_trailer_row(next))


func _attachment_shop_row(id: StringName) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	card.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pad.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	UITheme.label(text, "Name", ACAAttachments.display_name(id),
		UITheme.FONT_SUBHEAD, UITheme.INK)
	var blurb := UITheme.label(text, "Blurb", ACAAttachments.describe(id),
		UITheme.FONT_META, UITheme.INK_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.label(text, "Effect", ACAAttachments.effect_line(id),
		UITheme.FONT_META, UITheme.ACCENT_BRIGHT)

	var fits := PackedStringArray()
	for mower_id: String in ACAMowerUpgrades.MOWER_IDS:
		if ACAAttachments.fits(id, mower_id):
			fits.append(ACAMowerUpgrades.mower_name(mower_id))
	UITheme.label(text, "Fits", "Fits: %s" % ", ".join(fits),
		UITheme.FONT_MICRO, UITheme.INK_FAINT)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(170, 0)
	if Equipment.owns_attachment(id):
		buy.text = "OWNED"
		UITheme.style_button(buy, false, 44.0)
		buy.disabled = true
	else:
		var cost := Equipment.attachment_cost(id)
		buy.text = "BUY   %s" % UITheme.format_money(cost)
		UITheme.style_button(buy, GameSession.can_afford(cost), 44.0)
		buy.disabled = not GameSession.can_afford(cost)
		buy.pressed.connect(func() -> void: _purchase_attachment(id))
	row.add_child(buy)
	return card


func _purchase_attachment(id: StringName) -> void:
	var cost := Equipment.attachment_cost(id)
	if Equipment.try_purchase_attachment(id):
		AppUI.notify_success("Attachment bought", "%s - %s"
			% [ACAAttachments.display_name(id), UITheme.format_money(cost)])
	else:
		AppUI.notify_warning("Cannot buy that", "Not enough money.")
	_refresh()


func _trailer_row(tier: StringName) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	pad.add_child(column)

	UITheme.label(column, "Name", ACAHaulage.display_name(tier),
		UITheme.FONT_SUBHEAD, UITheme.INK)
	var blurb := UITheme.label(column, "Blurb", ACAHaulage.describe(tier),
		UITheme.FONT_META, UITheme.INK_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for line: Dictionary in ACAHaulage.summary_lines(tier):
		_card_row(column, String(line["key"]), String(line["value"]))

	var cost := Equipment.trailer_cost(tier)
	var buy := Button.new()
	buy.text = "BUY   %s" % UITheme.format_money(cost)
	UITheme.style_button(buy, GameSession.can_afford(cost), 46.0)
	buy.disabled = not GameSession.can_afford(cost)
	if not buy.disabled:
		buy.pressed.connect(func() -> void: _purchase_trailer(tier))
		UITheme.label(column, "After", _after_purchase_text(cost),
			UITheme.FONT_META,
			UITheme.WARN if _leaves_thin_reserve(cost) else UITheme.INK_FAINT)
	column.add_child(buy)
	return card


func _purchase_trailer(tier: StringName) -> void:
	var cost := Equipment.trailer_cost(tier)
	if Equipment.try_purchase_trailer(tier):
		AppUI.notify_success("Trailer bought", "%s - %s"
			% [ACAHaulage.display_name(tier), UITheme.format_money(cost)])
	else:
		AppUI.notify_warning("Cannot buy that", "Not enough money.")
	_refresh()


func _____The_Service_Lot_____():
	pass

## ---------------------------------------------------------------------------
## THE SERVICE LOT: WHAT GOES OUT TODAY
## ---------------------------------------------------------------------------
## The one screen in the game where a working day is PREPARED rather than
## reacted to. Which machine, what is bolted to it, how it is set up for the
## clippings, whether a support unit comes, what the weather is going to do, and
## which of the business's territories to work out of.
##
## Every one of those is a decision the player will feel on the lawn, and none
## of them is a slider. This panel owns none of it: `ACAEquipment` owns the
## loadout, `ACAWorldClock` owns the forecast and `ACAServiceTerritory` owns the
## territories. It asks, and it asks them to do things.
func _build_depot() -> void:
	_title.text = "SERVICE LOT"
	_subtitle.text = "Set the machine up for the day, and take the road out."

	var loadout := Equipment.loadout_summary()
	_stat_row("Trailer", String(loadout["trailer_name"]))
	_stat_row("Machines aboard", "%d of %d slots" % [
		int(loadout["machine_slots"]), int(loadout["machine_capacity"])],
		UITheme.WARN if int(loadout["machine_slots"])
			>= int(loadout["machine_capacity"]) else UITheme.INK)
	_stat_row("Attachments", "%d of %d slots" % [
		int(loadout["attachment_slots"]), int(loadout["attachment_capacity"])],
		UITheme.WARN if int(loadout["attachment_slots"])
			>= int(loadout["attachment_capacity"]) else UITheme.INK)

	_spacer(6)
	_build_machine_choice()
	_spacer(6)
	_build_mode_choice()
	_spacer(6)
	_build_attachment_bay()
	_spacer(6)
	_build_support_unit()
	_spacer(8)
	_build_forecast()
	_spacer(8)
	_build_travel()


## WHICH MACHINE GOES OUT. The same selection the workshop offers, put where the
## day is actually planned - a contractor picks the machine at the yard, not at
## the dealer.
func _build_machine_choice() -> void:
	_section_heading("THE MACHINE")
	var owned := Equipment.owned_mowers()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for id: String in owned:
		var button := Button.new()
		button.text = ACAMowerUpgrades.mower_name(id)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var chosen := String(Equipment.selected_mower()) == id
		UITheme.style_button(button, chosen, 40.0)
		button.disabled = chosen
		button.pressed.connect(func() -> void:
			Equipment.select_mower(id)
			_refresh())
		row.add_child(button)
	_body.add_child(row)
	if owned.size() <= 1:
		var note := UITheme.label(_body, "OneMachine",
			"The business owns one machine. The workshop sells the others.",
			UITheme.FONT_MICRO, UITheme.INK_FAINT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## HOW IT IS SET UP FOR THE CLIPPINGS. Three configurations, and which of them
## are offered is decided by what is bolted on - see `ACAAttachments`.
func _build_mode_choice() -> void:
	_section_heading("CONFIGURATION")
	var available := Equipment.available_modes()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for mode in ACAMowingMode.MODE_ORDER:
		var button := Button.new()
		button.text = ACAMowingMode.mode_name(mode)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var usable: bool = available.has(mode)
		UITheme.style_button(button, usable and Equipment.mowing_mode() == mode, 40.0)
		button.disabled = not usable
		if usable:
			button.pressed.connect(func() -> void:
				Equipment.set_mowing_mode(mode)
				_refresh())
		row.add_child(button)
	_body.add_child(row)

	var blurb := UITheme.label(_body, "ModeBlurb",
		ACAMowingMode.blurb(Equipment.mowing_mode()),
		UITheme.FONT_META, UITheme.INK_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var capacity := Equipment.selected_bag_capacity()
	_stat_row("Carries", ACAClippings.format_kg(capacity) if capacity > 0.0
		else "nothing - it leaves what it cuts",
		UITheme.ACCENT_BRIGHT if capacity > 0.0 else UITheme.INK_DIM)

	# WHAT IS MISSING, and how to get it. A greyed-out configuration with no
	# explanation is the worst possible answer to "why can I not do that".
	for mode in ACAMowingMode.MODE_ORDER:
		if available.has(mode):
			continue
		var wanted := ACAMowingMode.requires_attachment(mode)
		if String(wanted).is_empty():
			continue
		var line := "%s needs the %s." % [ACAMowingMode.mode_name(mode),
			ACAAttachments.display_name(wanted).to_lower()]
		if not Equipment.owns_attachment(wanted):
			line += " The workshop sells one."
		else:
			line += " It is owned - fit it below."
		var note := UITheme.label(_body, "Missing_%d" % mode, line,
			UITheme.FONT_MICRO, UITheme.INK_FAINT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## WHAT IS BOLTED ON. Everything the business owns that fits the machine going
## out, with the room left on the trailer counted honestly.
func _build_attachment_bay() -> void:
	_section_heading("THE ATTACHMENT BAY")
	var mower := String(Equipment.selected_mower())
	var owned := Equipment.owned_attachments()
	var any := false
	for id in owned:
		if not ACAAttachments.fits(id, mower):
			continue
		any = true
		_body.add_child(_attachment_row(id))
	if not any:
		var note := UITheme.label(_body, "NoAttachments",
			"Nothing in the shed fits this machine. The workshop sells attachments.",
			UITheme.FONT_META, UITheme.INK_FAINT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _attachment_row(id: StringName) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CARD_BG, UITheme.RADIUS_CARD))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	card.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pad.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	UITheme.label(text, "Name", ACAAttachments.display_name(id),
		UITheme.FONT_SUBHEAD, UITheme.INK)
	UITheme.label(text, "Effect", ACAAttachments.effect_line(id),
		UITheme.FONT_META, UITheme.ACCENT_BRIGHT)

	var fitted := Equipment.is_fitted(id)
	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 0)
	if fitted:
		button.text = "TAKE OFF"
		UITheme.style_button(button, false, 42.0)
		button.pressed.connect(func() -> void:
			Equipment.remove_attachment(id)
			_refresh())
	else:
		var gate := Equipment.can_fit(id)
		button.text = "FIT"
		UITheme.style_button(button, bool(gate["allowed"]), 42.0)
		button.disabled = not bool(gate["allowed"])
		if bool(gate["allowed"]):
			button.pressed.connect(func() -> void:
				Equipment.fit_attachment(id)
				_refresh())
		else:
			var why := UITheme.label(text, "Why", String(gate["reason"]),
				UITheme.FONT_MICRO, UITheme.WARN)
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(button)
	return card


## WHETHER A MACHINE COMES TOO. The escort was chosen from the job board before;
## it belongs here, with the rest of what goes on the trailer.
func _build_support_unit() -> void:
	if not Equipment.has_autonomous_units():
		return
	_section_heading("SUPPORT UNIT")
	var current := Equipment.escort_unit_uid()

	var none := Button.new()
	none.text = "NOBODY - THE MACHINE GOES ALONE"
	UITheme.style_button(none, current == 0, 38.0)
	none.disabled = current == 0
	none.pressed.connect(func() -> void:
		Equipment.clear_escort_unit()
		_refresh())
	_body.add_child(none)

	for entry: Dictionary in Equipment.fleet_summary():
		var uid := int(entry["uid"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_label := UITheme.label(row, "Name", String(entry["name"]),
			UITheme.FONT_BODY, UITheme.INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 0)
		if bool(entry["busy"]):
			button.text = "OUT ON A JOB"
			UITheme.style_button(button, false, 36.0)
			button.disabled = true
		else:
			var gate := Equipment.can_load_unit(uid)
			button.text = "LOADED" if current == uid else "LOAD"
			UITheme.style_button(button, current == uid, 36.0)
			button.disabled = current == uid or not bool(gate["allowed"])
			if not button.disabled:
				button.pressed.connect(func() -> void:
					Equipment.set_escort_unit(uid)
					_refresh())
			elif not bool(gate["allowed"]) and current != uid:
				name_label.text += "   -   %s" % String(gate["reason"])
		row.add_child(button)
		_body.add_child(row)


## ---------------------------------------------------------------------------
## THE FORECAST
## ---------------------------------------------------------------------------
## The same function the sky is driven from, evaluated further along the clock -
## see `ACAWorldClock.forecast()`. It cannot be wrong, because there is nothing
## separate for it to be wrong about.
func _build_forecast() -> void:
	_section_heading("THE FORECAST")
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	for entry: Dictionary in WorldClock.forecast(9.0):
		strip.add_child(_forecast_chip(entry))
	_body.add_child(strip)

	var advice := UITheme.label(_body, "Advice",
		ACAGroundConditions.forecast_advice(WorldClock.minutes_until_rain()),
		UITheme.FONT_META, UITheme.INK_DIM)
	advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var ground := ACAGroundConditions.current()
	_stat_row("Ground right now", ACAGroundConditions.state_name(ground),
		UITheme.WARN if ACAGroundConditions.is_wet(ground) else UITheme.INK)


func _forecast_chip(entry: Dictionary) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel",
		UITheme.stylebox(UITheme.CHIP_BG, UITheme.RADIUS_CHIP))
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	chip.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	pad.add_child(column)

	var preset := String(entry["preset"])
	var hour := int(floor(float(entry["hour"])))
	var when := "NOW" if bool(entry["is_now"]) else "%02d:00" % hour
	var when_label := UITheme.label(column, "When", when, UITheme.FONT_MICRO,
		UITheme.INK if bool(entry["is_now"]) else UITheme.INK_FAINT)
	when_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var mark := UIGlyph.make(_weather_glyph(preset), 20.0, _weather_colour(preset))
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(mark)

	var name_label := UITheme.label(column, "Preset", preset.to_upper(),
		UITheme.FONT_MICRO, _weather_colour(preset))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return chip


static func _weather_glyph(preset: String) -> int:
	if ACAWorldClock.is_rain(preset):
		return UIGlyph.Kind.RAIN
	if ACAWorldClock.is_damp_air(preset) or preset == "Overcast" 			or preset == "Partly Cloudy":
		return UIGlyph.Kind.CLOUD
	return UIGlyph.Kind.SUN


static func _weather_colour(preset: String) -> Color:
	if ACAWorldClock.is_rain(preset):
		return UITheme.SAGE
	if ACAWorldClock.is_damp_air(preset) or preset == "Overcast":
		return UITheme.INK_DIM
	return UITheme.WARN


## ---------------------------------------------------------------------------
## THE ROAD OUT
## ---------------------------------------------------------------------------
## Travel between the business's own service lots. An hour of the working day
## and a scene change - there is no road between the territories and building
## one would be a driving game bolted to a mowing game.
func _build_travel() -> void:
	_section_heading("THE ROAD OUT")
	var owned := Territory.owned_regions()
	if owned.size() <= 1:
		var note := UITheme.label(_body, "OneRegion",
			"The business works one area. The office sells lots in the others.",
			UITheme.FONT_META, UITheme.INK_FAINT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return

	var here := Territory.active_region()
	for region: int in owned:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 1)
		row.add_child(text)
		UITheme.label(text, "Name", ACAServiceTerritory.region_name(region),
			UITheme.FONT_BODY, ACAServiceTerritory.region_colour(region))
		UITheme.label(text, "Presence", "%s   -   %s" % [
			Territory.presence_band_name(region),
			ACAServiceTerritory.native_work_line(region)],
			UITheme.FONT_MICRO, UITheme.INK_FAINT)

		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 0)
		if region == here:
			button.text = "YOU ARE HERE"
			UITheme.style_button(button, false, 38.0)
			button.disabled = true
		else:
			button.text = "DRIVE OVER"
			UITheme.style_button(button, true, 38.0)
			button.pressed.connect(func() -> void: _travel_to(region))
		row.add_child(button)
		_body.add_child(row)

	var cost := UITheme.label(_body, "TravelCost",
		"An hour on the road, and the trailer comes with you.",
		UITheme.FONT_MICRO, UITheme.INK_FAINT)
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _travel_to(region: int) -> void:
	close()
	GameSession.travel_to_region(region)


# ==================================================================== helpers

func _stat_row(key: String, value: String, value_colour: Color = UITheme.INK) -> void:
	var row := HBoxContainer.new()
	var k := UITheme.label(row, "Key", key, UITheme.FONT_BODY, UITheme.INK_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UITheme.label(row, "Value", value, UITheme.FONT_BODY, value_colour)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_body.add_child(row)


## A small capitalised rule, so one counter can hold two subjects without the
## player having to work out where one ends.
func _section_heading(text: String) -> void:
	var label := UITheme.label(_body, "Heading_" + text, text,
		UITheme.FONT_MICRO, UITheme.PAPER_INK_FAINT)
	label.add_theme_constant_override(&"line_spacing", 0)
	var rule := ColorRect.new()
	rule.color = UITheme.PAPER_RULE
	rule.custom_minimum_size = Vector2(0, 1)
	_body.add_child(rule)


func _spacer(height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	_body.add_child(s)


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
