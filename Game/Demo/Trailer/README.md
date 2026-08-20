# Trailer Capture — V3.1

DEVELOPMENT / MEDIA TOOLING. An automatic **~42 second** trailer that runs the
REAL game and stops on an end card.

**This is not the application main scene and must never be set as one.**

## Capture it

1. Open `res://Game/Demo/Trailer/Trailer Capture.tscn` in the editor.
2. Start recording in OBS.
3. Press **Play Scene** (F6).
4. It runs itself and then **holds on the end card**. Godot is never closed for
   you, so stop OBS whenever you like.

Nothing has to be driven, clicked or timed by hand.

| Key | (none are needed for a capture) |
|---|---|
| **R** | restart from the top |
| **SPACE** | pause / resume — freezes the whole tree, not just the camera |
| **ESC** | quit |

```
godot --path . "res://Game/Demo/Trailer/Trailer Capture.tscn"
```

| Flag | |
|---|---|
| `-- "--trailer-shots=<dir>"` | three review PNGs per beat, spread across each shot, plus a framing readout per frame |
| `-- "--trailer-quit"` | quit when the trailer ends, for an automated check |

---

## THE IDEA: A TRAILER IS A PRESENTATION, NOT A RECORDING

V2 tried to prove that every shot was ordinary gameplay. It was, and the footage
suffered for it. Composition had to be built around whatever the gameplay
controller would actually do, and because the rider is authored two units above
the lawn and falls into place, a shot that started the instant the mower was
repositioned could catch it dropping — or, at 1.4x speed, launching.

V3 keeps every piece of REAL GAME CONTENT and drops the requirement that it be
driven by NORMAL GAMEPLAY SIMULATION.

| | |
|---|---|
| **REAL** | the menu and its hover state, the Business Town, `ACAJobManager` generating and awarding a contract, the Job Board's own buttons, the transition and Job Intro screens, the canonical rider mower with its model, wheels, steering wheel and engine audio, the mowing GRID really losing the grass that disappears, the weather system, the real fuel system, the production HUD, and `GameSession.complete_current_job()` |
| **STAGED** | where the mower is and how fast it moves, which blades get cut and when, how far the storm is pushed, which UI layer is up, and where the camera is |

**`model.speed` is not written at all any more.** Shot speed belongs to the
mower adapter, so a capture cannot change gameplay tuning even by accident, and
`Trailer Test` asserts it by reading this folder's source.

---

## The presentation layer

```
Game/Demo/Trailer/
├── Trailer Capture.tscn        boot scene (shared runner_boot.gd shim)
├── trailer_director.gd         ACATrailerDirector  — the storyboard
├── README.md
└── Presentation/
    ├── cinematic_camera.gd        ACACinematicCamera
    ├── trailer_mower_adapter.gd   ACATrailerMowerAdapter
    ├── trailer_lawn_adapter.gd    ACATrailerLawnAdapter
    ├── trailer_weather_adapter.gd ACATrailerWeatherAdapter
    └── trailer_ui_director.gd     ACATrailerUIDirector
```

| | Owns |
|---|---|
| **TrailerDirector** | the beats, the deterministic world, what each shot is |
| **MowerAdapter** | the mower's transform for the length of a shot |
| **LawnAdapter** | which grass is cut, and when |
| **WeatherAdapter** | how much further than shipped the storm is pushed |
| **UIDirector** | exactly which UI layer is on screen |
| **CinematicCamera** | where the lens is and what it is looking at |

### THE MOWING SHOTS — what Milestone 13 changed

V3's mowing section was the weak part of the trailer: reviewed as a mower that
**bounced, flew above the grass and looked comical**. Three causes, all in the
presentation layer, none of them gameplay.

**1. The mower was not on the ground.** V3 let the mower's own physics settle
and planted it at the height it came to rest at. That height is wrong twice
over. Every blade of grass is a real `StaticBody3D` about three units tall, so a
mower dropped on an uncut lawn lands on the GRASS; and `Mowing Area` is a
`PlaneMesh` at its body's origin wrapped in a 50 x 1 x 50 `BoxShape3D`, so the
collision surface stands **half a unit proud of the dirt you can see** even
where the grass is gone. `_measure_ground_y()` measures both parts instead — the
visible plane from the grid's own node, and `ACATrailerMowerAdapter.visual_lift()`
for how far the mower's origin sits above its lowest visible point.

**2. The shots were too fast to be close.** V3 ran the mowing beats at 38–55 u/s
so a DISTANT camera would have something crossing its frame. The cost was the
whole section: at that speed no lens can be near the machine, so the mower was
four percent of the frame and what motion you could see read as scurrying. The
shots now run 13–24 u/s — SLOWER than gameplay's 30 — and the cameras are close.

