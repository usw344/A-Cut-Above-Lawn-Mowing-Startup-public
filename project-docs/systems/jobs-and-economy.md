# Jobs and Economy

Status: **Current** — source-verified 2026-08-30 (game-feel and debugger pass).
Canonical owners: `JobManager` (jobs) · `Economy` (market) · `MowerUpgrades`
(equipment) · `GameSession` (**money**).
Important paths:

- `Main Area/ACA_JobSystem/job_system/`
- `Game/Economy/economy_manager.gd`
- `Game/Economy/mower_upgrades.gd`
- `Main Area/ACA_BusinessTown/UI/business_services.gd`

## Integration points the host fills in

`ACAJobManager` carries optional `Callable`s the host sets once. The Job System
never touches a mower node, an economy or a lawn itself.

| | |
|---|---|
| `estimated_time_provider` | real minutes a contract is expected to take. Still unset — see the known limitations |
| `pay_multiplier_provider` | the market index and the difficulty's pay scale, applied ONCE when an offer is created |
| `site_note_provider` | a short phrase describing the site, printed on the offer's work order. `ACAGameSession` sets it to the SAME derivation the property generator uses, so a card that says "House and garden" is a card whose property has a house on it |

`ACAJobEnums.PropertyType` is the whole of the Job System's vocabulary for what a
property is. The host owns the rest and hands over a string.

## Purpose

Generate work, price it against a market that moves, pay for it, and let the
money buy fuel and machine upgrades that change how the game plays.

## Ownership

```
WorldClock.day_changed                    ACADifficulty (seven numbers)
        |                                          |
   Economy.advance_to_day()      <- the ONLY thing that moves the market
        |                                          |
   condition + event + drift  ->  job index / fuel price / equipment index
        |
        +--> JobManager      priced at GENERATION only
        +--> Supply Store    fuel price per unit
        +--> MowerUpgrades   equipment price index
                 |
        GameSession.try_spend()   <- THE ONE BALANCE
```

| Concern | Owner | Not the owner |
|---|---|---|
| Money | `GameSession` | `Economy`, `MowerUpgrades` — they price, never hold |
| Market condition, events, prices | `Economy` | anything with a `_process` |
| Job objects, offers, expiry, history | `JobManager` | `GameSession` |
| Upgrade levels and their effects | `MowerUpgrades` | the mower scenes |
| Shop presentation | `ACABusinessServices` | any of the above |

## Difficulty — `Game/Economy/difficulty.gd`

An **economy** setting, not a graphics setting. It is chosen when a game starts,
saved with that game, and changes seven numbers and nothing else.

| | Easy ("Steady") | Medium ("Working") | Hard ("Lean Season") | `legacy` |
|---|---:|---:|---:|---:|
| Starting money | $320 | $250 | $200 | $250 |
| Job pay scale | 1.15 | 1.00 | 0.88 | 1.00 |
| Base fuel price | $0.90 | $1.00 | $1.15 | $1.10 |
| Event daily chance | 0.10 | 0.11 | 0.15 | 0.11 |
| Recession job scale | 0.75 | 1.00 | 1.25 | 1.00 |
| ...effective payout | 0.88 | 0.84 | 0.80 | 0.84 |
| Upgrade cost scale | 0.85 | 1.00 | 1.15 | 1.00 |
| Full-tank seconds | 560 | 500 | 430 | 480 |

!!! danger "`recession_job_scale` is not the recession multiplier"
    It scales the **deviation from neutral**:
    `effective = 1.0 + (0.84 - 1.0) * scale`. This was read out of the offline
    simulator rather than assumed from the parameter's name, which reads as
    though it were the multiplier itself.

`legacy` is never offered to a new game. It is exactly the constants the game
shipped with, and it is what a save written before difficulty existed loads as —
so a business somebody has run for a hundred in-game days does not have its fuel
price and its contract rates moved underneath it by a patch.

`ACADifficulty` holds the numbers; **`GameSession` is the only thing that calls
`set_active()`**, because which profile is in force is session state. The active
profile is a static var rather than an autoload: fuel burn is read every physics
frame at 576 Hz, so the read has to be free.

Where each number is applied — once each, and never twice:

| Number | Applied in |
|---|---|
| starting money | `GameSession.start_new_game()` |
| job pay scale | `GameSession`'s `pay_multiplier_provider`, alongside the market |
| base fuel price | `Economy.base_fuel_price()` |
| event chance | `Economy.event_daily_chance()` |
| recession depth | `Economy._modifier()`, Recession/`job` only |
| upgrade cost | `MowerUpgrades.next_cost()`, before the market |
| fuel economy | `MowerFuel.full_tank_driving_seconds()` |

