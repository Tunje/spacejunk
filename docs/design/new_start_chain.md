# New Start Chain

Status: **draft**, task B23. Sections 1 and 2 are measured on the real `Sim`, from [data/scenarios/new_start.json](../../data/scenarios/new_start.json) on `main` at d85aac6. Section 3, Parts A to D, is measured by C's new-start bot (C14 at adf431a for Parts A to C, and C18b at a6de5ca through research, seed 12345; the optional Frost landing is from C16 at dce5c55 and B23's runs). Parts E and F, the drone and expansion, are measured by C22 at 3265798 on `gameplay/C22`, the bot's stage 6, with ticks updated for C24. Part F2, the self-feeding loop, is measured by C23 at 29bf68f, the bot's stage 7. This page is to the new start what [reference_scenario.md](reference_scenario.md) is to today's station game. When `reference.json` becomes the new start, the two pages swap names. Until then `reference_scenario.md` stays as the station fixture's worked chain, which many tests cite.

The chain follows [start_and_build.md](start_and_build.md) section 4 and the research route of [research.md](research.md) section 5.

## 1. Starting state

Seed: **12345**. The chain draws no random number. Research discovery can only draw at a variant's bench test, and the chain designs no variants.

### Bodies, deposits and the frame

| ID | What | Place | Radius |
| -- | ---- | ----- | ------ |
| 1 | Star | Origin. GM 132712440018 km³/s² | 696,000 km |
| 2 | Planet | Round the star at 1 AU. GM 3531.6 | 600 km |
| 3 | Frost, the moon | Round the planet at 12,000 km. GM 1.7658, which is half Kerbin's density | 60 km |
| 4 | Red Rock | Cluster, at local (50, 0, 0) km | 0.5 km |
| 5 | Deposit on 4: 200,000 kg hematite, hardness 6 | | |
| 6 | Brass Rock | Cluster, at local (30, 0, 40) km | 0.4 km |
| 7 | Deposit on 6: 100,000 kg chalcopyrite, hardness 4 | | |
| 8 | Green Rock | Cluster, at local (-20, 15, 20) km | 0.3 km |
| 9 | Deposit on 8: 50,000 kg olivine, hardness 7 | | |
| 10 | White Rock | Cluster, at local (-35, -10, -30) km | 0.6 km |
| 11 | Deposit on 10: 300,000 kg water ice, hardness 2 | | |
| 12 | The cluster frame | Round Frost at 300 km, starting at mean anomaly 180°, between Frost and the star | 60 km |

All four deposits start unfound. The probe starts in sunlight.

### The probe, ID 13

The template is `probe`. The probe sits at the cluster's local origin, undocked, with 2,500 kg of propellant, a full `propellant_tank_mk2`. There's no station and no other unit.

| ID | Part | ID | Part |
| -- | ---- | -- | ---- |
| 14 | `starter_hull` (root) | 24 | `solar_panel_mk1` |
| 15 | `basic_core` | 25, 26 | `battery_bank_mk1` |
| 16 | `propellant_tank_mk2` | 27 | `ore_container_mk1` |
| 17 | `chemical_thruster_mk1`, 15 kN | 28 | `heat_radiator_mk1` |
| 18–21 | `landing_legs_mk1`, on the tank | 29 | `mining_laser_mk1` |
| 22 | `docking_port_mk1` | 30 | `lidar_mk1` |
| 23 | `solar_panel_mk1` | 31 | `goods_container_mk1` |
| | | 32 | `compact_refinery_mk1`, 50 work a tick |
| | | 33 | `compact_fabricator_mk1`, 50 work a tick |
| | | 34 | `heat_radiator_mk1` |

| Figure | Value |
| ------ | ----- |
| Mass | 9,930 kg: 7,430 dry and 2,500 of propellant, against a 12,000 kg limit |
| Power | 322 of 420 kW rated. 120 kW of solar, and 720 MJ of batteries discharging up to 300 kW |
| Heat | 275 of 400 kW rated. 20 MJ limit |
| Holds | 2,000 kg of ore, 2,000 kg of goods, 2,500 kg of propellant |

