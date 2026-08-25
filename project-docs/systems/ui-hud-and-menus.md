# HUD, Menus, and Interface Systems

Status: **Current.** The polished `res://UI/` package is integrated throughout
the application, and was re-styled onto one visual identity on 2026-08-24.
Verified by the UI Smoke Test (60 assertions), the Flow Test (54), and a
21-screen screenshot review at 1920×1080.

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

## The visual identity

**Modern rustic with cozy illustrated accents** — roughly three parts grounded
structure to one part personality. Warm, inviting, readable, rural, low-poly.

The palette is five colours and their weights:

| | |
|---|---|
| warm cream | every piece of text, and the surface of anything that reads as PAPER |
| charcoal green | every panel drawn over the world |
| forest green | the primary action, and progress |
| muted sage | secondary information and rules |
| mower orange | ONE accent, used sparingly, for the thing that most wants the eye |

**Charcoal with a green cast, never blue-grey.** Over a green world a blue-grey
panel reads as a foreign object laid on top of the game rather than as part of
it, and that one change is most of why the interface now looks like it belongs.

### Two surface families, and they are not interchangeable

| Family | Constants | Used for |
|---|---|---|
| SLATE | `PANEL_BG` / `CARD_BG` / `CHIP_BG` with `INK` | everything drawn over the world: the HUD, the minimap, pause, settings, notifications |
| PAPER | `PAPER_BG` / `PAPER_BG2` with `PAPER_INK` | anything whose fiction is a printed document: the job board's work orders, the difficulty cards |

`INK` on a paper surface is unreadable and is meant to be. The Job System keeps
its own copy of the paper constants in `job_ui_style.gd`, because that folder is
deliberately portable and loads nothing from outside itself.

### Accessibility — requirements, not preferences

- `INK` on `PANEL_BG` and `PAPER_INK` on `PAPER_BG` both clear 4.5:1.
  `INK_ON_ACCENT` on `ACCENT` is about 5.2:1, so a primary button's label passes
  for BODY text rather than only for headings.
- `INK_FAINT` is for decoration, never for information.
- **Nothing is communicated by colour alone.** The fuel gauge changes its
  CAPTION as well as its colour; a selected difficulty card is raised, ruled and
  captioned; an offer running out of time changes its wording; the workshop says
  a purchase "leaves a thin reserve" as well as colouring it.
- Focus is a two-pixel `ACCENT_BRIGHT` ring present on every interactive style.
- `FONT_MICRO` is the floor and it is **12**, up from 11.
- Animation is restrained: `FADE` is a fifth of a second.

## Shared theme — `UI/Theme/`

`ui_theme.gd` (`class_name UITheme`, a `RefCounted` with only constants and
static helpers) is the single source for palette, radii, type scale and timing.
`Game UI.theme.tres` is assigned to the root node of every component scene.

Helpers worth knowing: `stylebox()`, `style_button()`, `style_accent_button()`,
`style_danger_button()`, `style_progress()`, `paper_panel()`, `status_colour()`,
`format_money(1234) -> "$1,234"`, `format_clock(522.0) -> "08:42"`,
`percent_text(0.723) -> "72%"`.

!!! note "How the re-palette was applied"
    The component scenes are generated from GDScript, so nearly every `Color()`
    literal baked into them was either a `UITheme` constant or a
    `lightened()` / `darkened()` variant of one. The re-style was therefore a
    mechanical old-to-new substitution over 476 literals across 17 files, with
    anything the map could not account for REPORTED rather than left silent —
    so a colour somebody had typed by hand showed up as work to do instead of
    as a seam.

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
| `UI/Minimap/` | `MinimapPanel` | mowing scene | the authoritative property state — see below |
| `UI/New Game/` | `NewGameScreen` | main menu | the `ACADifficulty` profile table, as plain dictionaries |
| `UI/Scenic Background for Menus/property_menu/` | `ACAMenuPropertyScenery` | main menu | a REAL generated property — see below; **composes `main_menu.tscn` inside its `MenuSafeOverlay`** |
| `UI/Scenic Background for Menus/scenery/` | `MainMenuScenery` | retired from the menu | the previous hand-built backdrop, kept and still loadable |
| `UI/Demo/UI Demo.tscn` | — | not shipped | component showcase, tooling |
| `Main Area/ACA_JobSystem/job_system/ui/` | `ACAJobBoard`, `ACAJobCard` | town | `JobManager` |
| `Main Area/ACA_BusinessTown/UI/` | `ACABusinessHUD`, `ACABuildingPanel`, `ACAPlaceholderScreen` | town | `town_screen.gd` |

