# Service Territories, Equipment and Operations

Status: **Current** — 2026-08-29, the regional-world and Sky3D pass.
Previous revision: 2026-08-25, the gameplay-expansion pass.

The business used to grow by getting richer. This pass makes it grow by getting
BIGGER: more of the map, more kinds of machine, more ways to configure one, more
than one contract in the air at a time, and a record of what it has already
done.

Everything here is an addition to the systems the business-simulation pass
built. Nothing was replaced.

---

## The shape of it

```
                       ACAServiceTerritory  ── which markets are open
                              │                 (a lot, bought once, in full)
                              ▼
  ACAJobManager ── offer_filter_provider ──> only work the business can take
        │         job_group_provider ─────> the board's region tabs
        │
        ▼
  ACAServiceAgreements ── multi-visit contracts, built out of ordinary ones
        │
        ▼
  GameSession.complete_current_job()  ── still THE one completion pathway
        │
        ├── ACABusiness      reputation, reviews, customers, condition stages
        ├── ACAServiceTerritory   local presence
        ├── ACAServiceAgreements  visits served
        └── ACAPortfolio     the before/after pair
```

On the property side:

```
  ACAPropertyParams ──┬── ACAPropertyArchetype   what KIND of place  (existing)
                      └── ACAPropertyCondition   what STATE it is in (new)
                                │
  ACAProperty.make_features() ──┴── ACAConservationZone   ground not to be cut
                                        │
                                   ACALawn.FLAG_PROTECTED
```

---

## Service territories

`Game/Business/service_territory.gd`, autoloaded as `Territory`.

Five regions, and the order they come in **is the geography**. A business starts
owning the streets it was founded on and buys the rest, once, in full, out of
money it has actually earned. There is no financing anywhere in this game and
there never will be.

| # | Region | Native work | Lot | Standing wanted |
|---:|---|---|---:|---:|
| 1 | Small Town | Residential, Community | — | — |
| 2 | Medium City | Commercial, Institutional | $7,500 | 45, 10 contracts |
| 3 | Big Town | Hospitality, LARGE Commercial and Institutional | $16,000 | 56, 20 contracts |
| 4 | Rural Highway | Rural, Industrial | $26,000 | 64, 32 contracts |
| 5 | Country Parks | Public | $40,000 | 72, 46 contracts |

Prices are before `ACADifficulty`'s `upgrade_cost_scale` and before the market,
exactly like a machine's.

**The enum names did not move.** `Region.HOSPITALITY_STRIP` is Big Town and
`Region.CIVIC_PARK` is Country Parks, because a save file's region ids are built
from those names and a rename would be a migration for no gain. What a region IS
lives in `REGIONS`; the enum is only how it is spelled.

### The scale promotion

A district shopping centre and a hospital campus are not the same trade as a
parade of shops and a village school: they are the work a REGIONAL CENTRE has
and a market town does not. `SCALE_PROMOTION` moves the **LARGE** contracts of
those two kinds out of Medium City and into Big Town, which is what makes the
third market a bigger one rather than a differently-coloured one.

It is still a pure function of the property type and its size, so nothing about
it is stored, and it is checked before the local exception — which only ever
applies to smaller contracts, so the two rules cannot fight over the same one.

### A contract's region is DERIVED, never stored

The same rule `ACAContractTerms` is built on, for the same reasons. A contract's
region is a pure function of its property type, its size and its own seed:

* the same contract is always in the same place, in any build;
* a save written before territories existed loads with every one of its
  contracts already correctly placed;
* the mapping can be retuned without a save migration.

### The local exception, and why the starting market is not two types wide

A small shop, a neighbourhood green and a village school ARE in the town the
business works in — they are simply not what the trade calls commercial, civic
or institutional work. So a seeded minority of the SMALLER contracts of those
three kinds are local, and the player meets them from day one.

`ACAServiceTerritory.LOCAL_EXCEPTION` is that rule, and `Expansion Test` asserts
the SHARE rather than any individual seed: which seeds land where is balance,
and the fact that some do is the contract.

### Local presence

0–100, per region the business has entered. It never unlocks anything — buying
the lot is what unlocks a region. Presence is the record of the work: it moves
with completed contracts (weighted by size and by the review), it moves back
when a rival takes work in that market, and it decides two things —

* how much plant is standing on that region's service lot, and
* whether the market is established enough to offer a service agreement.

### The Job System never learns what a region is

Two new integration points on `ACAJobManager`, both the same shape as the site
note, the pay multiplier and the second action that were already there:

```gdscript
offer_filter_provider = func(job) -> bool          # may this be published?
job_group_provider    = func(job) -> Dictionary    # { id, label, colour }
```