The first free entity ID is 35. Tasks, jobs and built units take IDs from it, so later IDs are read from events.

**Start totals.** Matter is 659,930 kg: 650,000 in deposits, 2,500 of propellant and 7,430 installed. Batteries are full, heat is 0, science points are 0, and no theory is proven.

## 2. Trip prices

These are routes inside the cluster from the probe's start, as `quote` gives them (in-frame figures: 500 m/s, 1 kg/s at the 10 t rated mass, scaled by mass). The probe starts at the origin, not at an undock point, because it is docked to nothing.

| To | Distance | Ticks | Seconds | Propellant |
| -- | -------- | ----- | ------- | ---------- |
| Red Rock | 49.35 km | 987 | 98.7 | 98.0 kg |
| Brass Rock | 49.45 km | 989 | 98.9 | 98.2 kg |
| Green Rock | 31.57 km | 632 | 63.2 | 62.8 kg |
| White Rock | 46.42 km | 929 | 92.9 | 92.3 kg |

A trip costs about 1 kg a second at full mass, and less as the tank empties. Trips between rocks, and from a station site, follow from the same formula. C14's run gives the legs it actually flies.

**Frost.** A trip down to Frost and back is a burn, not a route. A26 measured about 640 m/s flown by hand, and the `land` and `take_off` commands now price by thrust-to-weight (A27). On a full tank the probe has 870 m/s.

## 3. The chain

Each part names the goals of [start_and_build.md](start_and_build.md) section 4.1 that it meets. A tick is 0.1 s, and 36,000 ticks are one game hour. The bot gives each order as soon as it can and keeps the refinery and fabricator queues busy while the probe travels, so its times are a floor for a person.

**Run lengths on the compact facilities** at 50 work a tick: frame 600 ticks, wiring 400, processor 1200, refine_hematite 1200, refine_chalcopyrite 1200, refine_olivine 1800, refine_water_ice 1200, small_station 12,000. A full-size facility at 100 a tick takes half as long.

### Part A: prospect (goals 1 and 2), measured

| Step | Start tick | Ticks |
| ---- | ---------- | ----- |
| Fly to Red Rock | 1 | 988 |
| Scan it (survey) | 989 | 301 |
| Mine 2,000 kg of hematite | 1290 | 1001 |

Goal 1 is at tick 1289 and goal 2 at 2290, about 4 game minutes in.

### Part B: the seed factory (goals 3 and 4), measured

From tick 2291 both queues run while the probe works:
- Refine 20 runs of hematite: 24,000 ticks.
- From tick 3491, as iron arrives, make 27 frames: 23,400 ticks.

Trip 2 is one mixed hold, with the fabricator still running:

| Step | Start tick | Ticks |
| ---- | ---------- | ----- |
| Mine 350 kg more hematite | 26291 | 176 |
| Fly to Brass Rock, scan, mine 900 kg of chalcopyrite | | 879 + 301 + 451 |
| Fly to Green Rock, scan, mine 300 kg of olivine | | 1111 + 301 + 151 |
| Fly to White Rock, scan, mine 100 kg of ice | | 1148 + 301 + 51, ending at 31161 |

From tick 31161:
- Refining: hematite ×2 (2,400), chalcopyrite ×9 (10,800), olivine ×3 (5,400) and ice ×1 (1,200), done at 50,960.
- Fabricating: frames ×3, wiring ×18, `small_station` (12,000 ticks, built at tick 53,961), processors ×4, a LIDAR and a solar panel.

### Part C: the first station (goals 5 to 8), measured

The probe builds `small_station` at its own position, and the station appears docked to it.

1. **Fail and fix, goal 7.** From tick 63,560, fitting a LIDAR to the station is refused for `over_power_budget`. A solar panel is fitted. The LIDAR is refused again, for `over_heat_budget`. A heat radiator is fabricated (1,800 ticks) and fitted, and the LIDAR fits at tick 65,365.
2. **Haul, goal 8.** A `small_ore_container_mk1` is fabricated (600 ticks) and fitted to the station. 150 kg of hematite is unloaded into it, ending at tick 65,997, which is 1.8 game hours.

