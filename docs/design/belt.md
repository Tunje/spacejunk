# The Asteroid Belt

Status: **proposal**, task B18. Nothing in `data/`, `sim/`, the client or the contracts changes until the Lead and the owner approve it. It follows the owner's ruling of 2026-11-06 ("both asteroid groups exist, with different resources") at the top of [workplan.md](../../plan/workplan.md), and the catalogue in [spec.md](spec.md) sections 3 and 4.

## The short answer

- **Two places to mine, two economies.** The cluster round Frost holds the industrial ores and water ice: iron, copper, silicon and propellant, everything the first ships and stations need. The belt round the star holds the precious and alloying metals, ammonia and carbon. Those are what the second era's better parts need.
- **The owner's belt list, as the catalogue already rules:**
  - native gold, silver, copper and platinum;
  - garnierite (nickel), sphalerite and smithsonite (zinc);
  - ammonia ice;
  - carbon feedstock.
  Graphene and ozone are not mined. Graphene is made from the belt's carbon, and ozone from oxygen out of water ice. That is open question 1.
- **Every belt material gets a use in a better part,** so the belt is a reason to expand, not a list of trophies. Examples: silver-zinc battery cells, nickel superalloy thruster bells, platinum catalysts, gold contacts for the Adaptive Core, ammonia radiator loops, and graphene frames.
- **The belt is far.** At 2.7 AU, a transfer from Frost's planet costs about 11 km/s and takes about 15 months each way, with a window every 15 months. On today's chemical thruster that is a mass ratio of about 39, which is impossible. It takes three things:
  - electric propulsion, which is an era III theory;
  - a power source that still works at 14% sunlight;
  - a long-coast time warp (open question 2).
- **It is a mid-game goal by design.** Reaching the belt is what era III is for. Until then the cluster, Frost and the planet are the whole playing field.

## 1. Where the belt is

- **A ring round the star at 2.2 to 3.2 AU,** centred on 2.7 AU. That is where a real belt sits, beyond the planet's 1 AU.
- **Fields, not one frame.** The belt is a set of **belt fields**. Each one is a co-moving frame like the cluster, with 4 to 8 rocks, on its own circular orbit at its own distance and phase. A frame is the existing mechanism ([orbital_flight.md](orbital_flight.md) section 11.2), so this needs no new sim concept.
- **How many:** six fields in the first belt data, spread round the ring. That's enough for choice and travel. More can come from a seeded generator later.
- **Each field leans one way.** One is rich in native metals, another in zinc and nickel, another in ammonia and carbon. Choosing a field is a real decision, and different automated routes serve different fields.

## 2. Resources

Stage 1 is the deposit and Stage 2 the mined item, as in [spec.md](spec.md) section 2. The yields respect each mineral's real element share, as the validator's ceiling table requires.

| Mined item (Stage 2) | Deposit kind | Refines to (Stage 3) | Proposed yield per 100 kg | Ceiling basis |
| -------------------- | ------------ | -------------------- | ------------------------- | ------------- |
| `native_gold` | Metal-rich rock | `gold` | 5 kg, 95 slag | Ore grade, set in data |
| `native_silver` | Metal-rich rock | `silver` | 10 kg, 90 slag | Ore grade |
| `native_copper` | Metal-rich rock | `copper` | 60 kg, 40 slag | Ore grade. The same `copper` the cluster makes |
| `native_platinum` | Metal-rich rock | `platinum`, `iridium` | 5 kg and 0.5 kg, 94.5 slag | Ore grade, a natural Pt-Ir alloy |
| `garnierite` | Nickel rock | `nickel` | 25 kg, 75 slag | Ni share of the mineral, up to about 30% |
| `sphalerite` | Zinc rock | `zinc` | 60 kg, 40 slag | ZnS is 67% zinc |
| `smithsonite` | Zinc rock | `zinc` | 48 kg, 52 slag | ZnCO₃ is 52% zinc |
| `ammonia_ice` | Ice rock | `ammonia` | 90 kg, 10 slag | Dirty ice, like `water_ice` |
| `carbon_feedstock` | Carbon-rich rock | `carbon` | 30 kg, 70 slag | Carbonaceous rock |

**Made, not mined:**

| Material | Stage | Recipe | Where |
| -------- | ----- | ------ | ----- |
| `graphene` | 4 | `carbon` at a new facility type, `materials_lab`: 10 kg of carbon gives 10 kg of graphene, with the work as the cost | A station. An era III theory |
| `oxygen`, `hydrogen` | 3 | Water electrolysis: 100 kg of water ice gives 80 kg of oxygen, 10 kg of hydrogen and 10 kg of slag | The refinery. It replaces nothing: `refine_water_ice` stays for propellant |
| `ozone` | 3 | `oxygen` at the `materials_lab`, 1 kg to 1 kg | Only if it gets a use (open question 1) |

Every new deposit is mined by today's laser rules. Its `hardness` sets which laser can take it: native metals 5, garnierite and the zinc ores 6, ammonia ice 2 and carbon 3. So nothing here needs a new acquisition method in the first belt data. Gas scooping is the gas giant's, later.

