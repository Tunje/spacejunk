# Simulation Contracts

Contract version: 4. Signed off by the Lead (task L7) after review by Agents A, C and D. Version 2 added the job queue (C9). Version 3 adds orbits and frames ([orbital_flight.md](orbital_flight.md) section 11, task A10). Version 4 makes jobs take work points, not time (C11). Version 5 adds research: science, theories, prototypes and variants (C12). Changes go through the Lead.

These contracts expand section 5 of `plan/workplan.md`. If the two disagree, raise it with the Lead.

## 1. Units and ranges

All simulation state is plain data: Dictionary, Array, 64-bit `int`, String and bool. Floats are never stored in state, and no float may feed a value written to state, except at data load.

| Quantity | Sim unit | Data file unit | Valid range |
| -------- | -------- | -------------- | ----------- |
| Matter | gram | kg | 0 to 10^15 per stack; 9 x 10^18 world total including sinks, checked at scenario load |
| Power and heat rate | watt | kW | 0 to 10^12 per module or network. Negative values appear only as derived net figures. |
| Energy | joule | kJ | 0 to 10^15 per store |
| Heat | joule | kJ | 0 to 10^15 per loop |
| Position | millimetre, per axis | mm | within +/-4 x 10^18 (about 0.42 light-years) |
| Volume | litre | m3 | 0 to 10^12 per store |
| Time | tick | whole seconds | 0 to 10^15 |
| Any per-second rate | sim unit per second | data unit per second | 0 to 10^12 |
| Angle (`_angle`) | binary angle, 2^48 to a turn | millidegrees (`_mdeg`) | 0 to 2^48 - 1 |
| Ratio or direction (`_q30`) | Q30, where 2^30 is 1.0 | parts per million (`_ppm`) for eccentricity | -2^31 to 2^31 |
| Speed and delta-v inside orbits (`_um_s`) | micrometre per second | m/s | -10^12 to 10^12 |
| Gravitational parameter (`gm`) | 1000 m³/s² | km³/s² (`gm_km3_s2`) | 0 to 9 x 10^18 |
| Orbit period (`_subticks`) | 1/65536 tick | none, derived | 1 to 2^55 |

Valid ranges are asserted at commit in test runs.

**Places.** Every body, frame and unit is in one place at a time ([orbital_flight.md](orbital_flight.md) section 11.1):
- **On an orbit:** `orbit` is an orbit record around the body `orbit.parent`, and `pos_mm` is relative to that parent, derived from the tick in phase 2.
- **In a frame:** `frame` is a frame's ID, and `pos_mm` is local to it. A frame is a co-moving region, such as the rock cluster, with an orbit and a `radius_mm`, and no gravity inside it. Travel inside one frame works exactly as networks.md section 6 says.
- **Neither:** `frame` is 0 and `orbit` is `{}`. This is the old world, in which nothing moves on its own. A scenario without frames is entirely here, and behaves as in contract version 2.
- **Landed** (from A15): `landed` is `{ body, cell }`, and `pos_mm` is the cell's centre relative to the body, at its integer height. A landed unit never moves, because planets don't rotate. A body's terrain comes from its `planet` settings, `{ seed, height_range_m, sea_level_m, weights }`, agreed with B, through `PlanetGrid`. `sea_level_m` is optional, and its absence means a dry world. `weights` defaults to [4, 2, 1]. A body without them is a smooth sphere.
- **Low flight** (from A19): `low_flight` is a body's ID, `pos_mm` is relative to its centre in its fixed frame, and `vel_um_s` is the only velocity. Gravity is applied every tick in integers. A unit on an orbit enters low flight below 20 km above the body's datum, which orbit records can't hold for near-vertical paths, and goes back to an orbit above 30 km. It meets the ground at the cell below's real height. At or under its touchdown limit it lands, and over it it crashes; either way it ends landed on that cell. The limit is the highest `landing_gear.max_touchdown_mm_s` of its healthy parts, and 0 with none.
- A docked unit is wherever its host is, and its own `frame` and `orbit` are not read.

An orbit record holds `parent`, `a_mm`, `b_mm`, `e_q30`, `p_q30` and `q_q30` (the directions towards periapsis and 90 degrees ahead), `period_subticks`, `m0_angle` and `epoch_tick`. A hyperbolic record (from A12) has `hyperbolic = true`, with `a_mm` as its positive semi-axis, `m0_rad` (mean anomaly in Q30 radians, which does not wrap) and `motion_q60` (mean motion in radians per tick, Q60) in place of `period_subticks` and `m0_angle`.

**Spheres of influence** (from A12). A body on an orbit with gravity has `soi_mm` = a (GM / GM of its parent)^(2/5), worked out at scenario load, and 0 if it has none. A unit on an orbit changes `orbit.parent` in phase 5 of the first tick it is past its parent's `soi_mm`, going up to the parent's parent, or inside a child body's, going down. Its orbit is re-expressed around the new parent from its position and velocity, and `soi_changed` fires. `OrbitMath` (sim/kernel/orbit_math.gd) is the only code that interprets it. The reference plane's normal is +Y, so a planet's north pole and an uninclined orbit's angular momentum point along +Y.