**The probe at each step:**

| Milestone | Tick | Propellant | Ore | Goods |
| --------- | ---- | ---------- | --- | ----- |
| Start | 0 | 2,500 kg | 0 | 0 |
| Scanned | 1,289 | 2,401 | 0 | 0 |
| Mined | 2,290 | 2,401 | 2,000 | 0 |
| Refined | 26,290 | 2,401 | 0 | 1,380 |
| Prospected | 31,160 | 2,020 | 1,650 | 1,380 |
| Ice refined | 50,960 | 2,110 | 150 | 581 |
| Station built | 63,560 | 2,110 | 150 | 581 |
| Fit fixed | 65,365 | | | 131 |
| Hauled | 65,997 | 2,110 | 0 | 51 |

No step was stopped by shadow or a power shortfall.

**The goods hold sets the order.** The probe's goods container holds 4 m³, and fabricated parts go into it. A solar panel (1.5 m³) and a radiator (2 m³) nearly fill it, so parts are fitted as they're made. The lab, the ore storage and every other part bigger than 4 m³ can't go through the hold at all. The Lead has ruled C15, "fabricate in place": a module job delivers straight onto a free connector of the facility's unit or a docked unit, through the normal fit. Parts D to F depend on it.

### Part D: research (goal 9), measured

C18b runs on from the end of Part C, which, with C15, ends at tick 71,546 with an `ore_container_mk1` built in place on the station. It is measured on `gameplay/C18b` at a6de5ca, seed 12345, with ticks updated for C24's queue skip (C24 at 58d9b98). All ticks are absolute. The route has five stages: chain, prep, lab, the gravity lap from the cluster, and research. Frost's landing and take-off are off it, and priced in the optional part below.

**Prep, to tick 147,291.**
- Take composition at Red, Brass and Green Rock (1,201 ticks each), and mine full holds of hematite, chalcopyrite and olivine.
- The compact facilities refine and fabricate the frames, wiring and 24 processors.
- Build into the station (fabricate in place, C15): a Basic Core, a goods container and a solar panel, 2,400 ticks each.
- C24 saves 12,450 ticks here. The processors and the station's parts go ahead while a frame job waits on the refinery's iron, instead of the fabricator standing idle behind it.

**The lab, to tick 158,542.**
- `research_lab_mk1` is built in place on the station (6,000 ticks), and the station's core is assigned.
- There's no ice top-up: that was only fuel for the Frost trip.

**The gravity lap, to tick 404,235.**
- The probe stays docked at the station and measures Frost's gravity field from inside the cluster (C18). The measurement lasts one lap of the cluster's orbit round Frost: 245,692 ticks, about 6.8 game hours, played warped (C17).
- The fabricator's processors and cores run on meanwhile.
- The probe never burns: it ends the lap with 1,701 kg.

**Proving it, to tick 422,291, which is 11.7 game hours.**
- Research starts with 140 points: surveys 40, compositions 60, the lap 40.
- Prove Autonomous Navigation at the lab: 3,000 ticks at 100 a tick. It costs 80 of the 140 points.
- `prototype:assisted_core` on the probe: 12,000 ticks at 50 a tick.
- `qualify:assisted_core` at the lab: 3,000 ticks. The Assisted Core is qualified at tick 422,291, which is goal 9.

| Stage | Ends at tick | Propellant | Points |
| ----- | ------------ | ---------- | ------ |
| 1. Chain (Parts A to C) | 71,546 | | |
| 2. Prep | 147,291 | 1,701 kg | 100 |
| 3. Lab | 158,542 | 1,701 | 100 |
| 4. Gravity lap | 404,235 | 1,701 | 140 |
| 5. Research, qualified | 422,291 | 1,701 | 60 left, 80 spent |

