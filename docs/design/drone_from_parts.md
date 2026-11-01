# Drones From Parts

Status: approved by the Lead, with all five rulings in section 10 decided, and done: on `main` at d5ad250.

This replaced `mining_drone_body` with a small hull and small modules fitted through `attach_part`, under the owner's rule that no part stands alone and every part can go on any ship.

## 1. Summary

- **The drone becomes eight parts:** a small hull, a small docking port and six small modules, plus its core as today.
- **Every lap figure is unchanged.** The drone is still 520 kg, or 580 kg with an Assisted Core, and it uses the same 8 frames, 10 wiring and 4 processors over the same 300 s.
- **It needs almost no new code.** The real sim built and flew this drone with only `data/` changed in memory. The one rule change is connector size (section 4).
- **The cost is player steps.** A drone goes from 1 job to 7 jobs and 6 attaches, and goal 7 takes 1 to 5 minutes longer at the times modelled in [balance.md](balance.md). Every further drone repeats those steps.

**Tested.** I ran a throwaway script against main at b374257, with these definitions patched in memory:

- The data validator passed the proposed data with 0 errors.
- `ReferenceBot` played the full chain with no problems and clean ledgers, with Part E rewritten as in section 7.
- `PersonRun` played all ten checks.
- The medium-on-small results in section 4 came from `sim.check`, with every non-core connector set to one size, which has the same effect as the proposed rule.

## 2. The parts

Each small part takes the medium part's ID with `small_` in front, except the hull.

| ID | Mass (kg) | Inputs | Seconds | Power / heat (kW) | Capability |
| -- | --------- | ------ | ------- | ----------------- | ---------- |
| `small_hull` | 60 | In `small_craft` | | 0 / 0 | `max_mass_kg` 1500, `heat_capacity` 5000 kJ |
| `small_docking_port_mk1` | 60 | 1 frame, 1 wiring | 30 | 0 / 0 | `port`: 50 kg/s, dock 20 s, undock 10 s |
| `small_chemical_thruster_mk1` | 50 | 1 frame | 40 | 2 / 6 | `thruster`: 250 m/s, 0.05 kg/s, rated 1000 kg |
| `small_propellant_tank_mk1` | 50 | 1 frame | 30 | 0 / 0 | `storage.propellant`: 100 kg, 0.1 m3 |
| `small_ore_container_mk1` | 80 | 1 frame, 3 wiring | 30 | 0 / 0 | `storage.ore`: 500 kg, 0.2 m3 |
| `small_mining_laser_mk1` | 90 | 1 frame, 2 wiring, 4 processors | 60 | 20 / 15 | `mine`: 5 kg/s, hardness 7 |
| `small_solar_panel_mk1` | 80 | 1 frame, 3 wiring | 40 | 0 / 0 | `generate`: 30 kW |
| `small_heat_radiator_mk1` | 50 | 1 frame | 40 | 0 / 0 | `radiator`: 40 kW |

**New recipe and template.** Recipe `small_craft` takes 2 frames and 2 wiring, runs 60 s at 100 kW, and outputs template `small_craft`, kind `drone`, name "Small Craft". The template is `small_hull` with `small_docking_port_mk1` on `stack_top`. Its 120 kg equals the recipe's input mass, so the existing balance check holds.

**Totals.** The port's own 30 s recipe is not part of a drone, because the template includes a port. That leaves 60 + 40 + 30 + 30 + 60 + 40 + 40 = 300 s, and 8 frames, 10 wiring, 4 processors and 520 kg. Because the inputs are the same, the chain's end stock is unchanged.

**Shape.** All capabilities come from the existing schema, and no new key or script is needed. The hull has one core connector, `stack_top`, `stack_bottom` and seven side connectors, of which the drone uses four, so three stay free for other parts. The stack follows the ship's pattern: hull, tank, thruster, with the port on top. Non-core load limits are 500 kg. Each module's volume is its mass at 200 kg/m3, as the validator's whole-density rule needs.

