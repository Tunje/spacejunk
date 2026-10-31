# Simulation Contracts

Contract version: 1. Signed off by the Lead (task L7) after review by Agents A, C and D. Changes go through the Lead.

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

Valid ranges are asserted at commit in test runs.

**Coordinates.** Simulation axes match Godot: right-handed, +Y up. Connector and collision positions are relative to the module origin. Orientation is not simulation state: the client derives heading from the route, and places docked craft from connector geometry.

**Tick rate.** `Sim.TICKS_PER_SECOND` is one constant, proposed as 10. Data states rates per second, never per tick. Durations in data are whole seconds in the slice, so they convert exactly at any integer tick rate.

**Rounding.** Use one kernel helper. A per-tick amount is `(rate + remainder) / TICKS_PER_SECOND`, rounded down, and the leftover becomes the new remainder.
- A remainder is a rate accumulator in units of 1/TICKS_PER_SECOND. It is not matter or energy, and it is outside the ledgers.
- Keep one remainder per quantity per owner.
- If availability clamps an amount, the clamped part is dropped and the remainder is unchanged.
- Remainders persist through a pause and reset to 0 on finish, cancel or stop.
- The helper takes non-negative values only. Never use it on net figures.

**Power and energy.** Power is allocated in watts. The per-tick balance is checked exactly in watt-ticks: generated + discharged = consumed + charged + curtailed. Surplus with nowhere to go is curtailed, which is an explicit loss. Rounding to joules happens only at each store (battery, heat loop), with one remainder per store and direction. Heat flows sum across a loop before conversion.