**Science:** 4 surveys at 10, 3 compositions at 20 and Frost's gravity field at 40, for 140 earned. The theory takes 80. Before C18b the route landed on Frost for a 50-point surface sample and qualified at tick 402,819 (11.2 h), about 0.5 game hours sooner, at a cost of about 2,100 kg of propellant and the ice runs to replace it.

**The long pole is now the lap.** About 6.8 game hours of the 11.7 is the lap. The compact fabricator's 64 processors take about 77,000 ticks, roughly 2.1 game hours, and run inside it.

### Part D, optional: landing on Frost

Landing and take-off are off the research route until a theory that needs a surface sample brings them back (research.md, design note on Photovoltaic Arrays). These figures are for a person who lands anyway, and for that later trip.

**C16's bot route, before C18b.** The tank was topped up from White Rock in two holds to 2,477 kg (ice fills the 750 L ore hold at about 690 kg, by volume). Then:
- The probe undocks, flies to Red Rock and burns 20 m/s retrograde. It leaves the cluster at tick 181,571 with 2,217 kg.
- It lands straight from the cluster's orbit, at tick 240,491, with 1,215 kg, and takes a surface sample (3,001 ticks, 50 points).
- It takes off to a 35 km orbit (523 kg left), flies one gravity-field lap of 43,790 ticks (40 points), and flies home in 81,150 ticks, docking with 364 kg.

**The landing is the propellant crunch.**
- Landing straight from 300 km cost about 1,000 kg, the climb to 35 km about 690, and the trip home 159. That's about 540 to 600 m/s, depending on the 0.5 to 1.65 t of cargo carried.
- Docking with 364 kg is about 120 to 135 m/s spare, under the 150 m/s line.
- On the bot's first try, without a full tank from ice, the probe was stranded on Frost: it landed with 604 kg and needed 619.
- The bot spent about 260 kg before leaving the cluster, on a trip to Red Rock and the 20 m/s departure burn. Leaving straight from the station with a full tank and an empty goods hold should keep about 190 m/s spare. That's the advice for a person. Measured below, it keeps about 227 m/s.

**The Lead's rulings on this, 2026-11-06:** no data change.
- **C18:** the gravity-field measurement can be taken from inside the cluster frame, so Autonomous Navigation needs no landing. The Lead keeps the full lap.
- **A36 and A39:** the land check warns before a landing the probe can't get back from, pricing the take-off to 30 km plus the leg back to the frame round Frost nearest the probe's orbit, the cluster.
- **For a person who lands:** top up from White Rock's ice, leave the goods hold empty, and leave straight from the station. The goal hint says so, and the hint keeps it.

**The human landing, measured after A39** (main at 48e2a79, merged into B23 at 4104325).
- **The flight.** A 20 m/s retrograde burn out of the cluster, `land` on the cell below, a surface sample, then `take_off` to 30 km (`LowFlight.LEAVE_MM`, the lowest A39 allows), then `move_to` home. Flown on the real `Sim` with no lap, since C18 takes the gravity field in the cluster.
- **The three cases.**
  - Case A is the game's start: it leaves from the cluster's origin with the full 2,500 kg tank and no station.
  - Case B starts from the C16 save after the lab stage, at tick 179,732. The goods are unloaded to the station: copper, iron, silicon and wiring, 451 kg in all. The tank is as topped up from ice, at 2,477 kg. The probe leaves straight from the station.
  - Case C is case B with the tank as it was before the ice top-up, at 1,701 kg.
- **Δv conversion.** Exhaust speed is about 3,000 m/s, from the measured landing.

