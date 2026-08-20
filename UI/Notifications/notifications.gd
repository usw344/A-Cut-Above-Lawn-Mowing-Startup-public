extends Control
class_name NotificationCenter

# ============================================================
# PUBLIC API
# ============================================================
#
# Host project should call:
#
#   push_notification(
#       title: String,
#       message: String = "",
#       type: NotificationType = NotificationType.INFO)
#
# Convenience wrappers (same thing, shorter at the call site):
#
#   info(title, message = "")
#   success(title, message = "")
#   warning(title, message = "")
#   error(title, message = "")
#   money(title, message = "")
#
#   clear_all()                 # drop everything on screen and queued
#   pending_count() -> int      # queued but not yet shown
#
# Types:
#
#   NotificationType.INFO       neutral grey-green
#   NotificationType.SUCCESS    accent green
#   NotificationType.WARNING    amber
#   NotificationType.ERROR      red
#   NotificationType.MONEY      bright green
#
# Signals emitted:
#
#   notification_shown(title: String)
#   queue_emptied()             # last toast finished, nothing pending
#
# Example:
#
#   toasts.push_notification("Job accepted", "A Residence",
#       NotificationCenter.NotificationType.SUCCESS)
#   toasts.money("Contract complete", "+$240")
#   toasts.warning("Fuel low", "18% remaining")
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================

const TOAST_SCENE := preload(
	"res://UI/Notifications/Notification Toast.tscn"
)

# If this path changes after copying the component into another project,
# update it HERE. It is the only preload in the component, and the toast
# scene lives in the same folder, so copying the folder keeps it valid.
#
# Notifications.tscn also references:
#
#   res://UI/Theme/Game UI.theme.tres   (root node theme property)
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# Presentation only. The centre does not decide when anything happens; the
# host calls push_notification() when a game event occurs.
#
# The root is a full-rect Control with mouse_filter IGNORE - toasts never
# block gameplay input, and they are not clickable.
#
# PLACEMENT: add it high in the host HUD so toasts draw over the gameplay
# HUD but under modal screens. Toasts stack downward from the top centre
# of the screen; change `stack_width` / the Stack node anchors in
# Notifications.tscn to move them.
#
# QUEUE: at most `max_visible` toasts are on screen at once. Extra calls
# queue up and appear as earlier ones expire, so a burst of events cannot
# cover the screen. Positions are tweened by this script rather than by a
# container, so the stack slides up smoothly when one expires.
#
# ============================================================


enum NotificationType { INFO, SUCCESS, WARNING, ERROR, MONEY }

signal notification_shown(title: String)
signal queue_emptied()

## Toasts visible at once. Further pushes wait their turn.
@export var max_visible: int = 3
## Seconds a toast stays on screen before it fades out.
@export var display_seconds: float = 3.2
## Vertical gap between stacked toasts, in pixels.
@export var stack_gap: float = 8.0
## Pixels a toast rises through as it fades in.
@export var enter_slide: float = 12.0

@onready var _stack: Control = %Stack

var _active: Array[NotificationToast] = []
var _queue: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.resized.connect(_relayout)


# ================================================================== pushing

func push_notification(title: String, message: String = "",
		type: NotificationType = NotificationType.INFO) -> void:
	_queue.append({"title": title, "message": message, "type": type})
	_drain()


func info(title: String, message: String = "") -> void:
	push_notification(title, message, NotificationType.INFO)


func success(title: String, message: String = "") -> void:
	push_notification(title, message, NotificationType.SUCCESS)


func warning(title: String, message: String = "") -> void:
	push_notification(title, message, NotificationType.WARNING)


func error(title: String, message: String = "") -> void:
	push_notification(title, message, NotificationType.ERROR)


func money(title: String, message: String = "") -> void:
	push_notification(title, message, NotificationType.MONEY)


func clear_all() -> void:
	_queue.clear()
	for toast in _active:
		if is_instance_valid(toast):
			toast.queue_free()
	_active.clear()


func pending_count() -> int:
	return _queue.size()


## The accent colour used for each type. Change it here to restyle.
static func type_colour(type: NotificationType) -> Color:
	match type:
		NotificationType.SUCCESS:
			return UITheme.ACCENT
		NotificationType.WARNING:
			return UITheme.WARN
		NotificationType.ERROR:
			return UITheme.URGENT
		NotificationType.MONEY:
			return UITheme.MONEY
		_:
			return UITheme.INK_FAINT


# ================================================================ internals

func _drain() -> void:
	while _queue.size() > 0 and _active.size() < max_visible:
		_spawn(_queue.pop_front())


func _spawn(data: Dictionary) -> void:
	var toast: NotificationToast = TOAST_SCENE.instantiate()
	_stack.add_child(toast)
	toast.setup(data["title"], data["message"], type_colour(data["type"]))

	# Width comes from the stack; height from the toast content.
	toast.size = Vector2(_stack.size.x, toast.get_combined_minimum_size().y)
	toast.position = Vector2(0.0, _next_y() + enter_slide)
	_active.append(toast)

	toast.fade_in(UITheme.FADE)
	_relayout()

	# The toast owns its countdown, so clearing the queue cannot leave a
	# timer pointing at a freed node.
	toast.expired.connect(_expire.bind(toast))
	toast.start_life(display_seconds)

	notification_shown.emit(data["title"])


func _expire(toast: NotificationToast) -> void:
	if not is_instance_valid(toast):
		return
	toast.faded_out.connect(_on_toast_gone.bind(toast))
	toast.fade_out(UITheme.FADE)


func _on_toast_gone(toast: NotificationToast) -> void:
	_active.erase(toast)
	_relayout()
	_drain()
	if _active.is_empty() and _queue.is_empty():
		queue_emptied.emit()


## Where the next toast starts, measured from the top of the stack.
func _next_y() -> float:
	var y := 0.0
	for toast in _active:
		if is_instance_valid(toast):
			y += toast.size.y + stack_gap
	return y


func _relayout() -> void:
	var y := 0.0
	for toast in _active:
		if not is_instance_valid(toast):
			continue
		toast.size.x = _stack.size.x
		var t := toast.create_tween()
		t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(toast, "position", Vector2(0.0, y), UITheme.FADE_FAST)
		y += toast.size.y + stack_gap
