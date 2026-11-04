# Orbital Flight and Automation

Status: proposal for the owner, written by Agent C (gameplay). Nothing here is decided, and order-based flight in [workplan.md](../../plan/workplan.md) stands until the owner rules. It is the automation part of the orbital flight question. [orbital_flight.md](orbital_flight.md) (Agent A) owns the flight model, and [planets.md](planets.md) (Agent B) owns where things orbit. Orbit figures are in A's table, [orbital_flight.md section 5, "Orbit figures"](orbital_flight.md#orbit-figures).

## 1. The plain answer

- **Automation survives gravity flight, if trips are on rails.** A drone's fixed cycle still works when bodies orbit, provided the sim can answer one question exactly: "if this unit leaves for that target on tick T, when does it arrive and what does it cost?" A's autopilot option gives that answer. Hands-on manoeuvre nodes do not, because a cycle can't replay a player's burns.
- **Where things orbit matters more than how flight works.** If the station and rocks stay a cluster in orbit around the star, distances barely change, and the cycle, the lap figures and the tests all stay as they are. If the station orbits a planet and the rocks are elsewhere, transfer windows appear, laps vary, and most of the cost in this page applies.
- **B recommends the cluster for the slice.** [planets.md](planets.md) keeps the station and the three rocks in one shared solar orbit, and proposes planets only after M4. So for the slice, automation needs no change. The window cost in sections 3 to 7 starts with a later planet scenario.
- **Tier 2 should wait for the window.** A lap leaves on the next transfer window, then follows its steps as today. It never takes a costlier path and never plans ahead. That keeps tier 2 a fixed cycle, as [spec.md](spec.md) section 5 defines it.
- **Planet trips are expeditions, not laps.** Inside a planet's gravity a transfer takes about half an orbit, and windows recur only once per synodic period, often hours apart. A repeating mining lap fits the rock cluster. Around a planet, a cycle is closer to an expedition, unless time warp goes well beyond 8x.
- **Orbits give tier 3 its first real job.** Choosing between waiting and paying more, cutting mining short to catch a window, and spacing drones so they don't queue at a port are real decisions. Today tier 3 would have little to do beyond picking deposits.
- **The fixed lap figures survive only in the cluster layout.** Around a planet, a test asserts the schedule the window rule gives, which a person can still work out by hand, and not one number per lap.
- **Recommendation: change nothing before the M4 judgement.** If the owner wants orbits afterwards, the cheapest version that keeps automation intact is real orbits with the autopilot, with each mining route in one orbit around the planet (section 2, layout B). Tier 3 waits until after that.

## 2. Three layouts

The same rules behave very differently depending on what orbits what. B's [planets.md](planets.md) recommends layout A for the slice. B or C would come only with a later planet scenario, such as a station in low orbit hauling from a surface or from a separate ring.

| Layout | What changes for a drone | Lap figures |
| ------ | ------------------------ | ----------- |
| **A. A cluster in solar orbit**: station and rocks 30 to 50 km apart, all circling the star | Nothing. The cluster is one co-moving frame, and trips inside it stay straight-line, as today. | Exact, as today. |
| **B. One ring around a planet**: station and rocks in the same orbit, at different points along it | No windows: every departure is as good as any other. But a hop takes about one orbit, so today's 3-minute trip takes over half an hour. | Fixed, but longer. |
| **C. Different orbits around a planet** | Transfer windows open and close. A drone waits, sometimes for hours. | Vary with orbital phase. Most of this page is about this layout. |

Trip times, propellant and window spacing for layouts B and C, with the orbits behind each figure, are in A's table, [orbital_flight.md section 5, "Orbit figures"](orbital_flight.md#orbit-figures). This page doesn't repeat them.

The table shows that in layout C, rocks close to the station's orbit have the rarest windows. A drone that laps in 9 minutes today could spend most of a session waiting.

**Layout A gives no Kerbal feel.** Gravity is present, but nothing visible changes, because over minutes a star's pull on a 50 km cluster is almost the same at every point. The Kerbal look and feel needs a planet, and so layout B or C.

## 3. Tier 2 cycles when things orbit

**Rule: each `move_to` leaves on the next window, and the cycle is otherwise unchanged.** A's flight model defines what a window is. For circular orbits in one plane, a Hohmann transfer comes round once per synodic period, the time for the two orbits to line up again, and the next one is worked out in closed form. A tier 2 drone takes that one. Inside the rock cluster there are no windows, and a `move_to` leaves at once, as today.