`_spawn_offer()` rerolls up to `ACAJobBalance.OFFER_FILTER_ATTEMPTS` seeds until
the host accepts one. An arrival every attempt refuses is not an error — a
market the business has no access to SHOULD be quiet.

The board draws its region filter row only when the offers on it fall into more
than one group, so a business working one market gets the board it always had,
with no extra row and no extra node.

---

## Regional hubs

`Main Area/ACA_RegionalHubs/`.

The Business Town is an authored scene of about four hundred nodes and it earns
that: it is where the player spends most of their time. Authoring four more
would be most of a pass.

So the four regional lots are a **layout description plus a builder**
(`ACARegionalHub`) hosted by one screen (`Regional Hub Screen.tscn`). They share
the town's asset library, its materials, its camera rig, its HUD, its picking
and its building panel — `ACABusinessTown` is the controller for a hub too,
because it never knew what a town was.

`GameSession` still calls all of them `Screen.TOWN`. A regional hub IS the town
for every purpose the application layer has.

### What makes four hubs four places

**Every model in `ACARegionalHub` also appears in at least one other hub.** None
of the difference between them is a unique asset, and all of it is composition:

| | |
|---|---|
| FOOTPRINT | the island, and the camera framing that goes with it. Big Town stands on 52 x 34 against Medium City's 42 x 23 and is framed a third wider, so it reads as bigger before anything on it has been looked at |
| STREET PLAN | `roads` is a list of STRIPS — an axis, a centre line, and where it starts and stops. Medium City is a grid, Big Town is a dual carriageway with a planted median and two cross streets, Rural is one four-unit highway across an otherwise empty county, and Country Parks is a park road with a spur off it |
| DENSITY | Big Town's backdrop blocks stand at 1.06-1.42 where Medium City's stand at 0.92-1.22. The SAME MODELS, standing bigger |
| BUILDINGS | the city regions use KayKit's three-to-five-storey blocks; Rural and Country Parks use Quaternius's one- and two-storey houses, painted with the town's own `quaternius_shop.tres`. An early render put four-storey apartment blocks on a highway service lot in open country, and it was the loudest single thing wrong with it |
| GROUND | grass, concrete, gravel and asphalt in different proportions, with grass squares kerbed into the hard-surfaced regions and ploughed field bands cut into the soft ones |
| TRAFFIC | four profiles over ONE mechanism: nine cars in Big Town, two on a country lane, and a highway with no loop on it because a highway is somewhere you pass through |
| HORIZON | a far shelf beyond the island carrying a skyline of blank boxes, a belt of trees, a pattern of fields, or a forest front |

### The traffic cannot leave the road

Routes are **derived from the same `roads` table the road tiles are laid from**,
one pair per through strip (or one, on a one-way carriageway), offset to one
consistent side of the direction of travel. A car therefore cannot be driving on
a street that was never laid.

`ACATownTraffic.configure()` is the door: the Business Town's own routes are
still the class's defaults and its authored node passes nothing, so the town
behaves exactly as it always has.

`Expansion Test` measures the claim rather than repeating it — every point of
every generated route, against every strip, with the car's own half-width to
spare. **44 points, 0 off the tarmac.**

### The lot grows with the presence

Additively, exactly as `ACABusinessYard` does: a lot just bought is a truck, a
machine and a crate; one worked for a month is fenced, lit, has a trailer, a
van, a bin and a board on the gate. `_yard_dressing()` adds the things a working
yard has that are not fleet — a bulk tank, fuel drums, stacked pallets —
because an apron with four vehicles on it and nothing else renders as a car park
with a truck lost in the middle of it.

### The scale corrections

Every pack in these scenes is authored at a different size, and the numbers in
`ACARegionalHub` are read off the Business Town rather than guessed: trees
0.26-0.30, cars 1.0, benches 1.7, hydrants 1.4, Quaternius houses 0.9, and the
Kenney work vehicles at half, which puts a pickup a little longer than a
hatchback.

### Where scenery may stand

Two rules, expressed separately.

* `plant` is a list of rectangles saying where a region HAS open ground.
* `_forbidden` is **derived** from what has already been built — every road
  strip widened by a car's width, every apron, every placed building, the pond,
  the trails — and nothing is scattered on any of it.

An earlier version kept one hand-written rectangle per region; half of every
island came out bare, and a tree stood in a car park the first time a layout
moved.

## Regional atmosphere

`Game/World/regional_context.gd` — `ACARegionalContext`.

A region is a tab on the job board until the player is standing on one. This is
what it means on the ground, and it does exactly two things.

**It reshapes the property.** Forest, openness, relief, the horizon, scrub and
rough grass, as multipliers on what the seed already drew — applied after the
archetype and before the condition, under the same rule both of those obey:
**it reshapes, it never draws.** `ACAPropertyParams.for_seed()` takes a fixed
sequence of draws and THE DRAW ORDER IS THE SAVE FORMAT, so a region that
consumed a random number would move every property that already exists. A
`region` of -1 — every caller that predates this — changes nothing at all.

