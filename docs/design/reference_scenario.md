# Reference Scenario

Status: reviewed by Agents A and C (task B8), with their corrections applied. Changes go through the Lead.

This is the one worked mining-to-manufacturing chain that every agent builds against. It is also the start of the slice for a person playing. The file is [data/scenarios/reference.json](../../data/scenarios/reference.json), in the format of [schemas.md](schemas.md) section 14.

C6 turns it into the first golden test. It runs the steps below in order, issuing each one when the previous one has finished, and asserts the outputs given. `tests/tools/test_reference_scenario.gd` already recomputes every trip price from `data/` with `IntMath`.

All numbers use the slice's first-pass balance. If B6 changes `data/`, this page and that test change with it.

## 1. Starting state

Seed: **12345**. No step in this chain draws a random number.

### Bodies and deposits

| ID | What | Position (mm) | Radius (mm) |
| -- | ---- | ------------- | ----------- |
| 1 | Star | [99731913800000, 99731913800000, 49865956900000] | 696000000000 |
| 2 | Red Rock | [50000000, 0, 0] | 500000 |
| 3 | Deposit on 2: 200000 kg hematite, hardness 6 | | |
| 4 | Brass Rock | [30000000, 0, 40000000] | 400000 |
| 5 | Deposit on 4: 100000 kg chalcopyrite, hardness 4 | | |
| 6 | Green Rock | [-20000000, 15000000, 20000000] | 300000 |
| 7 | Deposit on 6: 50000 kg olivine, hardness 7 | | |

All three deposits start unfound.

### Units

**Station, ID 8,** at the origin, template `starter_station`. It holds 4000 kg of propellant in its two tanks, which is both tanks full, and nothing else.

| ID | Part | ID | Part |
| -- | ---- | -- | ---- |
| 9 | `command_hub` (root) | 16 | `goods_storage_mk1` |
| 10 | `basic_core` | 17 | `solar_farm_mk1` |
| 11 | `docking_port_mk1`, free | 18 | `battery_bank_mk1` |
| 12 | `docking_port_mk1`, ship docked | 19, 20 | `heat_radiator_mk1` |
| 13 | `ore_refinery_mk1` | 21, 22 | `propellant_tank_mk1` |
| 14 | `fabricator_mk1` | | |
| 15 | `ore_storage_mk1` | | |

**Ship, ID 23,** template `starter_ship`, docked at the station from port 28 to port 12. It has 1000 kg of propellant. Its dry mass is 4580 kg.

| ID | Part | ID | Part |
| -- | ---- | -- | ---- |
| 24 | `starter_hull` (root) | 29, 30 | `solar_panel_mk1` |
| 25 | `basic_core` | 31, 32 | `battery_bank_mk1` |
| 26 | `propellant_tank_mk1` | 33 | `ore_container_mk1` |
| 27 | `chemical_thruster_mk1` | 34 | `heat_radiator_mk1` |
| 28 | `docking_port_mk1` | 35 | `mining_laser_mk1` |
| | | 36 | `lidar_mk1` |

The first free entity ID is 37. Tasks and jobs take IDs from the same counter, so IDs after this point are read from events and `view()`, never assumed.

**Start totals.** Batteries are full and heat is 0. All matter comes to 374510 kg: 350000 in deposits, 5000 of propellant, 14930 of station parts and 4580 of ship parts.

## 2. Trip prices

Each row uses the floored stop point and price of [networks.md](networks.md) section 6. Every trip starts from the undock point `[150000, 0, 0]`. Mass at departure includes the propellant being paid, and on the way back it includes 2000 kg of ore.

| Trip | Stop point (mm) | Ticks | Cost (g) | Ship propellant after (g) |
| ---- | --------------- | ----- | -------- | ------------------------- |
| 1 out, Red Rock | [49350000, 0, 0] | 984 | 54908 | 945092 |
| 1 back | [150000, 0, 0] | 984 | 74047 | 871045 |
| 2 out, Red Rock | [49350000, 0, 0] | 984 | 53639 | 817406 |
| 2 back | [150000, 0, 0] | 984 | 72791 | 744615 |
| 3 out, Brass Rock | [29671058, 0, 39559207] | 988 | 52608 | 692007 |
| 3 back | [90004, 0, 119998] | 986 | 71702 | 620305 |
| 4 out, Green Rock | [-19717607, 14789782, 19719709] | 634 | 32970 | 587335 |
| 4 back | [-93699, 70282, 93709] | 629 | 45083 | 542252 |