## Two surface families, and which screens get which

The theme has always had two surfaces. What changed is the rule for choosing
between them.

| | |
|---|---|
| **PAPER** — warm cream, `PAPER_INK` on it | the game's own documents and the operator's own instruments: the mowing HUD, the minimap, the job board's offers, the contract introduction, the results sheet, the notification toasts, the three town service counters, the difficulty cards |
| **SLATE** — charcoal green, `INK` on it | system chrome: the main menu, pause, settings, controls, load game, and the board those paper offers are pinned to |

The old rule was "paper for documents, slate for anything drawn over the world",
and it produced a correct, legible and completely forgettable mowing interface:
a dark grey box on a green field. What the game wants over the lawn is the thing
the operator would really have with them, which is the job sheet - and a job
sheet is paper.

So paper comes outside, at the alpha and the edge treatment a panel needs when
there is a moving world behind it:

| | |
|---|---|
| `HUD_BG` / `HUD_BG2` | cream, a few percent open so the lawn is felt through it |
| `HUD_EDGE` | a warm brown-green rule. Over a bright lawn a sixteen-percent black line disappears |
| `HUD_SHADOW` | what actually separates the card from the world. A soft dark band under the panel does more for legibility than another ten percent of opacity, and costs the view nothing |
| `HUD_GREEN` / `HUD_GREEN_BRIGHT` | progress and header green, a touch deeper than `ACCENT` so it holds against cream |
| `PAPER_TRACK` | the empty part of a bar drawn on paper. `TRACK_BG` is nearly black and reads as a hole punched in the card |

Helpers: `hud_panel()`, `hud_chip()`, `style_paper_progress()`.

### Repainting a slate screen as paper

`UITheme.repaint_to_paper(root)` walks a subtree and swaps one family for the
other by name. It is a small, total mapping — `INK` to `PAPER_INK`, `INK_DIM` to
`PAPER_INK_DIM`, `INK_FAINT` and `SAGE` to `PAPER_INK_FAINT`, `ACCENT` /
`ACCENT_BRIGHT` / `MONEY` to `HUD_GREEN`, `HAIRLINE` to `PAPER_RULE` — so what it
does can be predicted by reading it rather than by running it.

`WARN`, `URGENT` and `ORANGE` are left alone: all three were chosen to carry a
warning and all three still carry it on cream. So are **buttons**: a button is a
control rather than a surface, it already has its own fill, and restyling them
flattened every secondary button into the primary green.

It exists because several screens were laid out correctly on the old family and
only their colours were wrong. Rebuilding each scene to change its colours would
be a great deal of risk for a repaint.

## Drawn marks — `UI/Theme/ui_glyph.gd`

Nine small marks: a leaf, a sun, a cloud, rain, a fuel drop, a folded map, mown
stripes, a stone and a ripple. They are polygons drawn in a unit square and
scaled, not an icon font and not a folder of PNGs — six accents at twelve to
twenty pixels did not justify a new dependency, a new licence and a resolution
to argue about. They take their colour from whatever sets them.

**Nothing is ever communicated by a mark alone.** The weather glyph follows the
weather WORD; the fuel drop changes colour with a caption that also changes.

## The mowing HUD

`UI/Gameplay HUD/`. The layout is built in code; the scene is a bare `Control`
carrying the script and the shared theme.

That is a deliberate reversal. The scene held about forty nodes and a dozen
inline `StyleBoxFlat` sub-resources, each a copy of a colour that also lives in
`UITheme`, and restyling it meant editing colour literals in a text file no
reviewer could read. The layout is now one function readable top to bottom and
every colour comes from the theme by name. The public API is unchanged.

The four corners, and the middle left empty:

| | |
|---|---|
| top left | the contract. Site, property type and lawn size, the one objective with a percentage and a bar, and a three-line checklist |
| top centre | day, clock and weather, in one pill |
| top right | fuel — the only thing on this HUD allowed to shout, and the only place orange appears |
| bottom left | the minimap. Placed by the host, styled to match |
| bottom right | the pause hint, and nothing else |