Fuel economy is deliberately NOT applied in the mower controllers: each already
multiplies `delta` by its own `MowerUpgrades.fuel_multiplier()`, and applying
difficulty there too would tangle the two across three files.

Validated at 1,000 simulated business-years per difficulty. See
`../../ECONOMY_REBALANCE_REPORT.md` at the workspace root.

## The recession market bridge

`Economy` owns the condition. `ACAJobManager` owns the market. Neither knows the
other exists. The application layer connects them:

```
Economy.condition_changed  ->  GameSession._apply_economy_to_market()
                           ->  JobManager.set_economy(RECESSION | NORMAL)
                           ->  ACAJobMarket.market_strength()
```

Under the current Spring / Normal world that is the Job System's own existing
`-2` recession modifier on a Spring base of 4, so **offer capacity falls from 4
to 2 for as long as the downturn lasts** and returns to 4 when it ends. Nothing
was invented: the modifier has been in `ACAJobMarket` all along with nothing
driving it.

## Drought is dormant, and deliberately still dormant

`ACAJobMarket.market_strength()` has a `Climate.DROUGHT` branch that forces
market strength to zero. Nothing drives it — `GameSession` never calls
`set_climate()`, `WorldClock` has no climate progression, and `Economy` has no
drought in `CONDITIONS` or `EVENTS`. Activating it would mean inventing a
probability, a duration and a severity with no evidence behind any of them, for
a condition whose only existing rule is "no work at all". Recorded as future
work; the branch was left where it is.

## The market

Four conditions and one temporary event at a time.

| Condition | Job | Fuel | Equipment | Lasts |
|---|---|---|---|---|
| Stable | 1.00 | 1.00 | 1.00 | 8–20 days |
| Growth | 1.12 | 1.05 | 1.08 | 6–16 days |
| Inflation | 1.18 | 1.22 | 1.20 | 6–14 days |
| Recession | 0.84 | 0.92 | 0.90 | 6–16 days |

Six events (Fuel Shortage / Surplus, High Demand, Slow Season, Construction
Boom, Supply Delay), 2–8 days each, 11% chance per dry day, with a 3-day
cooldown so back-to-back events do not read as one permanent modifier.

Fuel adds a **mean-reverting daily drift** (AR(1), ±3.5% step, retention 0.72,
clamped to ±9%), so the price wanders rather than jumping. The final fuel
multiplier is clamped to 0.70 – 1.45 whatever conditions and events conspire to
produce.

```
fuel price  = BASE_FUEL_PRICE (1.10) x condition x event x (1 + drift)
job index   = condition x event
equipment   = condition x event          (no drift — shop prices are steady)
```

### Days, not frames

Nothing in `Economy` runs in `_process`. It moves on `WorldClock.day_changed`
and at no other time, so it cannot drift with frame rate or be affected by a
pause. `advance_to_day()` walks each intervening day, so a regime that should
have ended does — capped at `MAX_CATCHUP_DAYS` (400).

### Determinism

Every day's rolls come from a seed derived from `(economy_seed, day_index)`,
**not** from a running RNG stream. A stream would have to have its internal state
persisted exactly, and any divergence would silently reroll the economy on load.
`randomize()` is never called. Replaying day 41 always produces day 41.

## Job pricing, and the lock

```
generate_core(seed)          pure. The same seed always describes the same
       |                     PROPERTY: type, site, size, grid, base value
       v
generate(..., multiplier)    base_pay = round5(core value x market)
       |                     market_base_pay and market_multiplier are kept
       v                     for diagnostics only
ACAJob.base_pay              LOCKED. Stored on the job, paid on completion
```

!!! danger "Accepted contracts are immutable"
    The market is read **only at generation**. `GameSession.complete_current_job()`
    pays `job.base_pay` from the job object. A recession after the handshake
    cannot reprice work the player already agreed to do. `Economy Test` drives
    the market 120 days forward between accepting and completing and asserts the
    agreed figure is what is paid.

`ACAJobManager.pay_multiplier_provider` is injected by the application layer
(`ACAGameSession._ready`), exactly as the time provider is. **The Job System has
no idea an economy exists.** Left null, every offer is priced at its authored
value — which is why the 110 job-system tests were unaffected.

The job system's own seeded variation (`PAY_VARIATION_MIN/MAX`, 0.85–1.15) is
unchanged: that is the authored balance by lawn size, and the economy multiplies
on top of it rather than replacing it.

## Fuel

`MowerFuel` capacity is **100 units**; the UI says "units" rather than
pretending to be litres. A full tank in a neutral market is about $110.

