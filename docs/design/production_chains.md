# Production Chains

Status: **approved** by the Lead on 2026-11-08, task B29. It applies the owner's rulings of 2026-11-07 (workplan, "Owner's rulings"):
- deep, real production chains;
- research tests as field trials, with a chance of manufacturing defects;
- factory speed set by power, heat and throughput;
- fitting that warns and allows.

The data comes in two steps:
- **B29, additive:** the chain items, recipes and machines, the fluid tanks, the cryo capability and the validator. Nothing in the new start changes.
- **B30, the switch-over,** together with A53 stage 4 and C's route rewrite:
  - the parts made from chain materials;
  - the abstract `refine_*` recipes removed;
  - Black Rock in the scenario;
  - the probe's seed chips;
  - the fuel-cell battery;
  - hydrolox in the probe's tank, settled in the stage 4 rebalance.

Contract changes go through the Lead as usual.

## 1. Principles

- **Real reactions, balanced to the gram.** Every recipe is a real process.
  - Each run is sized on 100 kg of its main input.
  - Inputs and outputs balance exactly, from molar masses: the matter ledger holds with no abstract slack.
  - `abstract` becomes false on every chain recipe.
  - The figures come from a calculator script, not hand arithmetic. It's outside the repo for now, and can go into `tools/` if the Lead wants it.
- **Real energy and heat.** Each run states `energy_kj`, the energy put in, from real process figures. It also states `heat_kj`: the energy put in, less what the products store, plus any reaction heat. So an exothermic step such as copper smelting gives off more heat than its power, and the radiators hold it back (C30).
- **Nothing is vented that has a use.** Slag, scrap, salts, gases and anode slime are kept as items, each with a use. The only losses are physical ones: cryogenic boil-off, and a vent the player orders.
- **Purity is a grade, not an element count.**
  - `silicon` is metallurgical grade, `pure_silicon` is electronic grade, and blister copper is 99%.
  - A refining step's tail keeps the impurities as its own item.
  - This is a modelling convention for trace mass, not a skipped step: every step is there.
- **Ores are rich deposits, not pure minerals.**
  - Hematite ore is 90% Fe₂O₃ and 10% silica.
  - Chalcopyrite ore is 89.5% CuFeS₂, 10% silica and 0.5% trace metals.
  - White Rock's ice is 95% water and 5% dust.
  - Olivine is taken as forsterite, Mg₂SiO₄, the magnesium end of real asteroid olivine.
  - The gangue goes somewhere real. In copper smelting the silica is the flux that turns FeO into fayalite slag.

## 2. The loops

Three closed loops carry most of the mass. The player sees them as recycling. Each one costs power, not material.

1. **Hydrogen.**
   - Electrolysis splits water into hydrogen and oxygen.
   - The hydrogen reduces hematite to iron and turns back into water, which goes back to electrolysis. The Bosch reactor does the same with carbon monoxide.
   - So iron costs power, not hydrogen. Only the propellant that's burned leaves the loop.
2. **Carbon.**
   - The arc furnace reduces silica with carbon and gives off carbon monoxide.
   - The Bosch reactor turns that back into carbon and water with hydrogen.
   - So silicon costs power, and carbon is needed only to start the loop and for steel.
   - Overall the loop turns silica into silicon plus oxygen, by way of the water.
3. **Acid.**
   - Copper smelting's sulfur dioxide becomes sulfuric acid.
   - The acid leaches olivine into silica and magnesium sulfate.
   - Calcining the salt gives the acid back, plus magnesia for furnace linings.
   - So silicon's acid is lent, not spent. Copper's sulfur tops the loop up.

**Oxygen is a surplus.**
- Water gives 7.94 kg of oxygen for each kg of hydrogen, and the engines burn 6.
- Each 100 kg of water burned as propellant leaves 21.7 kg of LOX spare.
- Copper smelting, converting and the acid plant use that spare.

## 3. Items

