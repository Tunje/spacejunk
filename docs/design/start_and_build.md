# Start With One Ship, Build Everything

Status: **proposal**, task B10. Nothing in `data/`, `sim/`, the client or the contracts changes until the Lead and the owner approve it. This follows the owner's rulings of 2026-11-04 at the top of [workplan.md](../../plan/workplan.md).

## The short answer

- **The probe starts with a seed factory on board.** The one ship carries a compact refinery, a compact fabricator and a small goods hold, alongside today's laser, LIDAR, solar, batteries and tank. It can mine, refine and fabricate on its own from the first minute. That is also what a von Neumann probe is: a machine that arrives with just enough industry to copy itself.
- **Today's refinery and fabricator cannot go on a ship.** At 3000 kg and 2000 kg they break the ship's 1000 kg side-mount limit, and the ship's 120 kW of solar cannot run them. So the ship carries new compact versions, under 1000 kg each, which run at half speed and half power.
- **Every hull is built the way the drone already is.** A recipe outputs a unit template: a bare hull with a docking port. It appears docked to the craft whose fabricator built it, at that craft's position. A station is a hub that has no thruster, so it stays where it was built. You choose its site by flying there first.
- **Almost no new mechanism.** The sim already places a built unit at the building unit's position and docks it to that unit's free port, whatever its kind. The new things are 3 hull templates, 4 new parts, a facility speed field, letting ships carry goods, and one fallback for where a built unit docks.
- **A new first station is needed.** Today's command hub is 5000 kg, about 7 tonnes of hematite and over two hours of refining on the ship before anything else. A 1000 kg small hub makes the first station one ore load away.
- **The cost is time.** Bootstrapping from one ship builds more than today's chain, on slower compact facilities. Reaching the handover takes about 6 game hours of refining and fabricating, against about 2 today. That needs the owner's view (section 8).
- **Research is a test job at a station.** A new design is first built as a prototype, then run through a test bay on a station. The test uses the prototype up and unlocks the normal recipe. That makes "build stations to test new tech" literal. First proposal: three designs start unproven, among them the Assisted Core, so the handover itself needs a test.
- **Most tests survive.** Keep today's reference scenario as a test fixture under a new name, since most tests only need a station to dock to. Only the golden chain, the bot, the goal list and the playthrough have to be rewritten.

**Decisions needed** (section 8): propellant with no depot, compact speed, the research gate, display names, the test fixture, and where the cluster orbits. Section 9 proposes the schema fields A needs for orbits.

## 1. The new start

### 1.1 What the ship carries

The scenario holds the star, the three rocks and one unit: the probe. There's no station, no other unit and no starting goods. The rocks keep their positions in the co-moving cluster frame of [orbital_flight.md](orbital_flight.md).

| Connector | Today's starter ship | Proposed probe |
| --------- | -------------------- | -------------- |
| `core` | `basic_core` | `basic_core` |
| `stack_top` | `docking_port_mk1` | `docking_port_mk1` |
| `stack_bottom` | `propellant_tank_mk1`, then `chemical_thruster_mk1` | Same |
| Sides (12) | 2 solar panels, 2 battery banks, ore container, radiator, mining laser, LIDAR. 4 free | The same 8, plus **a second radiator, `compact_refinery_mk1`, `compact_fabricator_mk1` and `goods_container_mk1`**. None free |

| Figure | Today | Proposed |
| ------ | ----- | -------- |
| Dry mass | 4580 kg | 6780 kg (within `max_mass_kg` 12000) |
| Rated power | 172 of 420 kW | 322 of 420 kW |
| Rated heat | 160 of 200 kW | 275 of 400 kW |
| Propellant | 1000 kg | 2000 kg, a full tank (section 8, decision 1) |
| Holds | 2000 kg ore | 2000 kg ore, 2000 kg goods |