## 3. Uses: why go there

The validator requires every item to have a use. Each belt material goes into one or more better parts, mostly as **ideas** or new parts from [research.md](research.md):

| Material | Use | What it improves |
| -------- | --- | ---------------- |
| Silver, zinc | `silver_zinc_cell` component | A battery idea or bank: about 1.5× the energy per kg. This answers the eclipse problem for good |
| Nickel | `superalloy` (Stage 4, with chromium from a cluster chromite rock) | Thruster bells that run hotter: an idea with a better `exhaust_m_s` |
| Platinum, iridium | `catalyst` component | Refinery ideas that raise yield towards the ceiling, and the electrolysis recipe |
| Gold | `advanced_processor` component (gold contacts, with silicon and copper) | The Adaptive Core (era III) and better sensors |
| Ammonia | `coolant` charge in an `ammonia_radiator` part | About 2× `reject_kw` per kg. Ammonia is also a propellant for electric thrusters (section 4) |
| Carbon, graphene | `graphene_frame` component | Lighter structural frames: the same job as `structural_frame` at about 60% of the mass, so lighter ships and more Δv |
| Copper | Same as the cluster's | A second source, which matters once the cluster's copper runs low |

Ozone has no use in this list. That is why open question 1 proposes leaving it out.

## 4. Reaching the belt

From the planet's orbit round the star at 1 AU, as a Hohmann transfer. Leaving Frost and the planet adds a few hundred m/s, which A's planner prices exactly.

| Belt at | Δv out | Days in flight | Window every | Mass ratio at 3000 m/s | At 30,000 m/s | Sunlight |
| ------- | ------ | -------------- | ------------ | ---------------------- | ------------- | -------- |
| 2.2 AU | 9.4 km/s | 370 | 527 days | 22 | 1.37 | 21% |
| 2.7 AU | 11.0 km/s | 460 | 472 days | 39 | 1.44 | 14% |

Arriving is included in the Δv. The trip home costs the same again.

**What it takes:**
1. **Electric propulsion** (era III theory *Ion Propulsion*). An `ion_thruster_mk1` with `exhaust_m_s` about 30,000 and very low `thrust_kn`, so its burns last hours or days. Its propellant is **ammonia or water**, from the belt or the cluster, which keeps it inside today's catalogue. Helium, which the owner mentioned for electric thrusters, comes with gas giants later. A mass ratio of 1.44 there and back is a large tank, but buildable.
2. **Power far from the star.** Solar gives 14% at 2.7 AU, and an ion thruster needs tens of kW. So the belt also needs the era II/III fission theory, *Fission Power*, from the analysis's progression. The alternative is very large solar farms. Uranium is a planet ore, so this ties the planet into the route.
3. **A coast time warp.** 460 days is 57 days of play at today's 8×. The player cannot watch that. A23 already found the same for planets: a coast warp of about 10,000× when nothing needs attention, set by the client and the kernel. The Lead has ruled it is needed, and A sets the multiplier. Without it the belt is unplayable whatever the propulsion.
4. **An Adaptive Core** (era III) to fly the trip and run a belt operation on its own. A crewless probe that is 15 months away can't be micromanaged. That is the analysis's point about AI tiers setting what a machine can do alone.

So the belt is the natural goal of era III: four theories (Ion Propulsion, Fission Power, Hazard Prediction for the Adaptive Core, and a materials theory for graphene). A player can see the belt from the start but can only get there by advancing.

**A depot helps.** A station in a belt field, built by the first ship to arrive, refines ammonia into propellant there. Return trips then need only one way's propellant. That is the cluster's ice chain repeated, so it is the same mechanism.

## 5. Changes needed

**Data (B):**
- items for the nine mined and the new refined materials, and their deposits;
- refine recipes;
- the six belt fields in a scenario;
- the new components, parts and ideas;
- yield ceilings for the new ores.

All of this waits for the research data (B19) and C11's work points, so the belt arrives as era III content.

**Sim (A, C):** none for the fields, since they are frames. The coast warp is A's and D's. The `materials_lab` facility type is a schema change through the Lead.

**Client (D):** the belt fields on the system map, and the coast warp control.

**Task split:**
1. **B18 data:** after the owner's answers, B19 and C11.
2. **The coast warp:** A and D, a Lead call.
3. **The ion thruster and fission parts:** B, with research data.

## 6. Open questions for the owner

1. **Graphene and ozone.** The catalogue rules both are made, not mined: graphene from the belt's carbon, and ozone from oxygen. Is that right? And is ozone needed at all? Proposed: graphene is made from belt carbon, and ozone is left out until something needs it.
2. **A coast time warp:** settled by the Lead on 2026-11-06. A long-coast warp is needed whatever the propellant, and A sets the multiplier later.
3. **The belt's distance.** About 2.7 AU is realistic: about 11 km/s and 15 months each way. A closer belt at about 1.4 AU is 4.6 km/s and 8 months, but its windows come every 2.5 years. Proposed: 2.7 AU. Its windows come every 15 months, against 2.5 years, and the trip time is a coast-warp question either way.