| | A: start, full tank | B: station, as the hint advises | C: station, no ice top-up |
| --- | --- | --- | --- |
| Mass leaving | 9,930 kg | 10,197 kg | 9,421 kg |
| 20 m/s burn out of the cluster | 66 kg | 68 kg | 63 kg |
| Land check: down | 942 kg, 301 m/s | 978 kg, 304 m/s | 892 kg, 301 m/s |
| Land check: `return_propellant_g`, to the cluster | 803 kg | 825 kg | 758 kg |
| Land check: `cannot_return` | false | false | **true** |
| Landed with | 1,492 kg | 1,432 kg | 745 kg |
| Take off to 30 km | 644 kg, 225 m/s | 662 kg, 225 m/s | 608 kg, 223 m/s |
| In low orbit with | 848 kg | 769 kg | 138 kg |
| Home, 30 km to the cluster | 159 kg | 163 kg | refused, `no_propellant` |
| Used from landed to home | 803 kg | 826 kg | |
| Docked with | 689 kg, about 266 m/s spare | 606 kg, about 227 m/s spare | stranded at 30 km |

- **The warning agrees with every case.** In A and B the price matches what the flight home used, to the kilogram. In C it warns, since 745 kg is under 758 kg, and the probe does strand. The price covers only the way back to the cluster, not a trip on to elsewhere, so the hint keeps its ice advice.
- **The hint's ice top-up advice holds, and is needed.**
  - Following it, the probe docks with about 227 m/s spare, above the 150 m/s line. That's better than the 190 m/s first estimated, because unloading the goods saves about 450 kg.
  - Without the top-up, the probe lands, climbs back, and is stranded in low orbit with 138 kg.
  - From the start, with a full tank and nothing built, the trip is also safe, at about 266 m/s spare.
- **History.** Under A36, `return_propellant_g` priced the climb to `LowFlight.ENTER_MM` (20 km), from which `move_to` home was refused for `unsupported_orbit` and once crashed the script. In case C it said `cannot_return: false`, and the probe stranded. A39 refuses `take_off` below 30 km, cancels a move that loses its orbit, and prices the take-off plus the leg up to the cluster (`return_target`, ID 12).

### Part E: the drone and the handover (goals 10 and 11), measured

C22's stage 6 runs on from the end of Part D at tick 422,291. It is one stage, and all ticks are absolute, with C24's queue skip. At the start:
- The station (60) is docked to the probe's only port (22), and station port 63 is free.
- The probe holds 28 kg of copper, 74 kg of iron, 29 kg of silicon and 1,701 kg of propellant.
- The station holds 150 kg of hematite.
- The Assisted Core is qualified.

**Materials, to tick 426,455.** The probe, with the station in tow as in prep:
- Loads the station's 150 kg of hematite (31 ticks).
- Red Rock: moves there (1,468 ticks) and mines hematite (376 ticks, 900 kg held).
- Brass Rock: moves (876) and mines chalcopyrite (201, 400 kg).
- Green Rock: moves (1,111) and mines olivine (101, 200 kg).
- It ends with 1,300 kg of ore and 1,362 kg of propellant. The three moves burned 339 kg, since the probe tows the station.

**Refining and fabricating, to tick 471,661,** all on the probe's compact facilities:

| Job | Runs | Ticks |
| --- | --- | --- |
| `refine_hematite` | 9 | 10,800 |
| `refine_chalcopyrite` | 4 | 4,800 |
| `refine_olivine` | 2 | 3,600 |
| `structural_frame` | 11 | 7,400 |
| `wiring` | 11 | 8,600, from tick 431,256 |
| `processor` | 14 | 20,400 from tick 433,856, the long pole |
| `basic_core` | 1 | 2,400 |
| `assisted_core` | 1 | 6,000 |
| Small parts: solar 800, radiator 800, tank 600, thruster 800, ore container 600, laser 1,200, battery 1,200 | 7 | 6,000 |
| `small_craft` | 1 | 1,200, done at tick 469,856 |
| `propellant_tank_mk1`, the depot | 1 | 1,800, done at tick 471,656 |

- **C24's skip runs the wiring and processors** while frame jobs wait on the refinery's iron, so they overlap the frames instead of following them. That saves about 2,300 ticks against C22.
- **`small_craft` appears at station port 63.** C15's "a free port of the facility's unit, or the unit it is docked to" now works in either direction of the dock, since here the station is docked to the probe and not the other way round (C22).
- **The depot is built in place on the station's `stack_bottom`.** It needs a stack connector, not a side.
- **The drone is fitted through the docked group (C21)** with eight parts, the `mining_drone` design (B25): solar panel, radiator, small tank, thruster, small ore container, mining laser, `small_battery_bank_mk1` and `assisted_core`. Its core is assigned at tick 471,661, which is goal 10.

