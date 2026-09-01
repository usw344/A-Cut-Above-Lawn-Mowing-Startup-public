class_name ACABusinessTown
extends Node3D

## Business Town hub for "A Cut Above: Mow & Grow".
##
## Self-contained: everything it loads lives under res://ACA_BusinessTown/. It owns
## no game systems - it reports what the player asked for through
## [signal business_action_requested] and lets the host project route it.

signal business_action_requested(action: StringName)
signal building_selection_changed(building_id: StringName)

const PICK_LAYER := 9
const PICK_MASK := 1 << (PICK_LAYER - 1)
const RAY_LENGTH := 400.0

@export var camera_rig: ACABusinessCamera
@export var hud: ACABusinessHUD
@export var buildings_root: Node3D

@export_group("Placeholder readouts")
@export var starting_funds: int = 0
@export var starting_day: int = 1

var _buildings: Array[ACAInteractiveBuilding] = []
var _hovered: ACAInteractiveBuilding = null
var _selected: ACAInteractiveBuilding = null

# Picking is queued from input callbacks and executed during the physics step.
# This keeps direct_space_state access compatible with threaded 3D physics.
var _pending_hover_pick := false
var _pending_click_pick := false
var _pending_mouse_position := Vector2.ZERO


func _ready() -> void:
	_collect_buildings()

	if hud != null:
		hud.set_funds(starting_funds)
		hud.set_day(starting_day)
		hud.open_requested.connect(_on_open_requested)
		hud.back_requested.connect(clear_selection)


func _collect_buildings() -> void:
	_buildings.clear()

	var root: Node = buildings_root if buildings_root != null else self

	for node in root.find_children("*", "ACAInteractiveBuilding", true, false):
		var b := node as ACAInteractiveBuilding
		_buildings.append(b)
		b.selected.connect(_on_building_selected)


func _unhandled_input(event: InputEvent) -> void:
	if hud != null and hud.is_modal_open():
		if event.is_action_pressed(&"ui_cancel"):
			hud.close_active_modal()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		_pending_mouse_position = event.position
		_pending_hover_pick = true

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_pending_mouse_position = mb.position
			_pending_click_pick = true
			get_viewport().set_input_as_handled()

	elif event.is_action_pressed(&"ui_cancel"):
		if _selected != null:
			clear_selection()
			get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if hud != null and hud.is_modal_open():
		_pending_click_pick = false
		_pending_hover_pick = false
		return

	# Prioritize clicks so a click uses the exact queued mouse position.
	if _pending_click_pick:
		_pending_click_pick = false
		_pending_hover_pick = false

		var hit := _pick(_pending_mouse_position)

		if hit != null:
			hit.click()
		else:
			clear_selection()

		_set_hovered(hit)
		return

	if _pending_hover_pick:
		_pending_hover_pick = false
		_set_hovered(_pick(_pending_mouse_position))


## Raycast against the building pick layer only.
## Must be called from the physics-processing window when threaded physics is enabled.
func _pick(screen_pos: Vector2) -> ACAInteractiveBuilding:
	if camera_rig == null or camera_rig.camera == null:
		return null

	var cam := camera_rig.camera
	var ray_origin := cam.project_ray_origin(screen_pos)

	var params := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + cam.project_ray_normal(screen_pos) * RAY_LENGTH,
		PICK_MASK
	)

	params.collide_with_areas = true
	params.collide_with_bodies = false

	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)

	if hit.is_empty():
		return null

	var node: Node = hit.get("collider")

	while node != null:
		if node is ACAInteractiveBuilding:
			return node
		node = node.get_parent()

	return null


func _set_hovered(b: ACAInteractiveBuilding) -> void:
	if _hovered == b:
		return

	if _hovered != null:
		_hovered.set_hovered(false)

	_hovered = b

	if _hovered != null:
		_hovered.set_hovered(true)

	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND if _hovered != null else Input.CURSOR_ARROW
	)


func _on_building_selected(building_id: StringName) -> void:
	for b in _buildings:
		if b.building_id == building_id:
			select_building(b)
			return


func select_building(b: ACAInteractiveBuilding) -> void:
	if _selected == b:
		return

	if _selected != null:
		_selected.set_selected(false)

	_selected = b
	b.set_selected(true)

	if camera_rig != null:
		camera_rig.focus_on(b.world_focus_point(), b.focus_zoom)

	if hud != null:
		hud.show_building(b)

	building_selection_changed.emit(b.building_id)


func clear_selection() -> void:
	if _selected == null:
		return

	_selected.set_selected(false)
	_selected = null

	if camera_rig != null:
		camera_rig.reset_view()

	if hud != null:
		hud.hide_building()

	building_selection_changed.emit(&"")


func selected_building_id() -> StringName:
	return _selected.building_id if _selected != null else &""


## Building ids the HOST PROJECT opens with a real screen of its own. The town
## emits its signal for them and then keeps out of the way; everything else
## still gets the town's own "coming soon" placeholder.
##
## Exported rather than hard-coded so this package stays generic - it does not
## need to know that A Cut Above happens to have a fuel shop.
@export var host_handled_buildings: Array[StringName] = [
	&"supply_store", &"business_hq", &"mower_dealer", &"service_lot",
]


func _on_open_requested() -> void:
	if _selected == null:
		return

	business_action_requested.emit(_selected.building_id)

	if hud == null:
		return

	if _selected.building_id == &"job_office":
		hud.open_jobs()
	elif not host_handled_buildings.has(_selected.building_id):
		hud.open_placeholder(_selected)