| Question | Answer |
| -------- | ------ |
| Does a lap wait for a window? | Yes. The `move_to` step waits in place, then flies. |
| Does it take a costlier path to go now? | No. In A's first step there is no costlier path to take: with Hohmann transfers only, every window costs the same, and no transfer leaves between windows. A paid early departure needs Lambert transfers, which A leaves for later. Even then, choosing to pay is a decision, so tier 2 still waits. |
| Does the cycle plan its windows? | No. Each move looks only at its own next window when it becomes current. Planning across a whole lap is tier 3. |
| Where does it wait? | After undocking, parked at the standoff beside the station. Waiting docked would hold the port for hours. |

**Waiting is not a block.** The task stays `running`, with a new operation `waiting` that carries the departure tick, so the client can show "leaves in 41 min" instead of a fault. Faults during a wait follow today's rules.

**What this does to laps.** Every departure lands on a window tick, so laps settle into whole multiples of the synodic period, plus or minus a tick of rounding. The first lap is the odd one out, because it starts whenever the player sets the cycle.

**What it does to several drones.** Drones on the same route all leave on the same window and arrive together. They then queue at the port, which today's first-come rule already orders deterministically (by `since_tick`, then entity ID). The cost is throughput: the last drone docks hundreds of ticks after the first and can miss the next window home, so the convoy settles into a slower rhythm. Tier 2 accepts this, and spacing the drones out is a job for tier 3.

## 4. Tier 3 re-planning

Today tier 3 is defined as "chooses and re-plans a whole operation". Straight-line flight leaves it little to do: every trip is the same price at any time, so the only real choice is which deposit to mine.

Orbits give it real decisions:

- **Wait or pay.** Go now at a higher cost, or wait for the cheaper window, given the propellant aboard and stocked at the station. This needs A's later Lambert transfers, because with Hohmann transfers alone every departure costs the same.
- **Cut mining short.** Leave with 80 % of a hold to catch a window rather than wait a full synodic period with 100 %.
- **Choose the route by window.** Mine the rock whose window opens first, not always the same one.
- **Stagger drones.** Spread the drones on one route over different windows, so they don't queue at the port together.
- **Plan propellant across laps.** Top up only what the next windows need.

So yes, orbits give the tiers a real reason to differ: tier 2 repeats a plan and pays in waiting, and tier 3 earns its place by not waiting. This is my main argument that layout C makes the automation game better. It is also the biggest single cost, and it belongs after M4.

## 5. What changes in today's rules

Section numbers are those of [autonomy.md](autonomy.md).

| Rule today | Change | Size |
| ---------- | ------ | ---- |
| `move_to` is priced from straight-line distance by `Travel.quote`, and leaves at once | Inside the cluster, unchanged. Into or around a planet, priced by the flight model at a departure tick, and both orders and cycles leave on the next window. | Medium: `MoveStep`, `CargoSystem` routes, the flight model |
| `stop` or a new order halts a moving unit in open space, with no refund | Once a transfer has departed, it is atomic, as docking is today: the task ends, but the unit coasts on to arrive. A stop during a wait cancels freely. | Small: the `is_atomic` hook exists |
| Re-entry, section 5: "halted in open space" re-enters at the `move_to` | Can't happen any more, because no unit is left floating. Re-entry otherwise works as it does now. | Removes cases |
| The standoff is a fixed point short of the target, and `at_target` is stored | `at_target` becomes "parked with": the unit's position follows the target's, plus the standoff offset, with no propellant spent holding station. Docked units already move with the station. | Small, if A agrees the position is derived |
| Cycle closure, section 5 | Unchanged. Placement (docked, or at a target) means the same thing. | None |
| Port queue, section 8 | The rule is unchanged, but it matters more, because arrivals bunch (section 3). | Tests only |
| `no_propellant` is checked per trip, as the trip starts | Add one check at the lap gate: the propellant aboard must cover every `move_to` in the lap. A drone then can't be stranded at a rock whose trip home costs more than the trip out. With Hohmann transfers a leg's cost doesn't depend on the window taken, so the check is exact. | Small |
| Mining, transfers, docking and undocking | Unchanged, since they are relative to the target. | None |
| A solar-powered drone has constant power | Around a planet it passes through the planet's shadow every orbit. A mining laser on solar power alone is shed, and the step is held with `no_power` until the drone leaves the shadow. That is today's rule working as written, but laps stretch, and batteries start to matter. | None in autonomy. B's balance, A's power model. |

Commands, events and the view gain one operation, `waiting`, with its departure tick, and the trip quote gains a departure tick. Nothing else in the contract surface changes for automation.

## 6. Lap figures, tests and saves

**Layout A or B.** The lap figures survive. In layout A, the Lead has ruled that the cluster is one co-moving frame, as A's page proposes: the cluster as a whole moves on its solar orbit, and trips inside it stay straight-line. Relative drift between the rocks never arises, so today's laps stay exact however long a game runs. In layout B the figures change once, because trips take about an orbit, and stay fixed after that.