The ship burns 457748 g across all eight legs.

The drone's mass with its Assisted Core is 580 kg. Starting each lap with a full 100 kg tank:

| Leg | Ticks | Mass at departure (g) | Cost (g) |
| --- | ----- | --------------------- | -------- |
| Out to Red Rock | 1968 | 680000 | 6692 |
| Back, with 500 kg of ore | 1968 | 1173308 | 11546 |

One lap costs 18238 g.

## 3. The chain

Durations are in ticks at the 10 per second rate, from the step starting to the next step starting. An operation of N ticks starting on tick S follows the timing rule in [networks.md](networks.md) section 6: `docked`, `undocked`, `arrived` and `transfer_done` fire on S + N - 1, and `mining_stopped` and `task_finished` fire on S + N. Each order is a separate command on the ship, unit 23, unless stated. All cargo orders omit `grams`.

### Part A: the ship, hand-run by a Basic Core (checks 1 to 3)

| # | Command | Ticks | Expected result |
| - | ------- | ----- | --------------- |
| 1 | `undock` | 100 | At `[150000, 0, 0]`, `at_target` 8 |
| 2 | `move_to` 2 | 984 | Trip 1 out |
| 3 | `scan` 2 | 300 | `deposit_found`: deposit 3, hematite, 200000000 g. **Check 1.** |
| 4 | `start_mining` deposit 3, module 35 | 1000 | Hold 2000 kg of hematite, `mining_stopped` with `cargo_full`. **Check 2.** |
| 5 | `move_to` 8 | 984 | Trip 1 back |
| 6 | `dock` port 28, target port 12 | 200 | Docked |
| 7 | `unload_cargo` to 8, `hematite` | 400 | Station holds 2000 kg of hematite. **Check 3.** |
| 8 to 13 | Steps 1, 2, 4, 5, 6, 7 again | 3668 | Trip 2. Station holds 4000 kg of hematite. |
| 14 | `undock` | 100 | |
| 15 | `move_to` 4 | 988 | Trip 3 out |
| 16 | `scan` 4 | 300 | `deposit_found`: deposit 5, chalcopyrite, 100000000 g |
| 17 | `start_mining` deposit 5, module 35 | 1000 | Hold 2000 kg of chalcopyrite |
| 18 | `move_to` 8 | 986 | Trip 3 back |
| 19 | `dock` port 28, target port 12 | 200 | |
| 20 | `unload_cargo` to 8, `chalcopyrite` | 400 | Station holds 2000 kg of chalcopyrite |
| 21 | `undock` | 100 | |
| 22 | `move_to` 6 | 634 | Trip 4 out |
| 23 | `scan` 6 | 300 | `deposit_found`: deposit 7, olivine, 50000000 g |
| 24 | `start_mining` deposit 7, module 35 | 1000 | Hold 2000 kg of olivine |
| 25 | `move_to` 8 | 629 | Trip 4 back |
| 26 | `dock` port 28, target port 12 | 200 | |
| 27 | `unload_cargo` to 8, `olivine` | 400 | Station holds 2000 kg of olivine |

Mining needs 152 kW against 120 kW of solar, so the ship's batteries cover the difference. No `power_shed` fires anywhere in the chain.

### Part B: refining at the station (check 4)

Jobs run on `start_job`, one after another. Each waits for the last `job_finished` of the one before. Slag goes to `slag_vent` and takes no storage.

| # | Job at facility 13 | Run ticks | Total | Output |
| - | ------------------ | --------- | ----- | ------ |
| 28 | `refine_hematite` x 26 | 600 | 15600 | 1794 kg iron, 806 kg slag vented. **Check 4.** |
| 29 | `refine_chalcopyrite` x 10 | 600 | 6000 | 340 kg copper, 660 kg slag vented |
| 30 | `refine_olivine` x 6 | 900 | 5400 | 114 kg silicon, 486 kg slag vented |

