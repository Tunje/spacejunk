# Research: Science, Theories, Prototypes and Ideas

Status: **proposal**, task B17. Contract version 5 (C12) fixes the names and rules; where this page and the contract differ, the contract wins. Derived IDs are `prototype:<design>` and `qualify:<design>`, and a variant is `base+idea+idea`, so authored IDs never hold ':' or '+'. Nothing in `data/`, `sim/`, the client or the contracts changes until the Lead and the owner approve it. It follows the owner's ruling on research of 2026-11-06 at the top of [workplan.md](../../plan/workplan.md), and replaces section 5 of [start_and_build.md](start_and_build.md).

## The short answer

- **Science points come from measuring things.** A measurement is a unit order, like `scan`. Survey an asteroid, take its composition, map a body's gravity field over one orbit, or sample the surface where you have landed. Each one pays points once, and then less each time it is repeated, down to nothing by the fourth time. Points are an integer in the state, paid in phase 6, with no randomness.
- **A theory is proven at a lab, with evidence.** A theory costs points. It also lists the measurements that must have been taken first, and a test run at a research lab on a station. Only a proven theory lets you build anything that uses it.
- **Every new design goes prototype, then test, then qualified.** Once its theory is proven, a design can be built only as a prototype, at about twice the normal cost. The prototype is a separate item and can't be fitted. A bench test at the lab uses it up, and the normal recipe unlocks.
- **Ideas improve a part, with trade-offs.** Each part lists potential upgrades in data. An idea changes some stats for the better and others for the worse, and adds complexity. A chosen set of ideas makes a variant, which also goes through prototype and test. The original design always stays buildable, and parts already built keep the stats they were built with.
- **Complexity is cost.** A variant's recipe takes more inputs and more time, by a quarter of the base for each point of complexity. The extra matter goes to a scrap sink, so the matter ledger holds. Simplification ideas take complexity away, at a cost in stats.
- **"A chance to reduce" is proposed as both.** A variant's bench test has a seeded chance to *discover* a simplification idea, which you then choose whether to apply. It is random but deterministic, and nothing is ever imposed on you. This is open question 1 for the owner.
- **The AI-core eras gate theories.** Each theory belongs to one of the six eras. Proving one needs a core of the era before it at the lab's station. So the Basic Core proves the theory behind the Assisted Core, and every later era is reached by the intelligence of the one before.
- **The first playthrough proves one theory before the handover.** Survey and analyse the three rocks, map the moon's gravity field, prove *Autonomous Navigation* at the first station's lab, prototype and test the Assisted Core, then build the drone with it.

## 1. Science tasks and points

### 1.1 Measurements

A measurement is a new unit order, `measure`, with `target` and `kind`. It is a task step like `scan`, so it runs under the same task and tier rules, can be a cycle step, and is interrupted the same way. A finished measurement pays points. An interrupted one pays nothing and starts again, as a scan does.

| Kind | Where | Part | Time | Base points |
| ---- | ----- | ---- | ---- | ----------- |
| `survey` | At an asteroid, undocked | LIDAR (`scan`) | The LIDAR's `scan.seconds`, 30 s | 10 |
| `composition` | At an asteroid, undocked | LIDAR | 120 s | 20 |
| `gravity_field` | On an orbit around a body | Any core | One full orbital period | 40 for a moon, 60 for a planet |
| `surface` | Landed on a body | LIDAR | 300 s | 50 |

- **`survey` is today's `scan`.** A finished scan also pays its points. `measure` with kind `survey` is the same step, so `scan` stays as it is and needs no client change.
- **`gravity_field`** is a measurement of a body, taken by flying round it. The task records the unit's orbit parent and the tick it started. It finishes after one period, as long as the unit stayed on an orbit around that body the whole time. A burn, a transfer or a sphere-of-influence change ends it, unpaid. It needs a core but no extra part, because the core reads the orbit's tracking data. The probe can take it on its way to a landing.
- **`surface`** keys on the landed cell's surface type. Until planets.md's rule tables are in `data/`, every body has one surface type, so a body pays once.
- **Base points are data**, in a new file `data/science.json`, with one entry per kind and an optional figure per body kind. The table above shows the proposed values. Nothing is hard-coded.

