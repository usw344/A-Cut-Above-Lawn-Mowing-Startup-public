# The Business Simulation

Status: **Current.** Added 2026-08-25; workmanship readout reconciled 2026-08-30.

Everything the company is, as opposed to everything the mowing scene is. Three
autoloads and two pure classes, which together turn *accept → mow → get paid →
repeat* into *compete for work → choose how to service it → build capacity →
keep customers → take market share*.

> **The mowing is still the game.** Every system on this page exists to give the
> next lawn a reason to matter. None of it mows anything.

---

## The owners

| Autoload | Owns | Must never |
|---|---|---|
| `Equipment` (`ACAEquipment`) | which mowers the business has bought, which one goes to the next contract, the autonomous fleet, bag capacities, off-screen assignments | hold money, own job state, offer credit |
| `Clippings` (`ACAClippings`) | the bag, the yard's inventory, the compost heap, the price of a kilogram | count particles, own a second balance |
| `Business` (`ACABusiness`) | reputation, reviews, customers, competitors, market share, the day's schedule, the yard's state | name a person, employ one, pay one |

| Pure class | |
|---|---|
| `ACAContractTerms` | what a contract asks for beyond "mow it" — **derived from its seed, never stored** |
| `ACABusinessYard` | the premises in the Town. Draws what `Business` decides; owns nothing |

`GameSession` remains the only balance and the only completion pathway.
`ACAJobManager` remains the only owner of a job.

---

## Contract terms are derived, not stored

`ACAContractTerms.terms_for(job)` is a **pure function of the contract's own
seed**, drawn from a stream mixed with a constant so it can never consume,
reorder or collide with the draws the job generator or the property generator
make from the same seed.

Nothing is written to a save file, nothing is added to `ACAJob`, and the Job
System does not know the class exists. That buys three things at once:

- the same contract always asks for the same things — on any machine, in any
  build, before and after a reload;
- **a save written before terms existed loads with terms already on its
  contracts**, correctly, because they were always implicit in the seed;
- a term can be added or retuned without a save migration.

The four terms, and the number each is scored against:

| Term | Measured by |
|---|---|
| `COLLECT` — take the clippings away | `Clippings.delivered_this_job()` |
| `MULCH` — leaving them down is fine | nothing; it is permission, not a target |
| `ON_TIME` — finish inside the service window | the contract stopwatch, in game minutes |
| `NO_DRY_TANK` — do not run out on site | `MowerFuel.emptied` firing on this property |

There is deliberately **no quality or neatness requirement in the contract**:
workmanship is measured only for optional recognition on the results screen, and
never changes completion, payout, reputation, or the save.

Roughly 55% of contracts carry any term at all. Only `COLLECT` is ever
*mandatory*, and only on about a third of the contracts that ask for it — a
deadline missed by ten seconds should cost a bonus, not a day's work.

---

## Clippings

**The unit is the kilogram**, everywhere. Nothing converts between two units.

```
0.015 kg per lawn cell   ->   a Medium contract yields about 285 kg
                              = a little over three Rider catchers
```

### Only fresh grass fills the bag

`ACALawn.mow_deck()` returns the number of cells that went from UNCUT to CUT.
**That return value** — not the deck's area, not time spent, not the particle
count — is what `Clippings.collect_from_cells()` converts into weight. Driving
over ground that is already mown produces exactly nothing, which is both what a
player expects and the only version that cannot be farmed.

The cosmetic clippings thrown by the deck are `ACAMowingEffects`. The two never
speak.

### A full catcher stops collecting, not mowing

One rule, applied consistently: when the catcher is full the machine keeps
cutting and what it cuts is **left on the lawn**. The contract still progresses
and the lawn still finishes; what is lost is the collection, which is what a
collection term is scored on.

Refusing to cut was rejected — a machine that will not mow because a box is full
turns a logistics decision into a wall, and makes a contract failable in a way
the player cannot undo without restarting.

### The yard

Unloading at the work truck moves the bag into the yard. The yard has a capacity
(`400 kg`, raised by the Yard Storage upgrade) that everything counts against,
so composting cannot be used to dodge a full yard. Fresh clippings can be sold
immediately, or heaped: four world days later the heap comes back as compost,
**68% of the mass at about 2.5× the price**. Both prices move with the market
through `Economy.resource_index()`.

Two upgrades, both of which change a number this class actually reads: catcher
capacity and yard capacity. There is no third, because there is no third number
worth changing.

---

## Equipment

### Mowers are owned per TYPE

A business that owns "two riders, one with a better engine" needs a serial
number on every machine, an upgrade record per serial, a selection UI that
distinguishes them and a save format that survives one being sold — and none of
it buys the player a decision they do not already have. So a mower type is owned
or it is not, and `MowerUpgrades` improves *the* one the business owns.

**A new business owns the Rider**, because the game has always started there and
the whole economy — fuel share of revenue, contract rates, all three difficulty
profiles — was tuned against it. The other two are bought outright.