### Part C: fabrication (checks 5, 6 and 10)

| # | Job at facility 14 | Run ticks | Total | Used up | Output |
| - | ------------------ | --------- | ----- | ------- | ------ |
| 31 | `structural_frame` x 35 | 300 | 10500 | 1750 kg iron | 35 frames. **Check 5.** |
| 32 | `wiring` x 21 | 200 | 4200 | 210 kg copper | 21 wiring |
| 33 | `processor` x 24 | 600 | 14400 | 96 kg silicon, 24 kg copper | 24 processors |
| 34 | `heat_radiator_mk1` x 1 | 900 | 900 | 2 frames, 100 kg copper | 1 radiator |
| 35 | `mining_laser_mk1` x 1 | 1800 | 1800 | 5 frames, 10 wiring, 10 processors | 1 laser |

The ship is still docked, so these are attached with `from` set to 8 and `parent_part` set to 24, through `part_connector` `mount`.

| # | Command on unit 23 | Expected result |
| - | ------------------ | --------------- |
| 36 | `attach_part` `mining_laser_mk1` at `side_b_nz` | `attach_failed`, `over_heat_budget`, 280000 W against 200000 W. Power passes at 322000 W of 420000 W. **Check 10, the failure.** |
| 37 | `attach_part` `heat_radiator_mk1` at `side_c_nx` | `part_attached`. Rejection is now 400000 W. |
| 38 | `attach_part` `mining_laser_mk1` at `side_b_nz` | `part_attached`. **Checks 6 and 10, the fix.** |

### Part D: expansion (check 9)

The expansion comes before the handover so that nothing is still being ordered while the drone runs, which keeps the chain's end exact.

| # | Step | Ticks | Expected result |
| - | ---- | ----- | --------------- |
| 39 | `start_job` facility 14, `ore_storage_mk1` x 1 | 3000 | Used up: 20 frames |
| 40 | On unit 8, `attach_part` `ore_storage_mk1`, `from` 8, `parent_part` 9, at `side_c_px` | Instant | `part_attached`. Station ore capacity doubles to 100000 kg. **Check 9.** |

### Part E: the drone and the handover (checks 7 and 8)

| # | Step | Ticks | Expected result |
| - | ---- | ----- | --------------- |
| 41 | `start_job` facility 14, `small_craft` x 1 | 600 | `unit_created`. A `small_hull` with a `small_docking_port_mk1`, docked at port 11, with no core, no tank and an empty inventory. Used up: 2 frames, 2 wiring. |
| 42 | `start_job` facility 14, `small_solar_panel_mk1` x 1 | 400 | Used up: 1 frame, 3 wiring |
| 43 | `start_job` facility 14, `small_heat_radiator_mk1` x 1 | 400 | Used up: 1 frame |
| 44 | `start_job` facility 14, `small_propellant_tank_mk1` x 1 | 300 | Used up: 1 frame |
| 45 | `start_job` facility 14, `small_chemical_thruster_mk1` x 1 | 400 | Used up: 1 frame |
| 46 | `start_job` facility 14, `small_ore_container_mk1` x 1 | 300 | Used up: 1 frame, 3 wiring |
| 47 | `start_job` facility 14, `small_mining_laser_mk1` x 1 | 600 | Used up: 1 frame, 2 wiring, 4 processors |
| 48 | On the drone, `attach_part` `small_solar_panel_mk1`, `from` 8, on the hull at `side_a_px` | Instant | `part_attached` |
| 49 | Likewise `small_heat_radiator_mk1` at `side_a_nx` | Instant | `part_attached` |
| 50 | Likewise `small_propellant_tank_mk1` at `stack_bottom` | Instant | `part_attached` |
| 51 | Likewise `small_chemical_thruster_mk1`, on the tank at its `stack_bottom` | Instant | `part_attached` |
| 52 | Likewise `small_ore_container_mk1`, on the hull at `side_a_pz` | Instant | `part_attached` |
| 53 | Likewise `small_mining_laser_mk1` at `side_a_nz` | Instant | `part_attached`. **Check 7.** |
| 54 | `start_job` facility 14, `basic_core` x 1 | 1200 | Used up: 4 processors, 1 wiring |
| 55 | `start_job` facility 14, `assisted_core` x 1 | 3000 | Used up: the Basic Core, 6 processors |
| 56 | On the drone, `attach_part` `assisted_core`, `from` 8, at the hull's `core` connector | Instant | `part_attached` |
| 57 | On the drone, `assign_core` with the part ID from step 56 | Instant | `core_tier` 2 |
| 58 | On the drone, `set_cycle` with the steps below | | Accepted. No further commands are submitted. |

