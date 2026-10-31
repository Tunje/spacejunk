# Simulation Contracts

Status: draft for review by Agents A, C and D (task L7). Changes after sign-off go through the Lead.

These contracts expand section 5 of `plan/workplan.md`. If the two disagree, raise it with the Lead.

## 1. Units and ranges

All simulation state is a 64-bit `int`. Floats are never stored in simulation state.

| Quantity | Sim unit | Data file unit | Valid range |
| -------- | -------- | -------------- | ----------- |
| Matter | gram | kg | 0 to 10^15 per stack |
| Power | watt | kW | -10^12 to 10^12 |
| Energy | joule | kWh or kJ, declared per field | 0 to 10^15 per store |
| Heat | joule | kJ | 0 to 10^15 per loop |
| Position | millimetre, per axis | m | within +/-9 x 10^18 |
| Volume | litre | m3 | 0 to 10^12 |
| Time | tick | seconds | 0 to 10^15 |

The tick rate is one constant, `Sim.TICKS_PER_SECOND`, proposed as 10. Data states rates per second, never per tick.

**Rounding.** A per-tick amount is `(rate + remainder) / TICKS_PER_SECOND`, rounded down, and the leftover is stored as the new remainder in that job's or module's state. Use one shared kernel helper for this; do not write the calculation locally. Rates stay non-negative in this helper, so rounding down never needs a negative case.

**Overflow.** Multiply before dividing only where the range table shows the product fits. Tests cover each such calculation at its limits.

**Loading.** The loader converts data units to sim units. The validator rejects any value that does not convert to an exact integer.

## 2. IDs

- Definition IDs are lowercase strings from `data/`, such as `mining_laser_mk1`.
- Runtime entity IDs are positive integers issued by a counter in the state, starting at 1 and never reused.
- Systems process entities in ascending ID order. Never iterate a Dictionary without sorting its keys.

## 3. Public API

The client and the bot use only this interface, on `sim/kernel/sim.gd`.

```gdscript
class_name Sim extends RefCounted

static func new_game(scenario_id: String, seed_value: int) -> Sim
static func from_save(save_text: String) -> Sim

func submit(command: Dictionary) -> int      # queues for the next tick, returns command ID
func step(tick_count: int = 1) -> void
func current_tick() -> int
func view() -> Dictionary                    # read-only copy of state; see section 7
func take_events() -> Array[Dictionary]      # events since the last call, oldest first
func to_save() -> String                     # canonical form; see section 8
func state_hash() -> String                  # SHA-256 of to_save()
```

The client must not hold references into simulation objects or change a view. Only `submit` changes the simulation.

## 4. Tick order

Each `step` runs these phases in order.

1. Apply commands stamped for this tick. Reject invalid ones with `command_rejected`.
2. Update tasks and unit instructions.
3. Calculate available power on each network.
4. Determine active operations, allocate power by priority, and reserve inputs and cargo space.
5. Run propulsion, mining and industry.
6. Update inventories, battery charge and heat.
7. Detect damage, faults and shutdowns, and set them in the state.
8. Emit events and commit.

Rules:
- `to_save` and `state_hash` run only between ticks.
- A fault set in phase 7 has effect from phase 1 of the next tick: commands aimed at the module are rejected, and it gets no power or new work. Its running job pauses with inputs held.
- Systems may read state written by earlier phases only. A system that needs later data waits for the next tick.

## 5. Commands

Every command has this envelope. `submit` fills in `id` and `tick`.

```json
{ "id": 1, "tick": 120, "type": "start_mining", "unit": 7, "args": { "deposit": 12 } }
```

| Type | Args | Meaning |
| ---- | ---- | ------- |
| `scan` | `target` | Scan a body for deposits |
| `move_to` | `target` | Travel to an entity along a route |
| `dock` | `port`, `target_port` | Dock at a port |
| `undock` | none | Leave the current port |
| `load_cargo` | `from`, `item`, `grams` | Transfer into this unit |
| `unload_cargo` | `to`, `item`, `grams` | Transfer out of this unit |
| `start_mining` | `deposit` | Begin mining |
| `stop` | none | Stop the current operation |
| `start_job` | `recipe`, `count` | Begin a recipe at a facility |
| `cancel_job` | `job` | Cancel and return held matter |
| `attach_part` | `part`, `parent_connector`, `part_connector` | Install a part |
| `detach_part` | `part` | Remove a part and everything below it |
| `assign_core` | `core` | Set a unit's AI core |
| `set_cycle` | `steps` | Set the repeating cycle for tier 2 |
| `set_priority` | `module`, `priority` | Change a module's power priority |

