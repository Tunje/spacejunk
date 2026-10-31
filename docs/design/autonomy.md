# Autonomy Spec (C0)

Status: draft for Lead review. Built on contract version 1.

This spec defines tasks, reservations, failure reporting, resumption and the six interruptions. It covers the C0 items in section 12 of [contracts.md](contracts.md). The contracts win if the two disagree. C5 implements this spec and owns `sim/autonomy/`.

## 1. Rules in brief

- A unit runs at most one active task. The active task is `unit.task`.
- Single orders end when interrupted. Cycles block, then resume by themselves.
- Tier does not need its own interruption rules: tier 1 can only run orders, and tier 2 can also run a cycle.
- The player always wins. An order overrides a cycle, and the cycle resumes when the order ends. `stop` ends everything.
- Tasks react to state in phase 2, and read what last tick committed. They never read events.
- Autonomy uses no RNG.

## 2. Tiers

| `core_tier` | Unit orders | `set_cycle` |
| ----------- | ----------- | ----------- |
| 0 (no core) | Rejected with `no_core` | Rejected with `no_core` |
| 1 Basic | Accepted | Rejected with `tier_too_low` |
| 2 Assisted | Accepted | Accepted |

Unit orders are `scan`, `move_to`, `dock`, `undock`, `load_cargo`, `unload_cargo` and `start_mining`.

These need no core: `start_job`, `cancel_job`, `attach_part`, `detach_part`, `assign_core`, `set_priority` and `stop`. Jobs belong to facilities, not tasks (section 9).

An order is also rejected with `tier_too_low` if a module it uses has `min_ai_tier` above `core_tier`.

**Coreless units.** The new drone appears docked, with no core and an empty tank ([spec.md](spec.md) section 7.3). It takes `attach_part` with the station as `from`, then `assign_core`. Until then it can receive but not act: another unit's transfer may name it as `from` or `to`, because only the unit giving the order needs a core. It can be refuelled two ways:
- Before it has a core, the station runs `unload_cargo` with `to` set to the drone. The station has a Basic Core.
- Once it has a core, by its own `load_cargo`, which is how a cycle refuels.

The order of check 8 is: fit `assisted_core`, `assign_core`, then `set_cycle`. The cycle's first step loads propellant, so no separate refuel is needed.

**Core changes.**
- `assign_core` with `core` 0 clears the core.
- Clearing or detaching the assigned core cancels all the unit's tasks with `no_core`.
- Assigning a tier 1 core cancels a cycle with `tier_too_low`. A running order continues.
- An assigned core with part state `shed` or `fault` is offline. `core_tier` still shows its tier.

## 3. Tasks

A task has one owner, the unit that holds it. Task IDs come from the entity counter.

| Field | Meaning |
| ----- | ------- |
| `id`, `owner` | Task ID and owning unit |
| `kind` | `order` or `cycle` |
| `state` | `running` or `blocked` |
| `reason` | Block reason, `""` when running |
| `hold` | `true` if the block keeps the current operation paused in place |
| `steps` | List of `{ type, args }`, in order |
| `step` | Index of the current step |
| `cycle` | Laps completed, for a cycle |
| `since_tick` | Tick the current state began |
| `command` | Command that created the task |

A task that has ended leaves `tasks` at commit, so `tasks` holds only live tasks.

Two unit fields are added:
- `cycle_task` is the unit's cycle while an order overrides it, otherwise 0.
- `last_cycle` is the steps of the most recent cycle, kept after it ends. The client's resume button submits `set_cycle` with these. It is `[]` if the unit never had a cycle.

### State machine

```
             set_cycle or order
                     |
                     v
   finished <---- running <----> blocked
                     |              |
                     v              v
                 cancelled <--------+
```

| From | To | Trigger | Event |
| ---- | -- | ------- | ----- |
| new | `running` | Accepted in phase 1 | `task_started` |
| `running` | `blocked` | Cycle hits a condition in section 7 | `task_blocked` |
| `blocked` | `blocked` | The reason changes | `task_blocked` |
| `blocked` | `running` | The reason clears | `task_resumed`, with the reason that cleared |
| `running` | ended | Order's step is done | `task_finished` |
| `running`, `blocked` | ended | Order interrupted, `stop`, or replaced | `task_cancelled` |

A cycle never finishes. It ends only through `task_cancelled`. `task_cycle_done` fires when the last step of a lap ends.

