# Orbital Flight and Automation

Status: proposal for the owner, written by Agent C (gameplay). Nothing here is decided, and order-based flight in [workplan.md](../../plan/workplan.md) stands until the owner rules. It is the automation part of the orbital flight question. [orbital_flight.md](orbital_flight.md) (Agent A) owns the flight model, and [planets.md](planets.md) (Agent B) owns where things orbit. Figures marked *illustrative* are worked examples for a Kerbin-sized planet, not data.

## 1. The plain answer

- **Automation survives gravity flight, if trips are on rails.** A drone's fixed cycle still works when bodies orbit, provided the sim can answer one question exactly: "if this unit leaves for that target on tick T, when does it arrive and what does it cost?" A's autopilot option gives that answer. Hands-on manoeuvre nodes do not, because a cycle can't replay a player's burns.
- **Where things orbit matters more than how flight works.** If the station and rocks stay a cluster in orbit around the star, distances barely change, and the cycle, the lap figures and the tests all stay as they are. If the station orbits a planet and the rocks are elsewhere, transfer windows appear, laps vary, and most of the cost in this page applies.
- **B recommends the cluster for the slice.** [planets.md](planets.md) keeps the station and the three rocks in one shared solar orbit, and proposes planets only after M4. So for the slice, automation needs no change. The window cost in sections 3 to 7 starts with a later planet scenario.
- **Tier 2 should wait for the window.** A lap leaves on the next transfer window, then follows its steps as today. It never takes a costlier path and never plans ahead. That keeps tier 2 a fixed cycle, as [spec.md](spec.md) section 5 defines it.
- **Orbits give tier 3 its first real job.** Choosing between waiting and paying more, cutting mining short to catch a window, and spacing drones so they don't queue at a port are real decisions. Today tier 3 would have little to do beyond picking deposits.
- **The fixed lap figures survive only in the cluster layout.** Around a planet, a test asserts the schedule the window rule gives, which a person can still work out by hand, and not one number per lap.
- **Recommendation: change nothing before the M4 judgement.** If the owner wants orbits afterwards, the cheapest version that keeps automation intact is real orbits with the autopilot, with each mining route in one orbit around the planet (section 2, layout B). Tier 3 waits until after that.

## 2. Three layouts

The same rules behave very differently depending on what orbits what. B's [planets.md](planets.md) recommends layout A for the slice. B or C would come only with a later planet scenario, such as a station in low orbit hauling from a surface or from a separate ring.

| Layout | What changes for a drone | Lap figures |
| ------ | ------------------------ | ----------- |
| **A. A cluster in solar orbit**: station and rocks 30 to 50 km apart, all circling the star | Almost nothing. Over a 4-hour session the rocks drift a few hundred metres relative to the station. | Exact, if each rock shares the station's orbit size. Otherwise the drift moves a lap by about 5 to 9 ticks over 4 hours. |
| **B. One ring around a planet**: station and rocks in the same orbit, at different points along it | No windows: every departure is as good as any other. But a hop takes about one orbit, and the 3-minute trip becomes about 32 minutes. | Fixed, but longer. |
| **C. Different orbits around a planet** | Transfer windows open and close. A drone waits, sometimes for hours, or pays a lot more propellant. | Vary with orbital phase. Most of this page is about this layout. |

How the figures were worked out, *illustrative*, from the standard formulas. Real radii and periods are A's to set in [orbital_flight.md](orbital_flight.md):

| Case | Result |
| ---- | ------ |
| Layout A: rock 50 km closer to the star than the station | Drifts 54 m per hour along the orbit |
| Layout B: rock 50 km ahead in a 100 km orbit, one-orbit phasing hop | 32.3 minutes, 17 m/s |
| Layout B: the same hop over 2 orbits | 64.9 minutes, 9 m/s |
| Layout C: station at 100 km, rock at 150 km | Window every 5.5 hours, 76 m/s, 17 minutes in flight |
| Layout C: station at 100 km, rock at 300 km | Window every 1.7 hours, 264 m/s, 20 minutes in flight |

