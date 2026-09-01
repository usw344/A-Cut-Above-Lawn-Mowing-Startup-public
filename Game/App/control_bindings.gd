class_name ACAControlBindings
extends RefCounted
## The project's REAL bindings, in the row format the Controls Help component
## wants: "KEY|Description", or a bare string for a section heading.
##
## One place, so the menu, the town pause menu and the gameplay pause menu can
## never drift apart. The component ships its own demo defaults; nothing in this
## project should use those.

const MOWING: PackedStringArray = [
	"MOWING",
	"W / S|Drive forward / reverse",
	"MOUSE|Steer and look (while the cursor is captured)",
	"ENTER|Capture / release the mouse cursor",
	"P|Lock the camera pitch (steering only)",
	"C|Precision view - closer to the deck, for tight work",
	"GENERAL",
	"ESC|Pause",
	"F5 / F9|Quick save / quick load",
	"1 / 2 / 3 / 4|Time of day: morning / day / evening / night",
	"7 / 8 / 9|Weather: clear / foggy / rain",
	"DEVELOPMENT",
	"H|Toggle the Super Debugger (day / weather / contracts / money)",
	"F10|Complete the contract instantly",
]

const TOWN: PackedStringArray = [
	"TOWN",
	"MOUSE|Hover and click a building",
	"ESC|Close a panel, then pause",
	"GENERAL",
	"F5 / F9|Quick save / quick load",
	"DEVELOPMENT",
	"H|Toggle the Super Debugger (day / weather / contracts / money)",
	"MOWING",
	"W / S|Drive forward / reverse",
	"MOUSE|Steer and look (while the cursor is captured)",
	"ENTER|Capture / release the mouse cursor",
	"ESC|Pause",
]

const MENU: PackedStringArray = [
	"MENU",
	"MOUSE|Select an option",
	"UP / DOWN|Move between options",
	"ENTER|Confirm",
	"MOWING",
	"W / S|Drive forward / reverse",
	"MOUSE|Steer and look (while the cursor is captured)",
	"ENTER|Capture / release the mouse cursor",
	"ESC|Pause",
	"F5 / F9|Quick save / quick load",
]
