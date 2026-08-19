# A Cut Above — Job System (portable subsystem)

A self-contained Job Market / Job Management system for **A Cut Above: Mow & Grow**
(Godot 4.6, GDScript).

Everything the system needs is inside this one folder. It has **no autoloads, no
project settings, no theme files and no references to anything outside
`res://ACA_JobSystem/`** — copy the folder into another Godot project and it works.

```
ACA_JobSystem/
├── job_system/              PRODUCTION - the shipping subsystem
│   ├── data/                job.gd (Resource), job_enums.gd, game_time.gd
│   ├── config/              job_balance.gd, job_catalog.gd   <- all tunables
│   ├── generation/          job_generator.gd                 <- seeded, versioned
│   ├── market/              job_market.gd                    <- demand model
│   ├── time/                job_time_provider.gd             <- world-time boundary
│   ├── manager/             job_manager.gd                   <- THE owner of all job state
│   ├── ui/                  JobBoard.tscn + JobCard.tscn + scripts + style
│   └── debug/               debug_time_provider.gd           <- test clock only
├── demo/                    STANDALONE demo + debug controls (dev only)
├── tests/                   headless assertion suite (dev only)
├── tools/                   scene builder for the UI scenes (dev only)
├── docs/JOB_SYSTEM.md       architecture notes
└── README.md
```

`demo/`, `tests/` and `tools/` are development-only. Nothing under `job_system/`
loads anything from them; they can be deleted from a shipping build.

## Try it without integrating anything

Run `res://ACA_JobSystem/demo/JobSystemDemo.tscn`:

```bash
godot --path <project> res://ACA_JobSystem/demo/JobSystemDemo.tscn
```

Debug controls for Season / Economy / Climate, game-time jumps (+30m, +1h, +4h,
+1d) and speed (pause / x1 / x10 / x60), plus force-offer, progress and
completion buttons. The board itself is the real, shipping UI.

Run the test suite (110 assertions, exits non-zero on failure):

```bash
godot --headless --path <project> res://ACA_JobSystem/tests/JobSystemTests.tscn
```

---

# Integrating Into A Cut Above

### 1. Which folder to copy

Copy the whole `ACA_JobSystem/` folder into the destination project so it sits at
`res://ACA_JobSystem/`. Keep the folder name and location: two literal paths
(`job_board.gd → DEFAULT_CARD_SCENE`, `job_system_demo.gd → BOARD_SCENE`) assume
it. If you must rename it, update those two constants — everything else resolves
through scene references and global class names.

Nothing else needs copying, and no project settings change.

### 2. Which node to instantiate

One `ACAJobManager` — a plain `Node` running `job_system/manager/job_manager.gd`.
Either add it as a child of your town/game root, or register it as an autoload
(`JobManager`) if the market must keep running while the player is elsewhere.
A single instance owns `available_jobs`, `current_jobs` and `past_jobs`; do not
create a second one.

```gdscript
var jobs := ACAJobManager.new()
jobs.name = "JobManager"
add_child(jobs)
jobs.set_time_provider(my_world_clock_provider)   # see step 5
```

### 3. Which UI scene to add

`res://ACA_JobSystem/job_system/ui/JobBoard.tscn` — a `Control`, not a
CanvasLayer, so it drops straight into the existing HUD.

Add it as a **new child of `BusinessHUD/Root`, placed last** (later siblings draw
on top). It is already anchored full-rect with `offset_top = 58`, which leaves the
Town's top information bar visible and uncovered, and its dim layer is partial
alpha so the live 3D town keeps rendering behind it.

Then, in `business_hud.gd`:

```gdscript
@export var job_board: ACAJobBoard

func open_jobs(manager: ACAJobManager) -> void:
    if job_board != null:
        job_board.set_manager(manager)
        job_board.open()

func is_modal_open() -> bool:
    return is_placeholder_open() or (job_board != null and job_board.is_open())
```

### 4. Connecting the Jobs building

`business_town.gd` emits `business_action_requested` with the raw `building_id`,
so the Jobs building sends **`&"job_office"`** (not `&"jobs"`). Its
`_on_open_requested()` currently also calls `hud.open_placeholder(...)` — drop
that call for `job_office`, or the "Coming Soon" screen will cover the board.

```gdscript
town.business_action_requested.connect(func(action: StringName) -> void:
    if action == &"job_office":
        hud.open_jobs(job_manager))
```

### 5. Supplying authoritative world time

The Job System never reads a clock directly. Subclass the boundary in
`job_system/time/job_time_provider.gd` and hand it over once:

```gdscript
class_name ACAWorldClockProvider
extends ACAJobTimeProvider

var _clock: MyGameClock

func _init(clock: MyGameClock) -> void:
    _clock = clock

func game_minutes() -> float:          # absolute, monotonic, in game minutes
    return _clock.total_minutes

func season() -> ACAJobEnums.Season:
    return _clock.season                # SPRING / SUMMER / AUTUMN / WINTER

func format_timestamp(minutes: float) -> String:
    return _clock.stamp(minutes)        # e.g. "Spring Day 12  09:15"
```

```gdscript
job_manager.set_time_provider(ACAWorldClockProvider.new(world_clock))
```

