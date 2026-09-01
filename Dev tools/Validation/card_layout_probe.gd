extends Node
## DEVELOPMENT ONLY. Renders the CONTRACT CARDS - the Job Intro work order and
## the Job Complete results sheet - at the content extremes they have to survive,
## and MEASURES whether anything crosses the sheet it is drawn on.
##
##   godot --path <project> "res://Dev tools/Validation/Card Layout Probe.tscn" \
##       -- "--card-output=<absolute path>"
##
## Needs a real renderer: it captures the viewport.
##
## WHY THIS EXISTS
##
## The intro card shipped with the heading clipped at the top, the values off
## the right edge and the status line cut in half at the bottom, and none of the
## existing suites saw it, because every one of them asserts on VALUES. A label
## whose text is correct and whose rectangle hangs forty pixels outside its
## parent passes them all.
##
## So this asserts on RECTANGLES. For each case it walks every Label on the card
## and checks its global rect against the sheet's, less the padding the sheet
## declares. Any label crossing that line is reported with the overrun in pixels
## and the run fails. The screenshots are for judging composition; the
## assertions are what makes it a test.

const DEFAULT_OUTPUT_DIR := "user://card_layout"

## Names chosen for the two ways a heading breaks: one word too long to fit on a
## line at all, and enough words to need three of them. Generic site names, in
## keeping with `ACAJobCatalog` - the game never names a person.
const SHORT_NAME := "Corner House"
const TYPICAL_NAME := "Suburban Home"
const LONG_NAME := "Light Industrial Storage Facility Grounds"
const UNBROKEN_NAME := "Llanfairpwllgwyngyllgogerychwyrndrobwllllantysilio"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(1280, 720),
]

var _dir: String = DEFAULT_OUTPUT_DIR
var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dir = _output_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	print("[CARD] writing to %s" % _dir)
	_run.call_deferred()


func _output_dir() -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--card-output="):
			return arg.trim_prefix("--card-output=")
	return DEFAULT_OUTPUT_DIR