The LIDAR does survey, composition and surface. That keeps the probe's 12 side connectors as they are, and needs no new part in the slice. A dedicated instrument pod, with faster or extra kinds, is an obvious first idea or later part (section 4).

### 1.2 Diminishing returns

Every measurement has a **key**: its kind, its target body, and for `surface` the surface type. The state counts how many times each key has paid.

- The nth payment of a key, counting from 0, is `base >> n`: full, then a half, then a quarter, then an eighth, rounded down.
- Once that comes to 0, the key pays nothing more. With base 10 that is after the fourth time. Any key's total is under twice its base.
- Two units measuring the same key finish in ascending unit ID within phase 6, so the second one gets the halved figure. Order can never change a total.
- The count is per key, not per unit. A drone looping over one rock adds almost nothing, and new rocks and new bodies are always worth more. That is the anti-farming rule, and it pushes the player outwards, which is the game's point.

### 1.3 Integer and deterministic

- Points are an `int` in the state: `science = { points, earned, spent, paid }`. `paid` maps each key string, such as `"composition:14"` or `"surface:3:ice"`, to its count. It is written sorted, like every map.
- Measurements pay in phase 6, in ascending unit ID. Nothing in this section draws from an RNG.
- Points are not matter, so they sit outside the matter ledger. A new tests-only check holds `earned - spent = points` every tick, alongside the three ledgers.
- A new event, `science_gained { kind, target, points }`, reports each payment. It fires with 0 points too, so the player can see that a key is exhausted.

## 2. Theories

### 2.1 What a theory is

A theory is a data entry in a new file, `data/theories.json`:

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `id`, `name` | string | |
| `era` | whole, 1 to 6 | The AI-core era it belongs to (section 2.3) |
| `requires` | array of theory IDs | Theories that must be proven first |
| `evidence` | array | Measurements that must have been paid at least once: `{ "kind": ..., "count": n }`, meaning n different keys of that kind, or `{ "kind": ..., "body_kind": ... }` |
| `test` | recipe ID | The lab recipe that proves it |
| `unlocks` | array of module IDs | The designs that can be prototyped once it is proven. Ideas name their own theory (section 4.1). Unit templates are all known from the start in the slice. |

### 2.2 How a theory is proven

A theory is proven by **running its test recipe at a research lab**. A test is a recipe in a new facility type, `lab`, so it uses the existing job system: `start_job`, the queue, power, heat, pausing, cancelling and `job_finished`.

- **Points are a recipe input.** A new optional recipe field, `points`, gives the science points a run takes. They are deducted when the run starts, as inputs are, and refunded on cancel. A run that can't pay waits with reason `missing_points`.
- **Evidence is checked when a run starts.** A test whose theory's evidence isn't met waits with reason `missing_evidence`. The view shows which entries are still missing.
- **Inputs are real goods.** A test uses some materials and components, which go to a new sink, `test_consumed`. That is the cost of building the apparatus and running the experiment.
- **The output is the proof.** A new output form, `{ "theory": id }`, marks it proven when the run finishes. That fires a new event, `theory_proven { theory }`. The theory weighs nothing, so its only companions are sink routes, which carry the test's inputs to `test_consumed`.
- **A lab can't run a theory whose `requires` aren't proven,** or one already proven. `start_job` refuses both, with `theory_locked` and `already_proven`.

So a theory needs three things: points from measuring, evidence from going to the right places, and a lab, which needs a station. That is the owner's "build stations to test new tech" and analysis section 8's "research station: analyzes discoveries".

**The lab** is `research_lab_mk1`, which replaces start_and_build's `test_bay_mk1`. It is 1000 kg, 100 kW and 60 kW of heat, built from 15 frames, 15 wiring and 20 processors over 300 s, with capability `facility { type: lab }`. Its mount carries 3000 kg, so like the refinery it needs a hub's side connector. The probe has none free.

### 2.3 Theories and the AI-core eras

Analysis section 10 ties six stages of civilisation to the six cores. Each theory's `era` places it in one of those stages:

