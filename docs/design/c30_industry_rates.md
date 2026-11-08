# C30: factory rates, fitting warnings and dock feeds (proposal)

Agent C, 2026-11-08, for the Lead. Applies the owner's rulings of 2026-11-07. Nothing here is built yet. Parts 1 and 2 touch A's power, heat and fitting code, B's data and D's job view, so all three parts need sign-off.

## 1. A job runs at the lowest of three limits

**Today.** A run needs `work` points and the facility does `work_per_tick` of them. The power draw is fixed: `recipe power_w × work_per_tick / 100`. It is all-or-nothing, and a shed run makes no progress. Heat is the module's flat `heat_w` whenever the facility runs. Radiators never slow a job; they only fault it.

**Proposed: a run needs energy, and its speed is the power it actually gets.**

Data (B's; B29 will set the real figures):
- **Recipe.**
  - `energy_kj`: the energy one run needs. It replaces both `work` and `power_kw`.
  - `heat_kj`: the waste heat one run gives off. It can be less than `energy_kj` where the products store energy, as in reduction or electrolysis, and more where the reaction gives off heat of its own.
  - The run's mass `M` is the sum of its inputs' grams.
- **Facility capability.**
  - `throughput_kg_s`: how much material the machine can handle.
  - Its existing `power_kw` stays as the most the machine can draw, its rating.
  - Its `heat_kw` stays as the fit rating only.

Each phase 4, for each running job, in keep order:
- `P_power`: what the unit's network grants the job, at most the facility's rating.
- `P_heat = H × E / Q`. `H` is the radiators' heat headroom left for this job, and `E` and `Q` are the run's energy and heat.
- `P_mass = throughput × E / M`.
- The job runs at `rate_w = min(P_power, P_heat, P_mass)`. It draws `rate_w` from the network, and gives `mul_div(rate_w, Q, E)` of heat to the loop.

The view's `limit` is whichever of the three set the rate. On ties it is the first in the order power, heat, throughput. The machine's own rating counts as throughput, since it is a limit of the machine and not of the supply. A job given nothing is shed with `no_power`, as now.

**Progress** is `energy_left_j` with an `energy_remainder`, taken off by `Rate.amount(rate_w, remainder)` each phase 5 tick. At 0 the run delivers, and anything left over is lost, as today. `work`, `work_left` and `work_per_tick` go.

**Power allocation** (A's `PowerSystem`) changes in two ways:
- Fixed loads (ops, cores, `always_on`) are still kept or shed whole, in the same order as now.
- Facilities become variable loads. Once the fixed loads are settled, what is left of `budget_w` goes to running jobs in keep order. Each job takes up to its want, which is `min(rating, P_heat, P_mass)`.
- **Alternative for A:** one walk in keep order that mixes fixed and variable loads, so a priority-3 factory could out-rank a priority-1 light. This is truer to `priority`, but changes today's shedding results.

**Heat headroom.** `H` is the healthy radiators' `reject_w` less the `heat_w` of the fixed loads kept this tick, floored at 0. It is handed to jobs in keep order, each taking only what its rate uses.
- A job therefore never adds heat faster than the radiators remove it. Stored heat, from a burn for example, still drains as now.
- `HeatSystem` takes each facility's heat from the job's figure, which `PowerSystem` puts in its flows, instead of from the module's `heat_w`.
- The over-limit faults stay for fixed loads.

**Coast.** `rate_w` is constant while the power flows and the heat headroom repeat, and the power and heat horizons already step every change to those. A running job coasts to the tick before `energy_left_j` runs out, in closed form like a cargo transfer. Its last tick is stepped.

**View** (contract v9). Each job shows:
- `energy_j` and `energy_left_j`;
- `rate_w` and `limit` (`"power"`, `"heat"` or `"throughput"`);
- `limits_w = { power, heat, throughput }`, so D can draw all three bars.

Progress is `1 - energy_left_j / energy_j`. The time left is `ceil(energy_left_j × TPS / rate_w)` ticks at the current rate.

**Interim data, until B29.** This gives the same energy as today, from figures already in the data:
- `energy_kj = power_kw × work / 1000`.
- `heat_kj = energy × the facility's heat/power ratio`: refinery 0.75, fabricator 0.8, lab 0.6.
- `throughput_kg_s`:
  - refinery 1.667, so the 100 kg ore runs keep their 60 s;
  - compact refinery 0.833;
  - fabricator 2.5;
  - compact fabricator 1.25;
  - lab 1.0.
- Run times will move. A recipe below its machine's rating now runs at the rating: wiring, at 50 kW on a 100 kW fabricator, halves to 10 s. So the new-start snapshots get regenerated.

**Who changes what:**
- **C:** JobSystem progress and the limit maths; JobSystem's coast and view; the tests.
- **A:** PowerSystem's variable loads and heat headroom, and HeatSystem's facility heat. I can write these with A's agreement, as in C20 and C29.
- **B:** the recipe and facility data fields, the validator, and schemas.md.
- **D:** the job panel.
- **Lead:** contracts sections 5 and 7, networks.md 2 to 4, and the save-format note.

## 2. Fitting warns and allows

`FittingSystem._fit_failure` (A's kernel) no longer refuses on `over_power_budget` or `over_heat_budget`.
- The attach goes ahead.
- `check` and the `part_attached` event carry `warnings: [{ code, need_w, have_w }]`, for example `{ "over_power_budget", 202000, 120000 }`.
- Mass, load and connector checks stay hard, since those are physical.
- The warning also travels with fits made by `copy_fit` and build-in-place (C15), which are mine: `job_finished` passes on the attach's warnings.

Running short in play is part 1's job: the factory slows, or a fixed load sheds.

## 3. Cross-dock transfers for job inputs (design only, as asked)

**The shortcut.** Since C26, a job draws its inputs from any unit in its docked group, at once and through any number of docks.

**Proposed: a feed through the dock.**
1. A run starts as now, once the group holds all its inputs. It takes what its own unit holds into `held` straight away.
2. For the rest, the run opens a **feed**: a transfer from a directly docked unit through that dock's two ports.
   - It runs at the same rate as `load_cargo`: the lower of the two ports' `transfer_g_per_s`, with a remainder, and whole units for whole-unit items.
   - It goes straight into the job's `held`, the machine's hopper, so it needs no hold room on the facility's unit.
   - One feed runs at a time, item by item in recipe order, and source by source in ascending unit ID.
3. While feeding, the run is `running` with `limit = "feed"`. It does no work until every input is held.
   - It counts as a run in progress for the queue skip (C24) and for cancelling, which hands `held` back to the job's own unit as now.
4. The dock is busy while a feed runs. A `load_cargo` or `unload_cargo` through the same dock waits on `port_busy`, as two transfers on one dock do today.
5. **Source reserve.** The source's stock for the feed is reserved, as transfers reserve theirs, through `Reservations`, which is A's. So a drone's own unload or a second job can't spend it.
6. **Undocking cuts a feed.**
   - What has moved stays moved.
   - The run goes back to waiting on `missing_inputs`, and feeds again from whatever is still docked.
   - The undock itself is not refused, so a station job can never trap a drone.
7. **Coast.** A feed is a closed-form transfer like C20's, and its last tick is stepped.

**Open question for the Lead: units more than one dock away.**
- Recommended: feed only from units docked directly to the facility's unit. Ore two docks away is moved by the player or a cycle, or a chain of feeds staged in the middle unit's hold, which needs room there.
- Neither is a shortcut. I recommend direct docks only for the first build, with staged chains as a later task if the owner wants them.

**Who changes what:**
- **C:** the feed in JobSystem, and the tests. This replaces C26's instant draw; C26's `_sources` and `_group_stock` stay as "is the run possible".
- **A:** Reservations for the feed's source stock, and port_busy and undock rules that know about feeds.
- **Lead:** the contract rows.

The new-start bot already unloads the drone's ore at the station in its cycle, so its timings barely move.
