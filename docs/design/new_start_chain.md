# New Start Chain

Status: **draft**, task B23. Sections 1 and 2 are measured on the real `Sim`, from [data/scenarios/new_start.json](../../data/scenarios/new_start.json) on `main` at d85aac6. Section 3, Parts A to D, is measured by C's new-start bot (C14 at adf431a for Parts A to C, and C16 at dce5c55 through research, seed 12345). Parts E and F, the drone and expansion, come with C's next bot task. This page is to the new start what [reference_scenario.md](reference_scenario.md) is to today's station game. When `reference.json` becomes the new start, the two pages swap names. Until then `reference_scenario.md` stays as the station fixture's worked chain, which many tests cite.

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

C16 runs on from the end of Part C, which, with C15, ends at tick 71,546 with an `ore_container_mk1` built in place on the station. All ticks are absolute.

**Prep, to tick 159,741.**
- Take composition at Red, Brass and Green Rock (1,201 ticks each), and mine full holds of hematite, chalcopyrite and olivine.
- The compact facilities refine and fabricate the frames, wiring and 24 processors.
- Build into the station (fabricate in place, C15): a Basic Core, a goods container and a solar panel, 2,400 ticks each.

**The lab, to tick 179,537.**
- Top up the tank from White Rock in two holds. Ice fills the 750 L ore hold at about 690 kg, by volume.
- `research_lab_mk1` is built in place on the station (6,000 ticks), and the station's core is assigned.
- The tank is topped up to 2,477 kg at tick 173,536.

**Frost, to tick 384,763.**
- The probe undocks, flies to Red Rock and burns 20 m/s retrograde. It leaves the cluster at tick 181,571 with 2,217 kg.
- It lands straight from the cluster's orbit, at tick 240,491, with 1,215 kg, and takes a surface sample (3,001 ticks, 50 points).
- It takes off to a 35 km orbit (523 kg left), flies one gravity-field lap of 43,790 ticks (40 points), and flies home in 81,150 ticks, docking with 364 kg.

**Proving it, to tick 402,819, which is 11.2 game hours.**
- Prove Autonomous Navigation at the lab: 3,000 ticks at 100 a tick. It costs 80 of the 190 points.
- `prototype:assisted_core` on the probe: 12,000 ticks at 50 a tick.
- `qualify:assisted_core` at the lab: 3,000 ticks. The Assisted Core is qualified at tick 402,819, which is goal 9.

| Milestone | Tick | Propellant | Points |
| --------- | ---- | ---------- | ------ |
| Prep refined | 99,542 | 1,927 kg | 60 |
| Prep done | 159,741 | 1,701 | 100 |
| Tank topped up | 173,536 | 2,477 | 100 |
| Left the cluster | 181,571 | 2,217 | 100 |
| Landed on Frost | 240,491 | 1,215 | 150 |
| Low orbit | 259,622 | 523 | 150 |
| Lap done | 303,412 | | 190 |
| Docked at home | 384,763 | 364 | 190 |
| Qualified | 402,819 | | 110 left, 80 spent |

**Science:** 4 surveys at 10, 3 compositions at 20, a surface sample at 50 and Frost's gravity field at 40, for 190 earned. The theory takes 80.

**The Frost trip is the propellant crunch.**
- Landing straight from 300 km cost about 1,000 kg, the climb to 35 km about 690, and the trip home 159. That's about 540 to 600 m/s, depending on the 0.5 to 1.65 t of cargo carried.
- Docking with 364 kg is about 120 to 135 m/s spare, under the 150 m/s line.
- On the bot's first try, without a full tank from ice, the probe was stranded on Frost: it landed with 604 kg and needed 619.
- The bot spent about 260 kg before leaving the cluster, on a trip to Red Rock and the 20 m/s departure burn. Leaving straight from the station with a full tank and an empty goods hold should keep about 190 m/s spare. That's the advice for a person, and it needs measuring in the drone task.

**The long pole is the compact fabricator.** Its 64 processors take about 77,000 ticks, roughly 2.1 game hours, and they run alongside the Frost trip.

### Part E: the drone and the handover (goals 10 and 11), planned

1. Build `small_craft` at the station.
2. Fit its six parts, plus `small_battery_bank_mk1` and an Assisted Core.
3. `set_cycle` from Red Rock to the station's ore storage, which is fabricated in place. Stop at the third lap.

**Fabricating in place needs a free connector.** All 12 of the probe's sides are used, so "Build into…" offers nothing on the probe itself until a station is docked. That's the intended flow: build the small station first, then build big parts into it. A second compact refinery (4.5 m³) or ore container (6 m³) for another craft is also built into a docked station or craft, since neither fits the probe's goods hold.

### Part F: expand (goal 12), planned

Fit a second ore storage to the station.

## 4. End state

Pending the full run through Part F. What's measured to the haul is in section 3.

## 5. Propellant for a person playing

Measured to the haul:
- **Trips in the cluster:** the four trips cost about 480 kg.
- **Ice:** one 100 kg ice run gave back 90 kg.
- **Margin:** the probe ended Part C with 2,110 kg, and its tank has room for 390 kg more.
- **Making it back:** ice is cheap to make. 100 kg of ice is 51 ticks of mining and 1,200 of refining for 90 kg of propellant. So a person who wastes propellant in the cluster can always make it back once the compact refinery runs.

**Still to measure:** the Frost round trip, about 640 m/s flown, from a tank that should be topped up first, and the drone's laps. Those come from Parts D to F.