**Coordinates.** Simulation axes match Godot: right-handed, +Y up. Connector and collision positions are relative to the module origin. Orientation is not simulation state: the client derives heading from the route, and places docked craft from connector geometry.

**Tick rate.** `Sim.TICKS_PER_SECOND` is one constant, proposed as 10. Data states rates per second, never per tick. Durations in data are whole seconds in the slice, so they convert exactly at any integer tick rate.

**Rounding.** Use one kernel helper. A per-tick amount is `(rate + remainder) / TICKS_PER_SECOND`, rounded down, and the leftover becomes the new remainder.
- A remainder is a rate accumulator in units of 1/TICKS_PER_SECOND. It is not matter or energy, and it is outside the ledgers.
- Keep one remainder per quantity per owner.
- If availability clamps an amount, the clamped part is dropped and the remainder is unchanged.
- Remainders persist through a pause and reset to 0 on finish, cancel or stop.
- The helper takes non-negative values only. Never use it on net figures.

**Power and energy.** Power is allocated in watts. The per-tick balance is checked exactly in watt-ticks: generated + discharged = consumed + charged + curtailed. Surplus with nowhere to go is curtailed, which is an explicit loss. Rounding to joules happens only at each store (battery, heat loop), with one remainder per store and direction. Heat flows sum across a loop before conversion.

**Overflow.** GDScript wraps silently. Any product of ranged values uses `IntMath.mul_div(a, b, d)`: non-negative, floored, with a 128-bit intermediate. Distance uses `IntMath.dist(a, b)`, which is floored and exact. Never square a position difference directly. A diagonal at the extreme of all three axes does not fit in 64 bits, so `dist` reports an error and returns the maximum integer. This is accepted, since no real star system is near that range.

**Loading.** The loader converts data units to sim units with `roundi(value * factor)`, and rejects a value if the difference exceeds 1e-9 relative. Item volume per mass rounds up, so 1 g never occupies 0 litres.

## 2. IDs

- Definition IDs are lowercase strings from `data/`, such as `mining_laser_mk1`. Items and modules share one namespace. Unit templates have their own, and a unit's `def` is its template ID.
- Runtime entity IDs are positive integers from one counter in the state, starting at 1 and never reused. It covers units, parts, tasks, jobs, bodies and deposits.
- Commands have their own saved counter.
- Ships, stations and drones are all units, distinguished by `kind`.
- Systems process entities in ascending ID order. Never iterate a Dictionary without sorting its keys.

## 3. Public API

The client and the bot use only this interface, on `sim/kernel/sim.gd`.

```gdscript
class_name Sim extends RefCounted

static func new_game(scenario_id: String, seed_value: int) -> Sim   # null on failure
static func from_save(save_text: String) -> Sim                     # null on failure
static func last_error() -> String   # corrupt, version_mismatch, data_mismatch, unknown_scenario

func submit(command: Dictionary) -> int      # queues for the next tick, returns command ID
func check(command: Dictionary) -> Dictionary  # side-effect-free validation
func step(tick_count: int = 1) -> void
func current_tick() -> int
func view() -> Dictionary                    # read-only copy of state; see section 7
func defs() -> Dictionary                    # read-only definitions in sim units
func take_events() -> Array[Dictionary]      # events since the last call, oldest first
func to_save() -> String                     # canonical form; see section 8
func state_hash() -> String                  # SHA-256 of to_save()
func ledger() -> Dictionary                  # tests only; see section 9
func predict(unit: int, from_tick: int, ticks: int, step: int) -> Dictionary  # path for drawing
func quote(unit: int, target: int, from_tick: int) -> Dictionary      # a move_to's trip and window
func next_window(unit: int, target: int, from_tick: int, cap_g: int) -> Dictionary
```

Rules:
- Only `submit` changes the simulation. The client must not hold references into simulation objects.
- All calls run on one thread, outside `step`.
- `current_tick()` is the number of completed ticks and is 0 in a new game. `step` runs tick `current_tick() + 1`. `step` with `tick_count < 1` does nothing.
- `submit` deep-copies its argument and stamps `current_tick() + 1`. A float in a command is rejected in phase 1.
- `check` runs phase 1 validation without effects and returns `{ ok, reason, detail }`. For `attach_part` and `detach_part`, `detail` gives projected mass, power and heat against limits. For `move_to`, it gives ticks and propellant. It is advisory: `submit` can still be rejected if the state changes.
- `check` of `plan_burn` previews the burn. On an orbit it flies the burn tick by tick from its tick, through the same steps as the real burn and assuming the thruster has power throughout, so `orbit`, `propellant_g` and `burn_ticks` are what the burn will give. A burn of over 20,000 ticks, or one in a frame, is previewed as one impulse, and an impulse preview on an orbit carries `approximate = true`. `detail` is `{ dv_um_s, propellant_g, burn_ticks, orbit, vel_um_s, leaves_frame }`:
  - `orbit` is the orbit record after the burn, with `parent`, or `{}` if the unit isn't on an orbit or would escape.
  - `vel_um_s` is the local velocity after the burn, for a unit in a frame.
  - `leaves_frame` is true for any drift in a frame.