| Item | Class | Density | From | Used for |
| --- | --- | --- | --- | --- |
| `water` | water | 1,000 | Melted ice, reduction, Bosch, pyrolysis | Electrolysis, the acid plant and regeneration |
| `hydrogen` (LH₂) | fuel | 71 | Electrolysis | Engines, iron reduction, Bosch |
| `oxygen` (LOX) | oxidiser | 1,141 | Electrolysis | Engines, smelting, converting, the acid plant |
| `sponge_iron` | goods | 3,500 | Hydrogen reduction | Steel |
| `steel` | goods | 7,850 | Arc furnace | Frames, tanks, thrusters, housings |
| `steel_scrap` | ore | 2,000 bulk | Frame offcuts | Remelting |
| `carbon` | goods | 1,500 bulk | Pyrolysis, Bosch | Steel, silica reduction |
| `copper_matte` | goods | 5,600 | Smelting | Converting |
| `blister_copper` | goods | 8,900 | Converting | Electrorefining |
| `copper` | goods | 8,900 | Electrorefining | Wiring, boards, chips, thruster chambers |
| `anode_slime` | ore | 3,000 | Electrorefining | Kept for the belt's precious-metal chains |
| `sulfur_dioxide` | gas | 1,460 (liquid) | Smelting, converting | The acid plant |
| `sulfuric_acid` | acid | 1,830 | The acid plant, regeneration | Leaching, the electrolyte, fab etch |
| `spent_acid` | acid | 1,600 | Fab etch | Concentrated back to acid |
| `silica` | goods | 600 bulk | The olivine leach | Silica reduction |
| `magnesium_sulfate` | goods | 1,200 bulk | The leach | Acid regeneration |
| `magnesia` | goods | 1,500 bulk | Regeneration | Furnace linings; later magnesium |
| `carbon_monoxide` | gas | 230 (200 bar) | Silica reduction | Bosch |
| `silicon` | goods | 2,330 | Silica reduction | Zone refining |
| `pure_silicon` | goods | 2,330 | Zone refining | Wafers |
| `silicon_scrap` | ore | 1,200 bulk | Refining tail, kerf, failed dies | Recast to silicon |
| `wafer` | goods, 50 g each | 2,330 | Crystal growth | Chips, solar cells |
| `chip` | goods, 2 g each | 2,330 | Chip fab | Processors |
| `phosphorus` | goods | 1,820 | Pyrolysis | The fab's dopant |
| `glass_fibre` | goods | 1,000 bulk | Slag | Insulation, circuit boards |
| `carbonaceous_ore` | ore | 2,200 | A new carbon rock (section 9) | Pyrolysis |
| `slag` | ore | 2,500 | Every smelt and filter | Glass fibre; later shielding and ballast |

- **`iron` and `propellant` go.** Iron is replaced by `sponge_iron` and `steel`, and propellant by `hydrogen` and `oxygen`.
- **The new cargo classes are water, fuel, oxidiser, acid and gas.** Each needs its own tanks, since none of them can share with another: hydrogen with oxygen is a bomb, and acid with water is unsafe. The two gases are kept apart from the oxidiser.

## 4. Machines

| Machine | Type | Rating | Throughput | Mass | Runs |
| --- | --- | --- | --- | --- | --- |
| `compact_refinery_mk1` | refinery | 100 kW | 0.05 kg/s | 900 kg | Melting, reduction, smelting, converting, the acid plant, leaching, regeneration, Bosch, pyrolysis |
| `ore_refinery_mk1` | refinery | 200 kW | 0.2 kg/s | 3,000 kg | The same, faster |
| `electrolyser_mk1`, **new** | electrolyser | 200 kW | 0.01 kg/s | 1,200 kg | Water electrolysis with liquefaction; copper electrorefining |
| `arc_furnace_mk1`, **new** | arc_furnace | 500 kW | 0.1 kg/s | 3,000 kg | Steel, remelting, silica reduction, glass fibre, silicon recasting |
| `semiconductor_fab_mk1`, **new** | semiconductor_fab | 300 kW | 0.002 kg/s | 5,000 kg | Zone refining, crystal growth and slicing, chip fab |
| `compact_fabricator_mk1` | fabricator | 50 kW | 0.02 kg/s | 800 kg | Frames, wire, boards, parts, hulls |
| `fabricator_mk1` | fabricator | 100 kW | 0.05 kg/s | 2,000 kg | The same, faster |

- The electrolyser liquefies its own products, because storing hydrogen and oxygen as gas would need two more tank types and a liquefier between them.
- New machines also need radiators, since most of their power ends as heat.
- The new machines' throughputs are first figures, to settle when machine sizes are balanced after C30 and stage 4.

## 5. The chains

Each run, on its machine at full rating, with 200 kW of radiator headroom. The limit column says which of C30's three rates sets the run's length.