| Era | Core | Stage | Example theories |
| --- | ---- | ----- | ---------------- |
| I | Basic | Early space operations | Known from the start: everything the probe carries, the hull templates, materials |
| II | Assisted | Industrial infrastructure | Autonomous Navigation (Assisted Core), Large-Scale Refining (ore refinery), Photovoltaic Arrays (solar farm) |
| III | Adaptive | Autonomous networks | Hazard Prediction (Adaptive Core), Ion Propulsion |
| IV | Strategic | Interplanetary | Fleet Coordination (Strategic Core), Fission Power |
| V | High-Order | Interstellar | Spacetime Metrics (High-Order Core) |
| VI | Self-Recursive | Self-improving | Recursive Design (Self-Recursive Core) |

**The gate:** a lab can prove a theory of era N only if the lab's unit has an assigned core of tier N − 1 or higher. Otherwise `start_job` refuses it with `tier_too_low`, the existing code. The Basic Core proves era II, and so builds the Assisted Core. The Assisted Core proves era III, and so on. Each era's own core is always among the first theories of that era.

This makes the cores the backbone of progression, as analysis section 3 asks. It does it without making cores faster: a core still sets what a craft does on its own, and now also which questions a station can answer. It also gives analysis section 2's rule, that new capability needs industry and not just points. Every theory needs a station, a lab, power, materials and a core.

## 3. Prototype, then test

### 3.1 The life of a design

Each design, a module or a variant from section 4, is in one of three states:

| State | What you can build | How it ends |
| ----- | ------------------ | ----------- |
| `locked` | Nothing | Its theory is proven |
| `prototype` | Its prototype | Its bench test finishes |
| `qualified` | The normal recipe | Never |

Designs that are known from the start are `qualified`. The state holds `research.designs`, a map from design ID to `prototype` or `qualified`, for every design that isn't known from the start. A design missing from the map, with an unproven theory, is `locked`.

### 3.2 End to end, for one new part

Take `assisted_core`, unlocked by *Autonomous Navigation*.

1. **Proof.** The theory's test finishes at a lab. `theory_proven` fires, and `assisted_core` becomes `prototype`.
2. **Prototype.** A new derived item, `prototype:assisted_core`, has the module's mass and volume and is discrete. Its recipe has the same ID and is derived from the normal recipe (C12's `ResearchDefs`). It uses the same facility, twice the inputs and twice the work. Half the input mass goes into the item, and the rest to a new sink, `fab_scrap`, so it balances. The prototype is not a module, so it can't be fitted. It is a test article.
3. **Bench test.** A lab recipe, `qualify:assisted_core`, also derived, takes the prototype plus the bench test's inputs (10 processors at 300000 work by default, from `theories.json`'s `bench_test`, or the theory's own `qualify` list), and outputs `{ "qualifies": "assisted_core" }`. The inputs go to `test_consumed`. When it finishes, `design_qualified { design }` fires and the normal recipe unlocks.
4. **Normal build.** `start_job` of recipe `assisted_core` now passes. Before qualification, it is refused with `design_unqualified`. Before the theory, it is refused with `theory_locked`.

Everything is a job, so the queue, power, heat, the fail-and-fix check and the matter ledger all work as they do now. The two new outputs, `theory` and `qualifies`, are each a recipe's only output, like `unit_template`.

**Why the prototype can't be fitted:** if it could, building prototypes forever at twice the cost would be an easy way round testing. The owner's rule is that a thing must be tested before it becomes a normal part.

**Field tests are reserved.** A later test kind could be a fitted prototype that must log a set amount of running time or work. It is not needed in the slice, and leaving it out keeps parts free of per-part counters.

### 3.3 What the loader derives

For every module that a theory unlocks, the loader makes the prototype item, the prototype recipe and the qualify recipe. Authors write only the normal recipe and the theory's `unlocks` list, so the three can never disagree. A design may override the qualify recipe's inputs with an optional `qualify` field on its theory entry.

## 4. Ideas: upgrades with trade-offs

### 4.1 Potential upgrades, in data

A module may list ideas under a new optional field, `ideas`:

```json
"ideas": [
  { "id": "focused_beam", "name": "Focused Beam", "theory": null, "points": 30, "complexity": 2,
    "deltas": { "capabilities.mine.rate_kg_per_s": 250000, "power_kw": 200000, "heat_kw": 250000 } },
  { "id": "light_frame", "name": "Light Frame", "theory": null, "points": 20, "complexity": 1,
    "deltas": { "mass_kg": -200000, "durability": -300000 } },
  { "id": "simple_optics", "name": "Simpler Optics", "theory": null, "points": 10, "complexity": -2,
    "simplifies": true,
    "deltas": { "capabilities.mine.rate_kg_per_s": -100000 } }
]
```

- **`deltas`** change numeric fields by parts per million of the **base** value, so +250000 is +25%. Allowed fields are `mass_kg`, `power_kw`, `heat_kw`, `durability`, and every numeric capability field except `ai_core.tier` and `facility.type`. The validator rejects anything else, and every idea must make at least one field better and one worse. That is the owner's rule as data: no idea is free.
- **Connectors, collision, capabilities' keys, `visual` and `min_ai_tier` never change.** A variant fits exactly where its base fits, and looks the same. Section 4.5 explains why.
- **`theory`** is the theory an idea needs. An idea that needs none leaves the field out, since data holds no nulls. So later science opens better ideas.
- **`points`** is what developing the idea costs, paid by its variant's prototype run (section 4.3).
- **`complexity`** is a small whole number, positive for an improvement and negative for a simplification (`simplifies`).

### 4.2 Variants

A **variant** is a base module plus a set of ideas.

- **ID.** Its ID is the base ID and the sorted idea IDs, joined by `+`, for example `mining_laser_mk1+focused_beam+light_frame`. The same set always gives the same ID, so two players or two saves agree, and an item stack of a variant is just an inventory key.
- **Stats.** Each changed field is `base × (1000000 + sum of the ideas' ppm) / 1000000`, worked out once in sim units with `IntMath.mul_div` and rounded down. Summing the ppm figures before applying them makes the order of ideas irrelevant. A result of 0 or less is refused when the variant is designed.
- **Recorded in the state.** The state holds `research.variants`, a map from variant ID to `{ base, ideas, complexity }`, and its design state sits in `research.designs`. Stats are derived from the data and the idea list, not saved, so a data change rebalances every variant.
- **Designing a variant** is a new command, `design_variant { base, ideas }`, sent with `unit` 0, because it is a plan, not an action. It is refused with `idea_locked` if an idea's theory isn't proven, `variant_exists`, or `malformed_command`. It adds the variant as `prototype`, from which it follows section 3 exactly: its prototype recipe takes the ideas' `points` as well as goods, and a bench test qualifies it.
- **Its recipes are derived when it is designed:** the normal recipe (ID: the variant ID), the prototype and the bench test, by sections 3.3 and 4.3. Like stats, they are derived and not saved, and `defs()` doesn't list them; the view's `research.variants` carries them.
- **Volume is the base's,** so a variant packs into cargo exactly like its base, whatever its mass.
- **Up to four ideas** per variant, to keep variants readable.

### 4.3 Complexity into cost and time

A variant's complexity is the sum of its ideas' `complexity`, but never below 0. Let `f = (4 + complexity) / 4`. Its normal recipe is derived from the base recipe:

- **Inputs:** each base input times `f`, with discrete counts rounded up. If the variant is heavier than the base, the inputs scale up further, until their mass covers the part.
- **Time:** the base `seconds` times `f`, rounded up. Power is unchanged.
- **Balance:** input mass beyond the part's mass goes to `fab_scrap`, so a lighter variant also balances.

So complexity 2 costs 1.5× the goods and the time, and complexity 4 costs 2×. Every point of complexity is a real cost in mining, refining and fabricating, which is the owner's "harder to build and more expensive". The prototype is twice the variant's recipe, as in section 3.

### 4.4 Simplification: the "chance to reduce"

Two routes, both proposed (open question 1):