**The fuel depot, to tick 471,766.** The drone's small tank holds 100 kg, and it can only transfer with a unit it's directly docked to, which is the station, not the probe. So the probe unloads 500 kg of propellant into the depot (101 ticks) and keeps 862 kg.

**The cycle.** `set_cycle` on the drone, with seven steps:
1. `load_cargo` propellant from the station.
2. `undock`.
3. `move_to` Red Rock.
4. `start_mining` hematite, 500 kg, a full small container.
5. `move_to` the station.
6. `dock` at port 63.
7. `unload` hematite to the station's `ore_container_mk1`.

| Lap | Ticks | Ends at tick | Station hematite | Depot after |
| --- | --- | --- | --- | --- |
| 1 | 7,276 | 479,042 | 500 kg | 395.0 kg |
| 2 | 7,261 | 486,303 | 1,000 kg | 366.2 kg |
| 3 | 7,261 | 493,564 | 1,500 kg | 337.4 kg |

- **Goal 11, the handover, is at tick 479,041,** the first lap done, 13.3 game hours in.
- **The steady-state lap** is 7,261 ticks, about 12.1 game minutes. It burns 28.8 kg of propellant and delivers 500 kg of hematite.
  - Lap 1 starts with an empty tank, so its first load is about 105 kg.
  - Each later lap loads back the 28.8 kg it burned, and the drone ends each lap with 76.2 kg aboard.
- **The depot would run about 11 more laps** from its 337 kg after lap 3, about 2.2 game hours. Part F2 makes it feed itself.
- **The station's 2,000 kg ore store is 1,500 kg full after lap 3,** and would fill on lap 4. That's Part F's reason.

**Fabricating in place needs a free connector.** All 12 of the probe's sides are used, so "Build into…" offers nothing on the probe itself until a station is docked. That's the intended flow: build the small station first, then build big parts into it. A second compact refinery (4.5 m³) or ore container (6 m³) for another craft is also built into a docked station or craft, since neither fits the probe's goods hold.

### Part F: expand (goal 12), measured

The tail of C22's stage 6.
- The drone's cycle is stopped at tick 493,565.
- The probe loads 500 kg of hematite back from the station (101 ticks). Then it refines it (`refine_hematite` ×5, 6,000 ticks) and makes frames (×6, 4,200 ticks).
- It builds a second `ore_container_mk1` in place on the station's next free side (2,400 ticks).
- **The second ore store is in at tick 501,465, 13.9 game hours.** That's goal 12, the last goal.

### Part F2: the depot feeds itself, measured (C23)

At the end of Part F the depot's 337 kg lasts about 11 laps, and then the drone stops. The owner's premise is that cores automate, so the Lead ruled that the chain ends on a loop that feeds itself. C23's stage 7 measures it, on `gameplay/C23` at 29bf68f. It needs no data change.

**The build-up, to tick 561,348 (1.66 game hours).**
1. **Free a side.** All eight of the station's side connectors are in use, and the depot's own sides carry only 500 kg, against a compact refinery's 900 kg. The station's LIDAR on `side_a_px` has done nothing since goal 7, so it is detached into the station's goods hold.
2. **Power.** Fitting sums the rated power of every part. Without the LIDAR the station is rated 102 kW, mostly the lab, so adding the refinery's 100 kW would exceed its 120 kW budget from two solar panels.
   - So two more `solar_panel_mk1` are built in place on the depot's own `side_px` and `side_nx` (150 kg each, against the 500 kg limit), 2,400 ticks each.
   - That makes the budget 240 kW, against 202 kW rated.
   - They must be fitted before the refinery is queued, because `queue_job` dry-runs the install when the command arrives.