| Recipe | Machine | In, per run | Out, per run | Energy | Heat | Run at full rating | Limit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `melt_ice` | compact_refinery_mk1 | water ice 100 kg | slag 5 kg, water 95 kg | 68 MJ | 7 MJ | 33 min | throughput |
| `electrolyse_water` | electrolyser_mk1 | water 100 kg | hydrogen 11.191 kg, oxygen 88.809 kg | 2,787 MJ | 1,199 MJ | 3.9 h | power |
| `reduce_hematite` | compact_refinery_mk1 | hematite 100 kg, hydrogen 3.409 kg | water 30.46 kg, sponge iron 72.949 kg | 200 MJ | 144 MJ | 34 min | throughput |
| `make_steel` | arc_furnace_mk1 | sponge iron 100 kg, carbon 0.173 kg | slag 13.708 kg, steel 86.465 kg | 190 MJ | 190 MJ | 17 min | throughput |
| `remelt_steel_scrap` | arc_furnace_mk1 | steel scrap 100 kg | steel 100 kg | 220 MJ | 220 MJ | 18 min | heat |
| `smelt_chalcopyrite` | compact_refinery_mk1 | chalcopyrite 100 kg, oxygen 31.211 kg | slag 45.039 kg, sulfur dioxide 46.863 kg, copper matte 39.309 kg | 30 MJ | 306 MJ | 44 min | throughput |
| `convert_matte` | compact_refinery_mk1 | copper matte 100 kg, oxygen 19.85 kg | sulfur dioxide 39.738 kg, blister copper 80.112 kg | 20 MJ | 155 MJ | 40 min | throughput |
| `electrorefine_copper` | electrolyser_mk1 | blister copper 100 kg, sulfuric acid 0.5 kg | anode slime 2.088 kg, copper 98.412 kg | 106 MJ | 106 MJ | 2.8 h | throughput |
| `make_sulfuric_acid` | compact_refinery_mk1 | sulfur dioxide 100 kg, oxygen 24.976 kg, water 28.123 kg | sulfuric acid 153.099 kg | 15 MJ | 376 MJ | 51 min | throughput |
| `leach_olivine` | compact_refinery_mk1 | olivine 100 kg, sulfuric acid 139.415 kg | magnesium sulfate 171.1 kg, water 25.609 kg, silica 42.706 kg | 40 MJ | 212 MJ | 1.3 h | throughput |
| `regenerate_acid` | compact_refinery_mk1 | magnesium sulfate 100 kg, water 14.967 kg | magnesia 33.486 kg, sulfuric acid 81.481 kg | 300 MJ | 171 MJ | 50 min | power |
| `reduce_silica` | arc_furnace_mk1 | silica 100 kg, carbon 39.981 kg | carbon monoxide 93.238 kg, silicon 46.743 kg | 1,851 MJ | 716 MJ | 1.0 h | power |
| `recover_carbon` | compact_refinery_mk1 | carbon monoxide 100 kg, hydrogen 7.197 kg | water 64.316 kg, carbon 42.881 kg | 50 MJ | 676 MJ | 56 min | heat |
| `refine_silicon` | semiconductor_fab_mk1 | silicon 100 kg | silicon scrap 10 kg, pure silicon 90 kg | 7,200 MJ | 7,200 MJ | 13.9 h | throughput |
| `grow_wafers` | semiconductor_fab_mk1 | pure silicon 100 kg | silicon scrap 50 kg, wafer 50 kg | 12,600 MJ | 12,600 MJ | 17.5 h | heat |
| `fab_chips` | semiconductor_fab_mk1 | wafer 0.5 kg, copper 0.1 kg, phosphorus 0.01 kg, sulfuric acid 5 kg | silicon scrap 0.41 kg, spent acid 5 kg, chip 0.2 kg | 5,400 MJ | 5,400 MJ | 7.5 h | heat |
| `pyrolyse_carbonaceous_ore` | compact_refinery_mk1 | carbonaceous ore 100 kg | water 12 kg, carbon 4 kg, phosphorus 0.1 kg, slag 83.9 kg | 180 MJ | 150 MJ | 33 min | throughput |
| `draw_glass_fibre` | arc_furnace_mk1 | slag 100 kg | slag 5 kg, glass fibre 95 kg | 540 MJ | 540 MJ | 45 min | heat |