- `predict(unit, from_tick, ticks, step) -> Dictionary` gives `{ place, points }` along the unit's current path, ignoring planned burns. It is read-only, like `view()`.
  - `place` is `{ orbit_parent }` or `{ frame }`.
  - `points` are in that place's coordinates, from `from_tick` every `step` ticks up to `from_tick + ticks`.
  - It returns `{}` for an unknown unit, or for 10,000 points or more.
  - In low flight it integrates gravity exactly as the simulation does. `place` is `{ low_flight }`, and it adds `contact`, `{ tick, cell, speed_um_s }` where the path meets the ground, or `{}`. It costs one integration step per tick asked for.
  - A docked unit predicts as its host.
- `quote(unit, target, from_tick) -> Dictionary` gives the trip a `move_to` would take, leaving at the first chance at or after `from_tick`. It is read-only, like `view()`. The result is `{ kind, target, depart_tick, arrive_tick, ticks, cost_g }`, or `{ reason }`:
  - `kind` is `"route"` for today's straight-line trip inside one frame or the old world. It leaves at `from_tick` and also carries the route's `from_mm`, `to_mm`, `length_mm` and `speed_mm_s`.
  - `kind` is `"transfer"` for an autopilot trip between places (orbital_flight.md section 11.12). It leaves at its next window and also carries `dv_um_s`.
  - `arrive_tick` is the tick `arrived` fires, `depart_tick + ticks - 1`.
- `next_window(unit, target, from_tick, cap_g) -> Dictionary` gives the same as `quote` if it costs at most `cap_g`, otherwise `{ reason: "no_window" }`.
- Sim code prices a leg the unit hasn't reached yet, such as a cycle's lap gate, with `Travel.quote_leg(ctx, unit, from_place, target, mass_g, from_tick)`. That gives the same dictionary, from the place of a body or unit at a given mass.
- `defs()` returns `{ modules, items, recipes, templates, sinks, theories, science, bench_test }`, each keyed by definition ID except the single `bench_test`, including connectors, collision and visual, so clients never parse data units. Fields are renamed to their sim unit: `mass_kg` to `mass_g`, `power_kw` to `power_w`, `heat_kw` to `heat_w`, `volume_m3` to `volume_l`, `load_limit_kg` to `load_limit_g`, `density_kg_m3` to `density_g_l`, `seconds` to `ticks` (except on recipes, which have `work` instead), and likewise for any other unit-suffixed field (`docs/design/schemas.md` section 2).
  - An idea's `deltas` keep their parts-per-million values unscaled; only each path's last field is renamed, so `capabilities.battery.capacity_kj` becomes `capabilities.battery.capacity_j`. A delta naming a field that is missing or not whole in its module fails the load (C12).
  - `defs()` is the game's own definitions: the authored ones, plus the `prototype:<design>` items and recipes and `qualify:<design>` recipes of every theory-unlocked module, plus the module, items and recipes of each variant the game has designed. The derived entries are never saved, and the data hash covers the authored definitions only. A loaded game rebuilds its variants from `research.variants` before anything reads its definitions. A client refreshes its copy on `variant_designed`.
- Scenario `"empty"` is built into the kernel for tests that precede `data/`.
- The event queue is bounded (A1 sets the bound) and starts empty on load.
- The client drains events before calling `to_save`, because undrained events are not saved.

## 4. Tick order

Each tick runs these phases in order.

1. Apply commands stamped for this tick, in ascending command ID. Reject invalid ones.
2. Move everything on rails to this tick (`RailSystem`, registered first). Then update tasks and unit instructions.
3. Calculate available power on each network.
4. Determine active operations and allocate power by priority. Move the inputs of starting jobs into the job, and reserve cargo space and ports.
5. Run propulsion, mining, scanning, transfers, docking and industry. Record deltas without touching inventories.
6. Apply deltas in ascending entity ID, including deposit depletion and job outputs. Update battery charge and heat.
7. Detect and clear damage, faults and shutdowns, and set them in the state.
8. Emit events and commit.

Rules:
- Within a phase, order follows the phase's list, then ascending entity ID.
- A system may read state from previous ticks and anything written earlier in this tick.
- Simulation systems never read events. Events are output only, and tasks react to state.
- `to_save` and `state_hash` run only between ticks.

**Faults.**
- A fault is set in phase 7 and takes effect from phase 1 of the next tick. Work completed in phase 5 of the fault tick stands.
- Commands aimed at a faulted module are rejected, except `cancel_job`, `move_job`, `stop`, `detach_part` and `set_priority`. The module gets no power or new work. Its running job pauses with inputs held.
- Limits fault only when strictly exceeded.
- Faults clear automatically in phase 7, with effect from the next tick. A heat fault clears when loop heat is at or below a declared clear level, which stops flapping. A0 defines the level.
- Shedding is not a fault. A shed job pauses and resumes when power returns.

