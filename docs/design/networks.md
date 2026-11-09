# Network and Cargo Spec

Task A0. Expands section 5 of `plan/workplan.md` and settles the A0 items in section 12 of [contracts.md](contracts.md). The contracts win if the two disagree. A3 to A6 build from this page.

Field names below are sim units, as `defs()` gives them. Capability fields are defined in [schemas.md](schemas.md) section 5. Task behaviour is in [autonomy.md](autonomy.md), and matter movements are in [accounting.md](accounting.md).

## 1. Fixed constants

All are kernel constants, so tuning them touches no content.

| Constant | Value | Meaning |
| -------- | ----- | ------- |
| `SHED_HOLD_SECONDS` | 5 | Minimum time a shed load stays off |
| `HEAT_CLEAR_PPM` | 800000 | Heat faults clear at 80% of the loop limit |
| `PPM` | 1000000 | Denominator of every integer ratio |

Every ratio in the simulation is an integer in parts per million, applied with `IntMath.mul_div(value, ratio_ppm, PPM)`.

## 2. Loads

A load is a part that wants power this tick. A faulted part is never a load.

| Part | Is a load when | Draws |
| ---- | -------------- | ----- |
| Facility | It has a run in progress that is not still feeding, including a shed run or one paused by heat or a fault | A variable draw, `rate_w`, from the power left after the fixed loads (C30, section 3) |
| Part with an operation | Its operation is active or held | The module's `power_w` |
| AI core | It is the unit's assigned core | The module's `power_w` |
| `always_on` module | It is healthy | The module's `power_w` |
| Thruster | Never, including during a trip | Nothing |
| Anything else | Never. Idle modules demand no power. | Nothing |

A fitted but unassigned core demands nothing. The module's `power_w` is also its fit rating, which the fit check sums whether or not it ever runs. So a thruster's `power_w` and `heat_w` count only toward fitting budgets in the slice.

Each load has the part's current `priority`, which `set_priority` may have changed from the data default.

A part runs when it is a load and is not shed. Waste heat comes from the module's `heat_w` for every running part except a facility, whose heat is its job's: `rate_w × heat_j / energy_j` (C30).

## 3. Power

One network per unit. Docking does not join networks.

**Phase 3, available power.** Parts already faulted contribute nothing.
- `supply_w` is the sum of `generate.power_w`.
- For each battery, `discharge_cap_w = min(max_discharge_w, stored_j * TICKS_PER_SECOND - discharge_remainder)`, floored at 0. This keeps the phase 6 subtraction from ever needing a clamp.
- `budget_w = supply_w + ` the sum of `discharge_cap_w`.

**Phase 4, allocation.**
1. Order loads by `priority` descending, then part ID ascending. This is the keep order.
2. Mark as held any load with `shed_until_tick` above the current tick.
3. Keep every load not held. Walk the keep order from the end, shedding until the kept total is at or below `budget_w`. Within a class, the highest part ID sheds first.
4. Walk the keep order from the start and re-admit any shed load that now fits, as long as it is not held. This stops one large load from blacking out smaller ones that would have fitted.

Steps 1 to 4 are for the fixed loads, which are everything but facilities. Then, **variable loads (C30):** each facility with a load-making job, by `priority` descending and then part ID, takes `rate_w`, the lowest of what is left of `budget_w`, its heat limit and its throughput limit (contracts section 5). Its heat limit comes from the heat headroom: the healthy radiators' `reject_w`, less the `heat_w` of the kept fixed loads and `TICKS_PER_SECOND` watts for rounding, floored at 0, and shared in the same order. A held facility is given nothing. One given nothing while power is its limit is shed like any load. One held at 0 by heat alone is kept, with no draw.

A load that stops running through this process sets `shed_until_tick = tick + SHED_HOLD_SECONDS * TICKS_PER_SECOND` and emits `power_shed` with reason `no_power`. A load that was shed and runs again emits `power_restored`. Events fire on those transitions only, never once per tick. The hold is what stops flapping at the edge of a battery running out.

A part's `state` is `shed` while it is a load but not running. A job on it pauses and keeps its inputs and progress. A part that stops being a load returns to `on`, and keeps any `shed_until_tick` it has, so an order given during the hold is shed again at once.

