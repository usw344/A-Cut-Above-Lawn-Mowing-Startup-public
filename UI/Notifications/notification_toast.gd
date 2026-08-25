extends PanelContainer
class_name NotificationToast

# ============================================================
# PUBLIC API
# ============================================================
#
# You normally do NOT talk to this script. It is one row inside
# res://UI/Notifications/Notifications.tscn, which spawns, positions and
# frees toasts for you. Use NotificationCenter.push_notification() instead.
#
# Called by notifications.gd:
#
#   setup(title: String, message: String, accent: Color)
#   start_life(seconds: float)  # begin the on-screen countdown
#   fade_in(duration: float)
#   fade_out(duration: float)   # frees itself when the fade completes
#
# Signals emitted:
#
#   expired                     # the countdown finished
#   faded_out                   # emitted just before queue_free()
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# This script preloads nothing.
#
# Notification Toast.tscn references exactly one external resource:
#
#   res://UI/Theme/Game UI.theme.tres   (root node theme property)
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# Copy this file together with notifications.gd, Notifications.tscn and
# Notification Toast.tscn - they are one component and the parent scene
# preloads the toast scene by path.
#
# ============================================================


signal expired()
signal faded_out()

@onready var _accent: ColorRect = %AccentBar
@onready var _title: Label = %Title
@onready var _message: Label = %Message


func setup(title: String, message: String, accent: Color) -> void:
	# A TOAST IS PAPER TOO. It is drawn over the world beside the mowing HUD's
	# cream cards, and a charcoal box next to them was the last thing on that
	# screen still speaking the old language. The accent stripe keeps whatever
	# colour it was given: it is the part that says which KIND of message this
	# is, and it is the only colour on the toast.
	add_theme_stylebox_override("panel", UITheme.hud_panel(UITheme.RADIUS_CARD, 0.0, 0.0))
	_title.add_theme_color_override("font_color", UITheme.PAPER_INK)
	_message.add_theme_color_override("font_color", UITheme.PAPER_INK_DIM)
	_title.text = title
	_message.text = message
	_message.visible = not message.is_empty()
	_accent.color = accent


## The countdown lives on the toast as a child Timer, so it dies with the
## toast. A SceneTreeTimer holding a reference to a freed toast would
## fire into nothing and log an error.
func start_life(seconds: float) -> void:
	var timer := Timer.new()
	timer.name = "Life"
	timer.one_shot = true
	timer.wait_time = maxf(seconds, 0.05)
	add_child(timer)
	timer.timeout.connect(_on_life_timeout)
	timer.start()


func _on_life_timeout() -> void:
	expired.emit()


func fade_in(duration: float) -> void:
	modulate.a = 0.0
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, duration)


func fade_out(duration: float) -> void:
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, duration)
	t.tween_callback(func() -> void:
		faded_out.emit()
		queue_free())