If several block conditions hold, `reason` is the first of: `core_offline`, `module_fault`, `no_power`, `module_missing`, `no_propellant`, `deposit_exhausted`, `cargo_full`, `port_busy`, `no_safe_step`.

### Phase 2 order

Units run in ascending ID. For each unit with a task:

1. If the step's operation ended last tick, complete the step.
2. Check interruptions (section 7) on the task's current step.
3. If blocked, re-test the reason. Clear it if it no longer holds.
4. If running with no operation in progress, start the current step.

A unit advances at most one step per tick. A step that ends at phase 2 starts the next one in the same tick. A step with nothing to do ends at the next tick's phase 2, so a lap cannot spin within a tick.

## 4. Steps

Each order is one step, and a cycle is a list of them.

| Step | Placement needed | Uses | Done when | Interruptible |
| ---- | ---------------- | ---- | --------- | ------------- |
| `scan` | Undocked, at the body | A `scan` module | Scan time has passed | Yes. Restarts from the beginning, since a scan has no partial result. |
| `move_to` | Undocked | A thruster at departure | `arrived` | Only by the player |
| `dock` | Undocked, at the target port's unit | Both ports at start | `docked` | No |
| `undock` | Docked | The docked port at start | `undocked` | No |
| `load_cargo` | Docked to `from` | The docked port | `grams` moved, or this unit's class is full, or `from` is out of the item | Yes |
| `unload_cargo` | Docked to `to` | The docked port | `grams` moved, or this unit is out of the item | Yes |
| `start_mining` | Undocked, at the deposit's body | `module` | Cargo is full or the deposit is empty | Yes |

Rules:
- **Loading never blocks.** It takes what is available and moves on. A shortage shows up as `no_propellant` at the next `move_to`, which is a single failure in the place the player can act on.
- **Unloading blocks if the destination has no room** and this unit still holds the item, because a cycle that keeps its cargo cannot do useful work.
- **Dock and undock are atomic.** Once started they complete, even if a module faults or the task is cancelled. An order submitted during one is rejected with `busy_docking`. `stop` is accepted, and it cancels the task at once while the operation finishes alone.
- **`move_to` pays at departure.** Propellant is burned when the trip starts, so a trip under way cannot run out (see section 12). Faults and shed power do not stop it. A player order or `stop` halts the unit at its current position, with no refund.
- **Progress on a step** is kept through a hold. `moved_g` on the task counts an explicit `grams` amount, and resets on rewind.

### Validation

A shared function tests a step against current state and returns a reason or `""`. Three callers use it:
- Phase 1 rejects an order that fails, with `command_rejected`. The rejected order does not disturb the running task.
- `check` returns the same result.
- Phase 2 blocks a cycle step that fails.

Further rejection reasons are `out_of_range`, `docked`, `not_docked`, `unknown_deposit`, `port_busy`, `no_propellant` and `deposit_exhausted`. `out_of_range` covers any failure of the "at the body" placement.

## 5. Cycles

### Setting one

`set_cycle` replaces any existing cycle, and cancels any order, each with `player_order`. It is rejected with `bad_cycle`, and `detail.step` set to the failing index, unless all of these hold:
- It has 2 to 16 steps.
- All steps are in the whitelist: `move_to`, `dock`, `undock`, `load_cargo`, `unload_cargo`, `start_mining`.
- At least one step is `move_to`. This guarantees that each lap takes time.
- Each step's references exist, and each `deposit` is known.
- The cycle closes: walking the steps from step 0 and back to step 0, each step's placement follows from the one before.

For the closure walk, `move_to` leaves the unit at its target, `dock` leaves it docked, `undock` leaves it undocked at that unit, and other steps leave placement unchanged.

The cycle then starts through re-entry (below), with `step` at 0. So a unit can be handed a cycle from anywhere.

The spec's check 8 requires a propellant load in the cycle. That is a content rule for the bot and the player, and `set_cycle` does not enforce it.

### Example

The drone's cycle, with the station as unit 2:

```gdscript
[
  { type = "load_cargo",   args = { from = 2, item = "propellant" } },
  { type = "undock",       args = {} },
  { type = "move_to",      args = { target = 3 } },
  { type = "start_mining", args = { deposit = 12, module = 40 } },
  { type = "move_to",      args = { target = 2 } },
  { type = "dock",         args = { port = 41, target_port = 5 } },
  { type = "unload_cargo", args = { to = 2, item = "hematite" } },
]
```