### The checklist is fed from the property, not from the contract

`ACAGameplayUI._refresh_site_readout()` reads the lawn's own mowable total and
whatever the feature set actually built:

```
Cut all grass                 18,220 / 20,736 m²
Mow around the pond and rocks              6
Contract                                 $215
```

A card that read those off the job would eventually promise a pond the property
does not have.

### What it deliberately does not do

Pointed at a reference image, it takes the warmth, the checklist, the edge
anchoring and the illustrated accents. It does not take the scattered decorative
flowers, the second decorative frame around every panel, the legend card
explaining the game to a player who is already playing it, or any ornament that
carries no information.

### Read-backs

`job_name_text()`, `reward_text()`, `game_time_text()`, `weather_text()`,
`progress()`, `fuel()`.

These exist because `Flow Test` used to reach into the scene for `%JobName` and
read its `.text`. When the layout moved into code those unique names went with
the scene that held them, eight checks silently stopped running, and the suite
still reported zero failures. The component answers by name now.

## The minimap — `UI/Minimap/`

`MinimapPanel` is presentation-only like every other component: the host hands it
everything, and **every one of those things is the object the game is already
using**.

| Drawn | Comes from |
|---|---|
| the playable rectangle | `ACAPropertyBoundary.rect()` |
| the contract | `ACALawn.lawn_centre()` / `lawn_half_extent()` |
| what has been cut | `ACALawn.cut_mask()` — the very texture the grass shader samples |
| the pond | `ACAPondFeature.shoreline_points()` — the outline its collision ring was traced from |
| solid obstacles | `ACALawnObstacles.obstacles()` — the list the exclusion queries read |
| the machine | the mower's own transform |

A minimap that kept its own idea of where the pond was would eventually be wrong,
and a minimap that is wrong is worse than none.

Three implementation notes worth keeping:

- **Three drawing layers, not one.** The cut mask needs a shader
  (`minimap_cut.gdshader`) because an uncut mowable cell is `(0,0,0,1)` and
  drawing it as an ordinary modulated texture paints the lawn solid black. The
  red channel becomes the alpha of one flat colour instead. A material belongs to
  a whole `CanvasItem`, so base / cut / overlay are separate `Control`s.
- **North is up and the map does not rotate.** A plan the player can build a
  mental model of beats one that is always correct and never the same twice.
- **The marker is interpolated.** The machine's transform jitters at 576 Hz.
- **It is drawn on the same paper as the rest of the HUD**, in five named
  colours that are a legend whether one is drawn or not: `PAGE_COLOUR` for the
  ground beyond the fence, `PLAYABLE_COLOUR` inside the boundary,
  `UNCUT_COLOUR` for the contract standing, `CUT_COLOUR` over it from the lawn's
  own mask, and `EDGE_COLOUR` for the one line the machine cannot cross. It used
  to be a dark slate panel, which was right against the old HUD and was the last
  charcoal box in the corner of a cream interface.
- **A compass mark.** A plan that does not rotate has to say which way is up, or
  the player has to work it out from the fence.

!!! warning "Children are ready before their parent"
    `Gameplay UI` is a child of the mowing scene, so its `_ready()` runs BEFORE
    the scene has generated a property. The first version of the binding asked
    for the property at that moment, got null, and hid the map permanently — no
    error anywhere, a green test suite, and an empty corner in the screenshot.
    The map now binds on the first frame the property is actually there.

## The scenic main menu — `UI/Scenic Background for Menus/property_menu/`

The menu background is a **real generated property**: the same terrain, lawn,
grass shader, wood, fence, pond and Sky3D integration the player is about to
drive around in. It is built from one seed, mown before the first frame with the
rider's real deck (so the stripes are the stripes), and the canonical Rider is
parked on it.

The backdrop it replaces was hand-built — its own trees, its own grass, its own
ground plane, its own painted mountains — and had been left behind by the mowing
world: different tree species, different turf, a dirt path the game does not
have, a palette the game does not use. A player arriving at the menu and then at
a contract was looking at two different games.

Nothing about it is a special case. If the grass changes, the menu changes.

It stays subordinate to the controls: the camera drifts slowly on three
incommensurate rates and never cuts, `menu_safe_overlay` sits between the world
and the buttons, and there is no audio of any kind.

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

