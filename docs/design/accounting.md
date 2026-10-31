# Resource Accounting

Status: draft for Lead approval (task B7). Changes after approval go through the Lead.

This expands "Resource accounting" in section 5 of [workplan.md](../../plan/workplan.md) and the matter ledger in section 9 of [contracts.md](contracts.md). It covers matter only. Energy and heat accounting belong to A0. Slice items, modules and sinks are defined in [spec.md](spec.md).

## 1. The rule

Every gram is in exactly one place at every commit. The sum of all places never changes after the scenario loads.

| Place | Counts | Held in |
| ----- | ------ | ------- |
| Deposit | `remaining_g`, found or not | The deposit |
| Inventory | Grams per item | The unit |
| Running job | Inputs of the run in progress, including a paused or blocked run | The job |
| Installed part | The module's mass, for every part including root parts and cores | The part tree |
| Sink | Grams per item per sink | The state |

Runs of a job that have not started hold nothing, because inputs are taken at the start of each run (contracts section 5).

These do not hold matter:

- **Deltas** recorded in phase 5. They are applied in phase 6, before the ledger is read.
- **Remainders.** They are rate accumulators, outside the ledger (contracts section 1).
- **Cargo reservations.** They hold space, not matter.
- **Bodies.** Only their deposits are matter. Asteroid rock around a deposit and decorative asteroids are not on the ledger.

Matter enters only at scenario load, as deposits, inventories and installed parts. No operation creates it afterwards.

## 2. Every movement

Each row moves the same number of grams out of one place and into another, in the phase shown. Nothing else may change a place.

| Operation | From | To | Phase |
| --------- | ---- | -- | ----- |
| Mining | Deposit | Unit inventory | 6 |
| Cargo transfer | Unit inventory | Unit inventory | 6 |
| Job start | Facility unit's inventory | Job | 4 |
| Job finish, item output | Job | Facility unit's inventory | 6 |
| Job finish, sink output | Job | Sink | 6 |
| Job finish, unit output | Job | Installed parts of the new unit | 6 |
| Job cancel | Job | Facility unit's inventory | 1 |
| Propellant burn | Unit inventory | `propellant_exhaust` | 6 |
| Attach | `from` unit's inventory | Installed part | 1 |
| Detach | Installed parts | `to` unit's inventory | 1 |

Rules for these movements:

**Mining and burning.** The amount per tick is the rate through the kernel helper, then clamped to what the source holds and, for mining, to free cargo space. Source and destination change by the clamped amount. A clamp drops the excess, which was never matter (contracts section 1).

**Job start is all or nothing.** All inputs of a run move together in phase 4, or none do and the job blocks with a reason. Output cargo space is reserved at the same moment, so a finishing run always has room. A sink output needs no space. A unit output reserves a port instead.

**Job finish is all or nothing.** All outputs of a run are delivered in one tick. A run never delivers part of its output, and the job's held grams reach zero on that tick.

**Pause and fault.** A shed or faulted job keeps its held inputs in place. Nothing moves until it resumes or is cancelled.

**Cancel.** Held inputs return unchanged to the facility unit. No partial output exists, and the output reservation is released. The space the inputs left may have been taken since, so C0 decides what happens when they do not fit (contracts section 12), within one limit: the matter stays on the job until it can go somewhere, and it is never destroyed.

**Attach.** The stack loses exactly one `unit_mass_kg` and the part gains exactly its `mass_kg`. Section 3 makes these equal.

**Detach.** The part and everything below it become one unit of their items each in the `to` inventory, in one phase. The whole detach is rejected if any of it does not fit, so a subtree is never split. Two further limits apply: see section 7, items 2 and 3.

**Destruction.** No slice operation destroys a unit or part. When that arrives, it needs its own sink.

## 3. Balance in data

The validator (B4) enforces these, so a balanced game cannot be authored wrong.

- **Recipe mass.** For every recipe, total input grams equal total output grams exactly, after conversion. Outputs include slag.
- **Slag is listed.** A refining recipe lists slag as an output with a declared sink route (B3 sets the field). No recipe may lose mass implicitly.
- **Abstract recipes.** Every slice recipe has `"abstract": true`: no reductants or reagents, and all output mass comes from the listed inputs.
- **Yield ceilings.** Refining outputs stay within the ceilings in spec section 7.1.
- **Module items.** A module's item has `unit_mass_kg` equal to the module's `mass_kg`.
- **Module recipes.** A recipe outputting a module has input mass equal to that module's mass.
- **Unit templates.** Part mass of a built template equals recipe input mass (contracts section 5). The drone's fitted core is not part of its template.
- **Discrete inputs.** A recipe's quantity of a discrete item is a whole multiple of its `unit_mass_kg`.
- **Sinks exist.** Every sink route names a declared sink.

## 4. Discrete items

A discrete item is a stack whose grams are a whole multiple of `unit_mass_kg`. This holds at every commit, and tests assert it.

- Commands naming an inexact amount are rejected with `not_whole_unit`.
- A transfer with `grams` omitted moves the largest whole multiple that fits.
- A rate-limited transfer accrues progress and moves one whole unit at a time, so a stack never holds part of a unit. No slice transfer reaches this, because ships and drones have no `goods` capacity, but the rule keeps the invariant unconditional.

## 5. Sinks

The slice has two sinks, declared in `data/`.

| Sink | Receives | From |
| ---- | -------- | ---- |
| `propellant_exhaust` | `propellant` | Thrusters |
| `slag_vent` | `slag` | Refining |

A sink keeps a running total per item, in the state and in the save. Matter never leaves a sink. Sink totals are bounded by the world total, not the per-stack limit (contracts section 1).

## 6. The ledger check

`ledger()` rebuilds totals from the state after commit, and is for tests only. Proposed shape:

```gdscript
{ start_g = 0, total_g = 0, deposits_g = 0, inventories_g = 0, jobs_g = 0, installed_g = 0, sinks_g = 0 }
```

`total_g` is the sum of the five places. The check fails if `total_g` differs from `start_g` on any tick, including the tick after a load. World total stays within 9 x 10^18 grams (checked at scenario load), so these sums fit in 64 bits.

Required tests, each owned by the agent building that operation:

| Test | Owner |
| ---- | ----- |
| The ledger check runs every tick of the reference scenario and all ten checks | C |
| The check fails when a deliberately unbalanced delta is injected, so a silent check cannot pass | A |
| Mining clamped by deposit and by cargo space, on one tick | C |
| Job started, paused, faulted and cancelled at each point of its run | C |
| `count` above 1, cancelled between runs and during one | C |
| Unit built, with the port reserved and with none free | C |
| Attach and detach of a subtree, including a rejected detach | A |
| Propellant burn to an empty tank | A |
| Save and load midway through a running job, with sinks non-zero | A |
| Discrete stacks stay whole multiples at every commit | A |

## 7. Open with the Lead

None of these block B3. This spec assumes the proposed answer.

| # | Issue | Proposed answer |
| - | ----- | --------------- |
| 1 | The ledger is not saved, but the check needs the starting total after a load, and sink totals must persist. Neither is named in contracts section 8 or the state view. | Add `matter_start_g` and `sinks` to the state and save. Both are additions. The view may omit them. |
| 2 | Inventory capacity is summed across a unit's storage modules. Detaching a storage module could leave a unit holding more than its capacity. | Reject the detach with `cargo_full`. |
| 3 | Nothing stops `detach_part` on a root part, which would leave a unit with no parts and nowhere for its inventory to be. | Reject it, with a new reason code `root_part`. |