Clock jumps (fast-forward, sleeping, loading) are fine: the manager compares
absolute times instead of accumulating deltas. Call `job_manager.evaluate_now()`
right after a big jump if you want the market to catch up in the same frame.

Economy and climate are set separately, because those systems do not exist yet:

```gdscript
job_manager.set_economy(ACAJobEnums.Economy.NORMAL)
job_manager.set_climate(ACAJobEnums.Climate.NORMAL)
```

### 6. Town modal behaviour on open/close

The board exposes `opened` and `closed`. The **host** decides what to switch off;
the board never reaches into the town:

```gdscript
hud.job_board.opened.connect(func() -> void: town.set_interaction_enabled(false))
hud.job_board.closed.connect(func() -> void: town.set_interaction_enabled(true))
```

The Town already has the two layers this needs:
- `ACABusinessTown._unhandled_input()` early-returns while a modal is open — extend
  that check to `hud.is_modal_open()` from step 3.
- The board is a full-rect `Control` with `mouse_filter = STOP`, so clicks are
  consumed before they reach building picking.

The camera rig is fixed (no pan/zoom/orbit), so it needs no blocking.

### 7. Where `begin_new_job()` lives

`res://ACA_JobSystem/job_system/manager/job_manager.gd`, line 298:

```gdscript
func begin_new_job(job_id: StringName) -> bool
```

It validates the current job, marks it `IN_PROGRESS` and emits
`begin_job_requested(job)`. **It does not change scenes, load the mowing scene,
build a grass grid, choose a mower or touch physics.** That is deliberate.

### 8. Connecting `begin_job_requested`

```gdscript
job_manager.begin_job_requested.connect(_on_begin_job_requested)

func _on_begin_job_requested(job: ACAJob) -> void:
    hud.job_board.close()
    _load_mowing_scene(job.grid_size, job.lawn_size, job.id)   # your code
```

`job.grid_size` is the real mowing grid (96×96 / 144×144 / 192×192); `job.seed`
and `job.generator_version` reproduce the contract deterministically.

The main project runs 3D physics on a separate thread. The Job System does none —
no `_physics_process`, no physics access, no threads. Keep the boundary on the
host side: if your handler touches physics-controlled state, use
`call_deferred()` / main-thread patterns there, not inside the Job System.

### 9. Reporting job progress

From gameplay, as often or as rarely as you like (0.0 – 1.0):

```gdscript
job_manager.update_job_progress(job_id, mowed_cells / float(total_cells))
```

The manager never inspects the mowing grid itself. A job with progress above 0
and below 1 makes the Current tab read **RETURN TO JOB** instead of **BEGIN JOB**.

Estimated Time is a placeholder until the mower system exists. Replace it without
touching the manager:

```gdscript
job_manager.estimated_time_provider = func(job: ACAJob) -> float:
    return mower.estimate_minutes(job.grid_size)
```

### 10. Completing a job

```gdscript
job_manager.complete_job(job_id)
```

Sets `COMPLETED`, progress 100 %, moves the job from Current to Past and emits
`job_completed(job)`. It deliberately does **not** pay money, change trust,
calculate bonuses or save — connect `job_completed` and do that in your own
systems.

---

## Public API at a glance

`ACAJobManager` (`job_system/manager/job_manager.gd`)

| Method | Purpose |
|---|---|
| `set_time_provider(p)` | world-time boundary (line 104) |
| `set_economy(e)` / `set_climate(c)` | demand inputs |
| `available_jobs()` / `current_jobs()` / `past_jobs()` | read-only copies |
| `accept_job(id)` | Available → Current (line 262) |
| `begin_new_job(id)` | gameplay handoff (line 298) |
| `update_job_progress(id, 0..1)` | external progress (line 312) |
| `complete_job(id)` | Current → Past (line 327) |
| `market_strength()` / `max_available_jobs()` | 0–5 demand and capacity |
| `evaluate_now()` | force a market evaluation |

Signals: `available_jobs_changed`, `current_jobs_changed`, `past_jobs_changed`,
`job_generated`, `job_expired`, `job_accepted`, `job_completed`,
`job_accept_failed(job_id, reason)`, `market_strength_changed(strength)`,
`begin_job_requested(job)`.

`ACAJobBoard` (`job_system/ui/job_board.gd`): `set_manager(m)`, `open(tab = -1)`,
`close()`, `toggle()`, `is_open()`, `show_tab(tab)`, signals `opened` / `closed`.

## Tuning

All balancing lives in `job_system/config/`:
`job_balance.gd` (lawn grids, pay, offer lifetime, arrival intervals,
`MAX_CURRENT_JOBS`, placeholder mow rate) and `job_catalog.gd` (site names and
per-property-type size pools).

## Regenerating the UI scenes

`JobBoard.tscn` and `JobCard.tscn` are generated from `tools/build_job_ui.gd`
(the same convention the Town project uses for its HUD). After editing the
layout code:

```bash
godot --headless --path <project> res://ACA_JobSystem/tools/BuildJobUI.tscn
```

You can also just edit the `.tscn` files by hand in the editor — the builder is a
convenience, not a dependency.
