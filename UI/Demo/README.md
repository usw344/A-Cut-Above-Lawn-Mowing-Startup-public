# UI Demo - showcase only

## Purpose
Exercises every component without the real mowing game, and doubles as the
integration example. **Do not copy this folder into the production project.**

## Main Scene
`res://UI/Demo/UI Demo.tscn` - the main scene of the project.

## Main Script
`ui_demo.gd` (`class_name UIDemo`)

## What to read
`_wire_components()` is the whole integration guide: every connection there is
a connection the host game will need to make. `_on_restart_requested()`,
`_on_abandon_requested()` and `_on_quit_requested()` show the confirmation
pattern; `_begin_job()` and `_on_return_to_town()` show the transition
contract.

## Using it
Press **F1** or the HIDE button to collapse the demo control panel - do that
before taking screenshots or recording footage.

The panel drives:
- job name (including a deliberately long one), size, reward, bonus, weather
- progress, fuel, game time and elapsed-time sliders
- set-progress-to-100%, complete job, low fuel, refuel
- one button per notification type, plus a 6-at-once burst to show the queue
- pause menu, transition, controls help, settings, confirmation dialog
- window size: 1920x1080, 1600x900, 1280x720

Flow: **BEGIN TEST JOB** -> Job Intro -> fade -> HUD -> pause/resume ->
progress to 100% -> COMPLETE JOB -> Job Complete -> RETURN TO TOWN -> fade
back to the fake town.

## Fake scenery
Placeholder only: a gradient sky, flat building silhouettes, and a lawn whose
mowed stripes follow the progress slider. No 3D, no mowing simulation.

## Notable difference from a real host
The demo does **not** set `get_tree().paused` when the pause menu opens,
because pausing the tree would freeze the demo controls too. A real host
should - see the comment in `_on_pause_opened()`.

The demo is also the only place that touches `DisplayServer` (the window-size
buttons). No component ever does.