So in layout C, rocks close to the station's orbit have the rarest windows. A drone that laps in 9 minutes today could spend most of a session waiting.

**Layout A gives no Kerbal feel.** Gravity is present, but nothing visible changes, because over minutes a star's pull on a 50 km cluster is almost the same at every point. The Kerbal look and feel needs a planet, and so layout B or C.

## 3. Tier 2 cycles when things orbit

**Rule: each `move_to` leaves on the next window, and the cycle is otherwise unchanged.** A's flight model defines what a window is. For circular orbits in one plane, the cheapest transfer comes round once per synodic period, the time for the two orbits to line up again. A tier 2 drone takes that one.

| Question | Answer |
| -------- | ------ |
| Does a lap wait for a window? | Yes. The `move_to` step waits in place, then flies. |
| Does it take a costlier path to go now? | No. That is a choice, and tier 2 makes none. The player can still order "go now" as a single order, at the quoted cost. |
| Does the cycle plan its windows? | No. Each move looks only at its own next window when it becomes current. Planning across a whole lap is tier 3. |
| Where does it wait? | After undocking, parked at the standoff beside the station. Waiting docked would hold the port for hours. |

**Waiting is not a block.** The task stays `running`, with a new operation `waiting` that carries the departure tick, so the client can show "leaves in 41 min" instead of a fault. Faults during a wait follow today's rules.

**What this does to laps.** Every departure lands on a window tick, so laps settle into whole multiples of the synodic period, plus or minus a tick of rounding. The first lap is the odd one out, because it starts whenever the player sets the cycle.

**What it does to several drones.** Drones on the same route all leave on the same window and arrive together. They then queue at the port, which today's first-come rule already orders deterministically (by `since_tick`, then entity ID). The cost is throughput: the last drone docks hundreds of ticks after the first and can miss the next window home, so the convoy settles into a slower rhythm. Tier 2 accepts this, and spacing the drones out is a job for tier 3.

## 4. Tier 3 re-planning

Today tier 3 is defined as "chooses and re-plans a whole operation". Straight-line flight leaves it little to do: every trip is the same price at any time, so the only real choice is which deposit to mine.

Orbits give it real decisions:

- **Wait or pay.** Go now at a higher cost, or wait for the cheaper window, given the propellant aboard and stocked at the station.
- **Cut mining short.** Leave with 80 % of a hold to catch a window rather than wait a full synodic period with 100 %.
- **Choose the route by window.** Mine the rock whose window opens first, not always the same one.
- **Stagger drones.** Spread the drones on one route over different windows, so they don't queue at the port together.
- **Plan propellant across laps.** Top up only what the next windows need.

So yes, orbits give the tiers a real reason to differ: tier 2 repeats a plan and pays in waiting, and tier 3 earns its place by not waiting. This is my main argument that layout C makes the automation game better. It is also the biggest single cost, and it belongs after M4.

## 5. What changes in today's rules

Section numbers are those of [autonomy.md](autonomy.md).

| Rule today | Change | Size |
| ---------- | ------ | ---- |
| `move_to` is priced from straight-line distance by `Travel.quote`, and leaves at once | Priced by the flight model at a departure tick. Tier 2 waits for the next window. An order can choose "now" or "next window". | Medium: `MoveStep`, `CargoSystem` routes, the flight model |
| `stop` or a new order halts a moving unit in open space, with no refund | Once a transfer has departed, it is atomic, as docking is today: the task ends, but the unit coasts on to arrive. A stop during a wait cancels freely. | Small: the `is_atomic` hook exists |
| Re-entry, section 5: "halted in open space" re-enters at the `move_to` | Can't happen any more, because no unit is left floating. Re-entry otherwise works as it does now. | Removes cases |
| The standoff is a fixed point short of the target, and `at_target` is stored | `at_target` becomes "parked with": the unit's position follows the target's, plus the standoff offset, with no propellant spent holding station. Docked units already move with the station. | Small, if A agrees the position is derived |
| Cycle closure, section 5 | Unchanged. Placement (docked, or at a target) means the same thing. | None |
| Port queue, section 8 | The rule is unchanged, but it matters more, because arrivals bunch (section 3). | Tests only |
| `no_propellant` is checked per trip, as the trip starts | Add one check at the lap gate: the propellant aboard must cover every `move_to` in the lap at its window cost. A drone then can't be stranded at a rock whose window home costs more than the window out. Windows can be predicted, so the check is exact. | Small |
| Mining, transfers, docking and undocking | Unchanged, since they are relative to the target. | None |
| A solar-powered drone has constant power | Around a planet it passes through the planet's shadow every orbit. A mining laser on solar power alone is shed, and the step is held with `no_power` until the drone leaves the shadow. That is today's rule working as written, but laps stretch, and batteries start to matter. | None in autonomy. B's balance, A's power model. |