**Pacing options.** These seconds are on today's scale. If the owner picks Option B or C from balance.md, the seven drone recipes halve to 30, 20, 15, 15, 30, 20 and 20 s, which stay whole numbers.

## 3. What moves

| Figure | Today | Proposed |
| ------ | ----- | -------- |
| Mining, ore, propellant, thrust, solar, radiator, heat limit, max mass | | Unchanged |
| Mass, with Assisted Core | 520, 580 kg | Unchanged |
| Laps | 5356, 5340, 5340 ticks | Unchanged |
| `propellant_exhaust`, `slag_vent` | 512.462, 1952 kg | Unchanged |
| End inventories of station and drone | | Unchanged |
| Tick of the third lap's end | 99943 | 99949 |
| Rated power, with Assisted Core | 24 of 30 kW | 26 of 30 kW |
| Rated heat, with Assisted Core | 19 of 40 kW | 25 of 40 kW |
| Draw while loading or unloading | 24 kW, 19 kW of heat | 4 kW, 4 kW of heat |

- **The six extra ticks** are the bot's: it takes one tick per attach, and there are six more attaches.
- **Rated power and heat rise** because the thruster now counts on its own, at 2 and 6 kW. It is still not a load during a trip, so running figures don't change.
- **The transfer draw falls** because the old body was the port, and a transfer's operation names the port. The new port draws nothing. The drone had power to spare, so no lap figure moves.

**Fit order now matters.** A bare craft has no solar or radiator, so the laser, the thruster and either core are refused with `over_power_budget` until those are fitted. The working order is solar, radiator, then the rest. The Fit screen's refusal already gives the numbers.

## 4. Question a: "any ship" both ways

Today two connectors join only if type and size match, so size refuses a part outright. **Proposed rule: size no longer decides a join, except that `core` joins only `core`.** Type, occupancy, load limit, mass, power and heat all stay as they are. `small`, `medium` and `large` remain as labels for the Fit screen. Docks already ignore size, so a small port docks at a medium port.

`connector_size_mismatch` stays, but means only a core and a non-core connector meeting. A one-way rule, where small fits on medium only, would refuse medium parts on a small hull, which is what the Lead ruled out.

**Medium parts on a small hull** (`sim.check` results):

| Part | Bare craft | Finished drone, spare side |
| ---- | ---------- | -------------------------- |
| Radiator, solar panel, battery, ore container | Fits | Fits |
| LIDAR | `over_power_budget`, 10 of 0 kW | `over_power_budget`, 36 of 30 kW |
| Mining laser | `over_power_budget`, 150 of 0 kW | `over_power_budget`, 176 of 30 kW |
| Propellant tank, docking port | Fits, on `stack_bottom` | No free stack connector |
| Chemical thruster | `over_power_budget`, 10 of 0 kW | No free stack connector |
| Ore storage | `over_load_limit`, 1000 of 500 kg | `over_load_limit` |
| Fabricator | `over_load_limit`, 2000 of 500 kg | Not tried, same load limit |

**Small parts on the starter ship.** Container, laser, solar panel and radiator all fit a free side connector. The small stack parts get `connector_occupied`, because the starter ship has no free stack connector, and neither do medium stack parts. A player has to remove something first. I propose no change, since the hull is an open question with the owner.

**Three effects of the rule to accept:**

- **A small thruster does nothing on a ship.** `Travel.thruster` uses the fastest healthy thruster, so it only works as a spare if the main one faults.
- **A medium thruster on a drone is a real upgrade.** By the trip formula it doubles speed at the same propellant per metre for a given mass, though it adds 250 kg of dry mass. Rated power of 34 of 30 kW means it also needs a second solar panel. I think that's a good choice to offer a player. The formula is worked out, not flown.
- **Cargo can pass `max_mass_kg`.** The limit is only tested at fitting, so a drone with a medium container can carry 2500 kg of ore over a 1500 kg limit. The rule already works this way, but until now nothing could get near it.