func _run() -> void:
	for resolution in RESOLUTIONS:
		await _set_resolution(resolution)
		for case in _intro_cases():
			await _run_intro(case, resolution)
		await _run_complete(resolution)

	print("[CARD] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _intro_cases() -> Array:
	return [
		{
			"label": "short-small",
			"name": SHORT_NAME, "size": "Small Lawn",
			"type": "Residential Contract", "notes": "",
			"reward": 60, "minutes": 5,
		},
		{
			"label": "typical-medium",
			"name": TYPICAL_NAME, "size": "Medium Lawn",
			"type": "Residential Contract",
			"notes": "A pond and six obstacles.",
			"reward": 240, "minutes": 12,
			"terms": [
				{"flag": 1, "text": "Collect the clippings (about 128 kg)",
					"mandatory": false},
			],
			"equipment": "On the trailer: Powered Walk-Behind.",
		},
		{
			"label": "long-large",
			"name": LONG_NAME, "size": "Large Lawn",
			"type": "Commercial Contract",
			"notes": "A pond, eleven obstacles and planted beds along the frontage.",
			"reward": 1480, "minutes": 34,
			# THE FULLEST CARD THE GAME CAN PRODUCE: a long name, a long site
			# line, every contract term at once and an equipment line. If the
			# composition survives this it survives anything the generator rolls.
			"terms": [
				{"flag": 1, "text": "Collect the clippings (about 285 kg)",
					"mandatory": true},
				{"flag": 4, "text": "Finish within 34 minutes on site",
					"mandatory": false},
				{"flag": 8, "text": "Do not run the tank dry on site",
					"mandatory": false},
			],
			"equipment": "On the trailer: Riding Mower, with the Commercial Autonomous Unit 3. It has no catcher, and this contract collects.",
		},
		{
			"label": "unbroken-large",
			"name": UNBROKEN_NAME, "size": "Large Lawn",
			"type": "Institutional Contract",
			"notes": "A pond and twelve obstacles.",
			"reward": 12480, "minutes": 120,
		},
	]


# ======================================================================= intro

func _run_intro(case: Dictionary, resolution: Vector2i) -> void:
	var scene := load("res://UI/Job Intro/Job Intro.tscn") as PackedScene
	var intro := scene.instantiate() as JobIntroScreen
	get_tree().root.add_child(intro)
	await get_tree().process_frame

	intro.set_contract_type(String(case["type"]))
	intro.set_site_notes(String(case["notes"]))
	intro.set_requirements(case.get("terms", []))
	intro.set_equipment_line(String(case.get("equipment", "")))
	intro.show_job(String(case["name"]), String(case["size"]),
		int(case["reward"]), int(case["minutes"]))
	intro.set_status("PREPARING EQUIPMENT...")
	# Past the entrance tween, so the capture is of the settled composition.
	await _settle(0.9)

	var label := "intro-%s-%dx%d" % [case["label"], resolution.x, resolution.y]
	await _capture(label)
	_measure(intro, label)

	get_tree().root.remove_child(intro)
	intro.free()
	await get_tree().process_frame


# ==================================================================== complete

func _run_complete(resolution: Vector2i) -> void:
	var scene := load("res://UI/Job Complete/Job Complete.tscn") as PackedScene
	var results := scene.instantiate() as JobCompleteScreen
	get_tree().root.add_child(results)
	await get_tree().process_frame

	results.show_results(LONG_NAME, 1.0, 1284.0, 1480, 220)
	# THE FULLEST RESULTS SHEET THE GAME CAN PRODUCE: clippings collected AND
	# spilled, fuel, an escort's contribution, three scored terms and a review.
	results.show_details({
		"completion": 1.0, "base_pay": 1480, "bonus": 220,
		"collected_kg": 268.4, "spilled_kg": 41.2, "fuel_used": 62.0,
		"autonomous_cells": 4820,
		"autonomous_name": "Commercial Autonomous Unit 3",
		"terms_met": 4 | 8, "terms_missed": 1,
		"review_stars": 3,
		"review_text": "Good service, though the job took longer than expected. The clippings were left behind.",
		"reputation_change": 0.4, "reputation": 47.6,
		"services": 3, "loyalty": 62.0,
	})
	results.finish_animation()
	await _settle(0.9)

	var label := "complete-long-%dx%d" % [resolution.x, resolution.y]
	await _capture(label)
	_measure(results, label)

	get_tree().root.remove_child(results)
	results.free()
	await get_tree().process_frame


# ==================================================================== measure

## The sheet a card is drawn on: the outermost PanelContainer under the screen.
func _sheet_of(root: Control) -> Control:
	for node in root.find_children("*", "PanelContainer", true, false):
		return node as Control
	return null


## Every Label must sit inside the sheet, less the padding the sheet's own
## MarginContainer declares. Anything hanging out is what the player sees as
## clipped text, and it is reported in pixels rather than as a verdict.
func _measure(root: Control, label: String) -> void:
	var sheet := _sheet_of(root)
	if sheet == null:
		_report(false, "%s: no sheet found" % label)
		return

	var pad := _padding_of(sheet)
	var safe := sheet.get_global_rect().grow_individual(
		-pad.x, -pad.y, -pad.z, -pad.w)
	var worst := 0.0
	var offender := ""
	for node in root.find_children("*", "Label", true, false):
		var text_label := node as Label
		if not text_label.is_visible_in_tree() or text_label.text.strip_edges().is_empty():
			continue
		var rect := text_label.get_global_rect()
		var over := maxf(maxf(safe.position.x - rect.position.x,
				safe.position.y - rect.position.y),
			maxf(rect.end.x - safe.end.x, rect.end.y - safe.end.y))
		if over > worst:
			worst = over
			offender = text_label.name

	# One pixel of slack: a rounded font metric is not a layout fault.
	# THE HOLDER MUST NOT OUTGROW THE SCREEN. A wrapped Label with no declared
	# measure reports a minimum size that depends on its current width, and a
	# CenterContainer takes its own size from that minimum: the two chase each
	# other and the holder ends up several screens tall, centring the card
	# somewhere below the window. That is invisible to a rect-vs-sheet check,
	# because the card is still perfectly composed - just not on screen.
	var holder := root.get_node_or_null(^"CardHolder") as Control
	if holder != null:
		var window_size := Vector2(get_viewport().get_visible_rect().size)
		_report(holder.size.y <= window_size.y + 1.0 and holder.size.x <= window_size.x + 1.0,
			"%s: holder %.0fx%.0f did not outgrow %.0fx%.0f" % [
				label, holder.size.x, holder.size.y, window_size.x, window_size.y])
		var centred := absf((sheet.get_global_rect().get_center().y) - window_size.y * 0.5)
		_report(centred <= 2.0,
			"%s: sheet centred to within %.1f px" % [label, centred])
	var ok := worst <= 1.0
	_report(ok, "%s: worst label overrun %.1f px%s" % [
		label, worst, (" (%s)" % offender) if not offender.is_empty() else ""])

	# A sheet wider than the window is the other way this breaks.
	var window := Vector2(get_viewport().get_visible_rect().size)
	var fits := sheet.size.x <= window.x and sheet.size.y <= window.y
	_report(fits, "%s: sheet %.0fx%.0f fits in %.0fx%.0f" % [
		label, sheet.size.x, sheet.size.y, window.x, window.y])


## Left / top / right / bottom padding the sheet declares, from its
## MarginContainer if it has one and from its stylebox otherwise.
func _padding_of(sheet: Control) -> Vector4:
	for child in sheet.get_children():
		var margin := child as MarginContainer
		if margin != null:
			return Vector4(
				margin.get_theme_constant(&"margin_left"),
				margin.get_theme_constant(&"margin_top"),
				margin.get_theme_constant(&"margin_right"),
				margin.get_theme_constant(&"margin_bottom"))
	var box := sheet.get_theme_stylebox(&"panel")
	if box == null:
		return Vector4.ZERO
	return Vector4(
		maxf(box.content_margin_left, 0.0), maxf(box.content_margin_top, 0.0),
		maxf(box.content_margin_right, 0.0), maxf(box.content_margin_bottom, 0.0))


# ===================================================================== helpers

func _set_resolution(resolution: Vector2i) -> void:
	get_window().size = resolution
	get_window().content_scale_size = resolution
	await _settle(0.2)


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, label]
	if image.save_png(path) != OK:
		print("[CARD] FAILED to write %s" % path)
	else:
		print("[CARD] %s" % path)


## Settled means SECONDS, not frames. The entrance tween is 0.32 s and this
## project runs uncapped: forty frames is a sixth of a second on this machine,
## and the first version of this probe captured every card mid-fade.
func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	await get_tree().process_frame


func _report(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
		print("[CARD]  ok   %s" % message)
	else:
		_fail += 1
		print("[CARD] FAIL  %s" % message)