**Overflow.** GDScript wraps silently. Any product of ranged values uses `IntMath.mul_div(a, b, d)`: non-negative, floored, with a 128-bit intermediate. Distance uses `IntMath.dist(a, b)`, which is floored and exact. Never square a position difference directly.

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
```

Rules:
- Only `submit` changes the simulation. The client must not hold references into simulation objects.
- All calls run on one thread, outside `step`.
- `current_tick()` is the number of completed ticks and is 0 in a new game. `step` runs tick `current_tick() + 1`. `step` with `tick_count < 1` does nothing.
- `submit` deep-copies its argument and stamps `current_tick() + 1`. A float in a command is rejected in phase 1.
- `check` runs phase 1 validation without effects and returns `{ ok, reason, detail }`. For `attach_part` and `detach_part`, `detail` gives projected mass, power and heat against limits. For `move_to`, it gives ticks and propellant. It is advisory: `submit` can still be rejected if the state changes.
- `defs()` returns `{ modules, items, recipes, templates, sinks }`, each keyed by definition ID, including connectors, collision and visual, so clients never parse data units. Fields are renamed to their sim unit: `mass_kg` to `mass_g`, `power_kw` to `power_w`, `heat_kw` to `heat_w`, `volume_m3` to `volume_l`, `load_limit_kg` to `load_limit_g`, `density_kg_m3` to `density_g_l`, and likewise for any other unit-suffixed field.
- Scenario `"empty"` is built into the kernel for tests that precede `data/`.
- The event queue is bounded (A1 sets the bound) and starts empty on load.
- The client drains events before calling `to_save`, because undrained events are not saved.

## 4. Tick order

Each tick runs these phases in order.

1. Apply commands stamped for this tick, in ascending command ID. Reject invalid ones.
2. Update tasks and unit instructions.
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
- Commands aimed at a faulted module are rejected, except `cancel_job`, `stop`, `detach_part` and `set_priority`. The module gets no power or new work. Its running job pauses with inputs held.
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
| `move_to` | `target` | Travel to an entity along a route |
| `dock` | `port`, `target_port` | Dock at a port |
| `undock` | none | Leave the current port |
| `load_cargo` | `from`, `item`, `grams` (optional) | Transfer into this unit |
| `unload_cargo` | `to`, `item`, `grams` (optional) | Transfer out of this unit |
| `start_mining` | `deposit`, `module` | Begin mining with a laser |
| `stop` | none | Stop the current operation |
| `start_job` | `facility`, `recipe`, `count` | Begin a recipe at a facility part |
| `cancel_job` | `job` | Cancel and return held matter |
| `attach_part` | `item`, `from`, `parent_part`, `parent_connector`, `part_connector` | Install a part |
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
- Connectors: type, size, occupancy, and mass carried below the connector against `load_limit_kg`.

Running shortfalls are still handled by shedding and faults.

**Building units.** A recipe output may name a unit template. When the job finishes, the unit appears docked at a free port of the facility's station. The port is reserved in phase 4, and the job blocks with `no_free_port` if none is free. B4 checks that template part mass equals recipe input mass.

**Jobs.** With `count` above 1, inputs are taken at the start of each run and `job_finished` fires per run.

New command types go through the Lead. C0 may refine autonomy commands, events, reason codes and task view fields without a separate change, and tells the Lead what changed.

## 6. Events

```json
{ "tick": 120, "type": "deposit_found", "unit": 7, "data": { "deposit": 12 } }
```

Events are ordered by phase, then entity ID.

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
| `unit_created` | `unit`, `def`, `job` |
| `part_attached`, `part_detached` | `part` |
| `power_shed` | `module`, `reason` |
| `power_restored` | `module` |
| `fault` | `module`, `reason` |
| `fault_cleared` | `module` |

Each failure emits exactly one event. Fitting failures emit `attach_failed`, and all other invalid commands emit `command_rejected`.

`reason` is a stable lowercase code, with display text held in the client. `detail` is an optional Dictionary of integers, such as `{ need_w, have_w }`, so the player sees numbers as well as a code.

Known reason codes: `over_mass_limit`, `over_power_budget`, `over_heat_budget`, `over_heat_limit`, `over_load_limit`, `connector_type_mismatch`, `connector_size_mismatch`, `connector_occupied`, `not_whole_unit`, `no_free_port`, `no_propellant`, `cargo_full`, `deposit_exhausted`, `root_part`, `part_busy`, `float_in_command`, `unknown_unit`, `unknown_part`, `invalid_target`. Autonomy adds its own codes, job statuses and view fields in `docs/design/autonomy.md` sections 3, 8, 9 and 10.

## 7. State view

`view()` returns native GDScript values, not JSON. Entity-ID keys are `int`, all numbers are `int`, and positions are 3-element Arrays of `int`, never `Vector3i`, which is 32-bit.

This shape is frozen. Fields may be added, but changes or removals go through the Lead. The sample below is GDScript.

```gdscript
{
  tick = 120, seed = 12345,
  units = { 7: {
    def = "...", kind = "ship", name = "...", pos_mm = [0, 0, 0],
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
    power = { supply_w = 0, demand_w = 0, stored_j = 0, capacity_j = 0, max_discharge_w = 0 },
    heat = { stored_j = 0, limit_j = 0, reject_w = 0, input_w = 0 },
  } },
  bodies = { 3: { kind = "asteroid", pos_mm = [], radius_mm = 0, visual_seed = 0, scanned = false } },
  deposits = { 12: { body = 3, item = "hematite", remaining_g = 0, hardness = 0 } },
  jobs = { 30: { unit = 2, facility = 8, recipe = "...", count_left = 1, status = "running",
                 reason = "", start_tick = 0, end_tick = 0 } },
  tasks = {},
}
```

- `op.type`: `idle`, `moving`, `docking`, `undocking`, `loading`, `unloading`, `mining` or `scanning`.
- A part's `state`: `on`, `shed` or `fault`.
- Each unit has one inventory, keyed by item. Capacity is by cargo class, summed across its storage modules.
- Unfound deposits stay out of the view. Decorative asteroids are client-only, generated from `seed`; only targetable bodies appear here.

## 8. Canonical serialization

Save text comes from one kernel codec. `JSON.stringify` is not used for output.

- `int` is written as `"123"` and String as `"s:text"`. A float or object in state is a hard error.
- Maps are written as key/value pairs, sorted with integers numerically first, then strings by code point.
- Lists whose order has no meaning are sorted by ID before writing. Lists whose order has meaning, such as task steps, keep it.
- Parsing rejects out-of-range integers.
- Derived caches are not saved. `to_save(from_save(x)) == x`, byte for byte.
- `state_hash` is the SHA-256 of that text. It is the only accepted way to compare states.

The save includes the contract version, `TICKS_PER_SECOND`, a hash of the loaded data, all RNG streams, all remainders, both ID counters, the pending command queue, `matter_start_g` and the running totals in `sinks`. The view may omit the last two.

The save excludes undrained events and the command log. Replay harnesses step to the tick before, then submit. A version or data mismatch makes `from_save` return null with a reason code.

**RNG.** One named stream per system, saved as a map, so an extra draw in one system does not shift another. Restore uses `RandomNumberGenerator.state`.

## 9. Ledgers

`ledger()` is rebuilt each tick, is not saved, and is for tests only. Each check runs every tick in tests and fails on any difference.

- **Matter:** the sum across deposits, inventories, running jobs, installed parts and sinks is unchanged.
- **Energy:** per network, in watt-ticks, generated + discharged = consumed + charged + curtailed.
- **Heat:** per loop, the change equals waste heat added minus heat rejected.

## 10. Data definitions

Task B3 owns the schemas. These fields are fixed here because other agents depend on them.

- **Modules:** `id`, `name`, `mass_kg`, `volume_m3`, `power_kw`, `heat_kw`, `priority`, `durability`, `min_ai_tier`, `realism`, `capabilities`, `fabrication`, `connectors`, `collision`, `visual`. `power_kw` and `heat_kw` are non-negative draw while active; generation is a capability. A higher `priority` sheds last.
- **Items:** `id`, `name`, `cargo_class`, `density_kg_m3`, and `unit_mass_kg` for discrete items.
- **Deposits:** item, grams, `hardness`.
- **Cargo classes:** `ore`, `goods`, `propellant`.
- **Capabilities:** `scan`, `mine`, `ai_core.tier`, `storage` (capacity by class), `max_mass_kg`.
- **`realism`:** `established`, `extrapolation`, `speculative` or `fictional`.
- **Connectors:** `id` (unique within a module), `type` (`stack`, `side`, `dock`), `size`, `pos_mm`, `facing`, `up`, `load_limit_kg`. `facing` and `up` are axis values (+/-x, +/-y, +/-z). Mated connectors have opposite facings and equal ups. `load_limit_kg` is the mass carried below the connector.
- **Collision:** `{ shape, center_mm, size_mm }`, where `shape` is `box` or `cylinder`, with the cylinder axis along the module's Y. `size_mm` is full extents `[x, y, z]`; a cylinder's diameter is `x` and its height is `y`. Placeholders use the same shape. B3 may extend it.
- **Recipes:** `id`, `facility`, `seconds`, `power_kw`, `inputs`, `outputs`, `abstract`. An output may route straight to a declared sink, such as `slag_vent`, instead of an inventory. B3 defines how.
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