**Small against medium.** Fitting small parts on ships makes the old one-part drone's figures comparable with medium parts, so I sized the masses to avoid a better deal:

| Part | Small | Medium | Result |
| ---- | ----- | ------ | ------ |
| Solar, kW per kg | 0.375 | 0.4 | Small is worse |
| Ore store, kg held per kg | 6.25 | 6.67 | Small is worse |
| Tank, kg held per kg | 2 | 10 | Small is worse |
| Radiator, kW per kg | 0.8 | 1.0 | Small is worse |
| Laser, kg/s per kW | 0.25 | 0.13 | Small is better, but only one laser runs at a time and it is a quarter the rate |
| Port | 60 kg | 150 kg, 2 frames, 5 wiring | **Small is better** |

The small port is strictly better, because it has to keep 50 kg/s to hold the lap figures. Nothing in the slice rewards replacing a port, so I would accept this now and raise the medium port's rate when it matters. The hull is light at 60 kg because of these masses, which only affects the total.

## 5. Question b: how a hull appears docked

**The template holds the hull and a small port**, and the recipe builds a unit, as the Lead suggested. This needs no sim change: `ConstructionSystem` already docks a new unit by `Units.ports(...)[0]`, and the trial showed it working with the port as a child part.

| Rule | What happens |
| ---- | ------------ |
| "Appears docked with no core and an empty tank" | Becomes "appears docked with no core and no tank: a hull and a port, with an empty inventory". It can't be refuelled until a tank is fitted. |
| schemas.md section 12: a root part has null `fabrication` | **Stays true.** `fabrication` means a recipe outputs the module as an item. `small_hull` never exists as an item: it comes only from a template. The validator passed it unchanged. |
| spec section 7.2: "Root parts are not fabricated" | Reworded to: "Root parts are never goods. A root part exists only inside a unit, made by the scenario or a unit recipe." `starter_hull` and `command_hub` stay scenario-only. |
| "Any module may fit any craft" | A root part is the exception. It has no `mount`, so `attach_part` refuses it with `invalid_target`, which the trial confirmed. |

**A new validator check is needed.** A recipe's unit template must hold a port, or `Units.ports(...)[0]` crashes when the job finishes. The old body was its own port, so this could not happen before. This is also a new sentence in the "Building units" rule.

If the owner later makes full-size hulls buildable, the same mechanism works: a template of `starter_hull` plus a port, with a recipe.

## 6. Extra player steps

| | Today | Proposed |
| - | ----- | -------- |
| Jobs for a drone | 1 | 7 |
| Attaches before the core | 0 | 6 |
| Least extra commands | | 12 |
| Commands in a modelled run to all ten checks | 52 to 55 | 73 to 76 |

The modelled run adds 21 commands, not 12, because it also makes frames and wiring in smaller batches for each part. A person who batches them adds fewer.

Time to a working drone, and to all ten checks, in minutes. Goal 7 here means the last part fitted, as section 8 proposes.

| Run | Goal 7 today | Goal 7 proposed | All ten today | All ten proposed |
| --- | ------------ | --------------- | ------------- | ---------------- |
| Practised, 1x | 59.5 | 60.7 | 85.9 | 87.1 |
| Practised, 8x | 8.8 | 10.2 | 12.6 | 14.0 |
| First time, 1x | 71.5 | 76.8 | 99.8 | 105.0 |
| First time, 8x | 18.0 | 22.8 | 23.0 | 27.8 |

Today's figures reproduce balance.md exactly. Like those, they are modelled lower bounds with guessed think times, not real play.

