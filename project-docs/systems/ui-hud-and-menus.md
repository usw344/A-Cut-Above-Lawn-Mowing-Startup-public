# HUD, Menus, and Interface Systems

Status: **Current.** The polished `res://UI/` package is integrated throughout
the application. Verified 2026-08-19 by the UI Smoke Test (54 assertions), the
Flow Test (54), and a 14-screen screenshot review at 1920×1080.

## Architectural rule

**UI displays state and emits intent. Domain systems own domain state.**

No component in `res://UI/` references a game scene, a job, or a manager. Each is
driven through its public API and reports back through signals. The integration
lives in exactly two host scripts:

- `Game/App/pause_layer.gd` (`ACAPauseLayer`) — **THE pause stack**, shared
- `Game/App/gameplay_ui.gd` (`ACAGameplayUI`, extends `ACAPauseLayer`) — the gameplay stack
- `Game/App/town_screen.gd` — instances `Pause Layer.tscn`
- `Game/App/main_menu_screen.gd` — the menu stack

Plus the persistent `AppUI` autoload for transitions and notifications.

## Shared theme — `UI/Theme/`

`ui_theme.gd` (`class_name UITheme`, a `RefCounted` with only constants and
static helpers) is the single source for palette, radii, type scale and timing.
`Game UI.theme.tres` is assigned to the root node of every component scene.

Helpers worth knowing: `stylebox()`, `style_button()`, `style_danger_button()`,
`style_progress()`, `format_money(1234) -> "$1,234"`,
`format_clock(522.0) -> "08:42"`, `percent_text(0.723) -> "72%"`.

No fonts are imported — everything uses the Godot default font. To swap in a real
font, set `default_font` on `Game UI.theme.tres`: one place, whole UI.

## Components and where they are used

| Component | Class | Used in | Driven by |
|---|---|---|---|
| `UI/Gameplay HUD/` | `GameplayHUD` | mowing scene | contract name/size/reward, live progress, fuel, clock, weather |
| `UI/Job Intro/` | `JobIntroScreen` | mowing scene | real contract + `JobManager.estimated_time_minutes()`; auto-dismisses after `intro_seconds` (2.4) |
| `UI/Job Complete/` | `JobCompleteScreen` | mowing scene | the `GameSession.job_settled` summary |
| `UI/Pause Menu/` | `PauseMenu` | mowing scene **and town** | Escape; `ACAPauseLayer` pauses the tree |
| `UI/Settings/` | `SettingsMenu` | mowing + town + main menu | `GameSettings` (incl. **Invert Look Y**) |
| `UI/Controls Help/` | `ControlsHelp` | mowing + town + main menu | `ACAControlBindings`, not the component defaults |
| `UI/Dialogs/` | `ConfirmationPrompt` | mowing + town | Restart / Abandon / Quit |
| `UI/Notifications/` | `NotificationCenter` | `AppUI` (global) | real domain events only |
| `UI/Transitions/` | `TransitionLayer` | `AppUI` (global) | `GameSession._swap_scene()` |
| `UI/Main Menu/` | `MainMenuScreen`, `RadialMainMenu` | main menu | option ids: `continue, new_game, load_game, options, credits, quit` |
| `UI/Credits/` | `CreditsScreen`, `ACACreditsLoader` | main menu | the `res://Credits/` folder |
| `UI/Load Game/` | `LoadGameScreen` | main menu | `SaveService.list_saves()` |
| `UI/Scenic Background for Menus/` | `MainMenuScenery` | main menu | 3D backdrop; **already composes `main_menu.tscn` inside its `MenuSafeOverlay`** |
| `UI/Demo/UI Demo.tscn` | — | not shipped | component showcase, tooling |
| `Main Area/ACA_JobSystem/job_system/ui/` | `ACAJobBoard`, `ACAJobCard` | town | `JobManager` |
| `Main Area/ACA_BusinessTown/UI/` | `ACABusinessHUD`, `ACABuildingPanel`, `ACAPlaceholderScreen` | town | `town_screen.gd` |

## Gameplay stack — `Game/App/Gameplay UI.tscn`

A CanvasLayer (layer 10) instanced into the mowing scene with
`gameplay_host = NodePath("..")`. Child order **matters**:

```
Gameplay HUD → Job Intro → Job Complete → Pause Menu → Settings → Controls Help → Confirmation Dialog
```

`_unhandled_input` reaches later siblings first, so the topmost modal consumes
Escape. `ACAPauseLayer._release_screen()` only returns control to gameplay when
nothing else in the stack is open — and always opens the incoming panel before
closing the outgoing one, or the screen resumes behind it.

`mower_fuel_fraction()` returns `MowerFuel.fraction()` — the authoritative
value, not a copy. The gauge captions itself **FUEL LOW** below 20% and **FUEL
CRITICAL** below 8%, and raises `low_fuel_entered` once per crossing.
`gameplay_ui.gd` turns that into one toast, plus one "Out of fuel" toast from
`MowerFuel.emptied`. Both are suppressed while the active mower is manual (the
Push Mower burns nothing) or while development Auto Refuel is on, and "Fuel low"
is suppressed if the tank is already empty. **Auto Refuel is never exposed here
— it lives on the F3 development HUD.**

The host must provide `mowing_progress()`, `mower_fuel_fraction()`,
`restart_current_job()`, `dev_toggle_debug_hud()`. `MVP.gd` implements all four.

`_on_job_settled()` **closes the entire pause stack and disables Escape-to-pause**
before showing results — without that the Pause Menu can draw on top of the
Job Complete screen (this was a real, screenshot-confirmed bug).

## Pause in the Town

