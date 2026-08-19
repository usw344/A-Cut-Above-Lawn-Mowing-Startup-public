# Job System — architecture notes

Transfer and integration steps are in `../README.md`. This file covers how the
system is built and why.

## Ownership

```
World state  (time provider, season, economy, climate)
        |
        v
   ACAJobManager        <- single authoritative owner of all job state
        |
        v
    ACAJobBoard         <- read-only view, rebuilds from the manager
```

`ACAJobManager` owns three collections and nothing else does:

```gdscript
_available: Array[ACAJob]
_current:   Array[ACAJob]
_past:      Array[ACAJob]
```

The accessors (`available_jobs()`, …) return **copies of the arrays** holding the
same job references, so callers can iterate freely but only the manager mutates
membership. There is no parallel job database in the UI, no per-job node, no
global model dictionary and no accepted-job subclass.

## Files

| File | Role |
|---|---|
| `job_system/data/job.gd` | `ACAJob` — one contract, a `Resource`, pure data |
| `job_system/data/job_enums.gd` | statuses, sizes, property types, season/economy/climate + display names |
| `job_system/data/game_time.gd` | duration/clock formatting helpers |
| `job_system/config/job_balance.gd` | every tunable number |
| `job_system/config/job_catalog.gd` | site names, per-type size pools |
| `job_system/generation/job_generator.gd` | deterministic seeded generation |
| `job_system/market/job_market.gd` | market strength, capacity, arrival intervals |
| `job_system/time/job_time_provider.gd` | world-time boundary (subclass this) |
| `job_system/manager/job_manager.gd` | the authority + public API |
| `job_system/ui/job_board.gd` + `JobBoard.tscn` | the three-tab modal board |
| `job_system/ui/job_card.gd` + `JobCard.tscn` | one contract row, three modes |
| `job_system/ui/job_ui_style.gd` | colours, styleboxes, button/tab styling |
| `job_system/debug/debug_time_provider.gd` | test clock (dev only) |

## Job lifecycle

```
GENERATED  --publish-->  AVAILABLE  --accept-->  ACCEPTED
                             |                      |
                        offer expiry           begin_new_job()
                             v                      v
                          EXPIRED              IN_PROGRESS
                        (dropped, not             |
                         business history)   complete_job()
                                                  v
                                              COMPLETED  -> past_jobs
```

Offer expiry applies **only** while a job is `AVAILABLE`
(`ACAJob.is_offer_expiry_active()`). An accepted contract never expires — a
*completion deadline* is a separate, future concept and is not implemented.

Expired offers are removed from `available_jobs` and emit `job_expired`. They
never enter `past_jobs`, which is business history for accepted work.

## Job data

`ACAJob extends Resource`, exported fields so a future save system can serialise
it directly:

```
id  seed  generator_version
job_site  property_type  lawn_size  grid_size  base_pay  offer_duration_minutes
created_game_time  expiry_game_time  accepted_game_time  completed_game_time
status  progress
```

`base_pay` holds the contract's offered pay: the size base value after seeded
variation, rounded to the nearest $5.

Jobs are **not nodes**. No `_process`, no `_physics_process`, no `Timer`, no UI
ownership, no scene ownership. Expiry and arrival are evaluated by the manager
comparing absolute game times — one timer for the whole system, not one per job.

## Generator: seed + version

`ACAJobGenerator.generate_core(seed, generator_version)` reproduces the same core
contract every time: property type → job site → lawn size → grid size → pay →
offer duration, drawn in that fixed order from a `RandomNumberGenerator` seeded
with the job seed.

```gdscript
ACAJobGenerator.generate_core(928471, 1)
# -> Rural / Rural Property / Large Lawn / $440 / 300 min offer   (verified)
```

Only the absolute timestamps depend on when the offer entered the market:

```
expiry_game_time = created_game_time + offer_duration_minutes
```

`generator_version = 1` for this implementation. **The draw order is part of the
contract**: inserting a draw, or reordering
`ACAJobCatalog.GENERATED_PROPERTY_TYPES`, changes what existing seeds produce —
bump the version instead. Save/load itself is not implemented; the seed/version
pair is the foundation for it.

## Lawn sizes

Stored internally as grid dimensions, never shown to the player as numbers:

| Size | Grid | Player sees |
|---|---|---|
| SMALL | 96 × 96 | "Small Lawn" |
| MEDIUM | 144 × 144 | "Medium Lawn" |
| LARGE | 192 × 192 | "Large Lawn" |

`TINY` (64 × 64) and `HUGE` (256 × 256) exist as reserved values but V1
generation never rolls them (`ACAJobBalance.GENERATED_LAWN_SIZES`).

## Market strength and supply

```
market_strength = clamp(season_base + economy_modifier + climate_modifier, 0, 5)
Climate == DROUGHT  ->  market_strength = 0, regardless of everything else
```

