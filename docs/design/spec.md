# Canonical Design Spec

Status: approved by the Lead (task B1). Changes go through the Lead.

This spec replaces [ideadock.md](../../plan/ideadock.md) and [analasysOfIdeadock.md](../../analasysOfIdeadock.md) wherever they disagree with it. Those two stay unchanged as history. It resolves every problem in section 3 of [workplan.md](../../plan/workplan.md) and fixes the slice content from section 7. [contracts.md](contracts.md) (contract version 1) remains the authority on how systems talk to each other. Section 9 records the Lead's rulings.

Part A (sections 2 to 5) is the whole-game catalogue. It exists to make the source docs consistent, and nothing in it is scheduled. Only Part B (sections 6 and 7) goes into `data/`.

## 1. Terms

The source docs use "stage" for three different things. From here on:

| Term | Meaning | Written as |
| ---- | ---- | ---------- |
| Economy stage | Where a thing sits in the resource chain | Stage 1 to Stage 6 |
| Era | A step of civilization progress, matched to an AI tier | Era I to Era VI |
| Process depth | How many manufacturing steps follow the refined material | Depth 1, 2, ... |

"Core" always means an AI core. The structural base of a craft is its **root part**. Where workplan section 5 says a craft is "rooted at its core", read root part.

The probe is crewless (workplan decision 1), so anything that exists only for a crew is out: life support, the Gravity Ring and breathable-atmosphere tanks. Inertial Dampeners protect the ship only.

# Part A: Whole-game catalogue

## 2. The six-stage economy

| Stage | Name | What it holds | How it appears in `data/` |
| ----- | ---- | ------------- | ------------------------- |
| 1 | Natural deposits | Ore bodies, ice, gases and native metals, in place | A deposit definition, not an item |
| 2 | Extracted feedstocks | What collection puts in a hold | Item |
| 3 | Refined materials | Pure metals, silicon, fuels, chemicals | Item |
| 4 | Engineered materials | Alloys, graphene, crystals, superconductors | Item |
| 5 | Manufactured components | Components and modules | Item, and a module definition for modules |
| 6 | Finished structures | Ships, drones, stations | Units, not items |

Rules:

- Every item has exactly one stage, held as a data field.
- A deposit is the Stage 1 body, and the ore it yields is the Stage 2 item of the same name. The analysis's "mineral concentrates" are the same Stage 2 item until a game needs beneficiation as a separate step.
- A name that is both a raw deposit and a refined product splits in two: native copper is Stage 1 and 2, copper is Stage 3.
- A refinery only extracts what its input contains. No recipe outputs an element absent from its input, unless it is a declared nuclear process.
- Each resource has one acquisition method: mining, gas scooping, ice mining, chemical refining, nuclear breeding or accelerator synthesis. These are different operations, not one "extractor".

Process depth, counted from Stage 3: basic equipment is depth 1 to 2, advanced is depth 3 to 4, experimental is depth 5 or more.

## 3. Environments

Four of the original eight environments hold deposits after the corrections below. The other four hold none, so they stop being resource environments.

| Environment | Role | Holds |
| ----------- | ---- | ----- |
| Asteroid Cluster | Mining | Bulk ores, and the slice's asteroid field |
| Asteroid Belt | Mining and ice mining | Native metals, zinc and nickel ores, water ice, ammonia ice, carbon feedstock |
| Planet | Mining and ice mining | Bulk ores, plus the crustal minerals found nowhere else |
| Gas Giant | Gas scooping | Hydrogen, helium, helium-3, methane, ethane, propane, butane, ammonia |
| Star | Power source only | Nothing is mined. It is what solar panels depend on. |
| Dust Cloud | Hazard | No deposits |
| Radiation Bursts | Hazard | No deposits |
| Solar Flares | Hazard | No deposits |

Hazard behaviour is post-slice (workplan section 9).

**Stars.** There is no star-mining technology. Hydrogen and helium move to gas giants, and carbon moves to the belt and planets. Oxygen comes from water electrolysis. Neon has no use anywhere, so it is cut, as are the unnamed trace elements. Hydrogen, helium and oxygen join the catalogue in section 4.

**The eight assignments the analysis rejected, all removed:**