**It says how far you can see.** `air_layer()` returns a small scale on the
composed depth fog and Sky3D's aerial quad, applied through the environment
package's PLACE layer. Big Town has the most air in it and Rural the least.

It is **not** a second weather system. It cannot make it rain, it does not
change with the sky, and `ACAWorldClock` remains the one authority on what the
weather is: two players in two regions at the same moment are under the same
sky, and one of them can see further through it.

The hub screens get the same treatment through
`ACATownLightAdapter.set_region_air()`, which tints the procedural sky's lower
hemisphere and adds a standing haze — with `fog_sky_affect` at zero, because a
fog that has swallowed the sky is not a fog, it is a background colour.

## Major service contracts

`Game/Business/service_agreements.gd`, autoloaded as `Agreements`.

An agreement is several related properties, serviced repeatedly, for a fixed
term, won on standing rather than on price. One per region, offered when the
business is established enough there.

**It is built out of ordinary contracts.** Every visit it schedules is a real
`ACAJob`, published on the real board through `ACAJobManager.commission_offer()`,
accepted the normal way, driven to the normal way and settled through
`GameSession`'s one completion pathway. The agreement notices afterwards.

Its own money is a **completion bonus** paid when the term is served out. There
is no second payment path and no per-visit retainer.

Its sites are **found, not invented**: seeds are rolled through
`ACAJobGenerator.generate_core()` — the same pure function the market uses —
until enough of them describe the kind of property the agreement is for.

Qualification is **fleet capacity**, not cash: an agreement is a promise to be
in several places repeatedly, and what makes that possible is machines.

Missing one visit never ends an agreement (`MISSES_ALLOWED` is 2). An offer left
on the table for four days goes to a rival.

---

## Equipment: attachments, modes and the trailer

Three static tables and one owner.

| | |
|---|---|
| `ACAAttachments` | the catalogue: what fits what, what each one does, what it costs, what geometry it hangs on the machine |
| `ACAMowingMode` | bagging / mulching / side discharge, and the ONE rule about which of them produces clippings |
| `ACAHaulage` | the three work trailers: machine slots, attachment slots, clipping capacity, spare fuel |
| `ACAEquipment` | what has been bought, what is FITTED, which mode, which trailer |

### The bagger is owned from the first morning

Every machine in this game has always had a catcher on it, and the contract
terms, the clipping prices and all three difficulty profiles were tuned against
that. So a new business owns the bagger, a save written before attachments
existed loads owning it, and a player who never opens the loadout screen plays
exactly the game they were playing before.

### One rule about clippings

`ACAMowingMode.collects()` decides whether a configuration produces any, and
`ACAEquipment.bag_capacity()` returns zero for the two that do not.
`ACAClippings` is handed that number and never asks why — a capacity of zero is
a machine that mulches, which it already handled.

### The visible half

`ACAMowerAttachment` builds the chute, the roller and the tow-behind sweeper
from primitives in the project's palette. **No collision, ever**: what stops a
machine is its chassis, and `ACAMowerClearance` is derived from the chassis of
the three canonical machines.

The **bagger has no geometry of its own**, deliberately: every canonical
machine's model already carries a catcher, and bolting a second one behind the
first is the one thing a visible attachment system must not do.

Where an attachment hangs is **measured** from the machine's own drawn geometry
and then **bounded** against the deck — the deck is a cutting rectangle rather
than a machine, and a walk-behind's mesh includes its handlebars.

---

## The service lot, and the day as a route

The town's `future_lot` — a "Coming Soon" placeholder for a lot being cleared —
became the **Service Lot**, which is where a working day is prepared: which
machine, what is bolted to it, how it is configured, whether a support unit
comes, what the weather is going to do, and which of the business's territories
to work out of.

Travel between lots is a scene change and an hour of the working day. There is
no road between the regions and building one would be a driving game bolted to a
mowing game; the hour is what stops a player skimming the best contract off five
markets in a morning.

### What persists between stops

The machine empties into the **trailer**, and the trailer empties at a **service
lot**. That is the whole of route persistence: fuel, the catcher, the trailer's
load and the loadout all carry over between contracts, and only a visit to a lot
resets the last of them.

The results sheet offers **STRAIGHT ON TO the next stop** when the day's
schedule has another accepted contract on it.

---

## Weather that moves, and ground that notices

### The sky is a schedule

`ACAWorldClock` divides time into 240-minute blocks and hashes `(weather_seed,
block)` for each one. Nothing accumulates and nothing is rolled per frame, so

```gdscript
WorldClock.forecast(8.0)     # is the same function, evaluated later
```

