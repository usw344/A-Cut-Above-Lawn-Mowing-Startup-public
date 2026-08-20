# Notifications

## Purpose
Small, queued toast messages that never block gameplay: job accepted, fuel
low, payment received, new contracts available.

## Main Scene
`res://UI/Notifications/Notifications.tscn` (root: `Control`, full rect)

## Main Script
`notifications.gd` (`class_name NotificationCenter`)
plus `notification_toast.gd` / `Notification Toast.tscn` for one row.

## Public API
```gdscript
push_notification(title: String, message: String = "",
                  type: NotificationType = NotificationType.INFO)

info(title, message = "")      success(title, message = "")
warning(title, message = "")   error(title, message = "")
money(title, message = "")

clear_all()
pending_count() -> int
```
`NotificationType` is `INFO`, `SUCCESS`, `WARNING`, `ERROR`, `MONEY` - the
type only picks the accent colour of the stripe.

## Signals
```gdscript
notification_shown(title: String)
queue_emptied()
```

## Hard-Coded Dependencies
```gdscript
const TOAST_SCENE := preload("res://UI/Notifications/Notification Toast.tscn")
```
Same folder, so copying the folder keeps it valid. Plus the shared theme on
both roots.

## Expected Host Data
Nothing. The host calls `push_notification()` when a game event happens.

## Copying / Integration Notes
- Copy **all four files** together - they are one component.
- Add it high in the host HUD so toasts draw over the gameplay HUD.
- Root `mouse_filter` is IGNORE; toasts are not clickable and never block
  input.
- Toasts stack downward from the top centre. Move the `Stack` node anchors
  in `Notifications.tscn` to reposition them.
- Exported knobs: `max_visible` (3), `display_seconds` (3.2), `stack_gap`,
  `enter_slide`.

## Known Limitations
- Positions are tweened by the script rather than by a container, which is
  what makes the stack slide up smoothly when one expires. If you reparent
  toasts into a `VBoxContainer`, that animation goes away.
- Toast width is authored at 380 px (`TOAST_WIDTH` in the builder). The text
  labels have their wrap width pinned to match; if you widen the stack, widen
  those too or the height calculation goes wrong.
- No click-to-dismiss and no icons.