Steps 41 to 47 take 3000 ticks in all. Solar and the radiator must go on first, because the laser and thruster are refused until there is a power and heat budget.

```gdscript
[
  { type = "load_cargo",   args = { from = 8, item = "propellant" } },
  { type = "undock",       args = {} },
  { type = "move_to",      args = { target = 2 } },
  { type = "start_mining", args = { deposit = 3, module = <small laser> } },
  { type = "move_to",      args = { target = 8 } },
  { type = "dock",         args = { port = <small port>, target_port = 11 } },
  { type = "unload_cargo", args = { to = 8, item = "hematite" } },
]
```

The cycle passes the closure rule in [autonomy.md](autonomy.md) section 5: it starts and ends docked, and propellant loads first, as section 2 sets out for a drone with a core.

A lap is 5356 ticks on lap 1: 20 loading, 100 undocking, 1968 out, 1000 mining, 1968 back, 200 docking and 100 unloading. Later laps top up 18238 g, which takes 4 ticks, so they run 5340. Each lap adds 500 kg of hematite to the station. **Stop on the tick of the third `task_cycle_done`.** A step that ends in phase 2 starts the next in the same tick, so on that tick lap 4's load has already moved one tick's 5000 g of propellant. **Check 8.**

## 4. End state

The figures below are the state on the tick of the third `task_cycle_done`. The drone's `op.type` is `loading`, and its task has `step` 0 and `cycle` 3.

| Place | Contents |
| ----- | -------- |
| Deposits | Hematite 194500 kg, chalcopyrite 98000 kg, olivine 48000 kg |
| Station inventory | Hematite 2900, chalcopyrite 1000, olivine 1400, iron 44, copper 6, silicon 18, propellant 3858.524 kg. No frames, wiring, processors or spare modules. |
| Ship inventory | Propellant 542.252 kg, empty hold |
| Drone inventory | Propellant 86.762 kg, empty hold |
| Installed parts | Station 15930 kg, ship 5180 kg, drone 580 kg |
| `slag_vent` | 1952 kg |
| `propellant_exhaust` | 512.462 kg: 457.748 from the ship, 54.714 from the drone |

These sum to 374510 kg, matching the start. C6 reads the two sinks from the `matter.sinks` map of `ledger()`.

## 5. Propellant for a person playing

The chain itself uses 512 kg of the 5000 kg at the start. The rest is there for a person, because a run must last to the M4 judgement.

| Use | Assumption | Propellant |
| --- | ---------- | ---------- |
| Ship | 20 round trips, five times the chain's four, for wasted trips and mistakes, at up to 130 kg each | 2600 kg |
| Drone | About 123 kg per game hour for 4 game hours | 492 kg |
| **Total** | | **3092 kg** |

That leaves about 1900 kg spare. The stock is 4000 kg at the depot, which is the full capacity of the station's two tanks, plus 1000 kg in the ship. An idle drone cycle alone would take over 30 game hours to empty the depot, so the handover can be watched for as long as the owner wants. Running out is still possible. It ends the run with `no_propellant`, and the slice has no way to make more, as spec section 7.1 accepts.

These assumptions are guesses until someone has played it, so B6 and the owner's playtest should recheck them.

## 6. Review notes

- **Top-ups.** Lap 2 and lap 3's 18238 g takes 4 ticks because of the per-tick clamp and the end test in phase 6: 5000 g a tick for three ticks, then the last 3238 g. It does not round the whole amount up.
- **Goods space.** Job outputs reserve `goods` space when a run starts, so `tests/tools/test_reference_scenario.gd` walks goods mass and volume through Parts B to E.
