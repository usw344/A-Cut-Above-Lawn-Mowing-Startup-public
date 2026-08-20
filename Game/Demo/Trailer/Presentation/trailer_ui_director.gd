class_name ACATrailerUIDirector
extends Node
## DEVELOPMENT / MEDIA TOOLING. Decides, explicitly, what UI is on screen in
## every trailer shot.
##
## The rule is that NOTHING is left up and hoped away by a fade. Each beat names
## the layer it wants and everything else is off:
##
##     menu        the real main menu, cursor visible
##     town        the town's business HUD
##     job board   the board, cursor visible
##     cinematic   nothing at all, cursor hidden
##     gameplay    the real production HUD, cursor hidden
##     results     the real Job Complete screen
##     end card    nothing but the branding
##
## Toasts are suppressed for the whole capture through
## `AppUI.set_notifications_suppressed()`, a development flag. No notification
## was removed or weakened to make the trailer work, and `restore()` clears it.

enum Layer { NONE, MENU, TOWN, JOB_BOARD, CINEMATIC, GAMEPLAY, RESULTS }

var _layer: int = Layer.NONE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Called once when the capture begins.
func begin_capture() -> void:
	AppUI.set_notifications_suppressed(true)
	AppUI.clear_notifications()


## Called on restart and on quit. Everything this file changed, undone.
func restore() -> void:
	AppUI.set_notifications_suppressed(false)
	AppUI.unlock_mouse_context()
	_layer = Layer.NONE


func current_layer() -> int:
	return _layer


## THE one entry point. Sets the requested layer and clears every other.
func show_layer(layer: int) -> void:
	_layer = layer
	AppUI.clear_notifications()

	match layer:
		Layer.MENU:
			_set_gameplay_ui(false)
			_set_town_hud(true)
			_cursor(Input.MOUSE_MODE_VISIBLE)
		Layer.TOWN:
			_set_gameplay_ui(false)
			_set_town_hud(true)
			_cursor(Input.MOUSE_MODE_HIDDEN)
		Layer.JOB_BOARD:
			_set_gameplay_ui(false)
			_set_town_hud(true)
			_cursor(Input.MOUSE_MODE_VISIBLE)
		Layer.CINEMATIC:
			_set_gameplay_ui(false)
			_set_town_hud(false)
			_cursor(Input.MOUSE_MODE_HIDDEN)
		Layer.GAMEPLAY, Layer.RESULTS:
			_set_gameplay_ui(true)
			_set_town_hud(false)
			_cursor(Input.MOUSE_MODE_HIDDEN)
		_:
			_set_gameplay_ui(false)
			_set_town_hud(false)
			_cursor(Input.MOUSE_MODE_HIDDEN)


## The whole gameplay UI stack -- HUD, job intro, results -- as one layer. The
## development F3 diagnostics HUD is a separate node the mowing scene already
## keeps hidden, and the trailer never turns it on.
func _set_gameplay_ui(shown: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ui := scene.get_node_or_null(^"Gameplay UI")
	if ui != null:
		# CanvasLayer is a Node, NOT a CanvasItem, so this cannot be typed as
		# one -- it has its own `visible`.
		ui.set(&"visible", shown)


func _set_town_hud(shown: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var town := scene.get_node_or_null(^"BusinessTown")
	if town == null:
		return
	var hud := town.get_node_or_null(^"BusinessHUD")
	if hud != null:
		hud.set(&"visible", shown)


## The cursor is owned by AppUI. Locking is the trailer-only path that stops a
## screen host's own `_ready()` from putting it back.
func _cursor(mode: int) -> void:
	AppUI.unlock_mouse_context()
	AppUI.lock_mouse_context(mode)


## Put a real cursor on a real control, so a click in the trailer looks aimed
## rather than teleported. A no-op on a headless DisplayServer, which is
## exactly right there.
func point_at(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	Input.warp_mouse(control.get_global_rect().get_center())