Two more recipes, not in the table:
- `fuse_silica`: 100 kg of silica to 100 kg of `glass` sheet, for solar-cell covers, on the arc furnace, at 250 MJ.
- `recast_silicon_scrap`: scrap back to `silicon`, at 0.6 MJ/kg.

### What a kilogram costs, through the loops

| Product | Energy per kg | Where it goes |
| --- | --- | --- |
| Hydrolox propellant | 36 MJ | Almost all of it is electrolysis. Liquefying hydrogen is 15% of it |
| Steel | 19 MJ | 13.5 MJ to win back the reduction hydrogen by electrolysis, 3.2 MJ for reduction, 2.2 MJ for the arc furnace |
| A 50 kg frame | about 1,070 MJ | 52.5 kg of steel, plus 75 MJ of forming |
| Copper | about 2.3 MJ, plus 1.3 kg of the spare LOX | Smelting is autogenous, so electrorefining is most of the power |
| Metallurgical silicon | about 103 MJ | 40 MJ for the furnace, 36 MJ for the Bosch reactor's hydrogen, 26 MJ for acid regeneration |
| Electronic-grade silicon | about 194 MJ | Zone refining adds 80 MJ |
| A wafer, 50 g | about 32 MJ | Crystal growth, with the kerf recycled |
| A chip, 2 g | about 57 MJ | 54 MJ of fab, the rest wafer |
| A processor, 5 kg | about 200 MJ | Two chips, a glass-fibre board, copper, a steel housing, and assembly |

- **Today's interim values in recipes.json are low.** They leave out the loops, so `refine_hematite`'s 352 MJ misses the 850 MJ of electrolysis that wins its hydrogen back.
- The chains replace those recipes, so the real totals arrive with them.

### Parts from the chains

The intermediate goods change; their item IDs stay.
- **`structural_frame`, 50 kg:** 52.5 kg of steel gives the frame plus 2.5 kg of `steel_scrap`, on the fabricator at 75 MJ. Throughput sets the run's length.
- **`wiring`, 10 kg:** 9 kg of copper and 1 kg of glass-fibre insulation, at 12 MJ.
- **`processor`, 5 kg:** 2 chips, 1.496 kg of glass fibre for the board, 0.5 kg of copper and 3 kg of steel for the housing, at 20 MJ of assembly and test.

Each part's recipe takes:
- its structure as frames or steel;
- its electronics as processors and wiring;
- its special materials by name:
  - copper for thruster chambers and radiator loops;
  - magnesia for furnace linings;
  - glass fibre for tank insulation;
  - wafers and glass for solar cells.

Every part's mass still balances to its inputs. The per-part list comes with the data step.

## 6. Engines and propellant

| Engine | Propellant | Mixture by mass | Exhaust speed | Thrust | Flow |
| --- | --- | --- | --- | --- | --- |
| `chemical_thruster_mk1` | LH₂ and LOX | 1 to 6 | 4,400 m/s | 15 kN | 3.41 kg/s |
| `small_chemical_thruster_mk1` | LH₂ and LOX | 1 to 6 | 4,200 m/s | 0.15 kN | 0.036 kg/s |

- **Hydrolox is the natural propellant from ice.** Its exhaust speed is real: about 450 s of specific impulse in vacuum for the large engine, a little less for the small one.
- **Electric engines come later.** The owner has ruled helium and other propellants to a later stage, and a water-fed resistojet is a candidate there.
- **A thruster gains a `mixture`,** as parts by mass of each propellant item, for example `{ "hydrogen": 1, "oxygen": 6 }`. A burn draws both in that ratio, and runs short when either one runs out.
  - This is A's change, and a contract change.
  - The frame-era fields `speed_m_s`, `propellant_kg_per_s` and `rated_mass_kg` go with A53.
- **The tanks hold the mixture's volumes.** At 1 to 6, hydrolox averages 361 kg/m³, against today's abstract 1,000.
  - The probe's 2.5 m³ `propellant_tank_mk2` holds 129 kg of LH₂ and 775 kg of LOX: 904 kg, not 2,500.
  - That brings the probe's Δv from about 870 m/s to about 500 m/s, even with the better exhaust speed.
  - **This must be settled in A's stage 4 fuel rebalance,** with bigger tanks or a different start, before the chains reach the new start. The Lead has ruled the rebalance waits for stage 4, so B29's data won't touch the probe's tank until then.
