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

	_build_ui_sound()

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


## THE FOUR TOASTS EACH HAVE THEIR OWN CUE, so a payment, a warning and an
## ordinary note are told apart without reading them. The sound is played HERE
## rather than by the caller, which is what keeps the pairing consistent: there
## is no way to raise a toast and forget its sound, or to play the wrong one.
func notify_info(title: String, message: String = "") -> void:
	if _notifications_suppressed:
		return
	_notifications.info(title, message)
	play_sound(ACAUISound.NOTIFY)


func notify_success(title: String, message: String = "") -> void:
	if _notifications_suppressed:
		return
	_notifications.success(title, message)
	play_sound(ACAUISound.CONFIRM)


func notify_warning(title: String, message: String = "") -> void:
	if _notifications_suppressed:
		return
	_notifications.warning(title, message)
	play_sound(ACAUISound.ERROR)


func notify_money(title: String, message: String = "") -> void:
	if _notifications_suppressed:
		return
	_notifications.money(title, message)
	play_sound(ACAUISound.MONEY)


func clear_notifications() -> void:
	_notifications.clear_all()


# ================================================================== ui sound
## ---------------------------------------------------------------------------
## THE INTERFACE'S OWN VOICE
## ---------------------------------------------------------------------------
## `AppUI` owns this for the same reason it owns the toasts and the cursor: it
## is the one node that is always alive, always above every screen, and already
## the place a screen asks for something that is not its own business. There is
## no new autoload, and no screen starts a sound of its own.
##
## WHAT THE CUES ARE is `ACAUISound`. What is here is only the POOL and the two
## rules that keep it honest:
##
##   A FIXED SET OF PLAYERS, created once. Nothing is instantiated per press, so
##   a screen that fires a hundred cues costs a hundred `play()` calls and no
##   allocation at all.
##   A VOICE LIMIT. Past `ACAUISound.VOICES` overlapping sounds the oldest is
##   taken, so a burst of notifications cannot pile up an unbounded chorus.
##
## Sounds are PROCESS_MODE_ALWAYS, so the pause menu and the Super Debugger both
## click.

var _sound_players: Array[AudioStreamPlayer] = []
var _sound_next := 0
var _sound_last := {}
var _sound_previous_clip := {}
var _sound_rng := RandomNumberGenerator.new()


func _build_ui_sound() -> void:
	_sound_rng.randomize()
	for i in ACAUISound.VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "UI Sound %d" % i
		player.bus = ACAAudioMix.UI
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_sound_players.append(player)


## Play a named cue. Unknown cues, a missing clip and a headless run are all
## silently nothing: UI sound is never allowed to be the reason a screen fails.
func play_sound(cue: StringName) -> void:
	if _sound_players.is_empty() or not ACAUISound.has_cue(cue):
		return
	var now := Time.get_ticks_msec() / 1000.0
	# THE REPEAT GUARD. Without it, a cursor dragged along a row of buttons
	# fires the hover cue every frame.
	var last: float = float(_sound_last.get(cue, -999.0))
	if now - last < ACAUISound.guard_seconds(cue):
		return
	_sound_last[cue] = now

	var index := _pick_clip(cue)
	if index < 0:
		return
	var stream := load(ACAUISound.clip_path(cue, index)) as AudioStream
	if stream == null:
		return
	var player: AudioStreamPlayer = _sound_players[_sound_next]
	_sound_next = (_sound_next + 1) % _sound_players.size()
	player.stream = stream
	player.volume_db = ACAUISound.level_db(cue)
	player.pitch_scale = ACAUISound.pitch_for(cue, _sound_rng)
	player.play()


## Never the same clip twice running, where a cue has more than one. Repeating
## is what makes a set of variations sound like a single sample.
func _pick_clip(cue: StringName) -> int:
	var paths: Array = ACAUISound.clips(cue)
	if paths.is_empty():
		return -1
	var index := 0
	if paths.size() > 1:
		var previous: int = int(_sound_previous_clip.get(cue, -1))
		index = _sound_rng.randi() % paths.size()
		if index == previous:
			index = (index + 1) % paths.size()
		_sound_previous_clip[cue] = index
	return index


## Attach the standard press and hover cues to a button. Called by
## `UITheme.style_button()` and friends, so every button in the project gets
## them without any screen asking - and a screen that wants a different cue
## simply calls this again with one.
func attach_button_sound(button: Button, press_cue: StringName) -> void:
	if button == null:
		return
	# A BOUND CALLABLE IS NOT THE SAME CALLABLE, so `is_connected(play_sound)`
	# would answer false every time and a button styled twice would click twice.
	# A mark on the node is the honest test of "has this already been done".
	if button.has_meta(&"aca_ui_sound"):
		return
	button.set_meta(&"aca_ui_sound", true)
	button.pressed.connect(play_sound.bind(press_cue))
	button.mouse_entered.connect(play_sound.bind(ACAUISound.HOVER))


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