The Supply Store: shows the level, the price per unit and the cost to fill;
offers a full refuel, and a **partial** one for whatever the player can afford —
being short of a full tank is not the same as being unable to buy fuel at all.

Money leaves FIRST and fuel goes in second, so a failed payment can never leave
the player with free fuel.

The F7 development refuel and F8 Auto Refuel are unchanged and still free. They
are development tools; paid refuelling is the production system.

## Upgrades

Stable ids `rider` / `powered` / `push` — the keys `MVP.mowers_scene_list` and
`model.current_mower` already used. **Not scene paths**, so moving a mower scene
cannot invalidate a save.

| Category | Stat | rider | powered | push | Levels |
|---|---|---|---|---|---|
| Engine & Drive | speed | ✔ | ✔ | — | 4 |
| Fuel System | burn rate (lower is better) | ✔ | ✔ | — | 4 |
| Steering | yaw response | ✔ | ✔ | — | 4 |
| Lightweight Frame | speed | — | — | ✔ | 4 |
| Bearing Kit | yaw response | — | — | ✔ | 4 |

Controllers ask one question per stat:

```gdscript
model.get_speed() * 3.0 * MowerUpgrades.speed_multiplier(MOWER_ID)
MowerFuel.consume(delta * MowerUpgrades.fuel_multiplier(MOWER_ID), _throttle)
mouse_yaw_smoothing * MowerUpgrades.handling_multiplier(MOWER_ID)
```

The authored base is never overwritten, so removing an upgrade would restore the
stock machine exactly.

Costs rise `base_cost * cost_growth^(level-1)`, deterministically, and the market
applies `equipment_index` on top. Rounded to $5.

!!! note "Two deliberate absences"
    **Cut width is not an upgrade.** `ACAMowerCutter` cuts the active mower's
    declared deck geometry through `ACALawn`; widening the deck would change
    the machine's authored physical footprint, not an economy multiplier.

    **The push mower has two categories, not three**, because it burns no fuel.
    That is the machine being simpler, not the system being incomplete.

## Town integration

| Building id | Opens |
|---|---|
| `job_office` | the Job Board (handled by the town itself) |
| `supply_store` | Supply Store — paid refuelling |
| `business_hq` | Business Office — the economy dashboard |
| `mower_dealer` | Mower Workshop — upgrades, per machine |
| `future_lot` | still the "Coming Soon" placeholder |

`ACABusinessTown.host_handled_buildings` is an **exported list**, so the town
package stays generic — it does not need to know that this game has a fuel shop.

## Persistence

| Section | Written by | Contains |
|---|---|---|
| `economy` | `Economy.to_save_dict()` | seed, condition, days left, event + days left, cooldown, fuel drift, last processed day |
| `upgrades` | `MowerUpgrades.to_save_dict()` | `{mower_id: {category: level}}` |

Derived values (indices, prices) are **not** saved — they are recomputed from the
state above, so they can never disagree with it.

Both sections are **OPTIONAL** and `SAVE_FORMAT_VERSION` did not change. A save
written before this milestone loads and gets a fresh market anchored to its own
day. Loading never calls `advance_to_day()`; the clock's own `day_changed` does
that when the world next moves.

## Validation

`Economy Test` — 122 assertions plus a **90-day simulation with a fixed seed**
that prints what the market actually did. Unit tests prove the economy is
consistent; they cannot say whether it is any good to live in.

Representative run (seed 20260820):

| | |
|---|---|
| fuel price | min $0.89, mean $1.11, max $1.49 (base $1.10) |
| biggest daily drift | 4.9% |
| biggest event/regime step | 26.4% |
| job index | 0.84 – 1.12 |
| equipment index | 0.90 – 1.18 |
| conditions | Stable 45 days, Recession 22, Growth 23 |
| events | 20 event days across 5 events |

## Known limitations

1. Ownership is per mower type, not per serial-numbered machine. `Equipment`
   owns the Rider by default; the Powered and Push types are purchased.
2. No fuel inventory or gas cans. Fuel goes into the tank.
3. Job payouts do not yet consider the mower used or the time taken — only lawn
   size, the authored variation, the market and the difficulty pay scale.
4. One event at a time by design. Stacked modifiers become unreadable.
5. `ACAJobManager.estimated_time_provider` is still unset, so `drive` and
   `steering` upgrades change how the machine handles but not how long the
   business thinks a contract takes. The offline study therefore scores them as
   nearly worthless, which is a limitation of the integration rather than a
   verdict on the upgrades — and is why their prices were NOT cut on the
   strength of it.
6. Upgrade uptake is low (about one run in five ever buys one) at every
   difficulty. What was changed in response was information, not price: the
   Mower Workshop now states what a purchase leaves, in money and in tanks of
   fuel at today's price.