### Last safe step

There are two ways back into a cycle, and each is the "last safe step" for its situation.

**Held.** If nothing moved the unit, it continues the same step with progress kept. Faults and shed power resume this way.

**Re-entry.** After an override, the unit may be anywhere. Start at the current step and walk backwards through the cycle, wrapping past step 0, until a step's placement is true. Resume there. If no step qualifies, block with `no_safe_step` and re-test each tick.

Re-entry looks only at placement. A resource problem at the chosen step blocks it in the normal way, and does not walk further back.

Every whitelisted step is safe to run twice, since each acts on the state it finds. An explicit `grams` amount may transfer again. Cycles should omit `grams` for that reason.

Examples, for the cycle above:

| Was on | Player left the unit | Re-enters at |
| ------ | -------------------- | ------------ |
| `start_mining` | At the same body | `start_mining` |
| `start_mining` | Halted in open space | The `move_to` before it |
| `unload_cargo` | Undocked, near the station | The `dock` before it |
| `unload_cargo` | Undocked, in open space | `move_to` the station |
| `move_to` the body | Docked at the station | `undock` |

### Lap gate

Before starting step 0 of a lap, the task checks that every deposit in the cycle has `remaining_g` above 0. If not, it blocks with `deposit_exhausted` at step 0. Without this, the drone would burn a round trip of finite propellant to learn the deposit is empty.

Tier 2 never picks a deposit or changes its steps ([spec.md](spec.md) section 5). Only the player can clear this block, with a new `set_cycle`.

## 6. Player commands

| Command | Unit has | Effect |
| ------- | -------- | ------ |
| Order | Nothing | Starts an order task |
| Order | An order | Old one cancelled with `player_order`, new one starts |
| Order | A cycle | Cycle blocks with `player_order` and clears its operation. New order starts. `unit.task` is the order and `cycle_task` the cycle. |
| Order | An overriding order and a cycle | Old order cancelled, new one starts, cycle stays suspended |
| `stop` | Any task | Every task on the unit is cancelled with `player_stop`, in ascending task ID. The operation clears. |
| `stop` | Nothing | Accepted, no effect, no event |
| `set_cycle` | Anything | See section 5 |

When the overriding order ends, however it ends, the cycle resumes through re-entry in the same phase 2. It emits `task_resumed` with `player_order`.

An order that fails during an override follows the normal order rules. The cycle then resumes and meets the same problem by its own rules.

A rejected command changes nothing, so a mistyped order does not disturb a cycle.

Attach and detach do not interrupt tasks directly. `detach_part` is rejected with `part_busy` if the subtree has an active operation, which includes one held by a block. A part that only a later step needs can still be detached. That step then gives `module_missing`. Reattaching does not clear this, because a reattached part gets a new ID. The player sets a new cycle.

## 7. Interruptions

An order ends and the unit waits for orders. A cycle blocks. The six named cases come first.

| Interruption | Detected from | Tier 1 order | Tier 2 cycle | Clears when |
| ------------ | ------------- | ------------ | ------------- | ----------- |
| Player order | Phase 1 | Replaced, `task_cancelled` `player_order` | Suspended, section 6 | The order ends. Re-entry. |
| Module fault | Used module has state `fault` | `task_cancelled` `module_fault` | Held, `module_fault` | State leaves `fault`. Same step. |
| Lost power | Used module has state `shed` | `task_cancelled` `no_power` | Held, `no_power` | State is `on`. Same step. |
| Full cargo, mining | No room for the tick's yield | `task_finished`, `mining_stopped` `cargo_full` | Step done, not a block | Not applicable |
| Full cargo, unloading | Destination has no room | `task_cancelled` `cargo_full` | Blocked, `cargo_full` | Room appears. Same step. |
| Exhausted deposit, while mining | `remaining_g` is 0 | `task_finished`, `mining_stopped` `deposit_exhausted` | Step done, so the load is hauled home | Not applicable |
| Exhausted deposit, at start | Validation or lap gate | Rejected | Blocked, `deposit_exhausted` | New `set_cycle` only |
| No propellant | `move_to` cannot cover the trip | Rejected | Blocked, `no_propellant` | Enough propellant is aboard. Same step. |

Other conditions:

| Condition | Tier 1 order | Tier 2 cycle | Clears when |
| --------- | ------------ | ------------- | ----------- |
| Core offline | `task_cancelled` `core_offline` | Held, `core_offline` | Core state is `on`. Same step. |
| Part missing | `task_cancelled` `module_missing` | Blocked, `module_missing` | New `set_cycle` only |
| Port busy | Rejected in phase 1. If it loses the phase 4 grant, `task_cancelled` `port_busy`. | Blocked, `port_busy` | Port granted. Same step. |

Notes:
- Mining and unloading filling up are the same event in cargo terms, but mining's job is to fill the hold, so it counts as success. For tier 1, a full hold is a finished order, and the player gives the next one.
- A held operation keeps its demand, so the power network can restore a shed module. Faulted modules get no power, as the contracts require.
- `scan`, `load_cargo`, `unload_cargo` and `start_mining` can be held. `move_to`, `dock` and `undock` have no held state, because of the section 4 rules.
- A blocked cycle at the end of a `move_to` or undock is simply waiting at its current position.
- A cycle stranded in space with `no_propellant` stays blocked. The slice accepts this: [spec.md](spec.md) says running out ends the run. It reports the reason, and does not stall silently.

### Timing

A fault set in phase 7 of tick T shows as `fault` at T. Commands aimed at it are rejected from T+1, and the task reacts in phase 2 of T+1, so `task_blocked` carries tick T+1. Work finished in phase 5 of T stands. Clearing follows the same pattern: `fault_cleared` at tick T, `task_resumed` at T+1.

`mining_stopped` is emitted in phase 2, when the task sees the operation has ended.

## 8. Reservations

Phase 4 makes all reservations. Each one has one holder and is released by that holder.

| Resource | Holder | Taken | Released |
| -------- | ------ | ----- | -------- |
| Port | Dock step | When granted | When the unit finishes undocking, or the docking fails to start |
| Port | Job building a unit | On the tick the run ends | When the new unit is docked there. It then holds the port as any docked unit. |
| Cargo space, transfer or mining | Operation | Each tick, for that tick's amount | At phase 6 |
| Cargo space, job output | Job | When a run starts, for all its outputs | When the run finishes or is cancelled |
| Deposit yield | Mining operation | Each tick in phase 5, in ascending unit ID, capped at `remaining_g` | At phase 6 |

Free space in a class is `cap - used - reserved`, for both mass and volume. `cargo` gains `reserved_g` and `reserved_l`.

Only a `dock` step or a unit-building job can hold a port before arrival, so `port_busy` means another unit has it, or it is reserved.

### Port contention

A dock step names one port and waits for that port. A unit-building job takes any free port.

Waiters are served in order of `since_tick`, then entity ID. A port going free goes to the earliest waiter. A waiter keeps its place in the queue if its block reason changes. First come, first served is used so three drones on one port cannot starve the highest ID.

A job claims a port only on the tick its run ends, not for the whole build. Otherwise a long build would close the port to the drones feeding the station.

## 9. Jobs

Jobs are not tasks. They belong to a facility part, have no owner task and need no core, so a station keeps refining while the cycle hauls.

| `status` | Meaning |
| -------- | ------- |
| `waiting` | No run in progress. Held back by `reason`. |
| `running` | A run is in progress |
| `paused` | A run is in progress, with its inputs held, and stopped by `reason` |
| `cancelling` | Cancelled, with inputs waiting for room to return |

| Condition | Status | `reason` | Clears when |
| --------- | ------ | -------- | ----------- |
| Inputs absent | `waiting` | `missing_inputs` | All inputs are present |
| No room for outputs | `waiting` | `output_full` | Room appears |
| Facility faulted | `paused` | `module_fault` | State leaves `fault` |
| Facility shed | `paused` | `no_power` | State is `on` |
| No port at run end | `paused` | `no_free_port` | A port is granted |

Rules:
- `start_job` does not check stock. It is rejected only with `facility_busy` if the facility has a job, or for an unknown recipe or wrong facility. A job can wait for ore that is still being hauled, so a large `count` is how a player sets up a production line.
- Each entry into `waiting` or `paused` emits `job_paused`, and each exit emits `job_resumed`. Moving to `running` for the first time emits `job_started`, and later runs emit nothing further.
- Work is counted in remaining ticks, held in the job. `end_tick` is recalculated on resume and is 0 while the job is not running.
- A job with `missing_inputs` can run forever. It costs nothing and is not an error.
- `detach_part` is rejected with `part_busy` if the subtree has a job, including a `cancelling` one. Cancel it first. Matter in a job must have a place to go.