3. **Materials:** 19 frames, 14 wiring, 10 processors and 100 kg of silicon.
   - The probe loads the station's 1,000 kg of hematite (201 ticks).
   - It mines Red Rock to 1,400 kg (move 1,468, mine 201) and Brass Rock's chalcopyrite to 500 kg (move 876, mine 251).
   - It refines the hematite, ×14 at 16,800 ticks, before it mines Green Rock's olivine to 600 kg (move 1,111, mine 301), since the ore won't all fit the 2 t hold at once.
   - Refining: chalcopyrite ×5 (6,000) and olivine ×6 (10,800).
   - Fabricating: frames ×19 (11,400), wiring ×14 (5,600) and processors ×10 (12,000).
4. **The refinery.** The panels are done at tick 555,348. `compact_refinery_mk1` is built in place on `side_a_px` (6,000 ticks) at tick 561,348. The probe keeps 534 kg of propellant.
5. **Two standing jobs on it, both with a large count.** `refine_water_ice` comes first, with propellant going to the depot. Then `refine_hematite`, with iron going to the goods container. C24 lets the second run whenever the first waits on its inputs.
6. **The drone's cycle gains an ice leg, at 13 steps.** After unloading hematite it undocks, goes to White Rock, mines water ice to fill the hold, returns, docks and unloads the ice. The small container takes 184 kg of ice, limited by its 200 L volume.

**The loop.**
- **Every cycle is 12,552 ticks, 20.9 game minutes.** Lap 1 was 12,548.
- Each cycle delivers 500 kg of hematite and 184 kg of ice.
- The drone burns 47.1 kg a cycle on the two legs. It fills to about 105 kg and ends each cycle with 57.9 kg aboard. A lap with no ice run shows the same figure, as the depot drops by exactly the drone's 47.1 kg refill.

| Lap | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Depot, kg | 308.5 | 351.4 | 484.3 | 617.1 | 570.0 | 882.9 | 1,015.8 | 1,058.6 | 1,191.5 | 1,324.4 | 1,277.3 | 1,590.1 | 1,723.0 |
| Ore store hematite, t | 0 | 0 | 0 | 0.2 | 0.7 | 0.6 | 0.8 | 1.3 | 1.8 | 2.3 | 2.8 | 3.3 | 3.8 |

- **Propellant: sustained.** The depot gains 117.9 kg a lap on average, against an estimate of 115. It's lumpy because the 90 kg ice runs land unevenly: a lap with no ice run drops by the drone's 47.1 kg refill. At this rate it would reach its 2,000 kg cap in 2 or 3 more laps. **The drone never runs dry.**
- **The refinery,** over the stage:
  - 27 `refine_hematite` runs made 1,863 kg of iron, and 23 `refine_water_ice` runs made 2,070 kg of propellant.
  - Every hematite run went ahead of the waiting ice job under C24, 27 `job_went_ahead` events. The ice job waited 105,016 ticks on `missing_inputs` in all.
  - Frost's shadow paused it for 33,853 ticks, since the station has no battery. It still kept up with the drone, so the optional battery isn't needed.
- **Iron fills the goods container first.** The last hematite run is at tick 643,081, about 6.5 laps after the refinery was built (estimated 5.8). The goods container then holds 1,863 kg of iron, the 100 kg LIDAR and the probe's leftovers. After that the hematite piles up in the ore stores, as the table shows.

**The honest limit: the hematite.**
- At **tick 731,708**, during lap 14's hematite unload, the drone's cycle is `task_blocked` with `cargo_full`. The two 2 t ore stores hold 3.8 t of hematite plus the ice.
- It's a clean block, not a stuck task, and it would resume if room appeared.
- That's 13 full laps, 170,360 ticks or **4.7 game hours** after the refinery was built, against an estimate of 5.6. The estimate was off because the cycle is shorter than expected: 12,552 ticks, not 14,500.
- Without the iron job the ore stores would fill after about 7.5 laps, about 2.6 hours. So the iron job delays the stop by about 2.1 hours, but it doesn't hold the loop steady.
- A steady loop needs something to use the iron: the player hauling it away, or a fabricator on another station module, since this station has no free side. Running out of room is the push to expand. It's the player's next decision, not a bug.