## 5. Commands

Every command has this envelope. `submit` fills in `id` and `tick`.

```json
{ "id": 1, "tick": 120, "type": "start_mining", "unit": 7, "args": { "deposit": 12, "module": 9 } }
```

| Type | Args | Meaning |
| ---- | ---- | ------- |
| `scan` | `target` | Scan a body for deposits |
| `move_to` | `target` | Travel to an entity along a route. Inside the unit's frame, or in the old world, as today. A target on an orbit or in another frame is refused with `unsupported_orbit` until A13's planner, which waits for a window and flies an atomic transfer. |
| `dock` | `port`, `target_port` | Dock at a port |
| `undock` | none | Leave the current port |
| `load_cargo` | `from`, `item`, `grams` (optional) | Transfer into this unit |
| `unload_cargo` | `to`, `item`, `grams` (optional) | Transfer out of this unit |
| `start_mining` | `deposit`, `module` | Begin mining with a laser |
| `stop` | none | Stop the current operation |
| `start_job` | `facility`, `recipe`, `count` | Begin a recipe at a facility part |
| `cancel_job` | `job` | Cancel and return held matter. A queued job ends at once with nothing to return |
| `queue_job` | `facility`, `recipe`, `count` | Add a job to the end of the facility's queue. On an idle facility it is the same as `start_job` |
| `move_job` | `job`, `position` | Move a job to a position in its facility's queue |
| `attach_part` | `item`, `from`, `parent_part`, `parent_connector`, `part_connector` | Install a part |
| `copy_fit` | `source`, `from` | Fit this unit like `source`, with parts from `from` |
| `detach_part` | `part`, `to` | Remove a part and everything below it |
| `assign_core` | `core` | Set a core installed on this unit |
| `set_cycle` | `steps` | Set the repeating cycle for tier 2 |
| `set_priority` | `module`, `priority` | Change a module's power priority |

**Tasks.** Every long-running unit order is a task: scan, move, dock, undock, load, unload and mining. A single order is a one-step task, so tier 1 and tier 2 share one state machine and one owner rule.

**Transfers.** Omitting `grams` means all that fits, since a fixed cycle cannot name an amount in advance. Refuelling is `load_cargo` of the propellant item.

**Cycles.** `set_cycle` steps are `{ type, args }`, taken from a whitelist of the unit orders above.

**Uninstalled parts.** An uninstalled part is an inventory stack of an item with the same ID as its module. Items with `unit_mass_kg` move only in exact multiples, or the command is rejected with `not_whole_unit`. The simulation issues the part ID on attach.

**Attach and detach.**
- `from` is this unit or a unit docked to it. Attaching is instant in phase 1 in the slice.
- `detach_part` sends the part and everything below it to the `to` inventory, and is rejected if it does not fit.
- Detaching a port with something docked to it is rejected.
- Detaching a root part is rejected with `root_part`.
- Detaching a subtree containing a part with a job or active operation is rejected with `part_busy`.
- A detach that would leave a unit over its cargo capacity, counting reserved space, is rejected with `cargo_full`.

**Fitting.** `attach_part` checks against declared ratings, and `check` reports the same results.
- Mass: total against the root's `max_mass_kg`.
- Power: summed `power_kw` against generation plus battery maximum discharge.
- Heat: summed `heat_kw` against radiator rejection.
- Connectors: type, a `core` connector joining only another `core` connector, occupancy, and mass carried below the connector against `load_limit_kg`. Other sizes do not decide a join.

Running shortfalls are still handled by shedding and faults.

**Building units.** A recipe output may name a unit template. When the job finishes, the unit appears docked at a free port of the facility's unit, or failing that of the unit it is docked to, and takes that unit's place (frame, orbit or landed cell). The port is reserved in phase 4, and the job blocks with `no_free_port` if none is free. B4 checks that template part mass equals recipe input mass, and that the template holds a port.

**Jobs.** With `count` above 1, inputs are taken at the start of each run and `job_finished` fires per run.

**Work points.** A recipe has no set duration. A run needs the recipe's `work` points, and its facility does its `facility.work_per_tick` each tick it runs, so a slower facility takes longer at the same recipe. Full-size facilities do 100 a tick, and a recipe's `work` is its old `seconds` times 1000, so every recipe kept its duration on them.
- A run sets the job's `work_left` to `work` when it starts in phase 4. Each phase 5 tick that the facility runs takes `work_per_tick` off it, floored at 0, and at 0 the run delivers in phase 6 of that tick. So a run takes `ceil(work / work_per_tick)` ticks. Work left over on the last tick is lost: nothing carries to the next run or job.
- A shed or faulted facility does no work that tick. The run pauses with its inputs and `work_left` held, and resumes when power returns. A cancelled run loses its progress.
- A run that builds a unit claims its port on its last tick of work, when `work_left <= work_per_tick`.
- A running job draws `ceil(recipe power_w * work_per_tick / 100)`, so a run uses the same energy on any size of facility, and full-size facilities draw the recipe's figure.