**3. The suspension was tuned for a distant chase.** The default bob and roll
are gentler, and `set_suspension()` lets a shot with a MOUNTED lens damp them
almost flat: at that range a bob is camera shake.

The section is now three shots instead of five, and each of them frames the
**boundary between cut and uncut lawn** — a mower in the middle of an untouched
field is a mower standing in a field, whatever the lens is doing.

### TrailerMowerAdapter — the important one

It takes the REAL rider over: `set_physics_process(false)` on the controller, so
gravity, `move_and_slide` and the input actions are out of the picture, and the
transform is written here instead. The mower's own visual script still runs, and
the adapter feeds it `send_speed_data` / `send_rotation_data`, so wheels and the
steering wheel animate exactly as in gameplay. `MowerFuel.consume()` is still
called, so the gauge in the HUD shot is a tank that is genuinely being burnt.

**Ground height is measured, not raycast and not settled.** See the Milestone 13
note above: a downward ray hits grass, and the settled height is on top of both
the grass and half a unit of invisible collision box. The director measures the
visible plane and the mower's own visual lift and hands the sum to `bind()`.

A small bob and a roll proportional to yaw rate are added ON TOP of that height,
never instead of it, so the mower cannot end up under the lawn. How much of each
is per shot — `set_suspension()` — because a lens bolted to the machine turns
every millimetre of bob into camera shake.

### TrailerLawnAdapter — the mowing has to READ

Two problems, one answer. The adapter owns the mower's transform, so there are
no slide collisions and the grid would never be told anything was cut; and a
Large Lawn is 36,864 blades, so forty seconds of footage cannot cut a visible
fraction of it by driving.

Both are solved through the grid's **own** api. `Custom_Gridmap.mow_swath()` runs
exactly the bookkeeping a collision would — the same `mow_item_silent`, the same
MultiMesh rebuild, the same counter, the same `mowing_progress_changed`. The
grass that disappears is really gone and the HUD percentage is true. What is
staged is only WHICH blades and WHEN.

Each beat also cuts a trail BEHIND the mower before the shot starts: a mower
that has only just been placed has nothing behind it, and "cut stripe streaming
away" is the whole point of the tracking shots.

### TrailerWeatherAdapter — the storm

`ACAWeatherVisualAdapter.set_presentation_override()` takes one extra layer in
the same `scale` / `set` shape as the shipped weather layers, composed last.
The trailer installs a blue-grey storm through it and clears it afterwards.

The colours have to be `set`, not `scale`: scaling a Color multiplies every
channel by the same factor, so it can only make a tint DARKER, never bluer. The
shipped Rain layer already scales those keys as far as scaling can take them
(R-020) and the result is still a dim warm sky.

It also turns the rain emitters up and widens the near-rain column, because rain
vanishes on compressed video, and puts every value back on `clear()`.

### CinematicCamera

`static`, `follow`, `orbit` and `rail` (a Curve3D dolly track), with a separate
`look_rail` so a move can ARRIVE at something rather than pivot around it,
per-shot `fov` → `fov_to`, easing, `look_lead` for negative space, a `min_ground`
floor, and camera-local depth of field through `CameraAttributesPractical` — on
the CAMERA, so no gameplay camera and no saved setting is touched.

**Damping is a distance, not a feeling.** A follow camera lags its nominal offset
by roughly `speed / damp` world units. On the fast beats that was quietly adding
fifteen to twenty-five units to the working distance and shrinking the mower to
a speck. Pick the framing distance first, then set `damp` to at least `speed / 6`.

---

## The storyboard

`at` is seconds of **visible footage**. Hidden pre-roll does not count.

| Time | Len | Beat | |
|---|---|---|---|
| 00:00 | 4.0 | main menu | the REAL menu, **NEW GAME hovered**, a real cursor on it, the scenery's own slow camera drift |
| 00:04 | 5.0 | town | a street-level dolly WEST down the main street, ending on a push to the **JOBS** shopfront |
| 00:09 | 2.8 | job board | three real generated contracts; the cursor lands on the one it takes |
| 00:11.8 | 2.2 | accept | the board's **own ACCEPT and BEGIN JOB buttons**, then the real Job Intro |
| 00:14 | 5.0 | mower over the top | **the hero shot.** The lens in the driving seat, wheel in frame, looking forward over the bonnet down the boundary between cut and uncut |
| 00:19 | 4.0 | mower low pass | low on the finished lawn, ahead and to the cut side, the machine coming on towards the lens at 21 u/s |
| 00:23 | 3.6 | mower close | front three-quarter close, wheels and bodywork, subtle DOF, drifting through at 13 u/s |
| 00:26.6 | 5.0 | weather hero | blue-grey storm, visible cloud deck, rain crossing frame |
| 00:31.6 | 3.4 | gameplay proof | the real production HUD over a two-thirds-finished lawn |
| 00:35 | 3.4 | completion | the lawn finished behind a cover, then the real Job Complete screen |
| 00:38.4 | 3.4 | end card | fade to black FIRST, then the title |
| 00:41.8 | | hold | |