### Cancelled inputs when storage is full

`cancel_job` releases the job's output reservation, then returns the current run's inputs to the facility's unit, all together. If they do not fit, the matter stays on the job ([accounting.md](accounting.md) section 2) and the job becomes `cancelling`, with `reason` `cargo_full`.

A `cancelling` job does no work and draws no power. It keeps the facility, so `start_job` there gives `facility_busy`. Phase 1 retries it each tick, after that tick's commands, in ascending job ID. `job_cancelled` fires when the inputs are delivered. A repeat `cancel_job` has no effect.

The player clears it by moving stock out of the class. Capacity is never exceeded.

## 10. Failure reporting

Each failure emits exactly one event (contracts section 6), and the view shows the same reason while it lasts.

| Situation | Event |
| --------- | ----- |
| Command fails validation | `command_rejected` |
| Fitting fails | `attach_failed` |
| Order interrupted | `task_cancelled` |
| Cycle interrupted | `task_blocked`, and `task_resumed` when clear |
| Job held | `job_paused`, and `job_resumed` when clear |

`task_blocked` fires once per reason, not per tick. Scan, mining and transfer events still fire when their operation ends, as a record of what was achieved. `transfer_done` gives the amount moved so far, including on an interrupted transfer. `detail` carries numbers where they exist, such as `{ need_g, have_g }` for `no_propellant`.

### Added reason codes

| Code | Used by |
| ---- | ------- |
| `player_order`, `player_stop` | Task cancelled or suspended by the player |
| `module_fault`, `module_missing`, `no_power` | Interruptions of tasks and jobs |
| `core_offline`, `no_core`, `tier_too_low` | Core problems |
| `port_busy`, `busy_docking` | Ports and atomic operations |
| `bad_cycle`, `no_safe_step` | Cycles |
| `out_of_range`, `docked`, `not_docked`, `unknown_deposit` | Step validation |
| `facility_busy`, `missing_inputs`, `output_full` | Jobs |

`part_busy` is defined in contracts section 5.

## 11. Save and determinism

All of this is ordinary state, and saves with no special handling: tasks, `moved_g`, reservations, `cycle_task`, `last_cycle` and job remaining ticks. The port queue is not stored. It is derived from `since_tick` and entity ID each tick.

The order of `steps` has meaning and is kept (contracts section 8).

A save taken while a task is blocked, overriding or mid-step must resume identically. C7 covers these cases.

## 12. Needed from other owners

**A0 and A6:**
1. Propellant for a trip is paid in full at departure and is priced from current mass, as `check` reports it. A route then runs to arrival, unaffected by faults or power.
2. A player order or `stop` halts a moving unit at its current position, with the route cleared.
3. One predicate for "at" a body or unit, shared by `check`, validation and re-entry. It has to be true after `arrived`.
4. A module with no active operation demands no power, and a held module keeps demanding it.

**B7:**
5. [accounting.md](accounting.md) section 2 says a unit output reserves its port at job start. Section 8 here reserves it on the tick the run ends, so a long build does not shut drones out. Update that sentence. The run then waits, with inputs held, as `paused` with `no_free_port`, and its delivery stays all or nothing.

**B5 and B8:**
6. The reference scenario's cycle has to pass section 5 closure, and needs to follow the section 2 refuelling route. The station's starting propellant must be fitted in `propellant_tank_mk1` units.

## 13. Test list for C5

Each row of the section 7 tables, for both tiers. Also:
- A rejected order leaves a running cycle untouched.
- Each row of the re-entry table.
- `set_cycle` from anywhere reaches the right step.
- `bad_cycle` for each rule, including a cycle that does not close.
- Lap gate blocks docked, with no propellant spent.
- Three drones on one port are served in arrival order.
- A build job does not hold a port until its run ends.
- A job cancelled with no room stays `cancelling`, then delivers once stock moves out, with the matter ledger exact throughout.
- Hold and resume keep remainders. Stop and cancel reset them.
- Save and load during each block state gives the same `state_hash` as an unbroken run.
- Check 8: `task_cycle_done` reaches N laps with no commands submitted after `set_cycle`.
