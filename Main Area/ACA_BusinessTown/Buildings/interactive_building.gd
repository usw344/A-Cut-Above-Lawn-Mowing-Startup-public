@tool
class_name ACAInteractiveBuilding
extends Node3D
## A clickable destination in the Business Town.
##
## The wrapper deliberately never touches the imported model's materials, so packs
## that share one atlas material across every building cannot cross-highlight each
## other. Hover / selection feedback is done with transforms and dedicated marker
## nodes that belong to this wrapper only.

signal selected(building_id: StringName)

const HOVER_LIFT := 0.10
const HOVER_SCALE := 1.03
const SELECT_LIFT := 0.16
const SELECT_SCALE := 1.05
const TWEEN_TIME := 0.16

@export var building_id: StringName = &"":
	set(v):
		building_id = v
		update_configuration_warnings()
@export var display_name: String = "Location"
@export_multiline var description: String = ""
## Label on the panel's primary button.
@export var action_label: String = "OPEN"
## A disabled building still hovers and shows its panel, but reports itself locked.
@export var enabled: bool = true
@export var accent_color: Color = Color(0.42, 0.68, 0.36)

## Where the camera should centre when this building is focused, in local space.
@export var focus_point: Vector3 = Vector3.ZERO
## Orthographic size the camera zooms to when this building is focused.
@export var focus_zoom: float = 11.0

@onready var _visual: Node3D = get_node_or_null(^"Visual")
@onready var _marker: Node3D = get_node_or_null(^"SelectionMarker")
@onready var _label: Label3D = get_node_or_null(^"NameLabel")

var _base_position := Vector3.ZERO
var _base_scale := Vector3.ONE
var _tween: Tween
var _hovered := false
var _selected := false


func _ready() -> void:
	# @tool is only here for the configuration warnings; the editor must not run
	# the runtime state setup or it would author hover state into the scene.
	if Engine.is_editor_hint():
		return
	if _visual != null:
		# Captured once so repeated hovers can never compound the transform.
		_base_position = _visual.position
		_base_scale = _visual.scale
	if _marker != null:
		_marker.visible = false
		_tint_marker()
	if _label != null:
		_label.text = display_name
		_label.modulate = Color(1, 1, 1, 0)
		_label.visible = false


func _tint_marker() -> void:
	# The marker mesh is generated per building instance, so tinting it is local.
	var mi := _marker.get_node_or_null(^"Mesh") as MeshInstance3D
	if mi == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat


func world_focus_point() -> Vector3:
	return global_transform * focus_point


func set_hovered(value: bool) -> void:
	if _hovered == value:
		return
	_hovered = value
	_apply_state()


func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	_apply_state()


func is_selected() -> bool:
	return _selected


func click() -> void:
	selected.emit(building_id)


func _apply_state() -> void:
	if _visual == null:
		return
	var lift := 0.0
	var scl := 1.0
	if _selected:
		lift = SELECT_LIFT
		scl = SELECT_SCALE
	elif _hovered:
		lift = HOVER_LIFT
		scl = HOVER_SCALE

	# Always retarget from the stored base state; never read the live transform.
	var target_pos := _base_position + Vector3(0.0, lift, 0.0)
	var target_scale := _base_scale * scl

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_visual, ^"position", target_pos, TWEEN_TIME)
	_tween.tween_property(_visual, ^"scale", target_scale, TWEEN_TIME)

	var show_extras := _hovered or _selected
	if _marker != null:
		_marker.visible = show_extras
		_marker.scale = Vector3.ONE * (1.12 if _selected else 1.0)
	if _label != null:
		_label.visible = show_extras
		_tween.tween_property(_label, ^"modulate:a", 1.0 if show_extras else 0.0, TWEEN_TIME)


func _get_configuration_warnings() -> PackedStringArray:
	var warn := PackedStringArray()
	if String(building_id).is_empty():
		warn.append("building_id is empty; the Business Town cannot route this location.")
	if get_node_or_null(^"Visual") == null:
		warn.append("Expected a child Node3D named 'Visual' holding the model.")
	if get_node_or_null(^"InteractionArea") == null:
		warn.append("Expected a child Area3D named 'InteractionArea' for mouse picking.")
	return warn
