# New Start Chain

Status: **draft**, task B23. Sections 1 and 2 are measured on the real `Sim`, from [data/scenarios/new_start.json](../../data/scenarios/new_start.json) on `main` at d85aac6. Section 3's timings and section 4's end state wait for C14's bot playthrough, and the TBD cells are filled from it. This page is to the new start what [reference_scenario.md](reference_scenario.md) is to today's station game. When `reference.json` becomes the new start, the two pages swap names. Until then `reference_scenario.md` stays as the station fixture's worked chain, which many tests cite.

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

Each part names the goals of [start_and_build.md](start_and_build.md) section 4.1 that it meets. Ticks are TBD from C14.

### Part A: prospect (goals 1 and 2)

1. Survey Red Rock: a `scan` that also pays 10 science points.
2. Take its composition (`measure` kind `composition`, 120 s, 20 points).
3. Mine 2,000 kg of hematite.

### Part B: the seed factory (goals 3 and 4)

1. Refine the hematite on `compact_refinery_mk1`: 100 kg runs, 60000 work each at 50 a tick, so 120 s a run, 200 kW drawn at half, so 100 kW.
2. Fabricate frames and wiring on `compact_fabricator_mk1`.
3. Make trips to Brass Rock and Green Rock for copper and silicon, surveying and taking composition at each. Then make processors.
4. Make a trip to White Rock to survey it, and mine ice to top up the propellant.

### Part C: the first station (goals 5, 6, 7 and 8)

1. Fly to a site near Red Rock and build `small_station` there: 24 frames and 10 wiring.
2. Fit a solar panel, `ore_storage_mk1`, a propellant tank, a Basic Core, a second battery bank (for Frost's eclipses) and `research_lab_mk1`.
3. The lab's fit is refused for power until the battery or a second panel is fitted. That is goal 7, fail and fix.
4. Unload ore into the station: goal 8, haul.

### Part D: research (goal 9)

1. The probe lands on Frost and comes back, flying one lap of the low orbit first for `gravity_field` (40 points). The landing also allows a `surface` sample (50 points).
2. Prove Autonomous Navigation at the station's lab: 80 points, with the evidence of 3 surveys and 1 gravity field. The station's Basic Core meets era II's gate.
3. Prototype the Assisted Core (`prototype:assisted_core`), then bench-test it (`qualify:assisted_core`). `design_qualified` is goal 9.

### Part E: the drone and the handover (goals 10 and 11)

1. Docked at the station, the probe builds `small_craft`, which appears at the station's spare port.
2. Fit its six parts, plus `small_battery_bank_mk1` for eclipses, and an Assisted Core.
3. `set_cycle` between Red Rock and the station's ore storage. Stop at the third lap.

### Part F: expand (goal 12)

The cycle's ore is refined, and a second `ore_storage_mk1` is fitted to the station.

## 4. End state

TBD from C14: matter by place, science points earned and spent, and propellant used and made from ice.

## 5. Propellant for a person playing

TBD from C14 and person_run. The questions this section answers:
- How much of the 2,500 kg the chain burns.
- How much ice refining makes back.
- How much a person's mistakes can cost before the ice chain is running.
- Whether the Frost trip's 230 m/s spare holds when flown in the chain's order.