`Town Screen.tscn` instances `Game/App/Pause Layer.tscn` as its **first** child.
`_unhandled_input` runs in reverse tree order, so `BusinessTown` sees Escape
first: it closes a building panel or clears a selection, and only an Escape it
does not consume reaches the pause menu.

The town disables RESTART outright and enables ABANDON only when a contract is
actually open. Resuming restores the town VISIBLE cursor, not a captured one —
that decision lives in `AppUI`, not in any menu button.

## Legacy MVP HUD

`Game/M.V.P/MVP_HUD.tscn` is **retained as a development diagnostics layer**:
hidden on load, toggled with **F3**. Mower swap, grid reset, speed slider, time
and weather controls all still work. Its weather buttons now write to
`WorldClock` rather than the scene.

## Notifications

`AppUI.notify_*`. Fired on real events only: contract accepted, new offer while
in town, payment received, low fuel, settings applied, contract abandoned.
The stack sits **top-right below the host's top-bar chips** — top-centre is where
the Job Board header and the town title bar live, and it overlapped there.

## Settings

The component supplies its own dropdown contents; the host supplies values.
See [application layer](../application-layer.md) for what each key actually does.
`ambience_volume` / `mower_volume` are stored but inert until those audio buses
exist. Settings persist to `settings.json` when APPLY is pressed.

**Invert Look Y** (GAMEPLAY section, under Mouse Sensitivity) is a `CheckButton`
with the unique name `%InvertYToggle`, key `invert_look_y`, default **off**.

## Repairs made to the transferred package

1. `UI/Scenic Background for Menus/**` — every internal reference pointed at
   `res://scenery/…`, `res://scenery_wind/…` and `res://Assets/Tree_*.gltf`,
   i.e. the root of the sandbox it came from. Assets were all present; only the
   prefixes were wrong.
2. `main_menu.gd` — `transparent_background` also set `Window.transparent_bg`,
   which disables SSS and depth of field. Split out as
   `request_transparent_window` (off by default).
3. `Notifications.tscn` — stack moved off top-centre.
4. `job_board.gd` `DEFAULT_CARD_SCENE` and the Job System test/tool scenes were
   missing the `Main Area/` path prefix.

## Credits — data driven, add a file

STATUS: **Current**, added 2026-08-19 (Milestone 6). Reached from the Main Menu
CREDITS option. Nothing about it depends on the mowing scene.

| | |
|---|---|
| Folder | **`res://Credits/`** — the whole data source |
| Convention | `<Name_Of_Thing>_licence.txt` → title `Name Of Thing` |
| Also accepted | `_license`, `_credit`, `_credits`; `.txt` and `.md` |
| Loader | `UI/Credits/credits_loader.gd` (`ACACreditsLoader`) |
| Screen | `UI/Credits/Credits.tscn` + `credits.gd` (`CreditsScreen`) |
| Host | `Game/App/main_menu_screen.gd`, node `Menu UI/Credits` |
| Test | `Dev tools/Validation/Credits Test.tscn` |

**Adding a credit is a file copy.** No code change, no list to update. The one
configured path is `ACACreditsLoader.CREDITS_DIRECTORY` at the top of the loader.

```
list_entries(directory = CREDITS_DIRECTORY) -> Array[Dictionary]  # {title,file,path}
is_credit_file(file_name) -> bool      title_from_filename(file_name) -> String
load_text(path) -> String              # verbatim, "" if unreadable
```

Sorted case-insensitively by title, then by file name, so the order is stable.
Entry text is read lazily, when an entry is selected.

Screen API: `open() / close() / is_open() / refresh() / entry_count() /
entry_titles() / selected_title() / select_index(i) / detail_text()`, signal
`back_requested()`. Left pane lists titles, right pane shows the text inside a
`ScrollContainer` with word wrap. Built from script, so it always matches
`UITheme`.

**Licence text is displayed VERBATIM.** Never summarise, reword or reformat it.

Export note: `.txt` is not a Godot resource, so `export_presets.cfg` carries
`include_filter="Credits/*.txt"`. A new credit file must match that filter or it
will not ship.

The old player-facing credits (two `Label.text` blocks and a CREDITS button
inside `Game/M.V.P/MVP_HUD.tscn`) were **migrated verbatim into `res://Credits/`
first, then removed**. `Credits Test` asserts both that they are gone and that
the attribution they carried is still reachable.

## KNOWN ISSUES
- The town's placeholder destinations (Supply Store, Mower Dealer, Business HQ,
  Future Lot) still open `ACAPlaceholderScreen`.

## Presentation APIs — for screenshots and the trailer, never for gameplay

Added 2026-08-19 (Milestone 10). These drive the **same code paths** a player's
input drives; there is no separate "trailer look" anywhere and there must not
be one.

| API | |
|---|---|
| `MainMenuScreen.preview_hover_option(option_id)` | Puts the menu into the visual state hovering that option produces — the node highlights and the centre hub shows its copy — and moves the keyboard selection there so the shot cannot show two items emphasised at once. Returns false for an unknown or disabled option. Suppresses the radial items' tooltips while active: each node already carries its name as a label beside it, so a pointer tooltip is a second copy of the same word sitting on top of the first. |
| `MainMenuScreen.clear_preview_hover()` | Undoes it, tooltips included. |
| `MainMenuScreen.option_screen_position(option_id)` | Where the option sits on screen, so a real cursor can be put on it. |
| `AppUI.set_notifications_suppressed(bool)` | DEVELOPMENT. While set, every `AppUI.notify_*` is dropped instead of queued, so a "Contract accepted" toast cannot land in the middle of a cinematic shot. It suppresses the trailer-irrelevant notifications by suppressing all of them for the length of the capture; no notification was deleted or weakened. Normal gameplay never sets it. |

Both are asserted by `Trailer Test`.