| Removed | Now |
| ------- | --- |
| Rare earths from dust clouds | Monazite and Xenotime on planets |
| Plutonium from dust clouds and radiation bursts | Bred from uranium |
| Antimatter from dust clouds and radiation bursts | Accelerator synthesis |
| Gold and platinum from solar flares | Native metal in the Asteroid Belt |
| Graphene from the belt and flares | Made from carbon at Stage 4 |
| Ozone from the belt, gas giants and flares | Made from oxygen |
| Uraninite from radiation bursts | Mined on planets |
| Tritium from radiation bursts and flares | Bred from lithium |

**Further removals the analysis did not list but its reasoning requires:** silver and copper from solar flares, helium-3 from solar flares, and lithium and silicon from dust clouds.

## 4. Resource catalogue

Every one of the 45 master resources appears below. **New** marks an addition.

### Mined ores (Stage 1 deposit, Stage 2 item)

Environments: C = Asteroid Cluster, B = Asteroid Belt, P = Planet.

| Ore | Found in | Refines to |
| --- | -------- | ---------- |
| Rutile | C, P | Titanium |
| Ilmenite | C, P | Titanium, iron |
| Hematite | C, P | Iron |
| Magnetite | C, P | Iron |
| Siderite | C, P | Iron |
| Bauxite | C, P | Aluminum, gallium (byproduct) |
| Chalcopyrite | C, P | Copper |
| Malachite | C, P | Copper |
| Bornite | C, P | Copper |
| Pentlandite | C, P | Nickel |
| Garnierite | C, B, P | Nickel |
| Sphalerite | C, B | Zinc |
| Smithsonite | C, B | Zinc |
| Galena | C | Lead |
| Cassiterite | C, P | Tin |
| Pyrolusite | C, P | Manganese |
| Rhodochrosite | C, P | Manganese |
| Chromite | C, P | Chromium |
| Olivine **(new)** | C, P | Silicon |
| Scheelite **(new)** | C, P | Tungsten |
| Arsenopyrite **(new)** | C, P | Arsenic |
| Uraninite | P | Uranium |
| Monazite | P | Lanthanum, neodymium, thorium |
| Xenotime **(new)** | P | Yttrium, dysprosium, terbium |
| Spodumene **(new)** | P | Lithium |

Uraninite, Monazite, Xenotime and Spodumene are planet-only because they need a differentiated crust. This gives planets a reason to exist beyond repeating the asteroid list. Thorium and cerium are not catalogue deposits: thorium comes from Monazite, and cerium has no listed use, so it stays in Monazite residue.

### Native metals and non-metals (Stage 1 deposit, Stage 2 item)

| Native resource | Found in | Refines to |
| --------------- | -------- | ---------- |
| Native gold | B | Gold |
| Native silver | B | Silver |
| Native copper | B | Copper |
| Native platinum | B | Platinum, iridium (byproduct, as natural platinum-iridium alloy) |
| Sulfur | P | Sulfur stays a Stage 2 reagent for chemical separation |
| Bismuth | P | Bismuth |
| Carbon feedstock | B, P | Carbon |

### Ices and gases (Stage 1 deposit, Stage 2 item)

| Resource | Found in | Method | Refines to |
| -------- | -------- | ------ | ---------- |
| Water ice | B, P | Ice mining | Water, then hydrogen and oxygen by electrolysis |
| Ammonia | B, Gas Giant | Ice mining, gas scooping | |
| Methane, Ethane, Propane, Butane | Gas Giant | Gas scooping | |
| Hydrogen **(new)** | Gas Giant | Gas scooping | Also from water electrolysis |
| Helium **(new)** | Gas Giant | Gas scooping | |
| Helium-3 | Gas Giant | Gas scooping | |

Water's job is propellant and chemical feedstock. It has no life-support role, since there is no crew.

### Refined materials (Stage 3)