With all 12 sides used, the probe cannot grow by fitting more parts. To get more capability, the player has to build another craft or a station, which is the point. The thruster is rated for 10000 kg, so a loaded probe pays a little more per trip: that is the existing trip formula, and nothing is refused.

### 1.2 Refining and fabricating with no station

The compact facilities have the same facility types as today's, `refinery` and `fabricator`, so they run every existing recipe. The sim's rule is that a job draws from and delivers to its facility's own unit, so the probe:

1. Mines into its ore container.
2. Refines with `compact_refinery_mk1`: ore from its hold, metal into its goods container, slag vented.
3. Fabricates with `compact_fabricator_mk1`: frames, wiring, processors, parts and whole hulls.

At half speed, a 200 kW refining run draws 100 kW and takes 120 s in place of 60 s. The probe has 120 kW of solar, so it can refine or mine at full rate on solar, but doing both at once drains its batteries. That's a real choice of when to do which, and a reason to build a station with more power.

**One rule changes:** [networks.md](networks.md) section 7 says ships and drones never carry goods, because goods capacity came only from `goods_storage_mk1`. `goods_container_mk1` gives a ship goods space. Nothing in the sim reads unit kind for this, so it is a doc change only.

### 1.3 The new parts

| ID | Mass | Power / heat | Recipe sketch | Capability |
| -- | ---- | ------------ | ------------- | ---------- |
| `compact_refinery_mk1` | 900 kg | 100 / 75 kW | 15 frames, 10 wiring, 10 processors, 300 s | `facility` `refinery`, speed 50% |
| `compact_fabricator_mk1` | 800 kg | 50 / 40 kW | 12 frames, 10 wiring, 20 processors, 300 s | `facility` `fabricator`, speed 50% |
| `goods_container_mk1` | 300 kg | 0 / 0 | 6 frames, 120 s | `storage.goods` 2000 kg |
| `small_hub` | 1000 kg | 2 / 2 kW | In template `small_station` only | Station root, section 2 |

**Facility speed** is a new optional field on the `facility` capability, defaulting to 100%. A run takes the recipe's time divided by the speed, and draws the recipe's power multiplied by it, so energy per run is unchanged. The validator's rule that a recipe's power is at most the facility's rating then compares the scaled power. This is the one new mechanism in the start, and it belongs to C (section 6).

The compact ones are rebuildable, like everything else, so a player can put a second seed factory on a new medium craft.

## 2. Building hulls, ships and stations

### 2.1 The mechanism

This extends `small_craft` from [drone_from_parts.md](drone_from_parts.md) section 5 and contracts section 5, "Building units".

1. A recipe outputs a `unit_template`. The template is a hull with at least one docking port, and its part mass equals the recipe's input mass. The validator already checks both.
2. When the job finishes, the unit appears **at the facility's unit's position**, docked to a free port on that unit. This is what `ConstructionSystem` does today, and nothing in it is station-only.
3. **New fallback:** if the facility's unit has no free port, use a free port on the unit it is docked to. So a probe docked at its station can build a drone, which appears at the station's spare port. Without this, the probe would have to undock to build anything. If neither has a free port, the job blocks with `no_free_port`, as now.
4. The new unit has no core, and none of its parts beyond the template. Parts are fitted with `attach_part` from the builder's hold while they are docked, then a core, then `assign_core`. This is the existing coreless-unit rule ([autonomy.md](autonomy.md) section 2).
5. A unit with no thruster never moves. A station stays where it was built.

**Where a built unit starts.** [orbital_flight.md](orbital_flight.md) section 11.1 puts every unit in exactly one of three places: on an orbit, in a frame, or landed on a cell. A docked unit follows its host. A built unit starts docked to the craft that built it, so it is wherever its builder is. When the two undock, it keeps that place:

| Builder is | The new unit, once undocked |
| ---------- | --------------------------- |
| In the cluster frame | A frame member at the builder's local `pos_mm` |
| On an orbit | On the same orbit. Separating needs A's undock rule for orbits |
| Landed on a cell | Landed on the same cell. A station built there is a surface base |

