# Jobs and Economy

Status: **Current and integrated.** Verified 2026-08-19 by the Flow Test (54) and
the Job System's own suite (110).

## Owner

`ACAJobManager` — `Main Area/ACA_JobSystem/job_system/manager/job_manager.gd`,
autoloaded as **`JobManager`**.

It is the single authoritative owner of every job. `available_jobs` /
`current_jobs` / `past_jobs` live there and nowhere else. The UI is a read-only
view; gameplay reports in through the public API. There is no job state in job
nodes, in global dictionaries, or in accepted-job subclasses.

The older prototype (`Managers/Job manager/`, `Job_Offer`, `Job_Type`,
`Job_Data_Container`) is **gone from `res://`** — see `Soft Delete/MANIFEST.md`.
`Model.gd` no longer has a job-offer dictionary.

## Package layout

```
Main Area/ACA_JobSystem/
  job_system/
    data/        job.gd (ACAJob : Resource), job_enums.gd, game_time.gd
    config/      job_balance.gd (ALL tunables), job_catalog.gd (site names)
    generation/  job_generator.gd  — deterministic from (seed, generator_version)
    market/      job_market.gd     — season+economy+climate -> strength 0..5
    time/        job_time_provider.gd  ← INTEGRATION POINT
    debug/       debug_time_provider.gd (demo/tests only, NOT the game clock)
    manager/     job_manager.gd
    ui/          JobBoard.tscn, JobCard.tscn, job_ui_style.gd
  demo/   tests/   tools/          — tooling, all working
```

## ACAJob (Resource)

Pure data — no timers, no `_process`, no scene tree, no UI.

`id`, `seed`, `generator_version`, `job_site`, `property_type`, `lawn_size`,
`grid_size: Vector2i`, `base_pay`, `offer_duration_minutes`,
`created_game_time`, `expiry_game_time`, `accepted_game_time`,
`completed_game_time`, `status`, `progress`.

**Reproduction key:** `ACAJobGenerator.generate_core(seed, generator_version)`
rebuilds site, property type, lawn size, grid size, pay and offer duration from
`(seed, version)` alone. Only the absolute timestamps depend on when the offer
entered the market. This is the foundation the save system builds on.

**Draw order in the generator is part of the contract.** Inserting a draw, or
reordering `ACAJobCatalog.GENERATED_PROPERTY_TYPES`, changes what existing seeds
produce — bump `GENERATOR_VERSION` instead.

## Lifecycle

`GENERATED → AVAILABLE → ACCEPTED → IN_PROGRESS → COMPLETED`, with
`EXPIRED` for lapsed offers and for abandoned contracts.

- Offer expiry applies to `AVAILABLE` only. Once accepted, a contract never
  expires; a completion deadline is a separate, future system.
- Expired offers are **not** business history — they never reach `past_jobs`.
- `MAX_CURRENT_JOBS = 1`. `current_jobs` stays a collection so raising that
  number is the only change required later.

## Public API

```
set_time_provider(provider)      time_provider()      now()
available_jobs() / current_jobs() / past_jobs()   -> Array[ACAJob] (copies)
get_job(job_id) -> ACAJob        has_current_capacity()   max_current_jobs()
market_strength()  max_available_jobs()  market_summary()  minutes_until_next_arrival()
evaluate_now()
seed_initial_offers(count = 2)
accept_job(job_id) -> bool
begin_new_job(job_id) -> bool          # emits begin_job_requested, changes NO scene
update_job_progress(job_id, 0..1) -> bool
complete_job(job_id) -> bool
discard_current_job(job_id) -> bool    # abandon: not completion, not history
estimated_time_minutes(job) / estimated_time_text(job)
debug_force_offer() / debug_add_offer_with_seed(seed) / debug_clear_all()
```

**SIGNALS:** `available_jobs_changed`, `current_jobs_changed`, `past_jobs_changed`,
`job_generated(job)`, `job_expired(job)`, `job_accepted(job)`, `job_completed(job)`,
`job_accept_failed(job_id, reason)`, `market_strength_changed(strength)`,
`begin_job_requested(job)`

## Integration points — all three are now filled in

| Point | Filled by |
|---|---|
| World time (`set_time_provider`) | `ACAWorldClockTimeProvider` wrapping `WorldClock`, set in `GameSession._ready()`. **Before this existed the manager ran on a stopped clock and no offer could ever be generated.** |
| Gameplay handoff (`begin_job_requested`) | `GameSession._on_begin_job_requested()` does the scene transition. The Job System still never changes scenes. |
| Progress reporting (`update_job_progress`) | `MVP._tick_job_runtime()` pushes `Custom_Gridmap.mowed_fraction()` at 2 Hz. |

`estimated_time_provider` is still **unset** — estimates come from
`ACAJobBalance.PLACEHOLDER_CELLS_PER_REAL_MINUTE`. Setting it is the clean way to
derive estimates from lawn size + mower capability later; do not edit gameplay
code for it.

## Market model

`ACAJobMarket.market_strength(season, economy, climate)` → 0..5, which **is** the
maximum number of simultaneous offers (a capacity, not a quota).
Spring 4 / Summer 3 / Autumn 2 / Winter 0; economy −2..+1; climate −1..+1;
**Drought is a hard zero** that overrides everything.

Arrivals come one at a time on a game-minute interval banded by strength
(strength 4 → 60–120 game minutes). Falling demand never deletes existing offers.

Season comes from the time provider (calendar-driven). Economy and climate are
exported on the manager and default to `NORMAL`; no system drives them yet.

## Economy

Deliberately minimal and honest:

- `job.base_pay` is the size base value with seeded variation, rounded to $5.
  Property type, mower, economy and climate **do not** affect pay in V1.
- `GameSession` owns money. `STARTING_MONEY = 250`.
- On completion `GameSession.complete_current_job()` adds `base_pay` and emits a
  `job_settled` summary with `bonus: 0` — the Job Complete screen hides the bonus
  row when it is zero. **No bonus/tip system was invented to fill the label.**
- There is no spending yet. The Supply Store, Mower Dealer and Business HQ are
  still placeholder destinations in the town.

## Presentation

`ACAJobBoard` (`JobBoard.tscn`) — Available / Current / Past, bound to the
manager by `ACABusinessHUD._ready()`. One board-level 0.5 s timer drives every
offer countdown; individual jobs and cards never own timers.
Player-facing wording only: the raw grid dimension is never shown.

## KNOWN ISSUES / NOT DONE

- No completion deadline on accepted contracts.
- No economy or climate simulation driving `market_strength`.
- No trust/reputation, no bonuses, no spending.
- Job persistence across save/load: see [save and load](save-and-load.md).