| Material | Route |
| -------- | ----- |
| Iron, Nickel, Titanium, Aluminum, Copper, Zinc, Lead, Tin, Manganese, Chromium, Tungsten, Bismuth, Arsenic, Gallium, Iridium, Gold, Silver, Platinum, Uranium, Thorium, Carbon | Chemical refining of the ores above |
| Silicon | Chemical refining of Olivine. Silicon is not a native deposit. |
| Lithium | Chemical refining of Spodumene |
| Neodymium, Dysprosium, Lanthanum, Terbium, Yttrium | Chemical separation of Monazite and Xenotime |
| Water, Oxygen **(new)** | Melting water ice, then electrolysis |
| Ozone | Synthesized from oxygen |
| Plutonium | Bred from uranium in a nuclear fuel-cycle facility |
| Tritium | Bred from lithium by neutron irradiation |

### Engineered materials (Stage 4), where section 3 touches them

| Material | Inputs |
| -------- | ------ |
| Steel | Iron, manganese |
| Superalloy | Nickel, chromium |
| Gallium Arsenide | Gallium, arsenic |
| YAG | Yttrium, aluminum, oxygen |
| Perovskite | Lead, plus others set when it enters `data/` |
| Quantum Dots | Zinc, plus others set when it enters `data/` |
| Solder **(new)** | Tin, bismuth |
| Graphene | Carbon |
| Antimatter | Accelerator synthesis |

Quartz stays a Stage 4 grown crystal. That is why the silicon chain does not use quartz as its ore (section 6).

### The orphaned ores: each keeps a use

| Metal | Use | Basis |
| ----- | --- | ----- |
| Zinc | Quantum Dots | Zinc sulfide shells |
| Lead | Perovskite, and reactor shielding | Lead-halide solar cells |
| Tin | Solder | Tin-bismuth solder, which also gives bismuth a use |
| Manganese | Steel | A standard alloying addition |
| Chromium | Superalloy | Nickel-chromium superalloys |

Uses for other catalogue entries are not decided here. They are set when an entry enters `data/`, where the validator requires them.

**Nuclear and antimatter accounting.** Antimatter synthesis turns energy into mass, which the matter ledger does not allow today. It will need a declared ledger source when it arrives. Not a slice concern.

## 5. Technology rulings

### AI tiers and eras

Tier N belongs to Era N. This moves "Strategic AI" from Era V to Era IV, where the analysis already put coordinated fleets, and gives Era V the High-Order core.

| Tier and core | Era | Era's focus | Autonomy |
| ------------- | --- | ----------- | -------- |
| 1 Basic | I Early Space Operations | Manual ships, chemical propulsion, basic mining | Runs one order to its end, then waits for the next |
| 2 Assisted | II Industrial Space Infrastructure | Automated extraction, fission, ion propulsion | Repeats a fixed, configured cycle, including its docking steps |
| 3 Adaptive | III Autonomous Industrial Networks | Automated factories, refinery networks | Chooses and re-plans a whole operation, reacts to hazards |
| 4 Strategic | IV Interplanetary Civilization | Fusion, coordinated fleets | Plans across units, fleets and supply networks |
| 5 High-Order | V Interstellar Expansion | Wormhole gateways, interstellar logistics | Predicts and simulates, optimizes logistics |
| 6 Self-Recursive | VI Self-Improving Civilization | Automated research | Improves designs, bounded by physical manufacturing, energy and materials |

**Mining autonomy.** Tier 2 repeats a fixed, configured cycle. Tier 3 chooses and re-plans. So the analysis's "simple mining cycles" belong to tier 2, and "an entire mining operation independently" belongs to tier 3. Tier 2 does not pick deposits or change its steps. When a cycle is interrupted, C0 decides what happens.

AI controls autonomy, not speed. A higher tier never makes a module run faster.

### Jump Coils

Jump Coils are the wormhole initiator, as in the analysis. Their old tracking role (spacetime resonance and gamma-ray bursts) moves to Wormhole Sensors, which already monitor resonance. Destination navigation stays with navigation instruments and sensors. Jump Coils have `realism: fictional`. Not in the slice.

### Entanglement comms

Real entanglement cannot carry a message. Quantum Entanglement Comms is declared **fictional**, working by an invented mechanism, with `realism: fictional`. B2 writes its rules within these limits: units are made in pairs, each pair must be physically carried to its endpoints, so nothing reaches a place before hardware does, and the device needs exotic materials. Not in the slice.

Wormhole energy, stability and accuracy thresholds also go to B2.

# Part B: The slice

## 6. Silica-bearing mineral: Olivine

The slice's third deposit is **Olivine**, (Mg,Fe)₂SiO₄.