- **Boil-off is real.**
  - Proposal: LH₂ tanks lose about 1% a day in sunlight, and LOX tanks about 0.1%, into a `boil_off` sink.
  - A tank's cryocooler stops it while it's powered, at a stated draw, for example 0.5 kW per m³ of LH₂.
  - The data fields would be `boil_off_ppm_per_day` per class and `cooler_kw`. This is a rule for A and C.

## 7. Research field trials

The owner's ruling: a prototype is proven by field trials judged on performance, plus a chance of manufacturing defects, and no test always passes.

**A theory's test** keeps its evidence: science from scans and measurements. Its lab job becomes an experiment with a stated prediction:
- The lab builds a test article from the theory's inputs, then runs it. The run measures the predicted quantity and passes when the result falls inside the theory's tolerance.
- The test article can have a manufacturing defect: a seeded draw at its build, from the `research` stream. A defective article spoils the run, and the theory is not proven.
  - The defect shows as a measured result outside tolerance, and the event names it.
  - The player builds another article and runs the test again.
  - The inputs are spent either way.

**A prototype's field trial** is the design doing its job in play, with its real stats drawn and measured:
- **Drawn stats.** A prototype's built stats come from a seeded spread round the design. One draw is made per stat, from the `research` stream: within ±`spread_ppm`, plus a defect chance `defect_ppm`.
- **The trial.** Each design names a trial by kind. The prototype passes when every stat measured during it falls within `tolerance_ppm` of the design and no defect showed.
- **A defect** shows at a seeded point during the trial, as a real `fault` on the part. The part stops, and the trial fails. A faulty prototype can be scrapped into its materials, at a loss, or repaired later, when repair exists.
- **Qualification** needs `trials` passes in a row: 1 for simple parts, 3 for cores and engines. Then the normal recipe opens.

| Design kind | Trial | Measured |
| --- | --- | --- |
| Engine | A burn of `seconds` | Thrust and exhaust speed, from the tank drop and the Δv achieved |
| Core | `laps` of a cycle it runs on its own | The cycle completes; propellant within tolerance of plan |
| Refinery, electrolyser, furnace, fab | `runs` of a stated recipe | Energy per run, and output |
| Solar | `seconds` in full sun | Power delivered |
| Radiator | `seconds` at its rated load | Heat rejected |
| Tank or container | Filled for `seconds`, then a burn at the craft's full thrust | Holds and stays sound |
| Landing gear | A landing at its slope and touchdown limits | Survives |
| Port | `docks` at its capture limits | Latches each time |

- **Normal builds can be defective too.** A qualified recipe has its own, lower `defect_ppm`, and a defect shows at a seeded point in the part's first hours of use. That's real manufacturing, and it gives the player inspection as a reason for spares.
- **Data:**
  - each theory names its experiment: the measured quantity, the tolerance and the inputs;
  - each design gets a `trial` object with its kind, amount, `tolerance_ppm`, `spread_ppm`, prototype `defect_ppm`, and the normal `defect_ppm`.
- Owners: C for the rules and the contract, B for the data and design, D for the trial readouts.

## 8. Fitting warns and allows

The owner's ruling: no hard power checks.
- Fitting reports the rated draw against the power made, and the heat rated against the rejection. Then it lets the part on.
- Running short is handled in play, by C30's rates and PowerSystem's load shedding.
- **Data side:** B25's validator check, which refused a design whose fit order broke a budget (`design_fit_order`), becomes a check on mass, load and connectors only. Power and heat are no longer refused.
- **Mass and connector load warn and allow too** (Lead, 2026-11-08). The physical consequence comes from the structure and damage item: an overloaded connector or structure fails under load.

## 9. The cluster: a mixed layout

The owner's ruling:
- close rocks near the start;
- farther rocks, the ice rock among them, out in a 30 to 50 km swirl;
- the fuel isn't rebalanced until A's stage 4.

On real orbits round Frost, every rock shares the semi-major axis of the start's circular 300 km orbit, so all have its period of 6.8 hours. None drifts away. Each moves round the start in a closed relative ellipse:
- a·e across the orbit and 2·a·e along it, from its eccentricity e;
- a·sin i above and below the plane, from its inclination i.

