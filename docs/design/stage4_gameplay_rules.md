# Gameplay rules on real orbits (draft, C33)

Status: **draft** for the Lead, Agent C, 2026-11-08, on `gameplay/C33`.

These are C's rules for A53's stage 4 ([real_orbits.md](real_orbits.md) section 6): cycles, mining and scanning on real ranges, and laps priced by flown quotes. They replace the "is at" flag (`at_target`) and the frame. The new-start route (C32) and the bot come after.

Built on:
- A54's relative state: `Sim.relative`, the range, closing speed and lateral speed between a unit and a target, exact in integers at any tick;
- A's stage 3 and 4 orders: flown plans, capture docking, anchoring;
- the Lead's inputs of 2026-11-08: instruments declare what each scan step reveals and the range it works at, and the LIDAR, spectrometer and magnesia wiring figures.

## 1. One reach test for every action

C adds **`Reach`** in `sim/industry/reach.gd`, a static helper. Every gameplay range check goes through it, so none of them holds its own geometry.

- `Reach.range_mm(ctx, unit, target)`: the distance from the unit to a body's centre or another unit, now.
  - A docked unit sits at its host plus its capture offset (real_orbits.md 3.4).
  - An anchored unit rides its rock.
  - The figure comes from A's internal relative state, the same code `Sim.relative` uses. **Ask A:** a static form of it for systems to call, as `RailSystem.world_mm` is.
- `Reach.surface_mm(ctx, unit, body)`: the range less the body's radius, floored at 0. This is for the miner's contact and the instruments' near steps.
- `Reach.speed_um_s(ctx, unit, target)`: the relative speed.
- `Reach.within(ctx, unit, target, limit_mm)`: true when the range is at or under the limit.
- `Reach.horizon(ctx, unit, target, limit_mm)`: the ticks before the range could cross the limit, either way, for coasting. It's a bound from the current gap and the largest relative speed the two can reach. **Ask A:** this is CoastBounds' kind of work, so A writes it or reviews it. Until then, a range-held op steps every tick.

## 2. Scanning in steps, each within its range

**Data, B's shape in schemas.md.** An instrument's `scan` capability lists its steps:

```
"scan": { "steps": [
  { "reveals": "shape", "range_m": 25000, "seconds": 30 }
] }                                                      // lidar_mk1
"scan": { "steps": [
  { "reveals": "class", "range_m": 10000, "seconds": 60 },
  { "reveals": "grade", "range_m": 1000,  "seconds": 600 }
] }                                                      // spectrometer_mk1
```

**What each step reveals:**

| Step | Reveals | Science |
| --- | --- | --- |
| `shape` | The body's size, shape and mass: `scanned_shape` on the body. Nothing about minerals | A share of today's survey |
| `class` | Each deposit's mineral: `found` with its `item`. Not how much | A share |
| `grade` | Each deposit's grams and hardness: `graded` | The rest. It is also today's `composition` measure, which this step replaces |

B splits today's 10 survey points across the three steps, and folds composition's 20 into `grade`.

**The order.** `scan { target, reveals? }`.
- With no `reveals`, it is the deepest step the unit can do now: the deepest any of its healthy instruments has, within that step's range.
- **Validation, in order:**
  - an instrument with that step: `module_missing`;
  - a body that is a scannable kind: `invalid_target`;
  - the range at or under the step's `range_m`: `out_of_range`, with `{ range_m, need_m }`.
- **Docked units can scan.** A craft on a station looks from its real place, so `docked` is no longer a refusal.

**Held for its time.**
- The step ends with `out_of_range` on the first tick the range goes over the limit. An interrupted scan starts again from nothing, as today.
- Coast: the op coasts to the lesser of its last tick and `Reach.horizon`.

**Mining needs the class.** `start_mining` needs the deposit `found`, that is, class known. The grade is the player's choice: they can mine blind, knowing only the mineral.

**In a cycle,** a scan of a step already done on that body passes in one tick, as C28 does now.

## 3. Mining anchored to the rock

**Data, B.** The mining capability gains `contact_range_m`, for example 5 m from the surface, and `contact_speed_m_s`, for example 0.1 m/s.

**`start_mining { deposit, grams? }`:**
- **Validation:** the existing checks, then:
  - `surface_mm` to the deposit's body at or under `contact_range_m`, or `too_far`;
  - relative speed at or under `contact_speed_m_s`, or `too_fast`.
  - Each comes with `{ range_m, need_m }` or `{ speed_m_s, need_m_s }`.
  - A docked unit is still refused with `docked`: a miner has to be on the rock.
- **Begin:** the unit **anchors**, with A's anchor (real_orbits.md section 6). From then it rides the rock at its contact point, off its own orbit. Event: `anchored { body }`.
- **End** (amount mined, hold full, deposit empty, fault, or cancel): the unit releases with A's small separation push, onto its own orbit beside the rock. Event: `released { body }`.
- **Coast:** an anchored unit is on rails with its rock, so mining coasts exactly as today.
- **Ask A:** the anchor state, `anchored = { body, offset_mm }`, with anchoring, release and its push. C calls them, as C30's feeds call `CargoSystem.dock_rate`.

**Deposits stay pools for now.** Giving a deposit a site on the rock, and the anchor a place on it, is C's realism item for after stage 4. `offset_mm` is ready for it.

## 4. Measuring

- **At an asteroid:** within the instrument's range, held for the measurement, with `out_of_range` as for scans.
- **Gravity field round a body:** one lap of the unit's own orbit round it.
  - A docked unit uses its host's orbit, so a probe docked to a station measures on the station's orbit. That keeps C18's "measure from where you are".
  - Any burn, or docking or undocking, changes the orbit and ends the measurement, by the existing `_moved_off` check on the orbit.
  - The frame branch goes.