- It is the common silicate of real rocky asteroids. Quartz, the obvious alternative, is rare there.
- Quartz is already a Stage 4 crystal in the idea doc, so using it as an ore would put one name at two stages.
- Silicon is about 19% of its mass, against about 70% iron in hematite and 35% copper in chalcopyrite. That makes silicon the scarce metal of the slice, on real numbers, and gives solar panels and processors something to compete over.
- Its natural green separates it from red hematite and brassy chalcopyrite, which helps the client show deposits by colour.

## 7. Slice content

This fixes workplan section 7. IDs below are final unless the Lead changes them. B5 sets all quantities and rates.

### 7.1 Items

| ID | Stage | `cargo_class` | Discrete | Source | Use |
| -- | ----- | ------------- | -------- | ------ | --- |
| `hematite` | 2 | `ore` | No | Mining | Refining |
| `chalcopyrite` | 2 | `ore` | No | Mining | Refining |
| `olivine` | 2 | `ore` | No | Mining | Refining |
| `iron` | 3 | `goods` | No | Refining | Fabrication |
| `copper` | 3 | `goods` | No | Refining | Fabrication |
| `silicon` | 3 | `goods` | No | Refining | Fabrication |
| `slag` | 3 | `ore` | No | Refining | Vented to a sink |
| `propellant` | 3 | `propellant` | No | Scenario stock only | Burned by thrusters |
| `structural_frame` | 5 | `goods` | Yes | Fabrication | Fabrication |
| `wiring` | 5 | `goods` | Yes | Fabrication | Fabrication |
| `processor` | 5 | `goods` | Yes | Fabrication | Fabrication |

Discrete items declare `unit_mass_kg` and move in whole units (contracts section 5). Each deposit definition references its ore item. Stage 4 does not appear in the slice, and Stage 2 has no concentrate step. Every slice recipe is depth 1 or 2, which is basic equipment.

**Yield ceiling.** Slice recipes are abstract, with one product plus slag. B5 may not set a yield above the element's real mass share: hematite 69.9% iron, chalcopyrite 34.6% copper, olivine about 19% silicon. All other mass goes to slag, including the iron in chalcopyrite. There is no off-gas item in the slice.

**Slag leaves automatically.** A refinery vents slag into the declared sink `slag_vent` when the job finishes. It takes no storage and no player action. If slag sat in storage, a tier 2 operation would slowly fill it and stall, punishing the handover the slice is meant to prove, with no real decision for the player. Slag stays on the matter ledger, and the slice's two sinks are `slag_vent` and `propellant_exhaust`. Its `ore` class is nominal, since every item needs one and slag never enters an inventory.

**Propellant** is one abstract item. It is on the matter ledger, and the slice has no way to make more. The stock must cover all ten checks with margin (B8), and a craft that cannot cover a trip reports `no_propellant` rather than stalling silently. Running out ends the slice run, which is accepted.

### 7.2 Modules

While uninstalled, each module is a discrete `goods` item with the same ID (contracts section 5). Realism is from the analysis's classification.

| ID | Listed under | Fabrication inputs | Realism |
| -- | ------------ | ------------------ | ------- |
| `starter_hull` | Ship | None, scenario only | established |
| `chemical_thruster_mk1` | Ship | `structural_frame`, `iron` | established |
| `propellant_tank_mk1` | Ship | `structural_frame`, `iron` | established |
| `solar_panel_mk1` | Ship | `structural_frame`, `wiring`, `silicon` | established |
| `battery_bank_mk1` | Ship | `structural_frame`, `wiring`, `copper` | established |
| `heat_radiator_mk1` | Ship | `structural_frame`, `copper` | established |
| `lidar_mk1` | Ship | `structural_frame`, `wiring`, `processor` | established |
| `mining_laser_mk1` | Ship | `structural_frame`, `wiring`, `processor` | extrapolation |
| `ore_container_mk1` | Ship | `structural_frame` | established |
| `docking_port_mk1` | Ship and station | `structural_frame`, `wiring` | established |
| `command_hub` | Station | None, scenario only | established |
| `solar_farm_mk1` | Station | `structural_frame`, `wiring`, `silicon` | established |
| `ore_refinery_mk1` | Station | `structural_frame`, `wiring`, `processor` | extrapolation |
| `fabricator_mk1` | Station | `structural_frame`, `wiring`, `processor` | extrapolation |
| `ore_storage_mk1` | Station | `structural_frame` | established |
| `goods_storage_mk1` | Station | `structural_frame` | established |
| `basic_core` | Core | `processor`, `wiring` | established |
| `assisted_core` | Core | `basic_core`, `processor` | extrapolation |
| `mining_drone_body` | Drone | None, built only through the `mining_drone` template | extrapolation |

