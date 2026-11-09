# Part Masses

Status: **approved** by the Lead on 2026-11-09: every real mass, applied in B30b together with A53 stage 4 and C35. This is the part-mass audit the Lead asked for after the chain data ([production_chains.md](production_chains.md), answer 4: "real masses throughout").

Each module's mass is set against a real reference, as mass per unit of what the part does: kg per kW, kg per kg held, and so on. Where today's figure is off by more than about 30%, the real figure is proposed.

These are first figures, from public data on flown or flight-qualified hardware. The references are named so they can be checked.

## 1. Power and heat

| Module | Today | Real reference | Proposed | Change |
| --- | --- | --- | --- | --- |
| `solar_panel_mk1`, 60 kW | 150 kg, 400 W/kg | ROSA and UltraFlex arrays, with structure and mechanism: about 100 W/kg at 1 AU | **600 kg** | ×4 |
| `small_solar_panel_mk1`, 30 kW | 80 kg | The same 100 W/kg | **300 kg**, or shrink to 5 kW at 50 kg | see below |
| `solar_farm_mk1`, 300 kW | 1,500 kg | The same | **3,000 kg** | ×2 |
| `heat_radiator_mk1`, 200 kW | 200 kg, 1 kg/kW | ISS PVR and ATCS: about 80 kg/kW with pumps. Modern deployable pumped-loop panels at about 300 K: 20 to 30 kg/kW | **5,000 kg** at 25 kg/kW | ×25 |
| `small_heat_radiator_mk1`, 40 kW | 50 kg | The same | **1,000 kg**, or shrink to 2 kW at 50 kg | see below |
| `battery_bank_mk1`, 100 kWh, as a fuel cell (B30b) | 300 kg | Regenerative fuel cell with tanks: about 350 Wh/kg | 300 kg | none |

**Radiators are the big one.** Rejecting heat in space is heavy. The whole ISS rejects about 70 kW.
- At real masses, the probe's 400 kW of radiators would weigh 10 t, more than its whole 12 t hull limit.
- So the fits have to change. Real ships make less heat: smaller machines, and hotter radiators for the furnaces. Radiators at 500 K reject about 5 times more per m² than at 300 K, so a high-temperature loop for furnace heat is about 5 kg/kW.
- **Proposal:** two radiators, both buildable.
  - A low-temperature `heat_radiator_mk1` at 25 kg/kW, for electronics and people-temperature loads.
  - A `high_temp_radiator_mk1` at 5 kg/kW, which only machines running hot can use: the arc furnace, the refinery, the electrolyser stack.

  Approved. `high_temp_radiator_mk1` is in the data since B30a, with `temp_k` on every radiator and `heat_temp_k` on the hot loads ([schemas.md](schemas.md), "Heat temperatures"). A's HeatSystem rule: a load dumps heat only into radiators at or below its temperature.

**Small craft must shrink their loads, not carry real-mass big parts.**
- A drone with a 30 kW panel at real mass would weigh 300 kg for the panel alone.
- The drone draws about 26 kW rated today, mostly its 20 kW laser.
- Real small mining craft would run at a few kW. See section 3.

## 2. Propulsion and docking

| Module | Today | Real reference | Proposed |
| --- | --- | --- | --- |
| `chemical_thruster_mk1`, 15 kN hydrolox | 300 kg | RL10: 110 kN at about 300 kg. Small pump-fed hydrolox engines of 10 to 20 kN: 50 to 80 kg | **70 kg** |
| `small_chemical_thruster_mk1`, 0.15 kN | 50 kg | Bipropellant RCS thrusters of 100 to 400 N: 2 to 5 kg with valves | **5 kg** |
| `propellant_tank_mk2`, 2.5 m³ | 250 kg | Cryogenic aluminium-lithium tanks with insulation: about 10 to 12% of the hydrolox they hold | for 904 kg of hydrolox, **100 kg**, or more if bigger for stage 4 |
| `hydrolox_tank_mk1`, 5 m³ with cooler | 450 kg | The same, plus a 1 kW cryocooler (about 30 kg) | **230 kg** |
| `docking_port_mk1` | 150 kg | NASA Docking System, IDSS-compliant: about 330 kg | **330 kg** |
| `small_docking_port_mk1` | 60 kg | Small-satellite docking mechanisms: 10 to 30 kg | **25 kg** |
| `landing_legs_mk1`, ×4 for 10 t | 150 kg each | Apollo LM landing gear: about 4% of landed mass in all, so for a 10 t lander about 100 kg a leg | **100 kg** |

## 3. Mining, sensing and computing

| Module | Today | Real reference | Proposed |
| --- | --- | --- | --- |
| `mining_laser_mk1`, 150 kW | 400 kg | Fibre lasers at about 5 kg/kW with power conditioning and cooling plate, plus optics | **900 kg** |
| `small_mining_laser_mk1`, 20 kW | 90 kg | The same | **120 kg**, or 5 kW at 35 kg for a real small drone |
| `lidar_mk1` | 100 kg, 10 kW | Flight lidars (OSIRIS-REx OLA 22 kg; LRO LOLA 14 kg), about 0.1 kW | **25 kg, 0.1 kW** |
| `spectrometer_mk1` (B30a) | 17 kg, 0.05 kW | OSIRIS-REx OVIRS, about 17 kg | in the data since B30a |
| `basic_core`, `assisted_core` | 30 kg, 60 kg | Flight computers in a radiation-hard chassis: 5 to 20 kg | **10 kg, 20 kg** |

## 4. Structure and storage

| Module | Today | Real reference | Proposed |
| --- | --- | --- | --- |
| `starter_hull`, 12 t limit | 2,000 kg | Primary structure is about 8 to 12% of a spacecraft's dry mass | 1,000 kg |
| `small_hull`, 1.5 t limit | 60 kg | The same | 120 kg |
| `ore_container_mk1` | 300 kg, takes up 6 m³ but holds 0.75 m³ | A 2 t ore bin needs about 0.5 m³ for dense ore and 2.5 m³ for ice. The outer volume should be the inner plus walls | 0.75 m³ inner is right for 2 t of hematite. Set outer volume to **1 m³**, since 6 is a data error |
| `goods_container_mk1` | 300 kg, outer 1.5 m³ but holds 4 m³ | Outer smaller than inner is impossible | outer **4.5 m³** |

## 5. What it changes

- **Every template's fit changes,** and some no longer fit their hulls by mass. The probe at real masses:
  - its radiators alone exceed its hull limit;
  - its thruster, lidar, cores and port get lighter;
  - its solar panels get heavier.
- **Fitting warns and allows** (section 8 of production_chains.md), so nothing refuses. But the starting templates must be designed to fit at real masses. That means redesigning the probe and the drone together with A53 stage 4's rebalance.
- **Applied in B30b** with the start: sections 1 to 4. The two-temperature radiator rule goes to A and C.

## 6. Rulings (Lead, 2026-11-09)

1. **Two radiator temperatures: approved.** `heat_radiator_mk1` at 25 kg/kW, and a buildable `high_temp_radiator_mk1` at about 5 kg/kW for hot loads.
2. **Small parts shrink to a few kW at real masses: approved,** rather than keeping their ratings at real mass. The small panel becomes 5 kW at 50 kg, the small laser 5 kW at 35 kg, and the small radiator 2 kW at 50 kg.
3. **Both container volume errors are fixed in B30b.**