## 4. End state

**At goal 12, tick 501,465, 13.9 game hours.**

| | |
| --- | --- |
| **Station** | Two `ore_container_mk1` holding about 1,000 kg of hematite. The depot, a `propellant_tank_mk1` with 337 kg. The research lab, the goods container, two solar panels, a LIDAR and its Basic Core. Docked to the probe. |
| **Drone** | A `small_craft` docked at station port 63, fitted to the `mining_drone` design, with the Assisted Core assigned and its cycle stopped. |
| **Probe** | 862 kg of propellant. 60 science points unspent. The Assisted Core qualified. |
| **Goals** | 1 to 12 done. 9 is at tick 422,291, 10 at 471,661, 11 at 479,041 and 12 at 501,465. |

**At the loop's stop, tick 731,708, 20.3 game hours.**
- **Station:** the LIDAR is in the goods hold, and a compact refinery sits on `side_a_px`. Two more solar panels are on the depot. The depot holds about 1,723 kg, the goods container 1,863 kg of iron, and the ore stores 3.8 t of hematite.
- **Drone:** blocked at the unload with `cargo_full`.
- **Probe:** 534 kg of propellant.

**Where the time goes.**

| Stretch | Ticks | Game hours |
| --- | --- | --- |
| Parts A to C, to the first station and haul | 71,546 | 2.0 |
| Part D: prep and lab | 86,996 | 2.4 |
| Part D: the gravity lap, warped | 245,693 | 6.8 |
| Part D: proving and qualifying | 18,056 | 0.5 |
| Part E: materials and the drone | 49,475 | 1.4 |
| Part E: three laps | 21,798 | 0.6 |
| Part F | 7,901 | 0.2 |
| **To goal 12** | **501,465** | **13.9** |
| Part F2: the refinery and panels | 59,883 | 1.7 |
| Part F2: 13 laps of the loop, warped | 170,360 | 4.7 |
| **To the loop's stop** | **731,708** | **20.3** |

The gravity lap is almost half the time to goal 12. It's played at warp, and the facilities work through it, so a person spends it prospecting and fabricating. Without the lap, goal 12 comes after about 7.1 game hours of active play. The compact facilities' long poles are the processors: 64 in Part D, 14 in Part E and 10 in Part F2.

## 5. Propellant for a person playing

Measured through the whole chain:
- **Trips in the cluster:** the four trips of Parts A to C cost about 480 kg.
- **Ice:** one 100 kg ice run gave back 90 kg.
- **Margin:** the probe ended Part C with 2,110 kg, and its tank has room for 390 kg more.
- **Making it back:** ice is cheap to make. 100 kg of ice is 51 ticks of mining and 1,200 of refining for 90 kg of propellant. So a person who wastes propellant in the cluster can always make it back once the compact refinery runs.
- **Research (Part D):** the probe never burns after Part C, and reaches goal 9 with 1,701 kg.
- **The drone (Part E):** the material trips, towing the station, cost 339 kg. The depot takes 500 kg, and the probe ends Part F with 862 kg.
- **The drone's laps:** 28.8 kg each in Part E, and 47.1 kg each with the ice leg in F2. Its tank, filled to about 105 kg, covers two of F2's laps without a refuel. It refuels every lap from the depot.
- **The loop (Part F2):** the depot gains about 118 kg a lap. The F2 build-up's trips leave the probe with 534 kg. Person-paced times and the loop's pricing are in [balance.md](balance.md) section 9.

**Landing on Frost** is optional, and the optional part of Part D prices it. Following the hint, it leaves about 227 m/s spare; without the ice top-up, the probe strands. After F2 the probe has 534 kg. A landing for Photovoltaic Arrays (research.md 5.1) needs the tank filled from ice first: about 1,970 kg, three or four ore holds of ice. The station's depot can also refill it once the loop has run, since it holds up to 2 t.
