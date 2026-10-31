# Network and Cargo Spec

Task A0. Expands section 5 of `plan/workplan.md` and settles the A0 items in section 12 of `contracts.md`. The contracts win if the two disagree. A4, A5 and A6 build from this page.

## 1. Fixed constants

All are kernel constants, so tuning them touches no content.

| Constant | Value | Meaning |
| -------- | ----- | ------- |
| `SHED_HOLD_SECONDS` | 5 | Minimum time a shed load stays off |
| `HEAT_CLEAR_PPM` | 800000 | Heat faults clear at 80% of the loop limit |
| `PPM` | 1000000 | Denominator of every integer ratio |

Every ratio in the simulation is an integer in parts per million, applied with `IntMath.mul_div(value, ratio_ppm, PPM)`.

## 2. Capabilities this spec reads

Section 10 of the contracts lists `scan`, `mine`, `ai_core.tier`, `storage` and `max_mass_kg`. These are requests to B3 to add alongside them.

| Capability | Fields | Notes |
| ---------- | ------ | ----- |
| `generate` | `power_kw` | Fixed output while healthy |
| `battery` | `capacity_kj`, `max_charge_kw`, `max_discharge_kw`, `charge_efficiency_ppm` | Efficiency may be 1000000 |
| `radiator` | `reject_kw` | Fixed rejection while healthy |
| `heat_capacity` | `limit_kj` | Summed across a unit to give the loop limit |
| `port` | `transfer_kg_per_s`, `dock_seconds`, `undock_seconds` | On every `dock` connector's module |
| `thruster` | `speed_m_s`, `propellant_kg_per_s` | Constant speed in the slice |

A module without a `generate`, `battery` or `radiator` capability is only a load. `power_kw` and `heat_kw` apply while the module is running. A passive module declares 0 for both.

## 3. Power

One network per unit. Docking does not join networks.

**A load** is a part with `power_kw` above 0 that wants to run this tick: an active operation, a running job, or a module marked always-on by its capability. Each load has the part's current `priority`, which `set_priority` may have changed from the data default.

**Phase 3, available power.** Parts faulted before this tick contribute nothing.
- `supply_w` is the sum of `generate` output.
- For each battery, `discharge_cap_w = min(max_discharge_w, stored_j * TICKS_PER_SECOND - discharge_remainder)`, floored at 0. This keeps the phase 6 subtraction from ever needing a clamp.
- `budget_w = supply_w + ` the sum of `discharge_cap_w`.

**Phase 4, allocation.** Faulted parts are not loads.
1. Order loads by `priority` descending, then part ID ascending. This is the keep order.
2. Mark as held any load with `shed_until_tick` above the current tick.
3. Keep every load not held. Walk the keep order from the end, shedding until the kept total is at or below `budget_w`. Within a class, the highest part ID sheds first.
4. Walk the keep order from the start and re-admit any shed load that now fits, as long as it is not held. This stops one large load from blacking out smaller ones that would have fitted.

A load that stops running through this process sets `shed_until_tick = tick + SHED_HOLD_SECONDS * TICKS_PER_SECOND` and emits `power_shed` with reason `power_shortfall`. A load that was shed and runs again emits `power_restored`. Events fire on those transitions only, never once per tick. The hold is what stops flapping at the edge of a battery running out.

A part's `state` is `shed` while it is wanted but not running. A job on it pauses and keeps its inputs and progress.

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
- `input_w` is the sum of `heat_kw` across parts that ran this tick.
- `reject_w` is the sum of `radiator.reject_kw`.
- `added_j = Rate.amount(input_w, heat_in_remainder)`, and heat rises by that first.
- `rejected_j = min(stored_j, Rate.amount(reject_w, heat_out_remainder))`. A clamped amount is dropped, so radiators build no credit while the loop is cold.