**Job queue.**
- A facility holds up to 16 jobs in order, by `queue_pos`. The job at 0 is active and has the statuses of [autonomy.md](autonomy.md) section 9. The rest are `queued` at 1 to n, hold no matter and reserve nothing. Positions stay contiguous.
- When the active job ends, by finishing or by cancelling, the next job becomes active at once and can start its first run in the next phase 4. So the next job starts on the tick after the last one finishes, the same gap as between two runs of one job, and on the same tick when the active job is cancelled in phase 1.
- `queue_job` makes the same checks as `start_job`, except that a busy facility is not refused. It is refused with `queue_full` when the facility holds 16 jobs. `start_job` still gives `facility_busy` on a facility with any job.
- `move_job` is refused with `job_busy` for a job with a run in progress (`running`, `paused` or `cancelling`), because it holds matter. A run in progress is never overtaken, so the lowest position then is 1. An active job that is `waiting` can be moved back, and becomes `queued`. Positions outside the queue are clamped to it.
- `detach_part` counts queued jobs as jobs in the subtree.

**Copying a fit.** `copy_fit` installs parts from `from`, which is this unit or a unit docked to it, as for `attach_part`. `source` can be any other unit with the same root module. It is instant in phase 1.
- It is refused with `fit_mismatch` if the root modules differ, `invalid_target` if `source` is this unit, and `unknown_unit` or `not_docked` as for `attach_part`.
- The source's parts are taken in ascending part ID, which puts each parent before its children and repeats the order they were fitted in. A part already in place on the matching connector is kept. Every other part is an ordinary `attach_part`, validated and applied by the same rules, with no bypass. Refused parts are retried in more passes until a pass fits nothing. A part whose parent did not fit is not tried.
- One `fit_copied` event reports the result. There is no `attach_failed` per part. `missing` counts whole parts still needed beyond what `from` holds, and `refused` gives each unfitted source part with its reason, which is `parent_not_fitted` when its parent did not fit.
- Core assignment, priorities, cycles, cargo and dock state are not copied.
- `check` dry-runs the copy and returns `detail` as `{ attach, missing, refused }` counts.

| `plan_burn` | `tick`, `prograde_um_s`, `normal_um_s`, `radial_um_s` | Places a burn. It also works landed, where it is a lift-off into low flight, and in low flight. There prograde is the level part of the velocity, or east around +Y when still, and radial is straight up. `tick` must be after the current tick, so "burn now" is `current_tick() + 1`. At its tick (phase 2) the burn fixes its direction from the unit's orbit, or from its frame's orbit, or from fixed axes (+X, +Y, +Z) in the old world. It then delivers thrust / mass each tick from phase 5 until done. The burn's ID comes from the entity counter. Refused with `not_flying` when docked, `burn_in_past`, `module_missing` with no thruster that has `thrust_n` and `exhaust_mm_s`, or `malformed_command`. |
| `cancel_burn` | `burn` | Removes a planned burn, or ends a running one with `burn_short` reason `cancelled`. `invalid_target` if the unit has no such burn. |

A burn whose tick comes while the unit has another operation, a route or a task is dropped with `burn_short` reason `part_busy`. A burn crossing the narrow band of orbits just below escape speed, which an orbit record cannot hold, carries each tick's change forward until the sum is past it, so a finite burn flies through escape without stopping. An order that replaces `burning` ends the burn the same way. 

| Command | Arguments | Effect |
| ------- | --------- | ------ |
| `land` | `body`, `cell` | From an orbit around `body`, an atomic autopilot descent to the cell. It needs landing gear, as a hand-flown landing does, and is refused with `no_landing_gear` without it. Its cost is the burn down half an ellipse to the surface, plus killing the remaining speed with a gravity loss that grows as thrust over weight at the surface falls ([orbital_flight.md](orbital_flight.md) 11.20, A27), by the rocket equation. It is paid at the start, and the op `landing` lasts the half ellipse. Refused with `not_flying` when not on an orbit around that body, `invalid_target` for a cell outside the grid, `thrust_too_low`, `no_propellant`, `module_missing` or `part_busy`. |
| `take_off` | `altitude_mm` | From a landed place, the same in reverse (op `taking_off`), onto a circular orbit at that altitude through the cell's direction, moving east around +Y. Refused with `not_landed`, `malformed_command`, `thrust_too_low`, or `invalid_target` at or past the body's sphere of influence. |

A unit on an orbit whose position falls below its parent body's radius crashes. It comes down landed on the cell below, a running burn ends with `burn_short` reason `crashed`, a transfer ends, and `crashed` fires. Damage is not modelled yet. Landing doesn't yet check a cell's surface type or slope, which waits for planets.md's rule tables in `data/`.

New command types go through the Lead. C0 may refine autonomy commands, events, reason codes and task view fields without a separate change, and tells the Lead what changed.

- **Unit 0** in a command means the player rather than a unit. Only a command type its system lists in `unitless_commands()` may use it, such as `design_variant` (C12). Any other command with unit 0 is refused with `unknown_unit`, and events and refusals for a unitless command carry unit 0.