- **The fabricator takes one job at a time.** The player has to return to Jobs seven times, 30 to 60 s apart at 1x, or every 4 to 8 s at 8x. At 8x the fabricator sits idle while they think, which is why 8x loses the most. This is the main friction, and it applies to all seven jobs.
- **Every further drone repeats all of it.** balance.md found two drones are needed to keep the refinery busy. There is no repeat action for fitting, so a second drone is another 12 commands. That is a cost of the owner's rule, and a "fit like this one" action would be the remedy, but I have left it out of this task.

## 7. Question c: checks and reference figures

**Checks.** Checks 1 to 5 and 9 are unchanged.

| Check | Change |
| ----- | ------ |
| 6 Install | Spec unchanged. `GoalTracker` needs a fix: any non-station attach counts, so a drone part completed it in the trial. It should count `kind` `ship` only. |
| 7 Build a drone | **Redefined**, section 8. |
| 8 Hand over | Spec unchanged. Fitting the core and the cycle work as before. |
| 10 Fail and fix | Spec unchanged. It can now also finish on the drone, if a refused laser is fitted after the solar panel. That is still a real fail and fix, so I would accept it. |

**[reference_scenario.md](reference_scenario.md).** Sections 1, 2, 4 and 5 keep their figures, and Parts A to D don't change. Part E becomes:

| # | Step | Ticks |
| - | ---- | ----- |
| 41 | `start_job` `small_craft` x 1. `unit_created`: hull and port, docked at port 11. | 600 |
| 42 to 47 | `small_solar_panel_mk1`, `small_heat_radiator_mk1`, `small_propellant_tank_mk1`, `small_chemical_thruster_mk1`, `small_ore_container_mk1`, `small_mining_laser_mk1` | 400, 400, 300, 400, 300, 600 |
| 48 to 53 | Attach them, in that order: `side_a_px`, `side_a_nx`, `stack_bottom`, the tank's `stack_bottom`, `side_a_pz`, `side_a_nz`. **Check 7** on step 53. | Instant |
| 54, 55 | `basic_core`, `assisted_core` | 1200, 3000 |
| 56 to 58 | Attach `assisted_core` at `core`, `assign_core`, `set_cycle` | Instant |

In the cycle, `<drone body>` splits in two: `start_mining` names the laser and `dock` names the port. That cycle is in section 3 Part E, not section 5. Section 3's lap text is otherwise unchanged. Neither the page nor `test_reference_chain` states an absolute end tick, since laps are measured from the cycle's start, so the six extra ticks change no expected figure.

**Contract changes, for the Lead to make:**

| Page | Change |
| ---- | ------ |
| contracts.md section 5, Fitting | Connectors: type, core against non-core, occupancy, and load |
| contracts.md section 5, Building units | The template must hold a port, and the validator checks it |
| contracts.md section 6, reason codes | `connector_size_mismatch` keeps its code, with the narrower meaning |
| schemas.md | Section 4 line on `fabrication`, section 5 "Used by" column and the multi-role sentence, section 6 join rule, section 8 examples, section 10 "empty tank", section 12 new port check |
| spec.md | Sections 7.2, 7.3 (including "one unit with one model"), 7.4, 7.5, 7.6 check 7 |
| networks.md section 7 | "depends only on type, size, occupancy and load" |
| autonomy.md section 2, Coreless units | "no tank", and refuelling needs a fitted tank |
| accounting.md section 3 | "The drone's fitted core is not part of its template" also covers its fitted modules |
| workplan.md | Section 7, slice content and visuals: "one mining drone", "and the drone" |

Commands, events and the view don't change. Existing saves break with `data_mismatch`, which the Lead has accepted.

## 8. Question d: who changes what

**Goal 7 should finish when the drone works, not when the hull appears.** Otherwise the goal fires on a bare hull that can't fly. Proposed test: a `kind` `drone` unit with parts giving `mine`, `thruster`, and ore and propellant storage. Testing capabilities rather than part IDs means a drone built with medium parts counts too. `kind` stays `drone`, since nothing in `sim/` reads it and the client uses it to tell drones from ships.