The Push Mower is cheap **and worth buying**: it burns no fuel at all, so on a
Small contract it turns the fuel line of the job to zero. That is why the
cheapest machine in the shop is not simply the worst one.

| | Rider | Powered | Push |
|---|---:|---:|---:|
| purchase | owned | $850 | $260 |
| catcher | 90 kg | 55 kg | 25 kg |
| fuel | yes | yes | none |

### Autonomous units are owned per MACHINE

Because owning three at once is the whole point of them. Three tiers, capped at
four machines. Each declares **two separate rates**, and they must not be derived
from each other:

- `cells_per_minute` — off screen, over game minutes, for the estimate that
  settles a contract nobody watched;
- `escort_speed` / `escort_deck` — on the lawn, in real seconds, for a machine
  that has to look like it is mowing.

The first version computed the second from the first and produced an escort that
crawled at three cells a second and would have taken ninety minutes to finish
its section.

**There is no operator, anywhere.** Not a hidden one, not an implied one. The
escort's body is assembled from primitives — a deck, four wheels and a trim band
— specifically because both mower meshes in this project are a single merged mesh
whose handlebar cannot be removed, and a walk-behind gliding along with nobody
holding it reads as an *invisible person*, which is worse than either.

---

## Off-screen contracts, and the two capacities

`ACAJobBalance.MAX_CURRENT_JOBS` is **5**. It was 1, and while the player was the
only thing that could mow, 1 was right: a contractor cannot be in two gardens at
once.

That is the **business's** capacity now. How many contracts the *player* may
personally hold is a different question, it is 1, and it belongs to the host —
so the Job System asks through `player_capacity_provider` and `GameSession`
answers. `accept_job(id, for_machine := true)` skips that gate, because a machine
being put on a contract is the business taking work rather than the contractor
taking a second garden to stand in.

`GameSession.current_job()` therefore returns the first current job that **no
owned machine is out on**. A contract a machine is finishing must never build the
mowing scene.

Off-screen work is a deterministic estimate — mowable area over the tier's rate,
with a clutter penalty — never a simulation. It costs **fuel at the market's
price** and nothing else: the machine is owned equipment, so there is no wage, no
tax and no premium.

---

## Reviews, reputation and customers

A rating is **measured**: it starts from how much of the lawn was actually cut,
then moves by the contract's own terms, each of which the game already has a
number for. Review text is authored — five bands of a few lines, chosen by the
rating and the contract's seed — plus one note naming the most important missed
term. No runtime language model, no template filling.

Reputation is one number, 0–100, moved only by finished work, starting at 45
(a firm with no history is unproven rather than disgraced). What it buys is
**first refusal on the good work** rather than a payout multiplier: above 62,
Large contracts are held for the player instead of being taken.

### A customer is a property

The customer id is the **contract seed**, because that is what rebuilds the same
ground. A returning customer is literally the same lawn — not a name attached to
a fresh one. That is also why this system needs no name generator, and why there
are no personal names anywhere in it: the project shows no humans, and a
returning garden the player recognises is a better memory than a surname.

Loyalty moves with the review. Below 18 a customer lapses; a lapsed customer may
come back later with their trust starting lower. Service intervals are seeded per
customer within per-property-type bounds, so two suburban gardens are not on the
same rota and the same garden is always on its own.

---

## Competitors

Four firms, one per archetype. Every `COMPETITOR_INTERVAL_MINUTES` **one** of
them may take **one** offer — never more, and **never the last offer on the
board**. A board a rival can empty is a board the player cannot use.

Every offer also gets a 90-minute grace period, so the player has always had a
chance at everything before anyone else could.

Market share is measured **by contract value** over a rolling window of 24, not
by count: winning four small gardens while the competition takes the town park is
not leading the market.

---

## Persistence

Three additive save sections, and **no save-format version bump**. Each holds
state that genuinely cannot be reconstructed; each has a defined meaning when
absent:

| Section | Missing means |
|---|---|
| `equipment` | the business owns the Rider it always drove, **plus** any machine it had bought upgrades for — inferred from `MowerUpgrades` |
| `clippings` | an empty yard and an empty bag. There was nothing to lose |
| `business` | no reviews and no customers. Completed contracts are **deliberately not** converted into reputation: they were played before there were terms to judge them by |

Nothing derivable is stored. A competitor's name, colour and appetite come from
the constant table, so only an id ever appears in a save; a unit's speed,
capacity and price come from its tier, so only the tier is written.

`Legacy Save Test` loads real saves written on 2026-08-20 — before any of this —
and passes 37/37.

---

## Permanent exclusions

Not a "later" list. These must never be added, under any name:

- income/sales/payroll/property/business tax, filings or penalties
- insurance of any kind
- loans, credit, financing, APR, interest, or debt service based on interest
- wages, payroll, a labour market, or employees of any kind
- visible humans, human faces, portraits, pedestrians or operators

Growth comes from earnings, saving, equipment purchases, operating decisions,
customer retention and resource sales.
