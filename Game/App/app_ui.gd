extends Node
## Persistent application UI layer. Autoloaded as `AppUI`.
##
## Holds the two UI components that must outlive a scene change:
##   * the fullscreen Transition, which has to stay up *while* the scene swaps
##   * the Notification centre, so a toast is not cut off by a transition
##
## Everything else (HUD, pause, results) is gameplay-scoped and lives in the
## scene that owns it.
##
## This is presentation plumbing only. It makes no decisions: GameSession asks
## for a covered screen, does the swap, and asks for it back.

## Emitted when the screen is fully covered and it is safe to swap content.
signal screen_covered()

const TRANSITION_SCENE := preload("res://UI/Transitions/Transition.tscn")
const NOTIFICATIONS_SCENE := preload("res://UI/Notifications/Notifications.tscn")

var _transition: TransitionLayer
var _notifications: NotificationCenter


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Toasts sit under the transition so a fade covers them too.
	var toast_layer := CanvasLayer.new()
	toast_layer.name = "Notification Layer"
	toast_layer.layer = 120
	add_child(toast_layer)

	_notifications = NOTIFICATIONS_SCENE.instantiate()
	toast_layer.add_child(_notifications)

	_transition = TRANSITION_SCENE.instantiate()
	add_child(_transition)
	_transition.screen_covered.connect(func() -> void: screen_covered.emit())


# ================================================================ transitions

func transition() -> TransitionLayer:
	return _transition


## Cover the screen. `screen_covered` fires when the swap is safe.
func cover(duration: float = -1.0) -> void:
	_transition.fade_to_black(duration)


func reveal(duration: float = -1.0) -> void:
	_transition.fade_from_black(duration)


func is_covered() -> bool:
	return _transition.is_covered()


func set_transition_title(title: String, subtitle: String = "") -> void:
	_transition.set_title(title, subtitle)


func clear_transition_title() -> void:
	_transition.clear_title()


# ============================================================== notifications

func notifications() -> NotificationCenter:
	return _notifications


## DEVELOPMENT / MEDIA TOOLING. While set, every notify_* below is dropped
## instead of queued. The Trailer Capture director turns it on so a "Contract
## accepted" or "Fuel low" toast cannot land in the middle of a cinematic shot.
##
## It suppresses the TRAILER-IRRELEVANT ones by suppressing all of them for the
## length of the capture; it does not delete or weaken any normal notification,
## and normal gameplay never sets it.
var _notifications_suppressed: bool = false


func set_notifications_suppressed(suppressed: bool) -> void:
	_notifications_suppressed = suppressed
	if suppressed:
		_notifications.clear_all()


func notifications_suppressed() -> bool:
	return _notifications_suppressed


func notify_info(title: String, message: String = "") -> void:
	if _notifications_suppressed:
		return
	_notifications.info(title, message)


func notify_success(title: String, message: String = "") -> void:
	if _notifications_suppressed:
		return
	_notifications.success(title, message)


func notify_warning(title: String, message: String = "") -> void:
	if _notifications_suppressed:
		return
	_notifications.warning(title, message)


func notify_money(title: String, message: String = "") -> void:
	if _notifications_suppressed:
		return
	_notifications.money(title, message)


func clear_notifications() -> void:
	_notifications.clear_all()


# ============================================================= mouse ownership
##
## THE one place in the project that writes Input.mouse_mode.
##
## Two things decide the cursor:
##
##   CONTEXT - what the current screen wants when nothing modal is up. The
##             mowing scene wants CAPTURED; the town and the menus want VISIBLE.
##             Screens declare it in _ready() through set_mouse_context().
##
##   HOLDS   - a modal that needs a usable cursor takes a named hold while it is
##             open. While any hold is outstanding the cursor is VISIBLE no
##             matter what the context is.
##
## Nothing else may assign Input.mouse_mode. Pause, results screens and dev
## tooling all go through hold_mouse() / release_mouse(), which is what keeps a
## menu from fighting a mower controller's _ready() capture.

## Hold tokens used by the project. Any StringName works; these are the ones
## that exist so they can be released defensively.
const MOUSE_HOLD_PAUSE := &"pause"
const MOUSE_HOLD_RESULTS := &"results"

var _mouse_context: int = Input.MOUSE_MODE_VISIBLE
var _mouse_holds: Dictionary = {}
## Set by the trailer capture tooling so nothing can steal the cursor mid-shot.
var _mouse_context_locked: bool = false


## Declare what this screen wants the cursor to do. Called from a screen host's
## or a player controller's _ready(). Ignored while the context is locked.
func set_mouse_context(mode: int) -> void:
	if _mouse_context_locked:
		return
	_mouse_context = mode
	_apply_mouse_mode()


func mouse_context() -> int:
	return _mouse_context


## Pin the context so set_mouse_context() cannot change it. Development/media
## tooling only (the Trailer Capture scene); normal gameplay never locks.
func lock_mouse_context(mode: int) -> void:
	_mouse_context_locked = false
	set_mouse_context(mode)
	_mouse_context_locked = true


func unlock_mouse_context() -> void:
	_mouse_context_locked = false


## Read-only. Exists so a test can prove the trailer released the lock it took.
func mouse_context_locked() -> bool:
	return _mouse_context_locked


## Take a hold: the cursor becomes visible until every hold is released.
func hold_mouse(token: StringName) -> void:
	_mouse_holds[token] = true
	_apply_mouse_mode()


func release_mouse(token: StringName) -> void:
	_mouse_holds.erase(token)
	_apply_mouse_mode()


func is_mouse_held() -> bool:
	return not _mouse_holds.is_empty()


## Called by GameSession when a scene swap starts. Holds belong to the screen
## that took them, and that screen is about to stop existing.
func clear_mouse_holds() -> void:
	_mouse_holds.clear()
	_apply_mouse_mode()


## The ENTER binding documented in Controls Help. Only meaningful in a context
## that captures the cursor, and deliberately inert while a modal holds it -
## otherwise confirming a menu button with Enter would grab the mouse.
func toggle_mouse_capture() -> void:
	if is_mouse_held() or _mouse_context_locked:
		return
	if _mouse_context == Input.MOUSE_MODE_CAPTURED:
		_mouse_context = Input.MOUSE_MODE_VISIBLE
	else:
		_mouse_context = Input.MOUSE_MODE_CAPTURED
	_apply_mouse_mode()


## The mode that would be applied right now. Useful for assertions.
func effective_mouse_mode() -> int:
	return Input.MOUSE_MODE_VISIBLE if is_mouse_held() else _mouse_context


func _apply_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = effective_mouse_mode()