Rulings on section 7's wording:

- **Any module may fit any craft** if the connectors allow it. The two lists say where a part is normally used. This is how the station gets radiators and batteries for refinery heat and load, since neither is on its list.
- **The depot is not a new module.** The finite propellant stock sits in `propellant_tank_mk1` units fitted to the station.
- **"Ore and goods storage" is two modules,** matching the idea doc's two container types. One docking port definition serves both ships and stations.
- **`command_hub` is the station frame.** It is the station's root part and carries its hardpoints, so section 7's "station frame" model and its "command hub" are one model. There is no separate frame module.
- **Root parts are not fabricated.** The slice has one starter ship and one station, so `starter_hull` and `command_hub` exist only through the scenario.

### 7.3 Components, cores and the drone

| ID | Facility | Inputs |
| -- | -------- | ------ |
| `structural_frame` | Fabricator | `iron` |
| `wiring` | Fabricator | `copper` |
| `processor` | Fabricator | `silicon`, `copper` |
| `mining_drone` (unit template) | Fabricator | `structural_frame`, `wiring`, `processor` |

**Cores** are modules, although workplan section 7 lists them under components. The contracts require this: a core carries the `ai_core.tier` capability, is fitted with `attach_part`, and is then selected with `assign_core`. Each root part has one small `side` connector for a core, so a slice unit carries one core at a time. Cores have no pipeline model, so the labelled placeholder rule applies. B5 keeps their power and heat draw small enough that fitting a core never fails a budget by accident. The starter ship and station begin with a `basic_core` fitted and assigned.

**The drone** is one unit with one model, as section 7 implies. Its template holds a single root part, `mining_drone_body`, with built-in mining, ore and propellant storage, thrust, power, heat and docking, plus a core connector. It has no LIDAR, so it works deposits that have already been found. It is built from components only, not from full-size modules, which keeps it small. It appears docked at a free station port with no core and an empty tank, so core fitting stays a separate step (check 8). Its `min_ai_tier` is 1: a Basic Core can fly it order by order, and only `set_cycle` needs tier 2.

**Unit templates.** A unit's `def` is its template ID. The slice has three: `starter_ship` (root `starter_hull`, kind `ship`), `starter_station` (root `command_hub`, kind `station`) and `mining_drone` (root `mining_drone_body`, kind `drone`). Only `mining_drone` is built by a recipe. B8 sets the other two.

**Fabrication output.** Goods stay on the station. Neither the ship nor the drone has goods capacity, so hauling in the slice means ore inward and propellant outward. A docked craft installs parts by naming the station as `from`.

### 7.4 Cargo classes

Each unit has one inventory, with capacity by the contracts' three classes:

| Class | Holds | Provided by |
| ----- | ----- | ----------- |
| `ore` | Ores | `ore_container_mk1`, `ore_storage_mk1`, `mining_drone_body` |
| `goods` | Materials, components, cores, unfitted modules | `goods_storage_mk1` |
| `propellant` | Propellant | `propellant_tank_mk1`, `mining_drone_body` |

A0 expands this in the cargo spec.

### 7.5 Fitting limits

`attach_part` checks mass, power, heat and connectors against declared ratings, as set out in contracts section 5. A failure gives `attach_failed` with a reason and numbers, and `check` shows the same result beforehand. Running shortfalls are handled separately by shedding and faults.

For check 10, B5 and B8 set numbers so that attaching the starter ship's first upgrade fails with `over_heat_budget`, and fitting one `heat_radiator_mk1` first fixes it. Heat is the preferred case because the analysis ranks it a top foundation.

The power and heat budgets sum every module's active draw, whether or not those modules ever run together. Starting fits and `mining_drone_body` must pass these same rules, so B5 needs ratings with that in mind, especially on the station, which carries the refinery and fabricator.