**Flows.** `consumed_w` is the sum of running loads, and from there:
- `discharged_w = max(0, consumed_w - supply_w)`, drawn from batteries in ascending part ID, each up to its `discharge_cap_w`.
- `surplus_w = max(0, supply_w - consumed_w)`, offered to batteries in ascending part ID, each up to `min(max_charge_w, free_w)`. `free_w` is the battery's free joules times `TICKS_PER_SECOND`, less its charge remainder, floored at 0.
- `charged_w` is what the batteries accept, and `curtailed_w = surplus_w - charged_w`.

Batteries fill and empty in part order rather than sharing evenly. This is deterministic, needs no division, and the view reports only unit totals.

**Phase 6, stores.** For each battery:
- `stored_w = mul_div(charged_w, charge_efficiency_ppm, PPM)` and `conversion_loss_w = charged_w - stored_w`.
- Add `Rate.amount(stored_w, charge_remainder)` joules, and subtract `Rate.amount(discharged_w, discharge_remainder)` joules.

**Ledger.** Each tick, per unit, `generated + discharged = consumed + charged + curtailed`, in watt-ticks. Conversion loss sits inside the store, so `ledger()` also reports `charged_w = stored_w + conversion_loss_w` per battery. A shed or faulted load consumes nothing.

## 4. Heat

One loop per unit. Docking does not join loops.