1. **Simplification ideas you choose.** Ideas with `simplifies: true` have negative complexity and a stat cost, like *Simpler Optics* above. You add one to a variant like any idea. This is always under your control.
2. **A chance to discover them.** Some simplification ideas start hidden, marked `hidden: true`. Each time a variant's bench test finishes, the sim draws once from a new RNG stream, `research`. With chance `discover_ppm`, set per idea in data, it reveals one hidden simplification idea that applies to that base. A new event, `idea_discovered { base, idea }`, reports it.

The draw is seeded and saved like every stream, so the same game always discovers the same idea at the same test. Order is fixed: tests finishing in one tick draw in ascending job ID. A discovery only adds an option to the list. Nothing is applied until you design a variant with it. That reads "you get a chance to reduce complexity" literally, while keeping the player in charge.

If the owner meant only a choice, route 2 is dropped, and nothing else in this page changes.

### 4.5 Reverting, and parts already built

- **The base is always there.** Reverting means building the base, or an earlier variant, again. Each stays qualified for good. There is no revert action, because nothing was ever replaced.
- **A built part keeps its variant.** A part's `def` is its variant ID, so the stats it was built with never change, whatever is designed later. Swapping it means detaching it and attaching another, by the existing rules.
- **Variants are never deleted.** A built part or an item in a hold may name one. The client can hide variants the player no longer wants.

### 4.6 Every part on any ship, and `copy_fit`

- **"Every part buildable on any ship" holds.** A variant has its base's connectors, mount and size, so it fits wherever the base fits. Fitting still checks mass, power and heat, so a hungrier variant can be refused, with the usual reasons. That is the trade-off doing its job.
- **`copy_fit` copies the exact variant.** A source part's def is a variant ID, and `from` must hold that variant. `missing` counts variants by ID, as it counts modules today. A part already in place keeps its place only if it is the same variant. A later option, `allow_base`, could let a copy take any variant of the same base, but it is not proposed now.
- **Templates name base modules.** A built unit gets base parts. Variants are fitted afterwards.

## 5. The first playthrough

This replaces Part F of start_and_build section 4, and fixes what starts locked.

**Known from the start (era I):** everything on the probe, every hull template, the small station, `research_lab_mk1`, `basic_core`, every material and component recipe, and every `small_` part. The bootstrap can never dead-end.

**Locked behind era II theories:**

| Theory | Unlocks | Points | Evidence | Test |
| ------ | ------- | ------ | -------- | ---- |
| Autonomous Navigation | `assisted_core` | 80 | 3 asteroids surveyed, 1 `gravity_field` | 10 processors, 10 wiring, 300 s |
| Large-Scale Refining | `ore_refinery_mk1` | 100 | 3 asteroids' composition | 20 frames, 10 processors, 600 s |
| Photovoltaic Arrays | `solar_farm_mk1` | 120 | 1 `surface` | 30 kg of silicon, 10 processors, 600 s |

**The path to the handover:**

1. **Prospect.** Survey Red Rock (10 points) and mine. Survey the other two rocks on the ore trips (+20), and take composition on each pass (+60). That's 90 points, and two pieces of evidence, from things the probe does anyway.
2. **Seed factory and first station**, as in start_and_build section 4. The station gets a `research_lab_mk1` and a Basic Core. Fitting the lab is a natural fail-and-fix: the small station's power budget refuses it until a second solar panel or a battery is fitted.
3. **Gravity field.** The probe flies one lap of its low orbit round the icy moon before it lands (+40). That's 130 points. A low orbit about a tenth of the radius up takes about 42 minutes at half Kerbin's density, and about 30 at Kerbin's. A lap at the cluster's 300 km would take about 7 hours. The probe's facilities keep running during the lap.
4. **Prove Autonomous Navigation** at the lab (-80 points), with the station's Basic Core: era II needs tier 1.
5. **Prototype and test the Assisted Core:** about 2× its 6 processors and its basic core, then a bench test. It is qualified.
6. **Build and fit the Assisted Core in the drone**, then `set_cycle` and hand over.

Goals 9 ("Prove a new tech") and 10 to 12 in start_and_build section 4.1 stay. Goal 9's trigger becomes `design_qualified` of `assisted_core`.