The storm is the beat that clears itself: it is followed directly by the
gameplay proof, which is therefore the beat that puts the weather back to Clear
behind its cover.

Shot lengths run from 2.2 to 5.0 seconds on purpose — a trailer where every shot
is four seconds is a slideshow, and `Trailer Test` asserts the variation.

Change `BEATS` in `trailer_director.gd` to re-cut it.

---

## Presentation is explicit

Every beat that changes state does the same thing:

```
UI dismissed -> screen COVERED -> state changed ->
hidden PRE-ROLL to settle -> reveal
```

`_hold_clock()` stops the storyboard clock during that hidden setup, so the
visible running time is all footage. `GameSession` reveals the instant a scene
swap finishes, which would expose an unprepared shot; the director hooks
`screen_changed` and snaps the cover back before that reveal renders a frame.

**The mower does not move until the shot is on screen.** Every beat places it
during the prep and calls `drive_*` immediately after `AppUI.reveal()`. Starting
it before the reveal cost twenty to forty units of travel at these speeds, so
every shot opened somewhere other than where it was composed.

`ACATrailerUIDirector` names the layer each beat wants and clears every other,
and toasts are suppressed for the whole capture through
`AppUI.set_notifications_suppressed()` — a development flag. No notification was
removed or weakened to make the trailer work.

---

## Things this world does to a camera

- **The lawn sits in a bowl ringed by trees twenty-odd units tall,** so from
  ground level the sky only starts about sixteen degrees up. Sky and a
  ground-level subject compete for the same frame: aim high enough for half a
  frame of sky and the mower falls out of the bottom. The storm shot's
  compromise — treeline about a third of the way down, mower in the lower third
  — is deliberate.
- **The grass is three units tall,** so a lens below about two films a wall of
  blades. The low shots work because the lawn adapter cuts the camera's own lane
  for it first — narrow, and overlapping its neighbours. A comb of lanes with
  uncut ridges between them puts a line of grass across the mower's wheels.
- **The mowing shots all drive +X** (`MOWING_YAW`), so the mower's LOCAL +x is
  world −Z. A camera given a positive local `offset.x` sits on the −Z side of
  the lane, which is the side the staged cut is laid on. Getting that sign wrong
  is what has put the lens nose-deep in uncut grass in the first cut of every
  low shot ever composed in this file.
- **The town is a MINIATURE.** Its buildings are two world units wide and four
  or five tall. Every camera height that sounds reasonable is above the
  rooftops, and it is a floating island in the procedural sky's flat grey ground
  colour, so anything high or distant frames that void. The town shot stays at
  1.9 units on the road with a long lens.
- **Distances are in world units and this world is big.** Camera offsets that
  look sane next to a two-metre character put the lens inside the bodywork here;
  that is what `SCALE` is for.

## Reviewing it

`--trailer-shots=<dir>` writes three PNGs per beat, spread across **that beat's
own length** so the end of a long dolly is not missed, and never while the
screen is covered. Each one logs where the mower actually landed:

```
[TRAILER]   09-mower-close-c.png  mower 0.62,0.52  w 0.40 h 0.43
```

x/y are fractions of the viewport (0.5,0.5 is dead centre) and w/h are the
mower's visual bounds as a fraction of the frame. It measures the VISUAL AABB,
not the node origin — the rider's origin sits below and behind the machine, so a
close shot that frames the bodywork beautifully reports its origin off-screen.

That readout is what makes framing tractable: an offset is in the mower's local
frame, the aim is somewhere else again, and the damping adds a speed-dependent
lag, so guessing from screenshots alone takes a pass per shot.

## Known limitations

- The town has no rain particles, so the weather hero shot is in the mowing
  scene rather than the town.
- No music. The trailer is captured silent-but-for-game-audio and scored later.
- The lawn is taken to 84% rather than 100% before the completion beat: the
  mowing grid fires its own completion at 1.0 and would settle the contract
  before the trailer pressed the button itself.