**Placing a station** is therefore: fly the probe to the site and build. In the cluster, the site is just a position. In orbit, the station keeps the orbit the probe was on. On a planet, it is the cell the probe landed on. A station has no thruster, so it never changes place afterwards.

**Crewing.** There's no crew, so a built craft is "crewed" by fitting a core. A core is a fabricated part like any other. A station needs a core only to give orders of its own: to start jobs at its facilities, or to unload propellant into a coreless drone. A plain depot can stay coreless, because the unit giving a transfer order is the one that needs the core.

### 2.2 Templates

| Template | Kind | Parts | Mass | Recipe sketch |
| -------- | ---- | ----- | ---- | ------------- |
| `small_craft` (exists) | `drone` | `small_hull`, `small_docking_port_mk1` | 120 kg | 2 frames, 2 wiring, 60 s |
| `medium_craft` | `ship` | `starter_hull`, `docking_port_mk1` | 2150 kg | 40 frames, 15 wiring, 600 s |
| `small_station` | `station` | `small_hub`, 2 × `docking_port_mk1` | 1300 kg | 24 frames, 10 wiring, 600 s |
| `station` | `station` | `command_hub`, `docking_port_mk1` | 5150 kg | 100 frames, 15 wiring, 1800 s |

All four recipes run at a fabricator, at 100 kW. Each sketch balances by mass: frames are 50 kg and wiring 10 kg.

**`small_hub`:** 1000 kg, `max_mass_kg` 50000, 2 kW always on. It has a core connector, four stack connectors (two for ports, plus a tank and one spare) and eight side connectors with a 3000 kg load limit, so today's refinery and fabricator fit on it. `command_hub` stays as the large hub for later.

**Kinds.** `kind` stays a label that the client reads, and the sim ignores it. The client's rule that a station takes no movement orders still holds, since player-built stations have kind `station`.

**The probe itself** is still placed by the scenario from the `starter_ship` template. Every part of it, including its hull through `medium_craft`, can be built again.

## 3. Everything buildable

Today 26 modules exist. 23 have a recipe already, and `small_hull` is built through `small_craft`. Two roots, `starter_hull` and `command_hub`, can only come from a scenario.

| Group | Modules | Status |
| ----- | ------- | ------ |
| Hulls and hubs | `small_hull`, `starter_hull`, `small_hub` (new), `command_hub` | Through the templates in section 2.2 |
| Ship and drone parts | thruster, tank, docking port, solar panel, battery bank, radiator, LIDAR, mining laser, ore container, and their 7 `small_` versions | Recipes exist, unchanged |
| Cores | `basic_core`, `assisted_core` | Recipes exist. `assisted_core` may need a test (section 5) |
| Station parts | `ore_refinery_mk1`, `fabricator_mk1`, `ore_storage_mk1`, `goods_storage_mk1`, `solar_farm_mk1` | Recipes exist. Too heavy for a ship side, so they need a hub |
| New | `compact_refinery_mk1`, `compact_fabricator_mk1`, `goods_container_mk1` | Recipes in section 1.3 |
| Research (section 5) | `test_bay_mk1` | 1000 kg: 15 frames, 15 wiring, 20 processors, 300 s. Facility `test_bay`, 100 kW. Station side only |

That means 4 new templates or recipes for hulls and 5 new parts, counting `test_bay_mk1`. Every module, after this, is either built by a recipe or exists only inside a template that a recipe builds. The validator can check exactly that: no module with neither a recipe nor a buildable template.

## 4. The new reference chain (outline)

This replaces Parts A to E of [reference_scenario.md](reference_scenario.md). It is an outline: the ticks and figures are B's to calculate once the rulings in section 8 are made. The material totals are rough, to size the run.