The other two theories and the first idea are for after the handover. They give the expansion phase an aim: a `surface` sample from the moon for the solar farm, and composition data for the big refinery. The Assisted Core stays gated, because the owner's ruling says nothing is click-and-it's-yours (Lead, 2026-11-06).

**Rough cost** of research before the handover:

| Item | Frames | Wiring | Processors |
| ---- | ------ | ------ | ---------- |
| The lab | 15 | 15 | 20 |
| The theory test | | 10 | 10 |
| The prototype: 2 basic cores and 12 processors | | 2 | 20 |
| The bench test | | | 10 |
| **Total** | **15** | **27** | **60** |

start_and_build section 4 put research at about 15 frames, 15 wiring and 30 processors. This route costs 12 more wiring and 30 more processors. That's about 120 kg of silicon, or a third of a probe load of olivine, plus about an hour of fabricating processors at compact speed.

## 6. Contract and schema changes

### 6.1 Contracts

| Area | Change |
| ---- | ------ |
| Commands | `measure { target, kind }` (unit order, tier 1). `design_variant { base, ideas }` (no unit). `scan` also pays points. |
| Recipes | Optional `points`. Facility type `lab`. Output forms `{ theory }` and `{ qualifies }`, each the only output. |
| Jobs | Reasons `missing_points`, `missing_evidence`. Refusals `theory_locked`, `design_unqualified`, `already_proven`, `idea_locked`, `variant_exists`. `tier_too_low` also for a lab below a theory's era. |
| Events | `science_gained`, `theory_proven`, `design_qualified`, `idea_discovered` |
| State and view | `science = { points, earned, spent, paid }`, `research = { theories, designs, variants, discovered }`. The view adds each variant's resolved module, so the client never recomputes stats. |
| `defs()` | Adds `theories`, `science`, the derived prototype items and recipes, and each module's `ideas` |
| Ledgers | New sinks `fab_scrap` and `test_consumed`. A tests-only points check: `earned - spent = points`. |
| RNG | A new stream, `research`, used only for idea discovery |
| Parts | A part's `def` may be a variant ID. `Units.module_of` resolves it from the base and the ideas. |

### 6.2 Schemas

- **New files:** `data/science.json` (measurement kinds and base points), `data/theories.json` (section 2.1).
- **Modules:** optional `ideas` (section 4.1).
- **Recipes:** optional `points`, the facility `lab`, and the two output forms.
- **Capabilities:** `facility.type` gains `lab`.
- **Validator:**
  - every theory reference resolves, and `requires` has no cycles;
  - every design is reachable from the starting set;
  - each idea's deltas name allowed fields and make at least one field better and one worse;
  - a theory's `era` is above every era it `requires`.

### 6.3 Task split

| Agent | Task |
| ----- | ---- |
| **A** | The `science` and `research` state, the canonical save of both, the derived items and recipes in the loader, variant resolution in `Units.module_of`, the `research` RNG stream, and the points check. |
| **C** | The `measure` step, with `gravity_field`'s one-lap rule. Lab jobs: `points`, evidence, the era gate, and the `theory` and `qualifies` outputs. The `design_variant` command, and `copy_fit` with variant IDs. |
| **D** | A research panel: points, theories with their evidence and costs, designs with their state, and a variant designer showing stat changes, complexity and the resulting recipe. A `measure` button by `scan`. The new goal trigger. |
| **B** | `science.json`, `theories.json`, ideas for the first parts, the lab module and its brief, validator rules, the reference chain update in B11, and balance figures. |

Order: B's data and A's state first, then C's jobs and step, then D's panel. Nothing here touches orbits, so it can run alongside B11.

## 7. Open questions for the owner

1. **"A chance to reduce complexity":** random, a choice, or both? Proposed: both. Simplification ideas are always a choice, and a variant's test has a seeded chance to discover new ones (section 4.4).
Settled by the Lead on 2026-11-06:
- **The Assisted Core is gated.** The ruling that nothing is click-and-it's-yours decides it, so one theory is proven before the handover.
- **Points count when a measurement finishes.** They aren't carried back to a station first. This will be revisited if the owner objects.
