# HUD, Menus, and Interface Systems

Status: Mixed current playable and partially integrated interfaces

## Current MVP HUD

Primary files:

- `Game/M.V.P/MVP_HUD.tscn`
- `Game/M.V.P/mvp_hud.gd`

The HUD is instantiated under a CanvasLayer in `Minimum Viable Game.tscn`.

### Current controls

- Version label.
- Mower-selection popup.
- FPS, static-memory, and CPU timing display.
- Time-of-day slider.
- Mower-speed slider.
- Reset Map and Location button.
- Day, Evening, and Night buttons.
- Clear, Foggy, and Rain buttons.
- Controls/help label.
- Credits button and license panels.

The authored version label is `Version 0.2`.

### Signals to the MVP

The HUD declares and emits:

- `tod_slider_value_changed(value)`
- `ms_slider_value_changed(value)`
- `mower_change_selected(mower_id)`
- `reset_map_and_location`
- `tod_day_requested`
- `tod_evening_requested`
- `tod_night_requested`
- `weather_clear_requested`
- `weather_foggy_requested`
- `weather_rain_requested`

All ten are connected in `Minimum Viable Game.tscn`.

### Direct model access

The HUD reads `model.get_speed()` in `_ready()` so the speed slider begins at the shared current speed.

The MVP handles changes and writes the selected speed back to the model.

### Development behavior

The performance label updates every physics frame using Godot `Performance` monitors.

Keyboard shortcuts:

- `/` toggles mouse capture.
- H toggles HUD visibility.

The HUD is functional but is still a development/MVP interface rather than the complete intended production HUD.

## Main-menu prototype

Primary files:

- `UI/Main Screen/Menu Hierarchy.tscn`
- `UI/Main Screen/Menu Hierarchy.gd`
- `UI/Main Screen/Main Menu/Main Menu.tscn`
- `UI/Main Screen/Main Menu/main_menu.gd`

`Menu Hierarchy.tscn` provides a background and instances the main-menu component.

The main menu presents:

- New Game.
- Load Game.
- Option.
- A version label.

Button methods emit `new_game`, `load_game`, and `options`. The hierarchy has an intended `handle_button_press(action)` method, but the custom signals are not connected in the authored scene and all action branches are empty.

This menu is a partially integrated system, not the application entry point.

## New-game prototype

Primary files:

- `UI/Main Screen/New Game Menu/New Game.tscn`
- `UI/Main Screen/New Game Menu/New Game.gd`

The scene contains:

- Background.
- Text-entry panel.
- Game-name entry.
- Go button.

The script validates that the name is non-empty, creates or opens `user://saves`, and calls `model.get_game_profile_object()`.

The model method is empty, and the script does not serialize a profile or load gameplay.

## Information Bar

Primary files:

- `Main Area/Information Bar/Information Bar.tscn`
- `Main Area/Information Bar/Information Bar.gd`

It defines:

- Time button.
- Weather button.
- Money button.
- Settings button.

Every process frame it requests time, weather, and money strings from the model. Those model methods currently return empty strings.

The script has a `setup_signals()` helper for all buttons, but `_ready()` does not call it. Only the Settings button is connected in the scene.

The information bar is not instantiated by the active MVP.

## Main Area

`Main Area/Main Area.gd` describes an abstraction between interface signals and a future 3D business/storefront scene.

`Main Area/Main Area.tscn` currently contains only a `Node3D` and does not attach the adjacent script.

It is partially integrated scaffolding.

## Mowing Information UI

Primary files:

- `Mowing Section/UI/Information UI.tscn`
- `Mowing Section/UI/Information UI.gd`

It provides:

- Fuel progress.
- Cuttings progress.
- Time-left progress.
- Management prompt.
- Contextual open prompt.

Fuel reads `model.get_mower_fuel()`. Cuttings calls `model.get_cuttings()`, which is not part of the current model API. The script also stores an optional `Job_Data_Container`.

The scene is not part of the current MVP.

## Job Offer Display

The job display is documented with the job system because its lifecycle is owned by `Job_Manager`.

Interface behavior includes:

- Current offer details.
- Pay, size, and completion time.
- Acceptance timeout progress.
- Left/right offer browsing.
- Decline.
- Accept.
- Close.
- Empty-offer state.

Decline, left, right, and close are connected. Accept is not connected to an implementation.

## Full-HUD direction

The repository contains foundations for a fuller interface:

- Current MVP controls and diagnostics.
- Fuel/cuttings/time status UI.
- Global information bar.
- Job-offer display.
- Main menu and profile entry.

These should be treated as partially integrated systems. A future interface integration pass needs to decide:

- Which controls remain development-only.
- Production HUD scene ownership.
- Pause/menu navigation.
- Money, fuel, storage, time, and job presentation.
- Input remapping and controller/mobile support.
- How interface state survives scene changes.