New command types go through the Lead. `C0` may refine the autonomy commands.

## 6. Events

```json
{ "tick": 120, "type": "deposit_found", "unit": 7, "data": { "deposit": 12 } }
```

| Type | Data |
| ---- | ---- |
| `command_rejected` | `command`, `reason` |
| `deposit_found` | `deposit`, `item`, `grams` |
| `arrived`, `docked`, `undocked` | `target` |
| `transfer_done` | `item`, `grams` |
| `job_started`, `job_finished`, `job_cancelled` | `job` |
| `attach_failed` | `part`, `reason` |
| `part_attached`, `part_detached` | `part` |
| `power_shed` | `module`, `reason` |
| `fault` | `module`, `reason` |
| `fault_cleared` | `module` |
| `task_blocked`, `task_resumed` | `task`, `reason` |

`reason` is a stable lowercase code such as `over_heat_limit`, with display text held in the client. Every rejection and failure gives a reason, as check 10 and the player's debugging both rely on it.

## 7. State view

`view()` returns plain data, keyed by entity ID.

```json
{
  "tick": 120,
  "units": { "7": {
    "def": "starter_hull", "pos_mm": [0, 0, 0], "core": 21, "task": 4,
    "parts": { "id": 9, "def": "mining_laser_mk1", "fault": "", "children": [] },
    "inventory": { "hematite": 5000 },
    "power": { "supply_w": 0, "demand_w": 0, "stored_j": 0 },
    "heat": { "stored_j": 0, "limit_j": 0, "reject_w": 0 }
  } },
  "bodies": {}, "deposits": {}, "tasks": {}, "jobs": {}
}
```

The exact fields are finalized with A0, C0 and B3. Scan-gated information, such as unfound deposits, stays out of the view.

## 8. Canonical serialization

- `to_save` writes the entire state as JSON with sorted keys, in a defined order, with no whitespace differences between runs.
- All integers are written as decimal strings. Godot's JSON parser reads numbers as floats, which would corrupt values above 2^53.
- Lists whose order has no meaning are sorted by ID before writing. Lists whose order has meaning, such as task steps, keep it.
- `state_hash` is the SHA-256 of that text. It is the only accepted way to compare states.
- The save includes the RNG state, all remainders, the ID counter, the pending command queue and the contract version.

## 9. Ledgers

Each runs every tick in tests and fails on any difference.

- **Matter:** the sum across deposits, inventories, running jobs, installed parts and sinks is unchanged, after adding declared starting stock.
- **Energy:** per network, generated plus drawn from storage equals consumed, plus stored, plus explicit losses.
- **Heat:** per loop, the change equals waste heat added minus heat rejected.

## 10. Data definitions

Task B3 owns the schemas. These fields are fixed here because other agents depend on them.

- Modules: `id`, `mass_kg`, `volume_m3`, `power_kw`, `heat_kw`, `durability`, `min_ai_tier`, `realism`, `capabilities`, `fabrication`, `connectors`, `collision`, `visual`.
- `realism`: `established`, `extrapolation`, `speculative` or `fictional`.
- Connectors: `type` (`stack`, `side`, `dock`), `size`, `pos_mm`, `facing`, `load_limit`.
- Recipes: `id`, `facility`, `seconds`, `power_kw`, `inputs`, `outputs`, `abstract`.
- `visual` is read by the client only. The simulation never reads it.

## 11. Client rules

- Steps run at the fixed tick rate from the client bridge. Pause and speed controls change how many steps run, never the simulation's behaviour.
- The client interpolates positions between views for display.
- Until the kernel lands, the client uses a stub with this same API at `client/stub/stub_sim.gd`.
