# A Cut Above — UI Component Sandbox

Self-contained, transplantable UI components for *A Cut Above: Mow & Grow*.
Built in this disposable sandbox so they can be copied into the production
project by hand, one folder at a time.

**Run it:** the project's main scene is `res://UI/Demo/UI Demo.tscn`.
Press **F1** (or the HIDE button) to collapse the demo control panel and see
the components on a clean screen.

---

## Component index

| Component | Scene | Purpose |
|---|---|---|
| Shared Theme | `Theme/Game UI.theme.tres` | Palette, type scale, control styling |
| Gameplay HUD | `Gameplay HUD/Gameplay HUD.tscn` | Job, progress, fuel, time, weather |
| Job Complete | `Job Complete/Job Complete.tscn` | End-of-job results and payout |
| Pause Menu | `Pause Menu/Pause Menu.tscn` | Pause interface |
| Notifications | `Notifications/Notifications.tscn` | Queued toast messages |
| Transitions | `Transitions/Transition.tscn` | Fullscreen fades |
| Job Intro | `Job Intro/Job Intro.tscn` | Contract intro / loading mask |
| Settings | `Settings/Settings.tscn` | Settings presentation |
| Controls Help | `Controls Help/Controls Help.tscn` | Player control reference |
| Dialogs | `Dialogs/Confirmation Dialog.tscn` | Reusable confirmations |
| Demo | `Demo/UI Demo.tscn` | Showcase — **do not copy** |

Each folder has its own README with the public API, signals and integration
notes. The script headers are the primary documentation; the READMEs are the
short version.

---

## Dependencies between components

Deliberately almost none. The full dependency graph is:

```
Every component  ->  UI/Theme/Game UI.theme.tres   (root node `theme` property)
Notifications    ->  Notifications/Notification Toast.tscn   (preload)
Demo             ->  all nine component scenes     (instanced in the scene)
```

That is the complete list. In particular:

- The **Pause Menu does not know about Settings or the Confirmation Dialog.**
  It emits `settings_requested` / `abandon_job_requested` and the host decides.
- The **Settings menu does not know about Controls Help.** It emits
  `controls_requested`.
- **Job Complete does not change scene.** It emits `return_to_town_requested`.
- **Transition does not know what comes next.** It emits `screen_covered` and
  waits for the host to call `fade_from_black()`.

No autoloads. No singletons. No `ProjectSettings`, `DisplayServer`,
`AudioServer` or `InputMap` access anywhere in the components. Nothing
references a town scene, job scene, `model`, `GameManager`, `JobManager` or
`PlayerManager`.

---

## Integration philosophy

These are **presentation adapters**, not game systems:

```
Host game  --(supplies data via setters)-->  Component
Host game  <--(emits user intent)---------  Component
```

The host owns every decision. A component never completes a job, pays the
player, changes scene or pauses the tree.

**Conventions used throughout:**

- All 0–1 parameters are `0.0 -> 1.0`, never `0 -> 100`. Values are clamped.
- Money is passed as whole `int` currency units and formatted by the UI
  (`240` renders as `$240`, `12500` as `$12,500`).
- Durations are passed as raw seconds; the UI formats them (`522.0` -> `08:42`).
- Modal screens set `process_mode = ALWAYS`, so they keep working when the
  host pauses the tree. They never set `get_tree().paused` themselves.
- Full-screen components are `Control`s with full-rect anchors. Drop them
  under any `CanvasLayer` or `Control` in the host HUD.
- The one exception is `Transition.tscn`, whose root is a `CanvasLayer`
  (layer 128) so it always draws over everything.

---

## Shared theme

`res://UI/Theme/ui_theme.gd` holds the palette, corner radii, type scale and
animation timings as constants, plus small static helpers
(`format_money`, `format_clock`, `percent_text`, `stylebox`, `style_button`).

`res://UI/Theme/Game UI.theme.tres` is generated from those constants and is
assigned to the `theme` property of every component's root node. **It is the
single shared file every component depends on.** If you copy a component
without it, the component still lays out correctly — it just falls back to
Godot's default look.

The palette was matched by eye to the existing screens in this project:

- `res://ACA_JobSystem/job_system/ui/job_ui_style.gd` (Job Board)
- `res://ACA_BusinessTown/UI/` (Town HUD)

The colour values are intentionally identical to that file's, so the new UI
sits beside the Job Board without a seam. No fonts are imported; to swap in a
real font later, set `default_font` on `Game UI.theme.tres` — one place.

---

## Copying a component into the production project

1. Copy `res://UI/Theme/` once (both files).
2. Copy the component's folder.
3. Open its script and read the header — it lists the public API, the signals,
   every external path it references, and what it assumes about the host.
4. Fix the theme path if you put the theme somewhere else. It appears as an
   `ext_resource` in the `.tscn` and in the script header.
5. Connect the signals. `UI/Demo/ui_demo.gd::_wire_components()` is a working
   example of every connection.

Suggested order — least entangled first: **Transitions → Notifications →
Dialogs → Controls Help → Gameplay HUD → Job Complete → Job Intro →
Pause Menu → Settings.**

---

## `_tools/` — dev only, safe to delete

The component scenes are generated from GDScript so layout lives in
reviewable code (the same approach this project already uses for
`ACA_BusinessTown/UI` and `ACA_JobSystem/job_system/ui`).

| File | What it does |
|---|---|
| `Build UI.tscn` | Regenerates the theme and all 11 scenes |
| `Flow Test.tscn` | Headless smoke test of the whole flow — prints `FLOW TEST OK` |
| `Shot.tscn` | Screenshots every screen at 1920×1080, 1600×900, 1280×720 |

```bash
godot --headless --path . "res://UI/_tools/Build UI.tscn"
```

Nothing under a component folder loads anything from `_tools/`. The generated
`.tscn` files are ordinary self-contained scenes — edit them in the editor if
you prefer, but re-running the builder overwrites them.

---

## Sandbox changes outside `res://UI/`

Two lines in `project.godot`, so the demo runs:

- `run/main_scene` now points at `UI/Demo/UI Demo.tscn`
  (was `ACA_BusinessTown/BusinessTown.tscn` — change it back when you want
  the town scene).
- `window/size/viewport_width` / `viewport_height` set to 1920×1080.

Nothing else in the project was modified. The reference scenes under
`ACA_BusinessTown/` and `ACA_JobSystem/` were read but never touched.