Commands, events and the view gain one operation, `waiting`, with its departure tick, and the trip quote gains a departure tick. Nothing else in the contract surface changes for automation.

## 6. Lap figures, tests and saves

**Layout A or B.** The lap figures survive. In layout A, each rock needs the same orbit size as the station, otherwise the slow drift moves laps by a few ticks over a session. In layout B the figures change once, because trips take about an orbit, and stay fixed after that.

**Layout C.** Fixed per-lap numbers go, but the tests stay exact. The window rule is deterministic, so for circular orbits in one plane every departure tick can be worked out by hand from the orbit periods. The golden test then asserts:

- each `move_to` leaves on the tick the window rule gives, and arrives on the tick the flight model quotes;
- from lap 2, each lap equals the same whole number of synodic periods, within a tick;
- matter, energy and heat balance on every tick, as they do now;
- the end inventories, which still follow from the number of laps.

[reference_scenario.md](reference_scenario.md) would then list a schedule of departures and arrivals in place of a single lap figure. It stays checkable with a calculator, as now.

**Determinism.** This holds if positions are a pure function of the tick and stored orbit elements, computed in integers or fixed point, with no floating-point maths in the sim. That is A's choice to make. Autonomy itself still uses no RNG and reads no events, so it adds no new risk.

**Saves.** A transfer in progress is stored as a record (departure tick, arrival tick and the transfer's parameters), as today's route is. Loading recomputes the position from the record and the tick. Three new save tests would cover this: mid-transfer, mid-wait, and parked at a rock. The determinism replay would also add a save during a wait and one mid-transfer.

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
| Client: show the wait and its countdown, and a "go now or wait" choice on the order | D | Medium | After |
| Tier 3 planning (section 4) | C | Large | After the above has been played |

**Before M4, I'd change nothing.** M4 judges the slice as it stands, and every row above moves figures that M2 and M3 rest on. With B's cluster layout, the slice wouldn't need any of these rows anyway, so they are all post-M4 cost, for a planet scenario.

## 8. Agreed with A

Not yet agreed. I've asked A to confirm five assumptions this page rests on, and this section records their answers:

1. Bodies and units in transfer move on rails, as a pure function of the tick, in integer or fixed-point maths.
2. The flight model offers `quote(unit, target, depart_tick)` and `next_window(unit, target, from_tick)`, cheaply, in closed form for circular orbits in one plane.
3. A parked, mining or docked unit's position is derived from its target's, with no propellant spent holding station.
4. A departed transfer is atomic. Before departure, a stop cancels freely.
5. In layout A the relative drift is negligible.

**From B**, as B's recommendation and not a decision: in the slice, the station and the three rocks stay one cluster in a shared solar orbit, with no planet near them, so the fixed laps hold. Planets come only after M4. For the laps to stay exact, each rock should share the station's orbit size (section 6).

## 9. Questions for the owner

1. **Layout after M4.** The slice stays a cluster around the star, as B recommends. For a later planet scenario: one ring around a planet (fixed but slower laps), or different orbits (windows, waiting and a real job for tier 3)?
2. **Tier 2 waiting.** Is a drone that sits for an hour of game time waiting for a window acceptable for tier 2, given that tier 3 is the answer to it?
3. **Timing.** May this all wait until after the M4 judgement, as recommended?
