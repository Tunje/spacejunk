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

## 6. Rules that keep this true

- Anything derived from a unit's fitted parts goes in `UnitIndex`, not a fresh walk of the part tree. Attach and detach clear a unit's entry, and it is never saved.
- Hot paths read a unit's entry once per unit, not once per part.
- `Sim.to_save` takes about 35 ms at this load, so saves are not per-tick work. Strict checks and `ledger()` are for tests only.
