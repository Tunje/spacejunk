# Performance Budget

Task A7. Sets the numbers that section 5 of `plan/workplan.md` left to a first measurement. `tests/sim/kernel/test_perf.gd` measures them, and prints them as `PERF` lines in the test log.

## 1. The load

The test runs the reference scenario plus 76 starter ships: 78 units and 1,015 modules, about 66 tasks at once. All load types run together, and idle units are given new orders as they finish:

- Ships on routes between rocks.
- Ships mining, with power and heat in use.
- Ships repeating scans.
- Docked pairs transferring propellant.
- One `view()` per tick, as the client calls it.

This is about 20 times the slice's real size, which is under 60 modules with the drone and upgrades.

## 2. First measurement

Godot 4.7.2 headless on the owner's PC, from the editor binary, with other agents running. A release export should be somewhat faster, but that has not been measured.

| Measure | Mean | 99th percentile | Worst |
| ------- | ---- | --------------- | ----- |
| `step` | 8.9 ms | 10.4 ms | 11.2 ms |
| `view` | 6.9 ms | 8.3 ms | 8.5 ms |
| Step and view | 15.8 ms | 17.5 ms | 19.7 ms |

Before the per-unit index, step and view took 46.6 ms at 963 modules.

## 3. Budget

| Budget | Limit at the load above | Why |
| ------ | ----------------------- | --- |
| Step and view, mean | 16 ms | One frame at 60 frames per second, so a tick costs at most one frame |
| Step and view, 99th percentile | 33 ms | Two frames, the worst acceptable hitch |

The tick rate of 10 per second stands. At this load a tick takes under a fifth of its 100 ms.

The mean sits on its limit today. At the slice's real size it has plenty of room, but a load this size would drop one frame per tick while rendering, so any growth past 1,000 modules needs the work in section 5 first.

## 4. What the test enforces

Timing on a shared machine is noisy, so the test does not fail at the budget itself. It fails at 50 ms mean or 100 ms at the 99th percentile, about three times the budget. That catches a real regression, such as an accidental walk over every part, without failing on a busy moment. Read the `PERF` lines to check the budget.

## 5. If the budget is exceeded

In order of cost:

1. Give `view()` a partial form for what is on screen. It is 44% of the total, and most of that is the part tree and cargo tables.
2. Let the client call `view()` less often than once per tick. It already interpolates.
3. Run units far from the player as aggregate rates, as the workplan plans for remote sites.
4. Move the hot loops to a GDExtension.

## 5a. With orbits (A17)

`tests/sim/kernel/test_perf_orbits.gd` runs the same 20-times-slice size around a planet. There are 76 starter ships in four frames on orbits 100 km apart, and a quarter of the ships do each kind of work:
- routes inside a frame;
- transfers between frames, waiting for windows and then flying;
- repeated small burns on orbits;
- coasting on orbits.

There is one `view()` per tick, and the scenario has a star, so the planet casts a shadow.

| Measure | Mean | 99th percentile |
| ------- | ---- | --------------- |
| `step` | 10.4 ms | 21.5 ms |
| `view` | 4.4 ms | 9.0 ms |
| Step and view | 14.9 ms | 30.8 ms |

That is inside the budget of section 3, though closer to it than the flat load's 8.4 ms. Two fixes were needed to get there:
- **A frame-join check computed velocities for every orbiting unit against every frame each tick.** It now tests the stored positions first.
- **The planet-shadow test normalised star-scale vectors per unit,** which takes `IntMath`'s slow wide distance. The casting bodies are now worked out once per tick, and once per view.

**Queries, which are not per-tick work:**
- `quote` with a window costs about 0.26 ms.
- `check` of `plan_burn` flies the whole burn, as orbital_flight.md 11.12 sets out, at about 0.2 ms per burn tick: 183 ms for a 923-tick burn. Call it when the player edits a burn, not every frame. Phase 1 validation of the same command skips the preview, so applying a burn costs nothing extra in the tick.
- A burning unit costs about 0.2 ms per tick while it burns.

**Time warp at the slice's real size:** the reference scenario with the ship on a trip and one `view()` every 8 ticks costs about 0.23 ms a tick. One core can therefore run about **440x** real time, far more than the 8x the client offers. At 20 times the slice, the same figure is about 7x, so very large fleets would need the coast-skip mode of orbital_flight.md section 11.3, which isn't planned.

## 6. Rules that keep this true

- Anything derived from a unit's fitted parts goes in `UnitIndex`, not a fresh walk of the part tree. Attach and detach clear a unit's entry, and it is never saved.
- Hot paths read a unit's entry once per unit, not once per part.
- Anything a unit tests against every frame or body each tick tests stored positions first, and does orbit maths only for the few that pass.
- Vectors at star scale, around 10^14 mm, take the slow wide path in `IntMath.dist`, so normalise them once per tick, never once per unit.
- `Sim.to_save` takes about 35 ms at this load, so saves are not per-tick work. Strict checks and `ledger()` are for tests only.