**Layout C.** Fixed per-lap numbers go, but the tests stay exact. The window rule is deterministic, so for circular orbits in one plane every departure tick can be worked out by hand from the orbit periods. The golden test then asserts:

- each `move_to` leaves on the tick the window rule gives, and arrives on the tick the flight model quotes;
- from lap 2, each lap equals the same whole number of synodic periods, within a tick;
- matter, energy and heat balance on every tick, as they do now;
- the end inventories, which still follow from the number of laps.

[reference_scenario.md](reference_scenario.md) would then list a schedule of departures and arrivals in place of a single lap figure. It stays checkable with a calculator, as now.

**Determinism.** A has proved this holds. A body's position is a pure function of the tick, taken mod an integer period in ticks, so it can't drift. A's throwaway proof gave identical positions stepped, after a save and load, at 8x, and evaluated directly, and still identical after 1000 periods in game year 30. Autonomy itself still uses no RNG and reads no events, so it adds no new risk.

**Saves.** A transfer in progress is stored as {depart_tick, arrive_tick, parent body, transfer orbit elements}, as today's route is stored. Loading recomputes the coast position from those elements and the tick. The arrival point is fixed at departure: the target's position at `arrive_tick`, plus the standoff. Three new save tests would cover this: mid-transfer, mid-wait, and parked at a rock. The determinism replay would also add a save during a wait and one mid-transfer.

## 7. Cost, and what can wait

Keep today's straight-line flight as one flight model behind the same quote function, and add orbits as a second one chosen by the scenario. The autonomy tests then keep running on the straight-line model, and only new tests need orbits. Without this, the roughly 50 cycle tests would all need orbit set-ups.

| Work | Owner | Size | Before or after M4 |
| ---- | ----- | ---- | ------------------ |
| Flight model with the quote and window functions, on rails | A | Large | After |
| `waiting` operation, tier 2 window rule, atomic transfers, derived parking | C | Medium | After |
| Round-trip propellant check at the lap gate | C | Small | Could go in now. It helps the straight-line game too. |
| A test flight model with windows every N ticks, for fast cycle tests | C | Small | After, with the above |
| Save, replay and window-schedule tests | C | Medium | After |
| Reference scenario Part A and Part E as departure schedules | B, with C | Medium | After |
| Client: show the wait and its countdown on the order and the cycle | D | Medium | After |
| Tier 3 planning (section 4) | C | Large | After the above has been played |

**Before M4, I'd change nothing.** M4 judges the slice as it stands, and every row above moves figures that M2 and M3 rest on. With B's cluster layout, the slice wouldn't need any of these rows anyway, so they are all post-M4 cost, for a planet scenario.

## 8. Agreed with A

A (newmanprobe-db) agrees all five assumptions, with these details:

1. **Rails**, for A's options 2 and 3. A body's position is a pure function of the tick, from stored elements and an integer period in ticks. A transfer is a stored record, and its coast position comes from that record.
2. **The two queries.** `quote(unit, target, depart_tick)` gives `{ arrive_tick, cost_g }` in closed form for a Hohmann transfer between circular orbits in one plane. Time of flight is half the transfer orbit's period, fixed for each pair of orbits, and `cost_g` comes from the rocket equation in integers. `next_window` is also closed form, because the phase gap closes at a constant rate. Eccentric orbits need a bounded search. Inside the rock cluster, today's straight-line quote stays.
3. **Parking.** Co-moving: the target's position plus a fixed offset, in a frame that doesn't rotate, with no propellant spent holding station. A landed unit's position comes from its planet cell, and planets don't rotate in the proposal.
4. **Atomic after departure.** This fits the autopilot. A paid trip runs to arrival, unaffected by faults or power, and a stop while waiting for a window cancels with nothing paid.
5. **Scale.** Real drift between the rocks would be negligible over a slice run but would add up over a long game. The Lead ruled for A's co-moving frame, so the slice has none.

A also adds the pacing fact in section 1: a planet trip takes about half an orbit, and windows between close orbits are hours apart. The figures are in [A's "Orbit figures" table](orbital_flight.md#orbit-figures).

**From B**, as B's recommendation and not a decision: in the slice, the station and the three rocks stay one cluster in a shared solar orbit, with no planet near them, so the fixed laps hold. Planets come only after M4.

## 9. Questions for the owner

1. **Layout after M4.** The slice stays a cluster around the star, as B recommends. For a later planet scenario: one ring around a planet (fixed but slower laps), or different orbits (windows, waiting and a real job for tier 3)?
2. **Tier 2 waiting.** Is a drone that sits for an hour of game time waiting for a window acceptable for tier 2, given that tier 3 is the answer to it? Or should planet trips stay player-run expeditions, with automated laps kept to the cluster?
3. **Timing.** May this all wait until after the M4 judgement, as recommended?