### 7.6 The ten checks against this content

| # | Check | Path |
| - | ----- | ---- |
| 1 | Scan | `lidar_mk1` on the starter ship scans an asteroid. LIDAR identifying minerals is a declared simplification. |
| 2 | Mine | `mining_laser_mk1` fills `ore_container_mk1` from a found deposit |
| 3 | Haul | Fly and dock, then unload into `ore_storage_mk1` |
| 4 | Refine | `ore_refinery_mk1` makes metal and vents slag |
| 5 | Fabricate | `fabricator_mk1` makes a `structural_frame` or other component |
| 6 | Install | Components become a module, attached to the docked ship. Only modules attach, so this check needs one more fabrication step than check 5. |
| 7 | Build a drone | The `mining_drone` recipe at the fabricator, appearing at a free port |
| 8 | Hand over | Hand-run the cycle first on the starter ship. Then fit an `assisted_core` to the drone with `attach_part`, select it with `assign_core`, and start `set_cycle`. The cycle must include a propellant load. |
| 9 | Expand | Attach one more station module. B8 picks which. |
| 10 | Fail and fix | Section 7.5 |

## 8. Where each section 3 problem is resolved

| Problem | Resolved in |
| ------- | ----------- |
| Resources at mixed levels | 2, 4 |
| Eight incredible assignments | 3 |
| Quantum entanglement | 5 |
| Water, Magnetite, Monazite, Sulfur, Bismuth had no environment | 4 |
| Uraninite and Thorium had no source | 4 |
| Tungsten, Iridium, Gallium, Arsenic, Yttrium had no source | 4 |
| Zinc, Lead, Tin, Manganese, Chromium had no use | 4 |
| Hydrogen, Helium, Oxygen, Neon outside the list; star mining | 3, 4 |
| No silica-bearing mineral | 4, 6 |
| Jump Coils role | 5 |
| AI tiers and stages disagree | 5 |
| Mining autonomy disagrees | 5 |

Two problems not in section 3 are resolved here too. Lithium's only source was the Dust Cloud, which the analysis's reasoning rules out, so Spodumene is added. "Stage" had two numbered meanings, so Era is introduced.

## 9. Lead rulings

All four proposed answers are accepted. The workplan and contracts are updated to match.

| # | Issue | Ruling |
| - | ----- | --------------- |
| 1 | Workplan section 7 lists Basic and Assisted Core as components, but the contracts make them modules. | The contracts win. Update the workplan, or leave it, since this spec records the ruling. |
| 2 | Workplan task A3 says fitting checks volume. Contracts section 5 checks mass, power, heat and connectors only, so a module's `volume_m3` is not a fit limit. | The contracts win: volume limits cargo stores only. Correct A3's wording. |
| 3 | Contracts section 2 puts items and modules in one namespace, but says nothing about unit templates, and section 7 only shows `def = "..."`. | A unit's `def` is its template ID, in a namespace of its own. |
| 4 | Recipe outputs have no stated way to go straight to a sink. | No contract change. B3 adds the routing to the recipe schema, and contracts section 9 already counts sinks. Noted so that the ledger test expects `slag_vent`. |

## 10. Handed on

| Task | Takes from this spec |
| ---- | --------------------- |
| B2 | Entanglement limits and wormhole thresholds (section 5) |
| B3 | An item `stage` field, sink routing, unit template schema, and how a module's `volume_m3` relates to the `density_kg_m3` of its same-ID item, so the two cannot disagree |
| B4 | A source may be a deposit, a recipe or scenario stock. A use may be a recipe input, `attach_part`, propellant burn or a sink. The check applies to `data/` only, not Part A. Every unit template must pass the fit rules. |
| B5 | All quantities within the yield ceilings. Module mass must equal its recipe's input mass. Recipe `seconds` are whole numbers. |
| B7 | Sinks `slag_vent` and `propellant_exhaust` |
| B8 | `starter_ship` and `starter_station` fits, propellant stock, station expansion choice, check 10 numbers |
| A0 | Cargo classes in the cargo spec, propellant cost per trip |
| C0 | Interruption of a tier 2 cycle, including the refuel step |