| Part | What happens | Checks |
| ---- | ------------ | ------ |
| A. Prospect | Probe scans Red Rock, mines 2000 kg of hematite | Scan, mine |
| B. Seed factory | Refines on board, then makes frames and wiring. Two more trips for chalcopyrite and olivine, refined and turned into processors | Refine, fabricate |
| C. First station | Flies to a site near Red Rock, builds `small_station` (24 frames, 10 wiring). Fabricates and fits a solar panel, `ore_storage_mk1`, a propellant tank and a Basic Core, then docks | Build a station, install |
| D. Fail and fix | Fitting the test bay is refused, `over_power_budget`, until a second solar panel or a battery bank is fitted | Fail and fix |
| E. Haul | Probe unloads ore and propellant into the station | Haul into storage |
| F. Research | Builds the prototype Assisted Core, runs its test at the station's test bay, and the recipe unlocks | Prove a new tech |
| G. Drone | Docked at the station, the probe builds `small_craft`, which appears at the station's spare port. Six parts and a core are fitted, and the core is assigned | Build a drone |
| H. Handover | `set_cycle` between Red Rock and the station's ore storage. Stop on the third lap | Hand over |
| I. Expand | The cycle's ore is refined on the probe and spent on a second `ore_storage_mk1` for the station | Expand |

**Rough totals** to the end of Part H, with research:

| Measure | New chain | Today's chain |
| ------- | --------- | ------------- |
| Components | About 75 frames, 45 wiring, 50 processors | 35 frames, 21 wiring, 24 processors |
| Ore | About 5.6 t hematite, 1.5 t chalcopyrite, 1.6 t olivine. About 5 probe loads | 4 loads |
| Refining at half speed | About 3 game hours | 45 minutes, at the station |
| Fabricating at half speed | About 3 game hours | 70 minutes, at the station |

The test bay and the prototype are about a third of the components. Without research, the chain needs about 60 frames, 30 wiring and 20 processors. At full compact speed, both times halve. This is the largest cost of the new start, and section 8 decisions 2 and 3 set it.

### 4.1 The goal list

D's goal tracker needs this list. It goes from 10 checks to 12, and every old check survives.

| # | Goal | Done when | Old |
| - | ---- | --------- | --- |
| 1 | Scan a rock | `deposit_found` | 1 |
| 2 | Mine ore | Ore in the probe's hold | 2 |
| 3 | Refine | A refinery job finishes | 4 |
| 4 | Fabricate | A component job finishes | 5 |
| 5 | Build a station | A `station` unit is created | New |
| 6 | Install a part | A part is attached to a unit the player built | 6 |
| 7 | Fail and fix | A refused fit, later accepted on the same connector | 10 |
| 8 | Haul | A station holds ore | 3 |
| 9 | Prove a new tech | `tech_unlocked` | New |
| 10 | Build a drone | A working drone, tested by capability as now | 7 |
| 11 | Hand over | A cycle completes a lap | 8 |
| 12 | Expand | A part is attached to a station after the handover | 9 |

The two places D flagged keep working: "haul" still means a station holding ore, and "expand" still means a part attached to a station. Only the ordering and the hints change. A cycle still needs a dockable unit to unload into, so automation still starts after the first station. That's intended: a station is what makes automation possible.

## 5. Research: proving new tech by testing

First proposal, kept short.

- **A tech** is a data entry with: an ID, the recipes it unlocks, a prototype recipe and a test recipe.
- **A prototype** is built from its own recipe, at about twice the normal inputs. It is an ordinary item.
- **A test** is a job at a `test_bay_mk1`, which only fits a station. Its inputs are the prototype plus some processors, it runs with power and heat like any job, and its output is the unlock. The prototype goes to a new declared sink, `test_scrap`, so the matter ledger holds.
- **Unlocked tech** is a sorted list in the state. A recipe that names a tech is refused with `tech_locked` until it is in the list. A new event `tech_unlocked` reports it.
- **What starts unproven:** `assisted_core`, `ore_refinery_mk1` and `solar_farm_mk1`. Everything on the probe, every hull template and every material recipe is known from the start, so the bootstrap can never dead-end.
- **Later:** field tests, where a fitted prototype has to run for a set time or a set amount of work, and tech that improves an existing part rather than unlocking a new one.