**Phase 6.** Faulted parts contribute nothing.
- `input_w` is the sum of `heat_w` across parts that ran this tick, with each facility's job heat in place of its module's (C30).
- **Temperatures (A60, the Lead's rule).** A load's heat goes only to radiators at or below its temperature. A module's heat leaves at its `heat_temp_k`, and a radiator works at its `radiator.temp_k`, both 300 K when not given. The loads that ran are placed from coldest to hottest, ties by part ID. Each puts its heat into the healthy radiators at or below its temperature, hottest of those first, up to each one's `reject_w`. A hotter load may use every radiator a colder one may, so this places as much as the rule allows.
  - Heat that finds no radiator is stranded (`stranded_w`). It goes to the store, which counts as 300 K.
  - `reject_w` is the radiators that act on the loop: the heat placed this tick, plus the spare left on radiators at or below 300 K, which cool the store. A hot radiator's spare can't cool it.
  - With every load and radiator at 300 K, `reject_w` is the sum of `radiator.reject_w` and nothing strands, so the loop is as it was before A60.
- `added_j = Rate.amount(input_w, heat_in_remainder)`, and heat rises by that first.
- `rejected_j = min(stored_j, Rate.amount(reject_w, heat_out_remainder))`. A clamped amount is dropped, so radiators build no credit while the loop is cold.
- A job's heat is never stranded: PowerSystem offers each job, in keep order, only the spare on radiators at or below its facility's temperature, after the kept fixed loads are placed, and places what it takes there, hottest first (A60, C30).

**Phase 7, faults.** `limit_j` is the sum of `heat_capacity.limit_j`, which B4 requires on every unit that makes heat.
- If `stored_j > limit_j`, walk the parts that ran this tick with `heat_w` above 0, in reverse keep order. Fault each with `over_heat_limit` until the remaining `input_w` is at or below `reject_w`. This repeats on each tick the loop stays over its limit.
- If `reject_w` is 0, every heat-producing part faults, which is the correct failure for a unit with no radiator.
- When `stored_j <= mul_div(limit_j, HEAT_CLEAR_PPM, PPM)`, all of the unit's `over_heat_limit` faults clear together in phase 7. The gap down to 80% stops flapping. No repair command exists or is needed: the loop cools and the unit recovers.

The fault takes effect from the next tick, as the contracts require.

**Ledger.** Per loop, `stored_j` after minus before equals `added_j - rejected_j`.

## 5. Cargo

**Classes.** Each unit has one inventory, keyed by item, with capacity by the three classes in [spec.md](spec.md) section 7.4. `ore` and `propellant` come from storage on ships and drones, and `goods` only from `goods_storage_mk1`, so ships and drones never carry goods.

**Capacity.** Each class's `cap_g` and `cap_l` sum `storage` across the unit's fitted parts, faulted ones included. `used_g` sums stacks of that class. `used_l` sums `litres(g) = ceil(g / density_g_l)` per stack, recalculated from the stack's grams each time, never accumulated. Volume limits cargo stores only, never fitting.

**Grams that fit.** For an item holding `g` grams, the limit is the smaller of `cap_g - used_g` and `mul_div(cap_l - used_l + litres(g), density_g_l, 1) - g`, floored at 0. Discrete items round down to a multiple of `unit_mass_g`.

**Reservations.** Phase 4 holds one per-tick table per unit, rebuilt each tick and not saved. It holds destination space by class and source grams by item. Mining and transfer steps take from it in ascending unit ID in phase 5, so nothing can overfill, and nothing can spend grams a departure has already claimed. Space reserved across ticks for job outputs is C's ([autonomy.md](autonomy.md)), and counts as used here.

**Transfers.** Requires a docked pair. The rate is the smaller of the two ports' `transfer_g_per_s`. Each tick moves `Rate.amount`, clamped to what the source holds, the space left, and any requested `grams` still owed. The step's end conditions are in [autonomy.md](autonomy.md) section 4:
- **Loading never blocks.** It ends when `grams` have moved, the class is full, or the source runs out, with `transfer_done` giving the real amount. A shortage shows up later, such as `no_propellant` at the next `move_to`.
- **Unloading blocks with `cargo_full`** if the destination has no room and this unit still holds the item. It ends when `grams` have moved or this unit is out of the item.
- Omitted `grams` means all that fits.
- A discrete item accrues `credit_g` on the task, and matter moves only when the credit reaches `unit_mass_g`, so a stack never holds part of a unit. Credit is a rate accumulator, not matter, and is outside the ledger.
- A transfer needs no power in the slice.

## 6. Travel and docking

**Operation timing.** Every timed operation works the same way, so durations add up. An operation of N ticks starting on tick S is active on S to S + N - 1, and ends in phase 6 of S + N - 1, after that tick's deltas. Its own event (`arrived`, `docked`, `undocked`, `scan_finished`, `transfer_done`) fires on that tick. Phase 2 of S + N completes the step and starts the next one, so a step takes exactly N ticks from its start to the next step's start.

Transfers and mining test their end conditions in phase 6, after the tick's delta, so a store that fills exactly ends on that tick with no idle tick after it. A job run works the same way: started in phase 4 of S, it counts down in phase 5 from S and delivers on S + N - 1, so the next run starts on S + N.

**Nothing moves within a frame**, so a route is fixed when it starts. Everything here works in one frame's local coordinates, or in the old world of a scenario without frames (contracts.md section 1, Places). A frame itself moves on rails, carrying its members with it. A `move_to` target on an orbit or in another frame is refused with `unsupported_orbit` until the transfer planner (orbital_flight.md section 11, A13).

**Stand-off.** A unit never flies to a target's centre, which would put it inside an asteroid. It stops short by `STANDOFF_MM`, a kernel constant of 150000 (150 m), measured from the surface of a body (`radius_mm + STANDOFF_MM` from its centre) or from the position of a unit. `to_mm` is that stop point on the straight line from `from_mm` to the target, calculated with `IntMath`:

```text
total_mm = IntMath.dist(from_mm, target_mm)
stop_mm  = radius_mm + STANDOFF_MM, or STANDOFF_MM for a unit
to_mm    = from + sign * mul_div(abs(target - from), total_mm - stop_mm, total_mm), per axis
```

Each axis floors, so a unit can stop a millimetre or two outside `stop_mm`. Hand calculations must use these floored values, not rounded distances.

**Zero-length routes.** The route has zero length if `at(unit, target)` is already true, or if `total_mm <= stop_mm`. The `at` test comes first and ignores geometry, so repeating an order never pays for the rounding above. `to_mm` equals `from_mm`, and the unit stays where it is.

**At.** Each unit stores `at_target`, the entity ID it has arrived at, or 0. `arrived` sets it. Starting a route or a halt clears it, and also clears it on every undocked unit whose `at_target` is the unit that moved, so nothing stays at a target that has left. `undock` sets it to the host and places the unit `STANDOFF_MM` from the host along +X. `at(unit, target)` is true when `at_target` equals the target, and is never derived from geometry. A docked unit follows its host's position each tick and keeps `at_target` set to the host. A halted unit is at nothing. The function lives in the kernel, and `check`, validation and re-entry all share it.

**Thruster.** The fastest healthy thruster on the unit at departure, with the lowest part ID on a tie. Only that one is priced. Its speed is stored on the route, so nothing that happens to it later matters.

**Price.** With `length_mm = IntMath.dist(from_mm, to_mm)`, and `mass_g` the unit's whole mass at departure, including the propellant being paid:

```text
ticks   = mul_div_ceil(length_mm, TICKS_PER_SECOND, speed_mm_s)
base_g  = mul_div_ceil(ticks, propellant_g_per_s, TICKS_PER_SECOND)
cost_g  = mul_div_ceil(base_g, mass_g, rated_mass_g)
```

`IntMath.mul_div_ceil` is the rounded-up form of `mul_div`, added with A6. One function computes this, and `check` reports its `ticks` and `cost_g`, so the number shown is the number paid. A full hold costs more to fly. Speed does not depend on mass.

A zero-length route skips these formulas: `ticks` is 1 and `cost_g` is 0, and `check` reports those. It still goes through normal `move_to` validation, including the need for a healthy thruster, so there is one path and a unit with no thruster cannot arrive by order.

**Departure, on tick T.** Phase 1 validation and `check` compare `cost_g` with the unit's propellant. Phase 4 prices the trip again from current state, reserves `cost_g` on the stack, and sets the route. If the stack cannot pay in full, the trip does not start, and the task follows [autonomy.md](autonomy.md) section 7 for `no_propellant`. In phase 6 of the same tick the whole `cost_g` moves to `propellant_exhaust`. The reservation is what makes this safe, since nothing else can spend those grams in between.

**Route.** The route stores `from_mm`, `to_mm`, `length_mm`, `speed_mm_s`, `progress_mm`, a remainder and `eta_tick = T + ticks - 1`, the tick `arrived` fires. From tick T, each tick:
- Add `Rate.amount(speed_mm_s, remainder)` to `progress_mm`, clamped to `length_mm`.
- Each axis of `pos_mm` is `from + sign * mul_div(abs(to - from), progress_mm, length_mm)`. A zero-length route skips this step, because `length_mm` is 0.
- On reaching `length_mm`, `pos_mm` is exactly `to_mm`, and `arrived` fires. A zero-length route therefore arrives on tick T, and its step ends at phase 2 of T + 1.

The remainder carries, so the route takes exactly `ticks` of movement. Position always derives from progress, so rounding never accumulates and arrival is exact. Once paid, a route runs to arrival, unaffected by faults or power, and a trip under way cannot run out.

**Halt.** A player order or `stop` holds the unit at its current `pos_mm`, clears the route, and refunds nothing. A later `move_to` prices a new route from there.

**Docking.** Requires `at` the target unit, and both ports free. Docking runs for the `dock_ticks` of the port on the moving unit, and undocking for its `undock_ticks`. Both are atomic ([autonomy.md](autonomy.md) section 4). Port grants and contention are C's. While docked, a unit keeps its own networks.

**Matter.** Propellant leaves through `propellant_exhaust`. A transfer never holds matter in transit, because each tick's delta moves between two inventories in phase 6.

## 7. Connector geometry

A part's pose is derived from the part tree and is never saved. Facings and ups are axis values in the module's own frame, and a child turns as it mates, so one module fits any matching connector on a hull. The maths uses only signed-axis rotations, so it stays in integers.

- The root part has the identity rotation and sits at the unit's origin.
- A child's rotation `R` is the one rotation that maps its connector's `facing` to the opposite of the parent connector's `facing` in the craft's frame, and its `up` to that connector's `up`. It is found by mapping the three axes `facing`, `up` and `facing x up`. It always exists, because B4 requires `up` at right angles to `facing`.
- A child's origin is `parent_origin + R_parent * parent_connector.pos_mm - R * connector.pos_mm`.

Every non-root module has one `mount` connector at its origin, and mates through it. Further connectors on a module carry parts above it, or a dock. Whether two connectors may join depends only on type, whether either is size `core`, occupancy and load, never on rotation. The client uses the same rules to place parts and docked craft.