## 6. Events

```json
{ "tick": 120, "type": "deposit_found", "unit": 7, "data": { "deposit": 12 } }
```

Events are ordered by phase, then the event's `unit`, then emission order. Unit 0 means no unit, so those events come first in their phase.

| Type | Data |
| ---- | ---- |
| `command_rejected` | `command`, `reason`, `detail` |
| `attach_failed` | `command`, `item`, `reason`, `detail` |
| `task_started` | `task`, `command` |
| `task_finished` | `task` |
| `task_cancelled` | `task`, `reason` |
| `task_blocked`, `task_resumed` | `task`, `reason` |
| `task_cycle_done` | `task`, `cycle` |
| `scan_finished` | `target`, `deposits` |
| `deposit_found` | `deposit`, `item`, `grams` |
| `mining_stopped` | `deposit`, `grams`, `reason` |
| `arrived`, `docked`, `undocked` | `target` |
| `transfer_done` | `from`, `to`, `item`, `grams` (actual amount moved) |
| `job_started` | `job`, `command` |
| `job_finished`, `job_cancelled` | `job`, `recipe`, `facility` |
| `job_paused`, `job_resumed` | `job`, `reason` |
| `job_queued` | `job`, `command`, `position` |
| `job_moved` | `job`, `position` |
| `unit_created` | `unit`, `def`, `job` |
| `part_attached`, `part_detached` | `part` |
| `fit_copied` | `source`, `attached` (new part IDs), `missing` (`{ item: count }`), `refused` (list of `{ source_part, item, reason }`) |
| `power_shed` | `module`, `reason` |
| `power_restored` | `module` |
| `fault` | `module`, `reason` |
| `fault_cleared` | `module` |

Each failure emits exactly one event. Fitting failures emit `attach_failed`, and all other invalid commands emit `command_rejected`.

`reason` is a stable lowercase code, with display text held in the client. `detail` is an optional Dictionary of integers, such as `{ need_w, have_w }`, so the player sees numbers as well as a code.

Known reason codes: `over_mass_limit`, `over_power_budget`, `over_heat_budget`, `over_heat_limit`, `over_load_limit`, `connector_type_mismatch`, `connector_size_mismatch`, `connector_occupied`, `not_whole_unit`, `no_free_port`, `no_propellant`, `cargo_full`, `deposit_exhausted`, `root_part`, `part_busy`, `float_in_command`, `unknown_unit`, `unknown_part`, `invalid_target`, `unknown_command`, `malformed_command`, `queue_full`, `job_busy`, `fit_mismatch`, `parent_not_fitted`. Autonomy adds its own codes, job statuses and view fields in `docs/design/autonomy.md` sections 3, 8, 9 and 10. `connector_size_mismatch` means a `core` connector met a non-core one.