Gating `assisted_core` puts research inside the core loop, before the handover, as the owner asked. If that's too much for the first build, the test can gate only `solar_farm_mk1` and the chain can skip Part F.

## 6. What assumes the starter station

Counts are lines naming the station, its hub or its parts, on `main` at f570f78.

**Recommendation that cuts most of this work:** keep today's `data/scenarios/reference.json` as a test fixture, renamed to `station_fixture.json`, and write the new start as a new `reference.json`. Most sim and client tests only need a station to dock to, and for them the change is one scenario name. Only the tests in the first table below need real work.

### 6.1 Real changes

| Owner | File | Change |
| ----- | ---- | ------ |
| B | `data/modules.json`, `recipes.json`, `templates.json` | 5 new parts, 4 new unit recipes, 3 new templates, `starter_ship` refit, techs |
| B | `data/scenarios/reference.json` | The new start: probe only |
| B | `tools/data_validator.gd`, `tests/tools/test_data_validator.gd` | Every module buildable, facility speed against recipe power, tech references |
| B | `tests/tools/test_reference_scenario.gd`, `test_slice_data.gd` | New chain figures and part lists |
| B | `tools/person_run.gd`, `tools/balance_run.gd`, `docs/design/balance.md` | New chain and pacing figures |
| B | `docs/design/reference_scenario.md` | Rewritten for section 4 |
| B | `spec.md` (20 lines), `schemas.md`, `networks.md` section 7, `autonomy.md` section 2, `drone_from_parts.md` | Start, roots now buildable, ships carry goods, coreless stations, research |
| Lead | `contracts.md`, `plan/workplan.md` sections 1 and 7 | Building-units fallback port, `facility` speed, `tech_locked`, `tech_unlocked`, techs in the state and view |
| A | `sim/kernel/` loader and state | Techs in the state and save, facility speed loaded |
| C | `sim/industry/construction_system.gd`, `job_system.gd`, `sim/networks/power_system.gd` | Fallback port, facility speed for ticks and draw, the tech check and the test sink |
| C | `tests/bot/reference_bot.gd`, `tests/slow/test_reference_chain.gd`, `test_determinism.gd` | The new chain |
| C | `tests/sim/industry/test_construction.gd`, `test_jobs.gd` | New cases: building on a ship, the fallback port, compact speed, tests and locks |
| D | `client/ui/goal_tracker.gd` (8 lines), `tests/client/test_goals.gd` | The goal list in section 4.1 and its hints |
| D | `client/ui/order_list.gd` lines 55 to 70 | Unload and Load Propellant appear only once a host exists, as now. Hint text should point to building one |
| D | `client/ui/industry_logic.gd` | Works unchanged with the probe's compact facilities, plus a tech-locked state for recipes |
| D | `client/ui/automation_screen.gd` line 188, `cycle_plan.gd` | Text for "no dockable unit yet" |
| D | `tests/client/panel_player.gd`, `tests/slow/test_playthrough.gd` | Follow the new goal list |
| D | `client/stub/data/modules.json`, `client/stub/data/scenario.json`, `client/stub/stub_sim.gd` | Mirror the new start |
| D | `client/debug/screenshot_driver.gd`, `tests/client/test_frame_probe.gd` | Shots of the new start, and a station the player built |
| D | `client/ui/fitting_screen.gd`, `client/mock/standing_orders_mock.gd` line 11 | Wording only |

### 6.2 Fixture rename only

These load the reference scenario for a dock host, a station inventory or a known layout. With the fixture kept, each needs only the scenario name changed. Agents should check each one when they rename.

