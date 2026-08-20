# Dialogs - Confirmation

## Purpose
One reusable confirmation modal for destructive actions: abandon job, restart
job, quit to menu.

## Main Scene
`res://UI/Dialogs/Confirmation Dialog.tscn` (root: `Control`, full rect)

## Main Script
`confirmation_dialog.gd` (`class_name ConfirmationPrompt`)

> The class is **not** called `ConfirmationDialog` - that name is taken by a
> built-in Godot class.

## Public API
```gdscript
show_confirmation(
    title: String,
    message: String,
    confirm_text: String = "CONFIRM",
    cancel_text: String = "CANCEL",
    danger: bool = true)

hide_dialog()      # closes WITHOUT emitting either signal
is_open() -> bool
```
`danger` styles the confirm button as destructive (muted red). Pass `false`
for neutral confirmations and it becomes the normal green primary action.

## Signals
```gdscript
confirmed
cancelled
```
Exactly one fires per showing, and the dialog closes itself before emitting.
Cancelling includes Escape and clicking the dimmed backdrop.

## Hard-Coded Dependencies
`res://UI/Theme/Game UI.theme.tres` on the root node. Nothing else.

## Expected Host Data
A title and a message. The host decides what confirming means.

## Copying / Integration Notes
Because the signals are generic, do not wire them once and forget. Either
connect per use with `CONNECT_ONE_SHOT`, or hold the pending action - which
is what the demo does, and is the more robust pattern:
```gdscript
var _pending_confirm: Callable = Callable()

func _ready() -> void:
    dialog.confirmed.connect(_on_dialog_confirmed)
    dialog.cancelled.connect(func() -> void: _pending_confirm = Callable())

func _ask(title, message, confirm_text, on_confirm: Callable) -> void:
    _pending_confirm = on_confirm
    dialog.show_confirmation(title, message, confirm_text, "CANCEL")

func _on_dialog_confirmed() -> void:
    var action := _pending_confirm
    _pending_confirm = Callable()
    if action.is_valid():
        action.call()
```
One instance can serve every confirmation in the game. Put it above the pause
menu in the host HUD so the dialog reads as being on top.

Keyboard: Escape cancels, Enter confirms; the confirm button takes focus on
open. `process_mode = ALWAYS`.

## Known Limitations
- Not a window manager: no stacking, no queue, no result codes. Showing it
  again while open just re-populates it.
- Two buttons only.
- Fixed 460 px card width.