**Phase 7, faults.** `limit_j` is the sum of `heat_capacity.limit_kj`. A unit with no `heat_capacity` has a limit of 0, so B4 should require one on every unit that makes heat.
- If `stored_j > limit_j`, walk the parts running this tick with `heat_kw` above 0, in the shed order of section 3. Fault each with `over_heat_limit` until the remaining `input_w` is at or below `reject_w`. This repeats on each tick the loop stays over its limit.
- If `reject_w` is 0, every heat-producing part faults, which is the correct failure for a unit with no radiator.
- Generators and radiators fault only if they declare `heat_kw`.
- When `stored_j <= mul_div(limit_j, HEAT_CLEAR_PPM, PPM)`, all of the unit's `over_heat_limit` faults clear together in phase 7. Clear level 80% stops flapping. The player can also recover by detaching or by leaving the loop to cool, with no repair command.

The fault takes effect from the next tick, as the contracts require.

**Ledger.** Per loop, `stored_j` after minus before equals `added_j - rejected_j`.

## 5. Cargo

**Capacity.** Each class's `cap_g` and `cap_l` sum across the unit's storage modules. `used_g` sums stacks of that class. `used_l` sums `ceil(grams / density_kg_m3)` per stack, recalculated from the stack's grams each time, never accumulated. A density in kg/m3 is the same number as g/L, so no other factor applies.

**Grams that fit.** For an item already holding `g` grams, the limit is the smaller of `cap_g - used_g` and `(cap_l - used_l + litres(g)) * density - g`, floored at 0. Discrete items round down to a multiple of `unit_mass_kg`.

**Reservation.** Phase 4 keeps one per-tick reservation table per unit and class, and the mining and transfer steps in phase 5 take space from it in ascending unit ID. Nothing can overfill even with several sources writing to one unit in one tick. The table is rebuilt each tick and is not saved. Longer reservations belong to C0.

**Transfers.** Requires a docked pair. The rate is the smaller of the two ports' `transfer_kg_per_s`. Each tick moves `Rate.amount`, clamped to what the source holds, the space left, and any requested `grams` still owed.
- Omitted `grams` means transfer until the source is empty or the destination is full.
- A discrete item keeps a `credit_g` on the task. Matter moves only when the credit reaches `unit_mass_kg`, so inventories never hold part of a unit. Credit is a rate accumulator, not matter, and is outside the ledger.
- The transfer ends when nothing more can move, with `transfer_done` giving the real amount. A destination that was already full at the start is `cargo_full`, and what happens next is C0's.
- A transfer needs no power in the slice.

## 6. Travel and docking

**Bodies and stations do not move in the slice**, so a route is fixed when it starts.

**Route.** `move_to` stores `from_mm`, `to_mm`, `length_mm = IntMath.dist(from_mm, to_mm)`, `progress_mm` and a remainder. Rejected while docked. Each running tick:
- Add `Rate.amount(speed_mm_s, remainder)` to `progress_mm`, clamped to `length_mm`.
- Each axis of `pos_mm` is `from + sign * mul_div(abs(to - from), progress_mm, length_mm)`.
- On reaching `length_mm`, `pos_mm` is exactly `to_mm`, and `arrived` fires.

Position always derives from progress, so rounding never accumulates and arrival is exact.

**Speed and burn.** `speed_mm_s` comes from the unit's fastest healthy thruster. That thruster is a load for the whole trip, and burns `Rate.amount(propellant_g_per_s, remainder)` from the unit's `propellant` stacks each tick into the `exhaust` sink, clamped to what is left. With no propellant, the thruster stops, the task blocks with `no_propellant` and the unit holds position. The same happens if the thruster is shed or faulted. Resuming continues the same route.

`check` reports `ticks = ceil(length_mm * TICKS_PER_SECOND / speed_mm_s)`, using `mul_div` and an add of `speed_mm_s - 1` for the ceiling, and propellant as `ticks` times the burn per tick, rounded up. Mass does not change speed or burn in the slice.

**Docking.** Requires both units at the same position, and both ports free. Docking runs for `dock_seconds` of the port on the moving unit, and undocking for its `undock_seconds`. Port reservations and contention are C0's. While docked, a unit keeps its own networks and takes the host's position.

**Matter.** Propellant leaves through `exhaust`, which is the only sink this spec adds. A transfer never holds matter in transit, because each tick's delta moves between two inventories in phase 6.