- **Sim tests:** `test_cargo.gd` (44 lines), `test_fitting.gd` (39), `test_cycles.gd` (17), `test_scenario.gd` (16), `test_power.gd` (10), `test_heat.gd`, `test_tasks.gd`, `test_mining.gd`, `test_scan.gd`, `test_save.gd`, `test_perf.gd`.
- **Client tests:** `test_local_view.gd` (18), `test_stub_sim.gd` (16), `test_fit_clicks.gd` (12), `test_industry.gd` (11), `test_dock_progress.gd` (11), `test_fitting.gd` (10), `test_automation.gd` (10), `test_feedback.gd`, `test_save_ui.gd`, `test_real_flight.gd`, `test_real_scenario.gd`, `test_view_shape.gd`, `test_view_math.gd`, `test_inspection_panel.gd`, `test_system_map.gd`.
- **Client:** `client/main.gd` keeps loading `reference`, which becomes the new start.

`test_perf.gd` builds its load from the station scenario and should stay on the fixture, so the perf budget keeps its meaning.

### 6.3 Not affected

D confirmed the system map, the event log, the inspection panel, time controls, save and load, and dock progress. On the sim side: scanning, mining, travel, power, heat and the cycle logic. Each already works on any unit.

## 7. Work by agent, roughly

| Who | Work | Size |
| --- | ---- | ---- |
| Lead | Contract round, workplan sections 1 and 7 | One round |
| B | Data, validator, new chain figures, docs | 3 to 4 tasks: data and validator, chain and figures, research data, docs |
| A | Techs in state and save, loader fields | 1 task |
| C | Fallback port, facility speed, tech locks and test sink, bot and chain tests | 2 to 3 tasks |
| D | Goal list, hints, stub, screenshots, playthrough, fixture renames in client tests | 2 to 3 tasks |

Research (section 5) can be split off and done after the new start works. Without it, Part F and goal 9 drop out, and `assisted_core` stays open from the start.

## 8. Decisions needed

1. **Propellant.** With no station there's no 4000 kg depot, so the whole run has the probe's 2000 kg. That covers the chain's ship trips and the drone's laps, but much less room for a person's mistakes than [reference_scenario.md](reference_scenario.md) section 5 sized. Options:
   - **A (recommended):** bring the first post-slice chain forward. Put a water-ice rock in the cluster, and add `refine_water_ice`, an abstract recipe turning ice into propellant and slag. The game can then never run dry, and it gives the station a job beyond storage. It also moves water ice into the Asteroid Cluster, which [spec.md](spec.md) section 3 doesn't list there today.
   - **B:** start the probe with a second full tank. That's simpler, the run is still finite, and a third of a person's spare propellant from today is lost.
2. **Compact speed.** At half speed, the new chain takes about 6 game hours of refining and fabricating before the handover, against about 2 hours today (section 4). That breaks "leave the pacing figures as they are", whatever the speed, because the new chain builds more. The options:
   - **Half speed (recommended):** one number in `data/`, retuned in B6. It keeps a reason to build station-scale facilities.
   - **Full speed:** the compact facilities differ from today's only in mass, so no sim change is needed and the times about halve. But the probe can only run a 200 kW refining run on 120 kW of solar by draining its batteries, and a station refinery is no faster.

   Either way, the owner should see this figure before approving.