cannot be wrong. `set_weather()` TAKES the sky until `resume_scheduled_weather()`
hands it back, so a staged shot or a probe measuring rain is never rained off.

### Ground conditions

`ACAGroundConditions` — Dry / Damp / Wet, a pure function of the sky, how long
since it rained, the hour, and the property's own `dryness`. Nothing is
integrated behind the player and nothing is saved.

| | Dry | Damp | Wet |
|---|---:|---:|---:|
| clippings | 0.82 | 1.00 | 1.26 |
| dust | 1.35 | 0.70 | 0.00 |
| traction | 1.00 | 0.97 | 0.90 |
| autonomous time | 0.96 | 1.00 | 1.22 |

Deliberately gentle. Mowing in the wet should change how the player plans the
day and must never make the mowing itself unpleasant.

---

## Property condition

`ACAPropertyCondition` — NEGLECTED → RECOVERING → MAINTAINED, on the same seed,
the same archetype, the same house and the same pond. What the player's work
changes is the CONDITION, never the address.

**MAINTAINED is the neutral default and reshapes nothing**, which is what
guarantees the system cannot move a single existing property: the overwhelming
majority of contracts take that branch and are generated exactly as they were.

The stage is the contract's own seed plus one number the company keeps — how
many times it has finished a contract there — so nothing about it is stored.

A rescue pays a **premium**, and it is a bonus rather than a repricing:
`base_pay` is what the board promised and is never rewritten by anything.

---

## Conservation zones

`ACAConservationZone` — a wildflower meadow, a pollinator strip, a bank of long
grass. **Not an obstacle**: it can be driven straight through, and the challenge
is that the player is asked not to.

`ACALawn` gained two flags:

```
FLAG_PROTECTED   swept by the deck exactly as lawn is
FLAG_DAMAGED     what that sweep recorded
```

A protected cell is excluded from `total_item_count()` like any other excluded
ground, so a property with two meadows still finishes at exactly 100% — and the
player is never asked to mow the thing they are being asked not to mow. That
falls straight out of the existing feature interface.

The planting is drawn with **the lawn's own tuft mesh and the lawn's own
shader**, so a strip mown through visibly IS mown, through the bridge the lawn
already had, with no per-instance update.

`ACAPropertyFeature` gained `footprints()` for this: `bounds()` is the box around
everything a feature holds, and a dozen scattered obstacles have a combined box
covering most of a lawn. Placing against boxes rejected 88 of 89 eligible seeds;
against footprints it places 89 of 89.

---

## Finish patterns

`ACAFinishPattern` — straight, diagonal, cross. Scored off the heading record
`ACALawn` has always kept, folded over a HALF turn: a pass driven north and the
one beside it driven south lay the grass on the same axis and read as one stripe.

It scores CONSISTENCY, not precision. A player steering a real machine corrects
constantly; what is measured is how much of the lawn agrees on an axis, with
twenty degrees of tolerance.

A checkerboard and a perimeter finish need to know WHERE each pass was as well
as which way it went, and scoring one fairly is a harder problem than it is
worth here. Both are later work rather than shipped badly.

---

## The portfolio

`ACAPortfolio` + `ACAPortfolioCamera`.

Two photographs per contract from one standardised viewpoint, derived purely
from the property so the pair cannot drift apart. The camera renders its own
480×270 `SubViewport` sharing the scene's `World3D`, so the HUD is not in the
shot and nothing flickers.

**Images are files; metadata is save state.** JPEGs under `user://portfolio/`;
the save carries file names. Bounded at 60 pairs, and featured work survives the
cull while anything ordinary is left to drop instead.

Every entry point returns quietly on any problem. The contract settles, the
money is paid, the review is written, and the portfolio simply has one fewer
photograph in it.

---

## Save compatibility

Four new **optional** sections and no save-format version bump.

| Section | Absent means |
|---|---|
| `territory` | owns the Home Town, has bought no lot — which is exactly true, there were none to buy |
| `agreements` | none. Nobody offered that business one |
| `portfolio` | no photographs, because nothing was taking any |
| `equipment.attachments` / `fitted` / `mowing_mode` / `trailer` | the catcher every machine always had, fitted, set to bag, on the starting trailer |
| `clippings.trailer_kg` | nothing on the trailer |
| `world.weather_seed` | a world whose weather never moved, given a schedule derived from its own clock |

`ACAPropertyParams.GENERATION_VERSION` is **6**. A property generated at version
5 or below retains the legacy scatter obstacle layout when it reloads, so a
contract already in progress does not move its obstacles. Conservation-zone
compatibility remains governed by the saved property parameters.

`ACALawn.CUT_STATE_VERSION` is **3**, and version 2 is still read — the same
bitset with no damage record on it, which a save written before conservation
zones genuinely had.
