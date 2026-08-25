# Business Town

Status: **Current** — source-verified 2026-08-24.
Canonical owner: `Main Area/ACA_BusinessTown/BusinessTown.tscn`.
Important paths:

- `Main Area/ACA_BusinessTown/business_town.gd` — picking and selection
- `Main Area/ACA_BusinessTown/aca_town_traffic.gd` — the moving cars
- `Main Area/ACA_BusinessTown/UI/business_services.gd` — the three counters

The town is a hand-authored low-poly island, about 30 by 19.5 world units, seen
from a fixed isometric camera. It is the hub: the player clicks a destination
and the host routes the intent.

---

## The street network

Everything is on a two-unit grid, because every road tile in the KayKit City
Builder pack is a two-unit square centred on its origin. A tile at `x = 4` on the
main street therefore occupies `x` from 3 to 5.

| Street | Runs | Extent |
|---|---|---|
| Main Street | along X at `z = 0` | `x` = -14 to 14 |
| The back street | along X at `z = -6` | `x` = -14 to 14 |
| The side street | along Z at `x = 2` | `z` = -6 to 0, plus a stub at `z = 2` |
| The west connector | along Z at `x = -4` | `z` = -6 to 0 |

Two four-way junctions on Main Street (`x = -4` and `x = 2`), two T-splits where
the connectors meet the back street, and a pedestrian crossing at `x = -6`.

### Why the back street exists

The second row of buildings stood on open grass at `z = -7.5` with no road
anywhere near it. From the isometric camera it read as a row of shops dropped on
to a lawn.

The back street was laid at `z = -6` and the whole second row moved back to
`z = -8.2`, which is exactly where a two-unit building sits on the same 1.98-deep
concrete frontage the front row uses: the building spans `z` = -9.2 to -7.2 and
its frontage stops just behind the new kerb at -7.

### Why the connector is at `x = -4` and not `x = -8`

`x = -8` looks like the obvious gap on the main row — the Supply Store is at
-9.8 and the Mower Workshop at -6.2, and nothing is between them. But the Mower
Workshop's concrete pad is 2.4 units wide and its forecourt reaches out to the
main road, so a road at -8 ran through it. The main row is genuinely empty from
about -4 to +1, so the connector went there and two second-row buildings moved
aside for it.

The Mower Workshop and the Business HQ also moved from `z = -4.2` to `z = -3.9`,
because their pads reached 0.4 units into the new back street.

---

## Ambient traffic — `aca_town_traffic.gd`

A town with no moving traffic reads as a MODEL of a town. Three or four cars
going about their business is the whole difference.

It is decoration and it is built like decoration. There is **no navigation, no
steering behaviour, no physics, no collision avoidance and no signalling**. Each
car follows a `PathFollow3D` around a closed lane at a constant speed. From a
fixed camera thirty units up that is indistinguishable from what a simulation
would have produced, at about a thousandth of the cost and none of the failure
modes.

What keeps it believable is entirely in where the lanes are drawn:

- a lane is offset `LANE_OFFSET` (0.55) to ONE side of its street's centre line,
  the side that matches its direction of travel, so two cars passing each other
  pass on the correct sides;
- corners are rounded with real intermediate points — a `Curve3D` through a
  square corner makes a `PathFollow3D` snap through ninety degrees in one frame,
  which reads as a car glitching rather than turning;
- every lane is a CLOSED loop that stays on tarmac the whole way round, which is
  what stops a car ever driving over a pavement or through a building. It is not
  avoiding them; it is never routed near them;
- speeds and start offsets come from a fixed seed, so no two cars are ever in
  step and the town looks the same every time it is opened.

| Lane | Route | Cars |
|---|---|---|
| `east_block` | Main Street east, up the side street, back along the back street | 2 |
| `middle_block` | the short circuit between the connector and the side street | 1 |
| `west_run` | out west past the Supply Store, round both streets and back | 1 |

**Four cars, three loops, `PROCESS_MODE_PAUSABLE`.** Traffic stops when the game
is paused, because a car sliding past an open menu is worse than no car at all.

### The parked cars had to move

All three street-parked cars were at `z = ±0.55` — which is exactly where a lane
runs. They now sit on the frontage concrete beside the road, which is where a car
outside a shop would actually be and which no lane crosses.

---

## The three service counters

`business_services.gd` builds one panel and dresses it three ways. They are the
same counter with the same layout doing three different jobs, and building them
as three screens would be three screens to maintain and one interface to
unlearn.

| Service | Mark | Accent |
|---|---|---|
| Supply Store | a fuel drop | mower orange |
| Business Office | a folded map | forest green |
| Mower Workshop | mown stripes | muted sage |

The panel is **paper**. Each of the three is a transaction the business is doing
— a fuel receipt, a work order for an upgrade, a page of the books — and the
rest of the game draws its paperwork on cream. The body is still composed with
the shared slate palette and moved on to paper in one pass by
`UITheme.repaint_to_paper()`, rather than making three build functions each
remember to.

---

## KNOWN ISSUES

- The wide concrete between the two streets reads as a town plaza rather than as
  back yards. It is intentional-looking and was left alone.
- `road_corner.gltf` was copied into the project for a perimeter loop that was
  not built in the end. It is unused.