3. **Research gate.** Gate `assisted_core`, as recommended, or start with only `solar_farm_mk1` gated.
4. **Display names.** Rename `starter_hull` to "Medium Hull" and `command_hub` to "Large Hub" by `name` only, keeping their IDs to avoid churn in tests.
5. **The fixture.** Keep today's scenario as `station_fixture.json` for tests (recommended), or move every test to the new start.
6. **Where the cluster orbits.** A leaves this to B10 ([orbital_flight.md](orbital_flight.md) section 11.2).
   - **The star (recommended, and A agrees):** a circular orbit at 1 AU, which is where today's star position already puts the cluster. A's integer trig keeps the frame's absolute position within about 150 m at that distance, with no drift, and nothing inside the frame sees even that. There's no planet shadow, so every power figure and lap stays as it is, in line with "leave the pacing figures as they are". The cost is that the first planet is an interplanetary trip, which needs spheres of influence (A12) and the planner (A13) first.
   - **A 600 km planet, at a 1000 km orbit:** the planet is the first place to explore, with trips of about 22 minutes, 364 m/s each way and a window every 79 minutes (A's section 5 table). But the cluster would spend about a fifth of each 56-minute orbit in the planet's shadow (A16), which changes every solar figure in the start and the drone's laps.

## 9. Schema fields for orbits

These are now in [schemas.md](schemas.md) sections 2, 5 and 14, in the shapes A10 reads (contract version 3). This section keeps the values for the new start.

### 9.1 Thrusters

| Field | `chemical_thruster_mk1` | `small_chemical_thruster_mk1` | Why |
| ----- | ----------------------- | ----------------------------- | --- |
| `exhaust_m_s` | 3000 | 3000 | A's working figure |
| `thrust_kn` | 3 | 0.15 | Today's propellant flow times exhaust speed: 1 kg/s and 0.05 kg/s. Propellant per second therefore stays as it is |

- **Burn times.** The loaded probe, about 8.8 t with a full tank, accelerates at about 0.34 m/s², so a 100 m/s burn takes about 5 minutes. The drone, at about 0.68 t, accelerates at about 0.22 m/s². These are first figures for B6.
- **The old fields stay.** Agreed with A: `speed_m_s`, `propellant_kg_per_s` and `rated_mass_kg` are kept, because in-frame trips still read them ([networks.md](networks.md) section 6). Burns outside a frame read only `exhaust_m_s` and `thrust_kn`. A is correcting orbital_flight.md section 11.4, which said `speed_m_s` goes.

### 9.2 Bodies, frames and scenarios

| Field | On | Star | Planet (600 km) | Rocks |
| ----- | -- | ---- | --------------- | ----- |
| `gm_km3_s2` | Star, planet | 132712440018 | 3531.6 | None: rocks have no gravity in the frame |
| `soi_m` | Planet | None: the root body has no sphere of influence | About 1.5 × 10^11 if it orbits at 1 AU. Not read until A12 | None |
| `orbit` | Planet, frame | None | `parent` and `a_mm`, plus optional `e_ppm` and four angles in millidegrees, all whole numbers | None: members of the frame |
| `seed`, `kind` and settings | Planet | | As in [planets.md](planets.md) section 1. Not read until A15 | |
| `frame` with a local `pos_mm` | Rocks, starting units | | | The cluster frame |

Scenarios gain a `frames` list of `{ key, name, radius_mm, orbit }`. Frame IDs come after every body and its deposits, and before the units. Body kind `planet` arrives with A15. For the new start, the cluster frame's orbit is `{ "parent": "star", "a_mm": 149597870700000 }`, which is 1 AU and circular.

**GM units, agreed with A.** The star's GM is 1.327 × 10^20 m³/s², which fits neither JSON's 2^53 nor a 64-bit integer. So:
- **Data** states `gm_km3_s2` as a plain JSON number: the star is 132712440018, exact under 2^53, and the planet is 3531.6.
- **The simulation unit** is 1000 m³/s². The loader multiplies by 10^6 under the usual exact-conversion rule, so the star becomes 1.327 × 10^17, the planet 3,531,600,000, and a moon of about 200 km roughly 65,000,000.
- The loader converts whole numbers by integer multiplication, so the star's GM stays exact.

The new start's propellant gets tighter under the rocket equation. A's figures put a round trip between orbits at 5 to 44% of a ship's mass, and landing at 54 to 58%. That adds weight to decision 1, option A: making propellant from ice.
