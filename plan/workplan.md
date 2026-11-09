# Newman Probe: Workplan

Status: approved by the owner on 2026-10-31. M0, M1 and M2 are complete, and M3 is in progress.
Sources: [ideadock.md](ideadock.md) and [analasysOfIdeadock.md](../analasysOfIdeadock.md). This plan assumes you have read both.
Engine: Godot 4 (owner's choice).

## 1. Goal

Build one playable vertical slice that proves the core loop, then stop and judge it before committing to the full game.

The slice is one star system, one asteroid field, one starter ship and one small station. The player scans, mines, hauls, refines, fabricates, installs, builds a drone, hands the job to an AI core, and spends the output on expanding the station.

Nothing beyond the slice is scheduled in detail. Section 9 is direction only, and milestone M4 decides whether it happens.

### Owner rulings, 2026-11-04 (these override anything below that disagrees)

The core idea of the game is as follows:

- **You start with only your ship.** There is no station, no other ship and nothing built on a planet. Space holds rocks and planets, and nothing else.
- From there you mine, explore and create new technology. You then build ships and stations to refine, to test new technology and to gather more resources.
- You plan routes for your automated ships, which run on cycles until the resource runs out.

**Everything is buildable.** That covers every hull of every size, every station hub and station module, and every part. A ship or station exists only because the player built it. The starter station in sections 1 and 7 is withdrawn.

**Flight is mixed.** The player flies their own ship. Automated flight belongs to the AI cores, and is what a core does for a ship it controls. The autopilot is not how all flight works. Every run mixes player-flown and core-flown ships.

**Orbits:** option 3 of [orbital_flight.md](../docs/design/orbital_flight.md) is approved. It covers integer orbits on rails, an autopilot for core-flown ships, and manual burns. Because the player flies their own ship, manual burns are not to be pushed to the end.

**Owner's rule, 2026-11-07: "Shortcuts are not welcome in my game if it loses out on what I have asked for."** The straight-line, gravity-free co-moving frame (orbital_flight.md 11.2) is to be removed entirely. Every ship and rock moves on real orbits, including travel between asteroids, rendezvous and docking approaches. No simplification may be approved that drops anything the owner asked for; if in doubt, ask the owner first.

**Owner's rulings, 2026-11-07, applying that rule.** Simplified options are never offered as choices; the realistic version is the default.
- **Factories:** a job's speed is the lowest of the power supplied, the heat the radiators can reject, and the machine's material throughput. Work points as a bare number go.
- **Fitting:** no hard power checks. Fitting warns ("this can draw 202 kW, you make 120 kW") and allows; running out of power is handled in play. Mass and connector load also warn and allow (Lead, 2026-11-08). The physical consequence comes from the structure and damage item of the audits: an overloaded connector or structure fails under load ([schemas.md](../docs/design/schemas.md) section 5).
- **Landing:** land anywhere, at an exact position, with slope and height from the terrain under the legs. One site per hex goes.
- **Research tests:** prototypes are proven by field trials judged on performance (the design must actually do the job), plus a chance of manufacturing defects. Tests that always pass go.
- **Production:** deep, real chains: reductants for refining, water electrolysis to hydrogen and oxygen, real propellants per engine, slag kept, steel, wafers to chips, and so on.
- **Gravity:** patched conics (one body's pull at a time) stay, as the owner accepted.
- **Every other simplification** in A53's and the audits' lists is to be done; only the order is open.

**Lead's working decisions, 2026-11-08 and 09.** The owner may overrule any of these. Most are data and cheap to change.
- **Cluster layout:** mixed. Close rocks 3 to 8 km away near the start. White Rock and Black Rock (carbonaceous) out in a 30 to 45 km swirl.
- **Bootstrap:**
  - First steel by induction melt on the compact refinery.
  - Hydrogen borrowed from the tank until the electrolyser pays it back.
  - Blister-copper MI cable as the interim wiring.
  - Nickel from Red Rock's Fe-Ni by the Mond process.
- **Hold seeds**, all counted against hull mass:
  - about 200 chips;
  - KOH;
  - solar cells for two panels;
  - about 20 kg of graphite;
  - about 2 kg of rare-earth dopant;
  - laser pump diodes.
- **Parts:**
  - Real masses ([part_masses.md](../docs/design/part_masses.md)).
  - Two radiator temperatures. A load's heat goes only to radiators at or below its temperature.
  - Small parts at a few kW.
  - Fuel-cell main battery and nickel-iron small bank.
  - starter_hull gains ring side_d and a 16 t limit. command_hub becomes 16 m.
- **Mining:** rate = beam power / the rock's spall energy (about 1 MJ/kg).
- **Fitting:**
  - Warns on mass, load, power and heat.
  - Refuses only on connector type, size and occupancy, and on solid parts overlapping.
- **Wiring:** a refined harness loses 2%. Alternative grades lose in proportion to resistance. A part built with an alternative is its own derived item (`module~alternative`).
- **Scans:**
  - Instruments reveal in steps, each with its own range.
  - LIDAR: shape at 25 km.
  - Spectrometer: class at 10 km, grade at 1 km.
- **Docking:** a pair of ports uses the stricter port's capture limits.

**Work list additions, not yet scheduled:**
- stowed and deployed wings, deploy time and self-shading;
- deposits at sites on a rock (today a rock's ore is one pool);
- cryogenic boil-off in the sim;
- the thruster mixture;
- connector load in the view;
- collision damage;
- planet rotation (Frost is assumed not to rotate);
- turning time for steering, which is instant today;
- renaming leftover names from the frames.

**Planets:** hexes are a fixed size of about 7 km ([planets.md](../docs/design/planets.md)).

**Pacing:** leave the figures as they are for now ([balance.md](../docs/design/balance.md)).

**Approved:** a job queue for the refinery and fabricator, and a "fit like this one" action that copies one craft's fit onto another.

**Research:** "create new tech" and "run tests for new tech" are part of the core loop. Item 3 of section 4, which deferred research, is withdrawn.

### Owner ruling on research, 2026-11-06

- **Science points** come from scanning and from science tasks: measuring things in orbit and on asteroids.
- **Nothing is click-and-it's-yours.** Every new unlock starts as a theory. A theory has to be proven by testing before anything can be built with it.
- **Once a theory is proven**, you can build prototypes of things that use it, and each new thing needs its prototype tested before it becomes a normal part.
- **Every part can be improved** with ideas, chosen from a number of potential upgrades. Each improvement makes some stats better and others worse, and you can always go back to the original design.
- **Improvements add complexity.** Each one makes the part harder to build and more expensive. Some of the potential upgrades give a chance to reduce that complexity and cost again.

### Owner rulings on the new start, 2026-11-06

- **Propellant is made from ice.** Helium or other sources come at a later stage, possibly as propellant for electric thrusters. There is no second starting tank.
- **Work, not time.** A recipe or job has no set duration and no "half speed" variant. Each recipe needs a number of work points to complete. Each factory removes a number of work points per tick, so a smaller factory is simply slower at the same recipe. This also applies to research tests.
- **Both asteroid groups exist, with different resources.** There is a cluster near the starting moon (the icy, half-density 60 km moon at 300 km), and a belt round the star. Use the idea doc's split: the cluster holds the industrial ores, and the belt holds gold, silver, copper, platinum, sphalerite, smithsonite, garnierite, graphene, ammonia and ozone.

## 2. Assumed decisions

All are confirmed by the owner. Flight in the slice is order-based, not hands-on. "Newman Probe" and "spacejunk" are both placeholder names.

| # | Decision | Default | Why |
| - | -------- | ------- | --- |
| 1 | Who is the player? | The mind of a self-replicating probe. No crew. | Inferred from the project name (von Neumann probe); neither doc states it. It gives the game its premise, makes automation the point rather than a threat, and removes life support from scope. The analysis marks crew as conditional. |
| 2 | 2D or 3D | **3D** (owner's decision) | The game is 3D. Section 5 covers how the client handles it, and the art approach suits a team with no artists. |
| 3 | Language | Statically typed GDScript | One toolchain, fastest iteration, no .NET export limits. Hot loops can move to a GDExtension later if profiling demands it. |
| 4 | Time model | Real time with pause and speed controls, on a fixed simulation tick | Fits automation play and keeps the simulation testable. |
| 5 | Conflict | No combat or factions in the slice | The analysis marks both as conditional. Hazards and wear provide the pressure. |
| 6 | Platform | Windows PC, single player, mouse and keyboard | The owner's machine. Godot keeps other exports open. |
| 7 | Visual style | **In the style of Kerbal Space Program** (owner's decision) | Chunky, stacked, semi-realistic hardware that reads clearly at a glance. Section 5 defines it. This sets the look only, not KSP's gameplay. |

## 3. Problems in the source docs to fix first

Task B1 resolves these in a canonical spec. The two source docs stay untouched as history.

**Already flagged by the analysis**
- Resources sit at mixed levels of the economy and need the six-stage model.
- Eight environment assignments are not credible (antimatter in dust clouds, gold from solar flares and so on).
- Quantum entanglement cannot send messages, so it must be declared fictional with its own rules.

**Found while cross-checking the lists; not in the analysis**
- Five of the 45 master resources appear in no environment: **Water, Magnetite, Monazite, Sulfur, Bismuth**. Water is the worst case, because the analysis relies on it for propellant and life support.
- The analysis's corrections leave **Uraninite** with no source, since Radiation Bursts is its only listed location. **Thorium** has none either, since its only implied source is Monazite.
- **Tungsten, Iridium, Gallium, Arsenic and Yttrium** are required by the material list (Yttrium and Gallium Arsenide via YAG and GaAs crystals) but have no ore or source.
- Ores for **Zinc, Lead, Tin, Manganese and Chromium** exist but no listed material uses them. Give each a use or cut it.
- **Hydrogen, Helium, Oxygen and Neon** appear under Stars but are outside the "all 45" list. Mining a star also needs a defined technology, or these should move to gas giants and ices.
- The analysis's silicon chain needs silica-bearing minerals, but none is in the master list.
- **Jump Coils** are described as navigation in the idea doc and as the wormhole initiator in the analysis. Adopt the analysis's role.
- **AI tiers and stages disagree:** Strategic is tier 4, and Stage IV has coordinated fleets, but Stage V is the one labelled "Strategic AI". Align tier N with stage N.
- **Mining autonomy disagrees:** the tier table gives tier 2 "simple mining cycles", while the prose needs tier 3 for a whole operation. Rule used here: tier 2 repeats a fixed, configured cycle; tier 3 chooses and re-plans.

## 4. Where this plan departs from the analysis

1. **Add a tenth slice check: engineering limits must bind.** The analysis names heat, mass and logistics as its top foundations, but its nine-step checklist never tests heat or mass. The slice must include a fitting that fails on power, heat or mass, and that the player then fixes.
2. **Add a before-and-after autonomy moment.** The player runs the mining cycle by hand first, then hands it to a core. The handover is the game's main claim, so it needs to be felt.
3. **Defer research.** The analysis rates it critical, but its checklist omits it, and that omission is right. All slice recipes are available from the start. A tech system is the first candidate after the slice.
4. **Spike the late game early.** The analysis calls the shift from operator to policy-setter the strongest differentiator, yet the slice never reaches it. Task D6 mocks a standing-orders screen to test the idea cheaply.

## 5. Technical architecture

**Rule one: the simulation runs without the game.** `sim/` is plain typed GDScript (`RefCounted`) with no Node or SceneTree references. The client sends commands and reads state and events. This is what lets five agents work in parallel, and lets a scripted bot play the whole game in a headless test.

```
project.godot        Lead only
data/                JSON definitions: items, modules, recipes, deposits (Agent B)
sim/kernel/          tick loop, state, commands, events, save/load, RNG (Agent A)
sim/networks/        power, heat, cargo flow (Agent A)
sim/industry/        mining, refining, fabrication, construction (Agent C)
sim/autonomy/        task system and AI tiers (Agent C)
client/              3D scenes, UI, input, camera, rendering (Agent D)
assets/              3D models, materials, shaders (Agent B)
tests/               GUT tests, mirroring the folders above (each owner)
tools/               test runner, data validator, screenshot harness
docs/design/         canonical spec (Agent B, Lead approves)
```

**Simulation rules**
- Fixed tick, proposed 10 per second and provisional until the first performance and gameplay tests. The rate is one constant. Data states rates per second, never per tick, so changing it touches no content. No substeps in the slice. Rendering interpolates and never drives logic.
- Time is counted in ticks. All randomness comes from a seeded generator held in the state, so a run replays identically for a given seed and command list.
- All simulation state is 64-bit integer: matter in grams, power in watts, energy in joules, positions as 3D vectors in millimetres, and travel as progress along a route. Positions are limited to about 0.42 light-years either side of the origin, so differences cannot overflow, which is enough for one star system. Interstellar play will use a star-system ID plus local coordinates; that is not built in the slice. Floats are for display only. This lets conservation be tested exactly and keeps state hashes stable.
- Rounding: per-tick amounts round down, and the remainder is stored in the state and carried to the next tick, so nothing is ever lost or created. `contracts.md` documents each unit's valid range, and calculations that could overflow are tested at those limits.
- Ship movement in the slice is order-based along routes, not free Newtonian flight.
- Systems process entities in ascending ID order, so results never depend on creation or dictionary order.
- All state serializes to a save file from the first day, not as a later feature.
- Serialization is canonical: entities, tasks, inventories and all other collections are written in a defined sorted order. The state hash is calculated from this canonical form, never from dictionary iteration order.
- Commands and events are typed and logged. Commands are stamped with the tick they apply on.

**Tick order.** Every tick runs these steps, in this order. A change needs Lead approval.
1. Apply commands stamped for this tick. Invalid commands are rejected with an event.
2. Update tasks and unit instructions.
3. Calculate available power on each network.
4. Determine active operations, allocate power by priority, and reserve inputs and cargo space.
5. Run propulsion, mining and industry.
6. Update inventories, battery charge and heat.
7. Detect damage, faults and shutdowns, and set them in the state.
8. Emit events and commit. Saves and state hashes happen only between ticks.

Fault timing: a fault is detected and set in step 7, and reported in step 8 of the same tick. Its consequences apply from the start of the next tick. Commands aimed at the faulted module are rejected in step 1, and it receives no power or new work in steps 3 and 4. Its running job pauses with its inputs still held, and the job resumes or cancels under the C0 rules.

**Resource accounting.** Every kilogram is in exactly one place: a deposit, an inventory, a running job, an installed module, or a declared sink.
- A job removes its inputs when it starts and delivers its outputs when it finishes. Matter inside a running job is still counted, so cancelling cannot duplicate or destroy it.
- Every recipe balances exactly by mass, with byproducts listed explicitly (slag, off-gas).
- Slice recipes are abstract and labelled as such (`"abstract": true`): they use no reductants or other reagents, and all output mass comes from the listed inputs. Realistic chemistry with oxygen, carbon and water arrives after the slice under the same ledger.
- Matter enters only through the scenario's starting stock and leaves only through declared sinks, such as propellant exhaust.
- A test sums all matter every tick and fails on any difference.

**Power and heat networks in the slice.** Each vessel or station has one power network and one heat loop, and docking does not join them.
- Each module declares a priority class. On a shortfall, the lowest class sheds first.
- Loads are fully on or off, with no partial running.
- Batteries have a maximum discharge rate, so stored energy cannot always meet peak demand.
- Surplus power charges batteries. Radiators reject heat at a fixed rate, and exceeding the heat limit causes a fault shutdown.
- Energy is ledgered like matter. A test checks every tick that energy generated or drawn from storage equals energy consumed, stored and explicitly lost, including through conversion efficiencies. It also covers battery discharge, shutdowns and competing loads.
- Heat has its own simple ledger, separate from electrical energy: each loop's heat changes only by waste heat added and heat rejected.
- Links between networks wait until after the slice.

**Cargo operations.** Travel, dock, load, unload and undock are separate operations, and each takes time. Capacity limits apply to mass and volume. Transfer rate is limited by the docking port.

**Autonomy.** Every task has one owner and moves through a defined state machine. Task C0 specifies the states, reservations, failure reporting and resumption, and what happens on each interruption: a player order, a module fault, lost power, full cargo, an exhausted deposit and no propellant. The minimum behaviour: tier 1 stops and waits for orders when interrupted, and tier 2 resumes its cycle from the last safe step.

**Attachment contract.** One set of rules covers ship fitting and station expansion, and it is defined in `data/` and enforced by the simulation.
- **Connector:** each one states its type (stack, side or dock), size, position and orientation, whether it is occupied, and the load it can carry.
- **Compatibility:** two parts join only if their connector types and sizes match and the load limit holds. A failed join gives a stated reason, which feeds acceptance check 10.
- **Hierarchy:** each craft is a tree of parts rooted at its root part. Removing a part removes or detaches everything below it.

**Data over code.** The analysis's key recommendation is one module schema. New components should be data, not scripts. JSON is chosen over `.tres` because it is safe for agents to generate, easy to diff and easy to validate.

```json
{
  "id": "mining_laser_mk1",
  "mass_kg": 400, "volume_m3": 2,
  "power_kw": 150, "heat_kw": 120, "durability": 1000,
  "min_ai_tier": 1,
  "realism": "extrapolation",
  "capabilities": { "mine": { "rate_kg_per_s": 20, "hardness_max": 6 } },
  "fabrication": { "recipe": "mining_laser_mk1", "facility": "fabricator" },
  "connectors": [{ "type": "side", "size": "medium", "pos_mm": [0, 0, 0], "facing": "-z" }],
  "visual": { "model": "mining_laser_mk1" }
}
```

Data files use readable units such as kg and kW. The loader converts them to simulation units, and the validator rejects any value that does not convert exactly. Modules gain behaviour by declaring capabilities that systems read, so hundreds of parts need no new rules. The `realism` field carries the analysis's classification (established, extrapolation, speculative, fictional).

**Testing.** GUT is used, as it suits pure-GDScript projects and has a command-line runner. `tools/test.ps1` runs the import step and then the tests headless. The project is pinned to Godot 4.7.2 stable and GUT 9.6.1, which is committed under `addons/gut`.

**Performance.** Later scale will strain GDScript. Budget from the start: a perf test measures active ships, running tasks, inventories, networks and modules together, at the full tick rate. The proposed starting load is 1,000 modules; A7 sets the other numbers after a first measurement. Remote sites will run as aggregate rates rather than per-unit simulation.

**3D client.** The simulation rules above do not change. `sim/` stores positions and knows nothing about rendering.
- **Renderer:** Forward+, targeting PC.
- **Large distances:** standard Godot builds use single-precision floats, which jitter far from the origin. The client renders everything relative to the camera focus (a floating origin), and shows distant bodies such as the star at compressed scale. This avoids a custom double-precision engine build.
- **Views:** a local view with an orbit camera around the selected ship or station, and a 3D system map for routes and destinations.
- **Interaction:** objects are selected by raycast. Menus and panels are a 2D overlay on the 3D scene.
- **Ships and stations:** craft are built KSP-fashion as visible stacks of parts. The hull is a central spine with fixed stack and side mount points, in a small set of standard diameters. Stations are cylindrical modules joined at hubs. Fitted parts and station expansions visibly appear on the craft. Free-form 3D shipbuilding is outside the slice.
- **Art:** models come from the owner's image-to-3d pipeline (see below). A module with no model shows a labelled placeholder, so no task ever waits on art.
- **Visual style:**
  - Parts are chunky and rounded: cylinders, tapers, tanks, flanged joints and bolted-on boxes, slightly oversized for readability.
  - Colours are simple blocks of off-white, mid grey and safety orange, with foil-gold accents.
  - The look is clean and bright, with a strong star light and a dark, uncluttered sky.
  - Ships stay crewless, so there are no characters.
  - All designs are original. No KSP parts, logos or names are copied, and briefs describe the look in their own words.
- **Asteroids:** generated from the seed and drawn with `MultiMeshInstance3D`, so large fields stay cheap.
- **Verification:** rendered screenshots need a GPU, so the screenshot harness runs windowed rather than headless. A frame-time test covers the slice's full load on the owner's PC, with a proposed target of 60 frames per second.

**Asset pipeline.** The image-to-3d repo builds each model from one picture using TRELLIS.2, run through that repo's resident agent (session `image-to-3d-19`). Agent B handles all contact with it.
- **Requests:** text briefs only. We never make or supply images; Codex draws every picture from the brief. A request is one message giving the path to briefs held in this repo, in the format of `image-to-3d/wishlist/explorer/flight_windsock.md`. Neither project writes into the other's repo.
- **Each brief states:** real size, materials, view and triangle target, plus these instructions for Codex: whole object in frame, 3/4 view, pure white background, even light, no floor or shadow, mid-tone colours rather than near-black, at least 1024 px, and thin parts drawn thick.
- **Delivery:** `.glb` files land in `image-to-3d/data/props/out/newmanprobe/` with a check sheet. Agent B copies them into `assets/` and sets the import options.
- **Triangles:** the target must be set before generation. Reducing a model afterwards has shattered textures, so the pipeline's raw output of about 500k triangles cannot be fixed later. Godot's automatic LOD generation must be tested for the same fault.
- **Design for the pipeline:**
  - Use chunky, solid shapes. Station frames have thick members, and solar panels and radiators are solid slabs. Avoid lattices, grilles, thin rails and antennas.
  - Keep identity in the silhouette and colour, because fine stripes and decals come out ragged.
  - Use one solid mesh per module. Moving parts need a manual split, so the slice has none: a part that turns rotates as a whole.
  - Models are closed shells with invented backs, so nothing shows an interior.
- **Models are visual only.** They never determine collision, attachment positions, mass, volume or manufacturing data. All of those come from module definitions in `data/`. Collision and selection use simple shapes defined there, and placeholders use the same data, so swapping in a model changes nothing in the simulation.
- **Fit:** surfaces are slightly lumpy, so each model is aligned at import to the connector positions in `data/`, never the other way round. Each module's origin sits on its mount face, and modules end in collars or flanges that hide small gaps. Where an exact fit matters, use flat panels built as exact boxes.
- **Scale:** scaling is uniform, set from one dimension, so proportions come from the picture. Mass and volume in `data/` stay authoritative, and the import step reports how far each model differs.
- **Materials:** metallic and roughness are only estimates and come out mostly matte. Agent B sets final material values on import. The client adds glow and status effects by shader.
- **Set size:** each model gets the same level of detail regardless of real size, so large ships and stations are assembled from modules rather than built as one huge model.
- **Throughput:** expect about 10 models per one-hour GPU hold, with about 1 in 4 needing a redo. The slice's roughly 20 models need 2 to 3 holds, plus picture time. Holds are shared with other projects, so delivery dates are outside this team's control.

## 6. Team and working rules

| Role | Session | Owns |
| ---- | ------- | ---- |
| Lead | newmanprobe-14 | Architecture, contracts, reviews, merges, `project.godot`, integration |
| Agent A: Simulation Kernel | newmanprobe-4f | Tick loop, state, save/load, power, heat and cargo networks, perf |
| Agent B: Systems Design, Data and 3D Assets | newmanprobe-b9 | Canonical spec, schemas, all `data/`, validator, balance; `assets/` once M1 is done |
| Agent C: Gameplay Systems | newmanprobe-3e | Mining, refining, fabrication, construction, tasks, AI tiers, the bot |
| Agent D: Client | newmanprobe-aa | 3D scenes, camera, UI, input, feedback, screenshot harness, frame-time test |

**Rules**
- Each agent works in its own git worktree (`../newmanprobe-wt/<role>`) and never in the main checkout. All sessions share one disk, so this prevents overwrites.
- One branch per task, named `<role>/<task-id>`. Only the Lead merges to `main`.
- Agents edit only folders they own. Changes elsewhere go to the owner by message.
- Contracts (`docs/design/contracts.md`, covering commands, events, entity and state views, tick order, numeric units and the schema) change only through the Lead.
- A task is done when `tools/test.ps1` passes on its branch, its acceptance check holds, and new behaviour has tests.
- The full gate skips `tests/playthrough` (D31, a real-client playthrough of the new start, about 4 min). Run `tools/test.ps1 -Playthrough` before merging anything that touches the new start's UI, its snapshots (`tests/slow/new_start/`), or the order and jobs panels. The Lead runs it on those merges.
- Snapshots in `tests/slow/new_start/` are generated. Any branch whose change moves the data hash or the save format may commit them, regenerated with `tests/bot/new_start_snapshots.gd` and never hand-edited, and must then run `-Playthrough`. If main's snapshots change before the merge, regenerate again after merging main. Say "snapshots regenerated" in the commit.
- Client work also needs a screenshot read back by the agent. Agents cannot judge feel, so the owner is the playtester.
- If a task is blocked for more than a short attempt, report to the Lead rather than work around it.
- **GPU holds stop all Godot use.** The image-to-3d pipeline needs the GPU alone, and any Godot process, even headless, can corrupt its output. Before each hold the Lead creates `newmanprobe-wt/GPU_HOLD` (which makes `tools/test.ps1` refuse to run), tells all agents to stop, confirms that no Godot process is running, and tells the image-to-3d agent it can begin. The Lead removes the file and gives the all-clear afterwards. Agents keep doing non-Godot work during a hold.

## 7. Slice content

Everything else in the catalog waits.

| Category | In the slice |
| -------- | ------------ |
| Deposits | Hematite, Chalcopyrite, one silica-bearing mineral (B1 picks it) |
| Materials | Iron, Copper, Silicon, plus slag so that matter is conserved |
| Components | Structural frame, wiring, processor |
| Cores | Basic Core and Assisted Core, as modules |
| Ship modules | Hull, chemical thruster, propellant tank, solar panel, battery bank, heat radiator, LIDAR, mining laser, ore container, docking port |
| Station modules | Command hub, solar farm, ore refinery, fabricator, ore and goods storage, docking port |
| Drone | One mining drone: a small hull and small versions of the ship's modules, fitted like a ship |
| AI tiers | Tier 1 Basic and tier 2 Assisted only |
| Propellant | A finite depot stock, so every trip has a cost. Water-to-propellant is the first post-slice chain. |
| 3D visuals | One hull and one station frame with hardpoints, a model for each module above and each small drone part (from the pipeline, with placeholders until then), plus procedural asteroids, the star and a space backdrop (from the client) |

**Slice acceptance checks**, run by the scripted bot and later by a person:
1. Scan an asteroid and identify deposits.
2. Mine ore with the mining laser.
3. Haul the ore into storage.
4. Refine it into metals.
5. Fabricate a component.
6. Install it on a vessel.
7. Build a mining drone.
8. Assign a core and watch it run the cycle unaided.
9. Spend the output on a station expansion.
10. Hit and fix a failed fitting caused by power, heat or mass.

## 8. Milestones and tasks

Work is ordered by dependency. No dates are given because agent throughput on this project is unknown; M0 will give the first real measure.

### M0: Foundations (Lead)
Exit: an empty project opens, one test passes headless, all worktrees exist, and the contracts are signed off.

| ID | Task | Depends on |
| -- | ---- | ---------- |
| L1 | `.gitignore`, folder layout, `project.godot`, first commit. Repo initialized; `origin` is `github.com/Tunje/spacejunk`, and only the Lead pushes. | Sign-off |
| L2 | Install and pin Godot (it is not on PATH today), install GUT | L1 |
| L3 | `tools/test.ps1`, `CLAUDE.md` with the section 6 rules | L2 |
| L4 | Draft `contracts.md` from section 5 | L1 |
| L5 | Create worktrees and brief each agent | L3 |
| L7 | A, C and D review the contracts; Lead signs them off | L4, L5 |

### M1: Specification (B leads, A/C/D review)
Exit: all specs below are signed off, the reference scenario is complete, and the slice has no open questions.

Parallel implementation is gated on this. Only A1, A2, D1 and D2 rely on the contracts alone, so they may start after L7. All other implementation waits for M1 to exit.

| ID | Owner | Task | Depends on |
| -- | ----- | ---- | ---------- |
| A0 | A | Network and cargo spec, expanding section 5 | L7 |
| C0 | C | Autonomy task state machine | L7 |
| B1 | B | Canonical design spec resolving section 3 | L5 |
| B2 | B | Fictional physics rules page (wormhole energy, stability and accuracy thresholds; entanglement comms) | B1 |
| B3 | B | Module, item, recipe, deposit and connector schemas | L7, B1 |
| B7 | B | Resource accounting spec, expanding section 5 | B1 |
| B4 | B | Data validator: broken references, every item has a source and a use, recipes balance by mass | B3, B7 |
| B5 | B | Author all slice data from section 7 | B3, B7 |
| B8 | B | Reference scenario, reviewed by A and C (see below) | B5, A0, C0 |

**The reference scenario** is one worked mining-to-manufacturing chain that every agent builds against. It fixes the seed, starting inventories, equipment, deposits and command list, and gives hand-calculated expected outputs for each step. It becomes the first golden test.

### M2: Headless slice (A, C)
Exit: the bot passes the reference scenario and all ten checks in a headless run, the run replays identically, and it survives a save and load midway.

| ID | Owner | Task | Depends on |
| -- | ----- | ---- | ---------- |
| A1 | A | Tick loop in the section 5 order, state, commands, events, seeded RNG, canonical state hash | L7 |
| A2 | A | Canonical save/load with a round-trip test | A1 |
| A3 | A | Data loader, entities, attachment tree, fitting checks for connectors, mass, power and heat, matter ledger test | A1, M1 exit |
| A4 | A | Power network: output, storage, priorities, load shedding, energy ledger test | A3 |
| A5 | A | Heat network: waste heat, radiators, fault shutdown, heat ledger test | A4 |
| A6 | A | Cargo operations: inventories, travel, docking, transfer, throughput limits | A3 |
| A7 | A | Perf test across all load types plus one `view()` per tick, and budget | A4, A5, A6 |
| C1 | C | Scanning and deposits | A3 |
| C2 | C | Mining with depletion and power and heat draw | C1, A5 |
| C3 | C | Refining and fabrication with throughput limits | A6 |
| C4 | C | Installation and construction, including the drone and station expansion | C3 |
| C5 | C | Task system: tier 1 needs each order, tier 2 repeats a configured cycle | C2, C4 |
| C6 | C | Bot, the reference scenario golden test, and the ten acceptance checks | C5 |
| C7 | C | Determinism test: same seed and commands give the same canonical state hash, with and without a save and load midway | C6, A2 |
| B6 | B | Balance run: bot metrics, tune `data/` | C6 |

### M3: Playable slice (D, supported by all)
Exit: the owner completes the loop unaided from a fresh start. Placeholder models are acceptable, so neither this milestone nor M4 depends on the GPU queue.

D can start as soon as L7 is done, using a stub simulation, so M2 does not block it.

| ID | Owner | Task | Depends on |
| -- | ----- | ---- | ---------- |
| D1 | D | Client shell, sim bridge, pause and speed controls, screenshot harness | L7 |
| D2 | D | 3D local view: floating origin, orbit camera, raycast selection, issuing orders | D1 |
| D8 | D | Space scene: procedural asteroid field, star, lighting, backdrop | D2 |
| D9 | D | 3D system map | D2 |
| B9 | B | Style brief and style test: 2 models at a game-weight target (hull and one module) to prove the KSP-style look, off-white parts against the white picture background, and triangle budgets. No batch until this passes. | B5, D2 |
| B12 | B | Write all model briefs and request the full batch (renumbered from B10, which became the start redesign) | B9 |
| B11 | B | Import step: scale check, origins, materials, alignment to the connectors in `data/`; replace placeholders | B10 |
| D3 | D | Inspection panels: cargo, power, heat, status | D1, A6 |
| D4 | D | Ship fitting screen on the 3D hull, showing mass, power and heat limits | D3, A5 |
| D5 | D | Station, refinery and fabrication screens; AI assignment | D3, C5 |
| D6 | D | Mock standing-orders screen (the section 4 spike) | D1 |
| D10 | D | 3D feedback: mining beam, thrust, docking, radiator glow, visible station growth | D8 |
| D11 | D | Frame-time test at full slice load | D8, D10 |
| D7 | D | Onboarding, goals and feedback through all ten checks | D4, D5, D10 |
| L6 | Lead | Integration passes after each screen lands; save and load from the UI | D2 onward |

### M4: Decision gate (Owner, Lead)
The owner plays the slice, then decides: continue, change the core loop, or stop.

Questions to answer: Is the handover to the AI satisfying? Is hauling a good constraint or a chore? Does the fitting failure feel like engineering or a nuisance? Do you want to play one more cycle?

## 9. After the slice (direction only)

If M4 passes, in this order:
1. Tech progression, Assisted to Adaptive, and the water-to-propellant chain.
2. Wear and reliability, hazards, and distributed construction across specialized stations.
3. Interplanetary scale: more environments, fission and ion propulsion, and tiers 3 and 4.
4. Multi-stage jumps and gateways, interstellar logistics, and tiers 5 and 6 with the policy layer.

## 10. Design suggestions

- **Make light delay the reason for autonomy.** Comms have no gameplay role in either doc. If orders take real time to reach distant assets, you cannot micromanage them, so higher AI tiers become necessary. It also gives each antenna type a job, and makes entanglement comms a major late unlock. This is the suggestion I would most like to test, and it fits the probe premise.
- **Grow the probe into a distributed intelligence.** If decision 1 stands, progression should not just mean commanding more ships. The player should go from one self-sufficient machine to one mind spread across an industrial network, which ties the story directly to the AI, logistics and construction systems.
- **Keep intelligence and authorization separate.** The analysis's distinction becomes the late-game verb: the player grants permissions and limits rather than issuing orders.
- **Bound self-recursive AI with physical inputs.** Each improvement costs compute, energy and manufactured hardware, as the analysis suggests. Better designs still have to be built.
- **Make acquisition methods feel different.** Mining, gas scooping, breeding and accelerator synthesis should each have their own loop, not a new "extractor" module with a different label.
- **Let failure teach.** Failures should be diagnosable, recoverable and shown as a chain of causes, since the player is effectively debugging a machine.
- **Show system state on the craft.** The KSP-style look makes each part easy to recognize, so state can be read straight off the model, such as radiators glowing as heat rises.

## 11. Risks

| Risk | Mitigation |
| ---- | ---------- |
| Scope creep from the very large catalog | Section 7 is the limit. Anything else needs Lead and owner approval. |
| Agents overwrite each other | Worktrees, folder ownership, Lead-only merges |
| Integration failures between separately built systems (the main technical risk) | Signed-off contracts, fixed tick order, the M1 gate, and one shared reference scenario |
| Interface drift between sim and client | Contracts doc plus the stub simulation |
| Matter or energy duplicated or lost through system interactions | The matter ledger test on every tick, and inputs held inside jobs |
| Tests pass but the game is not fun | The M4 gate, owner playtesting, and the D6 spike |
| Hauling and refining feel tedious | Tier 2 removes the repetition; tune with B6 |
| 3D client work overloads Agent D and delays M3 | The stub simulation lets D start early, B takes over models after M1, and the Lead can move tasks once M0 shows real throughput |
| 3D art takes over the project | Models come from the image-to-3d pipeline, placeholders cover anything missing, and no art work goes beyond the section 7 list |
| Game-weight hard-surface models look poor (untested on this style) | The B9 style test runs before any batch. If it fails, the owner chooses between a heavier budget and hand-made or kitbashed models. |
| Pipeline models vary in style or scale, or miss mount points | One shared style brief, collars that hide gaps, and an import step that normalizes scale and origins |
| GPU queue delays art, as holds are shared with other projects | Placeholders mean no milestone depends on the queue; the owner sets queue order |
| Godot runs during a hold and corrupts a batch | The section 6 hold rule, with the Lead confirming no Godot process is running |
| Camera or selection in 3D makes a simple loop awkward | Owner tries D2 early rather than waiting for M4 |
| Rendering jitter at long distances | Floating origin and compressed distant bodies from D2 onward |
| GDScript too slow at scale | The perf budget from A7, aggregate remote sites, GDExtension if needed |
| Godot addon or version drift | Pinned engine and addon versions in the repo |