| Rock | Ore | Eccentricity | Inclination | Distance from the start |
| --- | --- | --- | --- | --- |
| Red Rock | hematite | 0.010 | 0 | 3 to 6 km |
| Brass Rock | chalcopyrite | 0.013 | 0.3° | 4 to 8 km |
| Green Rock | olivine | 0.013 | 0.5° | 4 to 8 km, with a 2.6 km vertical swing |
| White Rock | ice | 0.07 | 3° | the swirl, about 30 to 45 km |
| Black Rock, **new** | carbonaceous | 0.06 | 4° | the swirl, about 25 to 45 km |

Each rock's phase and node are spread so the rocks don't pass close to each other.
- **Trips stay cheap but real.** A relative trip costs about the orbit's mean motion times the distance, 2.6×10⁻⁴ per second:
  - about 1 to 2 m/s to a close rock;
  - about 8 to 12 m/s to the swirl, more with the plane change.

  A53's planner prices the actual arcs.
- **The ice rock being far is the point.** Every lap for ice costs real Δv, so the depot and the drone's propellant matter.
- **Black Rock is needed for carbon.** Steel needs a little, and starting the silicon loop needs some. No cluster ore holds carbon. The owner has the belt holding graphene, but a carbonaceous chondrite's 4% carbon is plain industrial ore, so it fits "the cluster holds the industrial ores". Please confirm with the owner.
- **The exact elements and the measured trip costs come after A53 is approved.** I'll place them with A53's planner and measure every route, as before.
- With all rocks on one period, the layout repeats every 6.8-hour orbit, so trip costs can be quoted for any departure time.

## 10. B28 under the rulings

B28's Part G (design/B28, 546fa40) doesn't stand as written:
- its trips are straight lines in the frame;
- its run times are work points;
- its propellant is the abstract item.

What does stand:
- the port and group-reach rulings, which are C30's;
- the `skip_if_full` ruling, C31;
- D44's press counts in balance.md 9.7.

So, my proposal:
- Don't merge B28 as it is. I fold its 9.7 and the gap rulings into B29.
- I rewrite Part G after A53 and C30, when its trips and rates can be measured.

## 11. What needs whom

| Change | Owner | Notes |
| --- | --- | --- |
| The chain items, recipes and machines in `data/`; the parts' recipes | B | After this page is approved |
| Validator: `abstract: false` recipes balance to the gram; slag kept, not sunk; new classes and machines | B | `slag_missing` and `recipe_not_abstract` change |
| Factory rates | C | C30, under way |
| Two-propellant burns (`mixture`), and the frame-era thruster fields going | A | Contract change. With A53 |
| Tank sizes and the probe's start, for hydrolox | A, B | Stage 4 fuel rebalance |
| Boil-off and cryocoolers | A or C | Proposal, section 6 |
| Field trials, drawn stats and defects; theory experiments | C | Contract change. B supplies the data |
| Fitting warns and allows | C, D | Section 8 |
| The rocks' orbits, and Black Rock | B | After A53 |
| A recipe-yield draw for chip dies | C | `fab_chips` passes each die at a `yield_ppm`, drawn per run |

## 12. Answers (Lead, 2026-11-08)

1. **Black Rock goes in the cluster,** out in the swirl, for carbon. It's added in B30, and its exact elements come with A53 stage 4.
2. **The probe carries about 200 seed chips** as cargo in its own hold. That isn't pre-built in space, and the fab path still stands. Added in B30.
3. **`battery_bank_mk1` becomes a regenerative H₂/O₂ fuel cell.** Its round trip is about 45%, against today's 90%. Changed in B30, since it alters the start's shadow behaviour.
4. **Part masses: real masses throughout.** The part-mass audit comes next, after the chain data.
5. **Fitting has no hard checks** (section 8).
6. **Boil-off with cryocoolers is approved.** It's in the data as `cryo` on `hydrolox_tank_mk1`: a power and heat load. A does the sim side.
7. **The thruster `mixture` goes to A.**
8. **Hydrolox's Δv drop stays real.** It's settled in the stage 4 rebalance, with a bigger tank or a different start. The start's propellant doesn't change before then.
9. **B28 isn't merged.** Its 9.7 and its gap rulings are now in balance.md, and Part G is rewritten after A53 and C30.

**Still open, for B30 or later:** the electrolyser's catalyst and electrolyte. Real electrolysers use nickel or platinum electrodes and a potassium hydroxide or membrane electrolyte, and the cluster has none of those. The B29 electrolyser is built from steel, copper and electronics. A real answer is either a seed of catalyst carried like the chips, or the belt's metals. That's a question for the owner.