| Owner | File | Change |
| ----- | ---- | ------ |
| B | `data/modules.json`, `recipes.json`, `templates.json` | Section 2, removing the old body, recipe and template |
| B | `tools/data_validator.gd`, `tests/tools/test_data_validator.gd` | Size rule in `_check_join` and `_fits_somewhere`, new port check. `test_connector_size_mismatch` moves to a core case. |
| B | `tests/tools/test_slice_data.gd`, `test_reference_scenario.gd` | ID lists, the budget test over all parts, lap dry mass, the goods walk |
| B | `tools/person_run.gd`, `tools/balance_run.gd`, `docs/design/balance.md`, `reference_scenario.md` | New Part E and figures |
| A, by the folder rule | `sim/kernel/fitting_system.gd` | One line, line 84, plus a test. The Lead should say who takes it, as the split named only B, C and D. `tests/sim/kernel/test_fitting.gd:144` passes as it is. |
| A, by the folder rule | `tests/sim/kernel/test_data_loader.gd` | Drone figures read from three modules |
| C | `tests/bot/reference_bot.gd` | Part E, with separate laser and port IDs |
| C | `tests/sim/industry/test_construction.gd` | The 28 references are mostly a rename. Real changes: mass 120 kg, `dock.port` is the port part and not the root, and `_fill_free_port` uses `Units.ports`. |
| C | `tests/sim/autonomy/test_cycles.gd` | `_shrink_world` patches three modules, `_make_drone` needs a fitted drone, and `_steps` takes laser and port separately. A shared fixture that fits a whole drone would suit this. |
| C | `tests/slow/test_reference_chain.gd`, `test_determinism.gd` | Job durations and labels |
| D | `client/ui/goal_tracker.gd`, `tests/client/test_goals.gd` | Goal 7 test, which needs module definitions in `observe_view`; check 6 fix; both hints |
| D | `client/stub/stub_sim.gd`, `client/ui/order_text.gd` | Same size rule, and new wording for the reason |
| D | `tests/client/panel_player.gd`, `test_automation.gd` | Play the seven jobs and six fits, and a parts tree in place of the one-part drone |

No change is needed in `CyclePlan`, which finds the laser and port by capability across the tree, in `FittingLogic`, which leaves rules to `Sim.check`, in `CraftLayout`, or in `IndustryLogic.name_of`, which already finds a template's name. D should still confirm by screenshot that a craft of eight placeholders docks and reads correctly.

## 9. Question e: models

All eight parts ship with `"model": null`, so the client draws labelled placeholders from their `collision` data, with tints matching the medium parts. There are no pipeline requests in this task.

If models are made later, this replaces the single `mining_drone` model in the workplan with eight: hull, port, thruster, tank, container, laser, solar panel and radiator. `visual` can't hold numbers, so reusing medium models at a smaller scale would need the client to work out the scale from `collision`. That's D's call when the time comes.

## 10. Rulings

1. **Size rule:** approved as in section 4, along with its three effects and the small port beating the medium one for now.
2. **Goal 7:** finishes when the drone works, tested by capability.
3. **IDs:** `small_craft` replaces `mining_drone` for the recipe and template, and `kind` stays `drone`.
4. **`sim/kernel/fitting_system.gd` and `test_data_loader.gd`:** stay with Agent A.
5. **Extra steps:** they don't block the work, since they follow from the owner's rule. The Lead is giving the owner the figures. Job queues and "fit like this one" stay out unless the owner asks.

## 11. Known risks

- **Cargo can pass `max_mass_kg`.** The limit is only tested at fitting, so a drone with a medium ore container can carry 2500 kg of ore on a hull limited to 1500 kg. Nothing stops it in flight, and the only cost is the higher trip price.
- **The small port beats the medium port** on mass and cost at the same transfer rate. Raise the medium port's rate if replacing ports ever pays.
- **A fitted drone costs at least 12 more commands,** and every further drone repeats them.