Season 4/3/2/0 (spring/summer/autumn/winter), economy −2/−1/0/+1, climate
+1/0/−1/hard-zero.

`maximum_available_jobs == market_strength`. It is a **capacity, not a quota**:
offers arrive one at a time, at a randomised game-time interval taken from
`ACAJobBalance.ARRIVAL_INTERVAL_MINUTES` (≈4–6 h at strength 1 down to ≈30–75 min
at strength 5).

Demand changes never delete contracts:

- **Falling demand** keeps every existing offer. They lapse or get accepted
  naturally; no new offer appears until the board is under the new capacity.
- **Rising demand** does not burst-fill. While the board is full (or the market
  is closed) the next-arrival time is continuously rescheduled relative to *now*,
  so no backlog can accumulate and the new slots fill one offer at a time.
- **Drought** stops new offers and leaves existing ones alone.

## World-time boundary

`ACAJobTimeProvider` is the only place the system asks about time:

```gdscript
func game_minutes() -> float                 # absolute, monotonic, game minutes
func season() -> ACAJobEnums.Season
func format_timestamp(minutes: float) -> String
```

The manager polls it from **one** `Timer` (0.25 s real time,
`ACAJobBalance.EVALUATION_INTERVAL_SECONDS`) and evaluates expiry, market strength
and arrivals by comparing absolute values — so clock jumps are safe and no delta
accumulates. `evaluate_now()` forces an evaluation; `auto_evaluate = false` turns
the poll timer off entirely (the test suite drives the manager by hand).

`ACAJobDebugTimeProvider` in `job_system/debug/` is the development clock used by
the demo. It computes time from the real clock on demand (so nothing ticks it)
and offers `advance_minutes/hours/days`, `set_speed`, `set_paused`, `set_season`.
It is not a competing world simulation — the real game replaces it.

## UI

`JobBoard.tscn` is a `Control`, full-rect with `offset_top = 58` so a host's top
information bar stays uncovered, over a partial-alpha dim layer so a live 3D
scene keeps showing through. `mouse_filter = STOP` swallows clicks before they
reach host picking; `opened` / `closed` let the host disable its own interaction.
The board knows nothing about towns, buildings or cameras.

Tabs:

- **Available** — job site, property type, lawn size, estimated time, pay, offer
  countdown ("Offer expires in 1h 35m", amber under 90 min, red under 30), ACCEPT.
- **Current** — pay, estimated time, progress bar and %, status, and a single
  action button that reads **BEGIN JOB** or, once progress is above 0,
  **RETURN TO JOB**. The wording and layout are ready for leaving and re-entering
  a property; that behaviour itself is not implemented.
- **Past** — job site, property type, lawn size, pay, completion stamp.

Seeds, generator versions and grid coordinates are never shown to the player.

One board-level timer (0.5 s) refreshes the visible countdowns; cards have no
timers and no `_process`. All styling is code-defined in `job_ui_style.gd` —
no theme resource, no imported font, no external texture, nothing loaded from the
Town project.

## Multithreaded physics

The main game runs 3D physics on a separate thread. This subsystem is business
simulation, world-time logic, data and UI: it has **no `_physics_process`, no
physics access and no threads of its own**, and runs entirely on the main thread.

The one place gameplay meets it is `begin_job_requested`. That signal is emitted
and nothing else happens — the host performs the scene transition and owns any
deferred/main-thread marshalling its physics-controlled systems require. Keeping
that boundary on the host side is why `begin_new_job()` is deliberately
boilerplate.

## begin_new_job()

`job_system/manager/job_manager.gd`, line 298. Validates the current job, sets
`IN_PROGRESS`, emits `begin_job_requested(job)`, returns. It changes no scenes,
loads nothing, and touches neither the mowing system nor the Town.

## Deliberate placeholders

| What | Where | Replace with |
|---|---|---|
| Estimated Time rate | `ACAJobBalance.PLACEHOLDER_CELLS_PER_REAL_MINUTE` | `ACAJobManager.estimated_time_provider` fed by the mower system |
| Economy / climate inputs | `set_economy()` / `set_climate()` | the future economy and weather systems |
| Debug clock | `job_system/debug/debug_time_provider.gd` | the game's authoritative world clock |
| Pay model | `ACAJobBalance.BASE_PAY` + variation | balancing pass; property type deliberately does not affect pay yet |

## Room left for later

Multiple current jobs (`MAX_CURRENT_JOBS` is the only limit — `current_jobs` is
already a collection), resuming partially completed contracts, completion
deadlines and penalties, consumer trust and reputation, recurring clients,
premium contracts, save/load via seed + version, non-mowing contract types. None
of them are implemented; the structure just does not block them.