- **Landed measures** don't change.

## 5. Cycles on places, not flags

**A step's placement** (`needs` and `leaves` in TaskStep) is a real test of the unit's state now. `_reenter` works it out once:

| Placement | True when |
| --- | --- |
| `docked: unit` | Latched to that unit, as now |
| `anchored: body` | Anchored to that rock |
| `near: target` | Within the step's own range of the target, undocked or docked |

Each step's `needs`:

| Step | Needs |
| --- | --- |
| `move_to` | Nothing: it flies from anywhere |
| `dock` | Not docked, and within the approach range of the target, from A's dock order. Otherwise re-entry walks back to the `move_to` before it |
| `undock` | Docked to the target |
| `start_mining` | Anchored to the deposit's rock, or within contact range |
| `scan`, `measure` | Within that step's range of the target |
| `load_cargo`, `unload_cargo` | Docked to the partner |

**`move_to` in a cycle** ends at A's standoff: braked near the target, never on top of it. The `dock` step after it does the approach and capture, as A's dock order does.
- A trip to a rock ends at the standoff. The `start_mining` step then needs the contact range, so **A's `move_to` to a rock takes an `arrive` mode**:
  - `standoff` for a dock or a scan;
  - `contact` for a miner, which ends anchored-ready on the surface.
- **Ask A** to name this.

## 6. Laps priced by flown quotes

**A leg starts only if the craft can fly the rest of the way.**
- Before a cycle's `move_to` starts, its leg is quoted by A's flown quote from the unit's real state.
- The legs after it are quoted too, each from where the one before ends, as a chain on a copy of the unit, up to the lap's refuel point:
  - its next `refuel` or propellant `load_cargo` step;
  - or the end of the lap, if it has none.
- **The step starts only if** the tank covers that total plus the cycle's reserve. Otherwise the task is `blocked` with `no_propellant`, and `{ need_g, have_g }` in the event.
- The craft is wherever the last leg left it: docked at the station, which is safe, or at a rock, which then needs the player.
- **Ask A:** a quote chain. Quote legs in order on one copy of the unit, each from the last one's arrival state. The rocks are on rails, so each later arrival is known.

**The reserve.** `set_cycle` takes an optional `reserve_g`, by default a tenth of the tank. B tunes the default.

**At `set_cycle`, warn, don't refuse,** as fitting does (C30):
- `check` and the `task_created` event carry `lap: { ticks, propellant_g, tank_g }` from one quoted lap;
- and a `lap_short` warning when one lap from a full tank couldn't be flown.

**The view.** The task view adds `lap_quote: { ticks, propellant_g, at_tick }`. It's refreshed at each lap start and each correction point, for D's ETA.

**Caching**, as A51 and A's section 4.2 do: a quote is kept until the unit's motion or the plan changes. A cycle costs one chain per leg start, not one per tick.

## 7. Refuelling a two-propellant tank

**Background.** Hydrolox is two items, `hydrogen` and `oxygen`, burned in the engine's mixture.
- A's rule (the Lead's message): a burn runs at the engine's mixture until either propellant runs out, and the excess sits unusable until it is rebalanced.
- A cycle that loads only one of them strands the drone.

**C adds a `refuel { from }` step.**
- It loads both propellants from a docked depot, in the amounts that fill the tank in the engine's mixture.
- It loads first what restores the ratio, then both together.
- It is a transfer like `load_cargo`, at the port rate, through the dock, with its own end test: the tank is full in ratio, or the depot can't give more.
- It also serves the player, as a one-click order.
- **Ask A:** which engine's mixture rules a craft with several engines; the first healthy thruster's is my guess. And whether the tank's own data fixes the ratio.

## 8. What changes for others

- **Contract,** through the Lead:
  - `scan` gains `reveals`;
  - new reasons `too_far`, `too_fast` and `lap_short`; `out_of_range` gets detail;
  - `docked` is no longer a scan refusal;
  - new events `anchored`, `released` and `scan_step_finished { target, reveals }`;
  - `set_cycle` gains `reserve_g` and the `lap` detail;
  - a new `refuel` order and cycle step;
  - the task view gains `lap_quote`;
  - `composition` folds into `grade`;
  - `at_target` and the `at` placement go.
- **A:**
  - the static relative state;
  - `Reach.horizon`'s bound;
  - anchoring, release and its push;
  - `move_to`'s arrive modes;
  - the quote chain;
  - the mixture rule for refuelling.
- **B:**
  - instrument steps, and `spectrometer_mk1` on the probe;
  - the miner's contact limits;
  - the survey and composition points split across the steps;
  - the default reserve.
- **D:**
  - scan steps in the scan panel;
  - `too_far`, `too_fast` and `lap_short` in text;
  - the lap quote for ETAs;
  - the anchored state drawn on the rock.
- **Tests, mine:**
  - scan, mining and measure tests move from frames to real orbits;
  - cycle re-entry tests use real places;
  - new tests for scan steps, anchoring, the lap gate, the quote chain and `refuel`;
  - C29's fleet fixture spawns drones on the station's orbit, which unblocks C29.

## 9. Order of work

1. **`Reach`** and the scan steps. They stand on A54's relative state, which is already on main, so this can start now, behind the old `at` test until stage 4 removes it.
2. **Measure** on the unit's own orbit, with the frame branch gone.
3. **Mining, anchored.** This waits on A's anchor.
4. **Cycle places, and `move_to`'s arrive modes.** This waits on A's stage 4 orders.
5. **The lap gate,** and `refuel`. These wait on A's quote chain and mixture.

Each is its own branch with its own gate. Steps 1 and 2 can start before stage 4.