Orbit reason codes:
- `unsupported_orbit`: a `move_to` target that is on an orbit or in another frame, a burn whose result is exactly parabolic (which neither orbit form can hold, and which rounding makes vanishingly rare), and later the planner's limits.
- `burn_in_past`, `not_flying`, and `cancelled` (a burn's end only).
- `no_window`: from `next_window`, when the trip costs more than the cap.
- `not_landed`: a `take_off` from anywhere but the ground.
- `no_landing_gear`: an autopilot `land` by a unit with no healthy landing gear.
- `thrust_too_low`: a `land` or `take_off` whose thrust over weight at the body's surface is 1 or less, at the unit's mass then (A27).
- Dropped: `too_fast_to_join`, because a unit arriving too fast simply doesn't join, and the view shows it. `not_over_cell` is also dropped, because landing costs don't depend on where the orbit passes.

Orbit events:
- `burn_started { burn }`.
- `burn_done { burn, dv_um_s, propellant_g }`.
- `burn_short { burn, reason, dv_um_s, propellant_g }`, with reason `no_propellant`, `part_busy`, `module_missing`, `unsupported_orbit` or `cancelled`.
- `frame_left { frame }` and `frame_joined { frame }`.
- `soi_changed { from, to }`, with the old and new parent bodies.
- `landed { body, cell }` and `crashed { body, cell }`. After a touchdown from low flight both also carry `speed_um_s`. `took_off { body }` is the autopilot's.
- `low_flight_entered { body }` and `low_flight_left { body }`. A burn running at touchdown ends with `burn_short` reason `landed` or `crashed`.

## 7. State view

`view()` returns native GDScript values, not JSON. Entity-ID keys are `int`, all numbers are `int`, and positions are 3-element Arrays of `int`, never `Vector3i`, which is 32-bit.

This shape is frozen. Fields may be added, but changes or removals go through the Lead. The sample below is GDScript.

```gdscript
{
  tick = 120, seed = 12345,
  units = { 7: {
    def = "...", kind = "ship", name = "...", pos_mm = [0, 0, 0], at_target = 3,   # 0 means at nothing
    frame = 6, orbit = {}, world_mm = [0, 0, 0],   # a docked unit shows its host's frame
    landed = {},                                   # { body, cell } on the ground
    low_flight = 0, touchdown_mm_s = 0,            # body ID near its surface; landing-gear limit
    core = 21, core_tier = 1, task = 4,   # core 0 and tier 0 mean no core
    op = { type = "mining", target = 12, part = 9, start_tick = 100, end_tick = 0 },
    route = { target = 3, from_mm = [], to_mm = [], eta_tick = 180 },  # {} when not moving
    dock = { port = 9, target_unit = 2, target_port = 5 },             # {} when not docked
    parts = { id = 9, def = "...", parent_connector = "", connector = "", state = "on",
              fault = "", draw_w = 0, priority = 0, children = [] },
    inventory = { "hematite": 5000 },
    mass_g = 0,
    cargo = { "ore": { used_g = 0, cap_g = 0, used_l = 0, cap_l = 0 } },
    fit = { mass_g = 0, mass_limit_g = 0, power_budget_w = 0, power_rated_w = 0,
            heat_budget_w = 0, heat_rated_w = 0 },
    power = { supply_w = 0, in_shadow = false, demand_w = 0, stored_j = 0, capacity_j = 0, max_discharge_w = 0 },
    heat = { stored_j = 0, limit_j = 0, reject_w = 0, input_w = 0 },
  } },
  bodies = { 3: { kind = "asteroid", pos_mm = [], radius_mm = 0, visual_seed = 0, scanned = false,
                   frame = 0, orbit = {}, gm = 0, soi_mm = 0, world_mm = [] } },
  frames = { 6: { name = "...", radius_mm = 0, orbit = {}, pos_mm = [], world_mm = [] } },
  deposits = { 12: { body = 3, item = "hematite", remaining_g = 0, hardness = 0 } },
  jobs = { 30: { unit = 2, facility = 8, recipe = "...", count_left = 1, status = "running",
                 reason = "", start_tick = 0, queue_pos = 0, work_left = 0, work = 0,
                 work_per_tick = 0 } },
  tasks = {},
}
```

- `power.supply_w` is what the generators give this tick. Generators are solar, so it is 0 while `in_shadow`: a body with gravity stands between the unit and the star, by a cylinder test (from A16).
- `op.type`: `idle`, `moving`, `waiting`, `docking`, `undocking`, `loading`, `unloading`, `mining`, `scanning` or `burning`. A `move_to` between places is `waiting` until its window. Its op carries `depart_tick`, and `end_tick` is `depart_tick - 1`. Nothing is paid while waiting, and `stop` cancels it freely. From departure it is `moving`, with the unit's `transfer` set to `{ target, depart_tick, arrive_tick, legs }` and `route` left `{}`. A paid transfer is atomic and runs to arrival.
- A trip across a sphere of influence (from A18) is a chain of orbits. `transfer.legs` lists the legs still to come, each `{ orbit, from_tick }`, and the unit's `orbit` switches to each in turn in phase 2 of its tick. That is a Hohmann ellipse, then a hyperbola around the moon or planet, then a phasing orbit, or the reverse. A trip within one sphere has `legs = []`. A trip two levels apart (from A22), such as from a star orbit to a moon of its planet, is two such chains joined at a parking circle around the planet, six legs in all. Its approach to the moon may be an ellipse rather than a hyperbola.
- While waiting, the op keeps the trip it will fly as `plan`. It is the same dictionary `quote` gives, so a save mid-wait leaves on exactly the same legs. While `burning`, `part` is the thruster, which draws power and gives heat like any running load. A shed thruster gives no thrust that tick.
- A unit also shows `vel_um_s`, its local velocity in a frame. It shows `burns`, its planned burns in tick order as `{ id, tick, prograde_um_s, normal_um_s, radial_um_s }`. And it shows `burn`, the running burn as `{ id, dv_um_s, done_um_s, start_tick }`, or `{}`.
- A part's `state`: `on`, `shed` or `fault`.
- A job's `status`: `queued`, `waiting`, `running`, `paused` or `cancelling`. `queue_pos` is its place in its facility's queue, 0 for the active job. `work_left` is the current run's work still to do, 0 until a run starts. `work` is one run's total, from the recipe, and `work_per_tick` is the facility's rate, so a client shows progress as `1 - work_left / work` and the time left as `ceil(work_left / work_per_tick)` ticks.
- Each unit has one inventory, keyed by item. Capacity is by cargo class, summed across its storage modules.
- `pos_mm` is in the object's own place (section 1): relative to its orbit's parent, local to its frame, or in the old world. `world_mm` adds up the chain to the root body, for drawing a system map. Floats are for drawing only: an orbit is drawn from its record with 64-bit floats as `position_float` in tests/sim/kernel/test_orbit_math.gd does, never Godot's 32-bit `Vector3`.
- Unfound deposits stay out of the view. Decorative asteroids are client-only, generated from `seed`; only targetable bodies appear here.

## 8. Canonical serialization

Save text comes from one kernel codec. `JSON.stringify` is not used for output.

- `int` is written as `"123"` and String as `"s:text"`. A float or object in state is a hard error.
- Maps are written as key/value pairs, sorted with integers numerically first, then strings by code point.
- Lists whose order has no meaning are sorted by ID before writing. Lists whose order has meaning, such as task steps, keep it.
- Parsing rejects out-of-range integers.
- Derived caches are not saved. `to_save(from_save(x)) == x`, byte for byte. The one exception is `pos_mm` of a body or frame on an orbit: it is a pure function of the stored orbit and the tick, recomputed in phase 2 of every tick, so saving it changes nothing.
- `state_hash` is the SHA-256 of that text. It is the only accepted way to compare states.

The save includes the contract version, `TICKS_PER_SECOND`, a hash of every definition the simulation reads after load (so not `visual` or scenarios, since a scenario is read once and its results are in the state), all RNG streams, all remainders, both ID counters, the pending command queue, `matter_start_g` and the running totals in `sinks`. The view may omit the last two.

The save excludes undrained events and the command log. Replay harnesses step to the tick before, then submit. A version or data mismatch makes `from_save` return null with a reason code. The contract version is checked before the state's shape, so a save from an older version is `version_mismatch`, not `corrupt`.

**RNG.** One named stream per system, saved as a map, so an extra draw in one system does not shift another. Restore uses `RandomNumberGenerator.state`.

## 9. Ledgers

`ledger()` is rebuilt each tick, is not saved, and is for tests only. It returns `{ tick, matter, energy, heat, science, violations }`, with the matter fields of `accounting.md` section 6 under `matter`, plus a `sinks` map of grams per sink, so tests can assert each sink separately. `science` is `{ points, earned, spent, held }`, where `held` sums the running lab jobs' `points_held`, and its check is earned = points + spent + held, with points and spent never below 0 (C12). Each check runs every tick in tests and fails on any difference.

Commit-time range checks match state by key name, so state fields keep their unit suffix (`_g`, `_w`, `_j`, `_l`, `_mm`, `_tick`, `_remainder`).

- **Matter:** the sum across deposits, inventories, running jobs, installed parts and sinks is unchanged.
- **Energy:** per network, in watt-ticks, generated + discharged = consumed + charged + curtailed.
- **Heat:** per loop, the change equals waste heat added minus heat rejected.

## 10. Data definitions

Task B3 owns the schemas. These fields are fixed here because other agents depend on them.

- **Modules:** `id`, `name`, `mass_kg`, `volume_m3`, `power_kw`, `heat_kw`, `priority`, `durability`, `min_ai_tier`, `realism`, `capabilities`, `fabrication`, `connectors`, `collision`, `visual`. `power_kw` and `heat_kw` are non-negative draw while active; generation is a capability. A higher `priority` sheds last.
- **Items:** `id`, `name`, `cargo_class`, `density_kg_m3`, and `unit_mass_kg` for discrete items.
- **Deposits:** item, grams, `hardness`.
- **Cargo classes:** `ore`, `goods`, `propellant`.
- **Capabilities:** the closed list in `docs/design/schemas.md` section 5.
- **`realism`:** `established`, `extrapolation`, `speculative` or `fictional`.
- **Connectors:** `id` (unique within a module), `type` (`stack`, `side`, `dock`), `size`, `pos_mm`, `facing`, `up`, `load_limit_kg`. `facing` and `up` are axis values (+/-x, +/-y, +/-z), written in the module's own frame. A child part is turned as it mates, so that in the craft's frame the connectors have opposite facings and equal ups. `load_limit_kg` is the mass carried below the connector.
- **Collision:** `{ shape, center_mm, size_mm }`, where `shape` is `box` or `cylinder`, with the cylinder axis along the module's Y. `size_mm` is full extents `[x, y, z]`; a cylinder's diameter is `x` and its height is `y`. Placeholders use the same shape. B3 may extend it.
- **Recipes:** `id`, `facility`, `work`, `power_kw`, `inputs`, `outputs`, `abstract`. `work` is a whole number of work points, at least 1. Every facility capability has `work_per_tick`, a whole number of at least 1. An output may route straight to a declared sink, such as `slag_vent`, instead of an inventory. B3 defines how.
- `visual` is read by the client only. The simulation never reads it.

## 11. Client rules

- The client bridge steps at the fixed tick rate. Pause and speed controls change how many steps run, never the simulation's behaviour.
- The client interpolates between views for display, subtracting integer positions relative to the camera focus before converting to float.
- Until the kernel lands, the client uses a stub with this same API at `client/stub/stub_sim.gd`, with fixtures in `client/stub/data/`.
- A shape test in `tests/client/` runs against the stub now and the real `Sim` once A1 lands.

## 12. Left to owners

- **A0:** shed tie-breaks within a class, flapping, which modules fault on a shared heat loop, battery order, efficiencies as integer ratios, and the heat clear level.
- **B3, B7, C4:** discrete item rules beyond section 5.
- **C0:** task states, reservations, port contention, and returning cancelled inputs when storage is full.
- **A7:** the perf budget includes one `view()` call per tick at slice load.
