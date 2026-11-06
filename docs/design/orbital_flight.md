# Orbital Flight

Status: option 3 approved by the owner on 2026-11-04, with one correction: flight is mixed, and the player flies their own ship, so manual burns come early, not last (rulings at the top of [workplan.md](../../plan/workplan.md)). Section 11 is the implementation plan (task A8), awaiting the Lead's approval. Sections 1 to 10 are the proposal as approved. Nothing in `sim/`, `data/`, `client/` or the contracts has changed yet. The planet half is in [planets.md](planets.md) by B, and what automation does with orbits is in [orbital_automation.md](orbital_automation.md) by C.

The owner asked: "gravity based movement like in kerbal maybe?" The workplan records order-based flight as owner-confirmed (lines 17 and 79), so this page looks at reversing that decision.

## 1. The short answer

- **It can be done without breaking determinism.** Section 3 has the proof. Orbits are worked out in whole numbers from the tick alone, so they never drift. Positions came out bit-identical after 5.6 hours of play, a save and load, and running at 8x. A position 1000 orbits later, in year 30, was exactly the same.
- **My recommendation is option 3:** real orbits with an autopilot first, and manual manoeuvre planning added later on the same maths. **Start it after the M4 judgement, not before.**
- **It changes nothing in the slice.** The slice's rocks are 30 to 50 km from the station, far from any planet. They drift apart by about 100 m over a whole run. Gravity only starts to matter once there is a planet to orbit, and planets come after the slice. Doing this before M4 would delay M4 for a change the owner couldn't see.
- **Full Kerbal-style flight (option 1) is a bad trade for this game.** The game's main claim is automation. Hand-flown burns can't be repeated by a drone, and Kerbal relies on time warp of 1000x and more, which this simulation can't reach.
- **The real costs are pacing and propellant.** In a gravity well a trip takes about half an orbit, and the right moment to leave comes round only every 41 minutes to 5.5 hours (section 5). A trip around a Kerbin-sized planet takes 17 to 44 minutes of game time, and a round trip costs 5 to 44% of a ship's mass in propellant. Today a whole drone lap costs 2.7%. Landing on a 600 km planet and returning to orbit costs well over half the ship's mass.

## 2. The three options

| | 1. Full patched conics | 2. Orbits with autopilot | 3. Option 2 now, manual nodes later |
| - | ---------------------- | ------------------------ | ----------------------------------- |
| What the player does | Plans burns on manoeuvre nodes and flies them | Picks a target and presses Move to. The autopilot waits for the window and flies the transfer. | As option 2, then adds a manual mode for players who want it |
| Integer determinism | Possible, but every burn makes a new orbit from position and speed, which needs more integer maths than I proved (section 9) | Proved: orbits on rails, planned transfers (section 3) | Option 2 first, then the same step as option 1 |
| Automation | Poor. A drone's cycle can't contain hand-flown burns, so automation would need option 2's autopilot anyway. | Good. A cycle step is still "move to target". It waits for a window instead of leaving at once (section 4). | Good. Manual nodes are for the player's own ships. |
| Pacing | Needs huge time warp | Trips of 17 to 44 minutes, and waits of up to a few hours of game time. 8x is enough (section 5). | Same as option 2 |
| Work | Largest. It needs a full flight-planning screen before anything flies. | Medium (section 8) | Option 2's work, then manual mode as a later step |

**Option 3, because** option 2 is the part that automation needs, and it is the foundation option 1 would need anyway. Manual planning later is a client screen plus one integer function, turning a burn into a new orbit, on top of the same rails.

## 3. Determinism

### How orbit positions are computed

- **On rails.** A body, station or coasting unit stores its orbit, not its position, and its position is a pure function of the tick. Nothing is added up from tick to tick, so there is nothing to drift. Running at 8x runs the same ticks, so it gives the same answers.
- **The stored orbit:**
  - semi-major axis and semi-minor axis, in mm
  - eccentricity, in Q30, where 2^30 means 1.0
  - two orientation vectors, in Q30
  - the starting angle
  - the period in whole ticks
  - the parent body
  - the epoch tick

  All are integers, and all are rounded once when the orbit is made. A save holds these and nothing derived from them.
- **Angles are binary angles, 2^32 to a turn.** The mean anomaly is `m0 + mul_div((tick - epoch) mod period, 2^32, period)`. Taking the tick mod the period is what makes it exact forever: the orbit repeats bit for bit every period.
- **Trigonometry is a table of 16,385 integer sines over a full turn, with linear interpolation.** It is built when the game loads, by integer CORDIC, a shift-and-add method with no floats. It takes 30 ms and is never saved. The worst error is 2.6e-8, which is 26 mm at 1000 km.
- **Kepler's equation is solved by exactly 5 Newton steps in integers,** starting from `M + e sin M`. A fixed step count, rather than "until it converges", keeps the result the same everywhere. Five steps are enough up to eccentricity 0.3. Higher eccentricities would need more steps, still a fixed count.
- **Every product goes through `IntMath.mul_div`,** which already has a 128-bit-safe path. A signed version is a one-line wrapper.
- **The rocket equation uses an integer `e^-x`**, by halving 10 times, a 6-term series, then squaring back. It takes 7 µs, with a relative error of 1.3e-6 up to twice the exhaust speed.
- **Speeds** come from vis-viva through `IntMath.isqrt`, with gravity (GM) stored in m³/s² so it fits 64 bits.

### Precision and range

| Quantity | Size | Fits because |
| -------- | ---- | ------------ |
| Orbit radius around a planet | up to about 10^12 mm, a million km | Times a Q30 sine is about 2^70, so it goes through `mul_div` |
| Position error from the sine table | 26 mm at 1000 km, about 26 km at 1 AU | Fine around planets. A planet's orbit around the star needs a 2^20-entry table, or positions stored relative to the parent, which patched conics does anyway. |
| Position error against float Kepler | 144 mm worst, over 1000 random orbits | Most of it is the sine table |
| Period | stored in whole ticks | Rounding the period moves the orbit's speed by less than 1 part in 6000. It's applied once, so it is consistent rather than drifting. |

Positions stay relative to their parent body, as in Kerbal's patched conics. The workplan's limit of about 0.42 light-years on positions isn't touched.

### Proof

Throwaway script, not committed: `C:\Users\simon\AppData\Local\Temp\claude\bb5dc2b14e56ba72\03cd21d6-0812-4544-b7db-26cc9307336c\scratchpad\orbit_proof.gd`, run headless in Godot 4.7.2 from the kernel worktree.

| Test | Result |
| ---- | ------ |
| 50 eccentric orbits over 200,000 ticks (5.6 h), four ways: every tick, saved and loaded halfway, 8 ticks per frame, and jumping straight to the end | All four give the same SHA-256 of `Canon` positions. **PASS** |
| 1000 orbits at year 30, compared with 1000 periods later | Every position identical. **PASS** |
| Save round trip | `Canon.encode(decode(x)) == x` for the stored orbits |
| Cost per position | 15.9 µs eccentric, 4.9 µs circular |
| Hohmann transfer, 700 to 760 km, compressed gravity | 149 + 146 m/s, 5.3 min, matching the float formulas |
| Rocket equation, 680 kg drone, 295 m/s | 63,711 g against 63,709.9 g in floats |

## 4. Automation

C's [orbital_automation.md](orbital_automation.md) covers this in full. What we agreed:

- **Moving targets.** Rocks and stations are on rails, so where a target will be at any future tick is known exactly. A trip is planned at departure to meet the target at its arrival-tick position, plus stand-off.
- **Two queries for cycles.** `quote(unit, target, depart_tick)` gives `{arrive_tick, cost_g}`, and `next_window(unit, target, from_tick, cap)` gives the earliest departure costing at most `cap`. For circular orbits in one plane, both are closed form. The phase gap closes at a constant rate, so the next window is one division away and repeats every synodic period. Eccentric orbits need a bounded search.
- **Hohmann transfers only, at first.** A Hohmann transfer is the cheapest transfer between two circular orbits, and every window costs the same, so a cap means only "yes" or "no". Faster, dearer transfers away from the window are a later step.
- **A tier 2 cycle** keeps its steps. "Move to" now means "wait for the next window, then fly". The wait is part of the step, and stop cancels it freely, since nothing has been paid yet. **Tier 3** re-plans with the same two queries.
- **Once departed, a trip is atomic.** It runs to arrival, as a paid trip does today. "Halted in open space" goes away, because it means nothing on a real orbit.
- **`at_target` and stand-off stay.** A unit parked at, mining on or docked to a target moves with it: its position is the target's plus a fixed offset, with no propellant spent to stay there. `at(unit, target)` is still never derived from geometry.
- **Inside the rock cluster, today's straight-line trips stay exact,** because gravity is negligible across 50 km (section 5). There are no windows there.

## 5. Scale and pacing

### A trip takes about half an orbit

In any gravity well, a cheap transfer takes half the transfer orbit's period. The next chance to leave comes round once per synodic period, which is long when two orbits are close. That is the physics, so a planet can't host 6-minute laps without changing it.

### Orbit figures

This is the one table of trip and window figures. [orbital_automation.md](orbital_automation.md) links here and doesn't repeat them.

All rows use a 600 km planet at Kerbin gravity (9.81 m/s² at the surface, GM 3.5316e12 m³/s²), with circular orbits in one plane and Hohmann transfers. Each case gives its orbits as radius from the planet's centre, with altitude in brackets. The station is always in a 700 km orbit (100 km altitude), which takes 32.6 minutes and moves at 2.2 km/s.

| Case | Rock's orbit | Time in flight | Delta-v each way | Propellant, round trip | Window comes round every | At 8x: flight, window spacing |
| ---- | ------------ | -------------- | ---------------- | ---------------------- | ------------------------ | ----------------------------- |
| Different orbits | 750 km (150 km) | 17.2 min | 76 m/s | 5% | 5.5 h | 2.2 min, 41 min |
| Different orbits | 760 km (160 km) | 17.4 min | 90 m/s | 6% | 4.7 h | 2.2 min, 35 min |
| Different orbits | 900 km (300 km) | 19.9 min | 264 m/s | 16% | 1.7 h | 2.5 min, 13 min |
| Different orbits | 1000 km (400 km) | 21.8 min | 364 m/s | 22% | 79 min | 2.7 min, 10 min |
| Different orbits | 2000 km (1400 km) | 43.7 min | 860 m/s | 44% | 41 min | 5.5 min, 5 min |
| Same ring, rock 50 km ahead, one-orbit phasing hop | 700 km (100 km) | 32.3 min | 17 m/s for the hop | 1% | Any time | 4.0 min, none |
| Same ring, the same hop over two orbits | 700 km (100 km) | 64.9 min | 9 m/s for the hop | Under 1% | Any time | 8.1 min, none |

- **Propellant** is the share of the ship's mass at 3000 m/s exhaust speed, there and back.
- **A wait** can be anything from zero to the full window spacing, depending on when the order is given.
- **The closer two orbits are, the rarer their windows:** 5.5 hours apart at 50 km of difference, 41 minutes at 1300 km.
- **The same-ring rows have no windows,** but a hop takes about one orbit however close the rock is.

**Compressed gravity, for comparison.** At GM 3.76e13, ten times Kerbin's, a 700 km orbit takes 10 minutes but moves at 7.3 km/s. The 700 to 760 km transfer takes 5.3 minutes and 295 m/s each way, with a window every 86 minutes.

The 600 km radius with Kerbin's 9.81 m/s² is already Kerbal's own compression: about ten times Earth's density, so a small world still has real gravity.

**Proposal:**
- **A Kerbin-like planet:** 600 km radius, GM 3.53e12 m³/s², and no rotation, as agreed with B.
- **Don't compress gravity further.** A 10-minute orbit needs 7.3 km/s of orbital speed, so landing and leaving would cost nearly all of a chemical ship's mass.
- **Orbits for stations and moons from 700 km to about 2000 km.**
- **Decided by the Lead: the rock cluster is one co-moving frame.** Inside it there is no gravity between members and no drift, and today's straight-line trips are exact. This keeps [reference_scenario.md](reference_scenario.md) and checks 1 to 10 unchanged by construction, and places no limit on where rocks sit. The alternative, giving every rock the station's period, was not chosen.
- **Planet trips are expeditions, not laps:** 17 to 44 minutes of game time, or 2 to 6 minutes at 8x. Windows come round every 41 minutes to 5.5 hours, and the autopilot waits on its own. Content should avoid orbits close to the station's, whose windows are hours apart, or put such rocks in the same ring.

### Time warp

8x works. The open question is whether more than 8x is wanted, and this simulation limits that.

- **Every tick runs every system.** At the performance test's load, about 20 times the slice, a step takes 8.9 ms, so the most the simulation can manage is about 11x in real time.
- **At slice size a step is far cheaper,** so 50x or more should be possible there. I haven't measured that.
- **Kerbal-style warp of 1000x and more** would need a coast mode that jumps many ticks at once, while nothing but rails and steady rates are running. It's possible in principle, because rails are a function of the tick, but every per-tick system would need a closed form. That is a large job and isn't proposed here.

## 6. Performance

- **Positions cost 5 to 16 µs each** (section 3).
- **The simulation only needs a position at departure, arrival and when a quote is made.** It never needs one every tick, because coasting is on rails and parked units ride with their target.
- **The client needs positions every frame,** so the view should send each object's orbit and the client draws it in floats. That is visual only, like the client's interpolation today. If the simulation sent positions instead, it would cost about 2.6 ms per tick at 20 times the slice, with about 160 objects on rails, all eccentric. That's 16% of the 16 ms budget, so worth avoiding.
- **Window searches** are a division for circular orbits. For eccentric ones, the search should be bounded and cached per (unit, target) until either orbit changes.
- **Planets:** a cell is computed on demand in about 20 µs. Generating all 100,002 cells takes about 4.4 s in GDScript, which only the client needs (section 7).

## 7. Burns, propellant and the ledgers

- **Burns are impulses, paid in full at departure.** Departure reserves and pays both burns, departure and arrival, into `propellant_exhaust`, as today. A trip under way still can't run out of propellant, and the matter ledger keeps its form.
- **The rocket equation replaces today's lump price.** Today's price is `ticks x propellant rate x mass / rated mass`. The new one is `mass x (1 - e^(-dv / exhaust speed))`. The thruster needs an exhaust speed in `data/`, which is a schema change. `speed_m_s` and `rated_mass_kg` stop deciding the price.
- **Propellant goes up sharply.** At 3000 m/s exhaust speed, a round trip of 2 x 90 m/s costs 6% of the ship's mass, 2 x 364 m/s costs 22%, and 2 x 860 m/s costs 44%. A drone lap today costs 2.7%. Section 1 of [balance.md](balance.md) found propellant isn't a problem today. With orbits it becomes the main limit, so B's balance work restarts.
- **Landing and takeoff are autopilot operations with a fixed integer delta-v cost.** They are not simulated descents. From a 600 km Kerbin-like planet with no air, reaching low orbit takes about 2.3 to 2.6 km/s, which is 54 to 58% of the ship's mass at this exhaust speed. A return from the surface needs fuel made or carried there. B's [planets.md](planets.md) builds on this.
- **Power and heat.** In the first step, burns are instant and the thruster isn't a load, as today. Long burns, with power and heat while the engine runs, only matter for low-thrust engines such as ion drives, which come after the slice. Then a burn becomes a timed operation that draws power like mining.
- **The energy and heat ledgers** don't change for impulses.

## 8. Planets: the integer side

The design is in B's [planets.md](planets.md). B and I agreed the boundary: the simulation reads only integers made from (planet seed, cell ID), stores only changes such as deposits mined and things built, and a save holds the seed plus those changes. The client's float noise never reaches the simulation, and the client takes each hex's centre height from the same integer function.

Measured at n = 100, in GDScript:

| Item | Result |
| ---- | ------ |
| Cells | 100,002: 12 pentagons, 99,990 hexagons, 300,000 edges, 200,000 faces. Euler's formula gives 2. No one-way neighbour links. |
| Cell IDs | North pole 0, south pole 1, then `2 + d n² + (i-1) n + j` over 10 diamonds of the icosahedron. A point on a diamond's edge maps to its one owner in O(1). Built from exact integer corners, and every shared point agreed. |
| Spacing | 5.4 to 7.9 km between neighbouring centres at 600 km |
| Time | IDs 0.15 s, neighbour table 0.55 s, unit directions 1.7 s, heights 2.0 s |
| Memory | Neighbour table 2.4 MB, directions 2.4 MB, heights 0.4 MB. None of it is saved. |
| Noise | 3-octave integer value noise on the cell's direction, with integer smoothstep. Each octave is a mix of values in 0..65535, so it can't leave that range. Heights came out -6963 to 6380 m, with a largest step of 2342 m between neighbours. A second run gave identical heights. |
| On demand | About 20 µs per cell, which is all the simulation needs |

No product in the hash or the noise passes 2^62, so nothing relies on integer wrap-around.

## 9. Cost

### What changes

| Area | Change |
| ---- | ------ |
| contracts.md | Travel and `move_to`: a window wait inside the step, an atomic coast, no halt in flight. Probably a new reason code for "no window under the cap". The view gains each object's orbit. |
| networks.md section 6 | Rewritten: rails, transfer records, rocket-equation price, co-moving parking. Stand-off and `at_target` keep their rules. |
| schemas.md, spec.md | Bodies and units store an orbit instead of a fixed `pos_mm` outside the cluster. Thrusters gain an exhaust speed. Planets gain a seed and settings (B). |
| autonomy.md | Windows in cycles, and atomic trips (C) |
| accounting.md | No change in form. Propellant still leaves through `propellant_exhaust` at departure. |
| reference_scenario.md | **No change** if the cluster is one co-moving frame, as section 5 proposes. Otherwise every trip figure in section 2. |
| Acceptance checks 1 to 10 | No change within the slice. New checks would be about planets and transfers, after M4. |
| perf_budget.md | Add rails and window searches to the load, and position cost to its rules |
| Client | A map with orbit lines, the next window and the trip's arrival on the Move order, time warp above 8x if wanted, and a planet renderer (B's page) |

### Work per agent, after M4

Rough, in tasks of about the size of this project's earlier ones:

| Agent | Work |
| ----- | ---- |
| A | Integer orbit maths with tests, the rails position and save fields, the transfer planner and rocket equation, the new Travel. Then planet cells, noise and gravity body. About 4 to 5 tasks. |
| B | Data for bodies, orbits, thrusters and planets, spec rewrites, a new propellant balance. About 3 to 4 tasks. |
| C | Windows in cycles and tier 3 re-planning, the reference bot, the orbital tests. About 3 tasks. |
| D | Orbit map, window and arrival readout, planet rendering, possibly warp. About 4 tasks, the largest share. |

Manual manoeuvre nodes (option 3's second step) add about 1 task for A and 2 for D.

### M3 and M4

- **Started now,** it would put roughly 14 to 16 tasks in front of M4, for a slice whose laps don't change. M4 would slip by about the length of M3 again.
- **After M4,** it fits workplan section 9's direction: planets, a second site and expansion.

Nothing needs to happen before M4. The proof script can stay as a reference for the first task.

## 10. What I didn't test

- **Turning a burn into a new orbit** (position and speed to an orbit). It's needed for manual nodes and for any non-Hohmann transfer. It needs an integer arctangent and arccosine, and CORDIC gives both, but I haven't built it.
- **Lambert transfers,** meaning a chosen flight time and windows with a cost cap, and transfers between eccentric or inclined orbits.
- **Moving between spheres of influence,** from the cluster to a planet and from a planet to its moons.
- **Orbits around the star at 1 AU** with the 16,385-entry table: about 26 km of error, not measured.
- **A real `Sim`.** All the proof ran outside the simulation. The cost of the new Travel and the view inside the 20-times-slice load is estimated in section 6, not measured, and so is the maximum time warp at slice size.
- **The client:** drawing 100,002 cells, orbit lines, and float noise matching integer heights at hex centres.
- **Landing and takeoff costs** are worked out from the formulas, not flown.
- **Godot in other builds and machines.** Everything is integer, so it should match, but I only ran it on the owner's PC with the editor binary.

## 11. Implementation plan (A8)

This section is for the Lead and the other agents. It turns option 3 into ordered kernel tasks, with the owner's correction applied: **the player flies their own ship with manual burns, and an AI core flies the ships it controls with the same burns, planned for it.** No sim code exists yet.

### 11.1 The shape of it

- **One way to change an orbit: a burn.** The player places a burn on their ship. A core's autopilot plans the same burns and places them for its ship. The simulation then runs every burn the same way, in phase 5, whoever placed it. Mixed flight therefore needs no second flight model, and a core-flown trip is just a list of burns that a player could have made by hand.
- **Three ways to be somewhere.** Every body and unit is in exactly one of these at any tick:
  - **On an orbit:** stored orbit elements around a parent body, with its position derived from the tick (section 3).
  - **In a frame:** a co-moving frame such as the rock cluster, with a local `pos_mm` and today's straight-line travel inside it.
  - **Landed:** on a planet cell, with its position derived from the cell (B's [planets.md](planets.md) section 8).
  - **Docked** units keep today's rule and follow their host, whichever of the three the host is in.
- **Positions are always derived and never added up**, so saves, the state hash and 8x stay exact (section 3's proof).

### 11.2 The co-moving cluster frame

- **A frame is a body.** It has an ID from the entity counter, an orbit on rails like any body, and no mass. Its members are the rocks and the units inside it.
- **Inside the frame, nothing changes.** Members store a local `pos_mm` relative to the frame's origin. `move_to`, stand-off, `at_target`, routes, prices and halts work exactly as [networks.md](networks.md) section 6 says today. Every figure in [reference_scenario.md](reference_scenario.md) section 2 holds, because those figures are already local.
- **The world position** of a member is the frame's rails position plus its local `pos_mm`. Only the view and frame changes need it.
- **Burns inside the frame (changed by A9).** A burn on a unit in the frame gives it a local velocity in mm/s, and it drifts in a straight line in the frame's coordinates, since the frame has no gravity inside it. This is how the player flies their ship by hand among the rocks. Stopping takes an opposite burn. `move_to` routes inside the frame are unchanged.
- **Leaving the frame.** A drifting unit leaves when it passes the frame's radius. Its orbit is then worked out from the frame's position and velocity at that tick, plus its local offset and velocity, and its local position is cleared. Leaving needs no special command.
  - A9 found why the conversion has to wait for the radius. The cluster orbits the star at 1 AU, where integer positions are good to about 300 m (11.7). Converting at the first burn would make a ship jump by up to that much in front of rocks 150 m away. At the radius, the same error is invisible.
- **Joining the frame.** A unit on an orbit joins when it is within the frame's radius and its speed relative to the frame is under a small threshold, checked in phase 5. Its local `pos_mm` and local velocity are then fixed from its world position and velocity, and its orbit is cleared. The autopilot's arrival burn at a frame target is planned to meet both conditions.
  - The radius and threshold are kernel constants for the Lead to approve. I propose the cluster's own radius plus 1000 km, and 1 m/s.
  - A player who arrives too fast drifts past. That is a real piloting mistake, and the view shows it.
- **Where the frame orbits,** the star or a planet, is scenario data, and B10 decides it. The frame needs nothing extra either way.

### 11.3 Kernel tasks, in order

Sizes compare with earlier kernel tasks: **S** is about A7's size, **M** about A4 (power), and **L** about A6 (travel and docking).

| # | Task | What it delivers | Depends on | Size |
| - | ---- | ---------------- | ---------- | ---- |
| A9 | **Orbit maths library** | `OrbitMath`, pure static functions with no state:<br>- sine table from integer CORDIC, plus an integer `atan2` (`angle_of`) and rounded square roots<br>- elliptic Kepler solve<br>- elements to position and velocity, and back again (the burn-to-new-orbit function)<br>- integer rocket equation<br>- signed `mul_div`, rounded to nearest<br>A float reference for the client, round trips of elements to position and velocity and back with stated error bounds, and range tests at the limits of section 3. **Done on kernel/A9; results in 11.8.** | Contracts for units (11.4) | M |
| A10 | **Rails, frames and landing places in state** | Bodies, frames and units carry `orbit`, `frame` or `cell`, and `pos_mm` is derived for orbits and cells. The scenario loader, `to_save`/`from_save`, strict-check range rules, and `view()` with orbit elements per object. Today's in-frame travel is moved under the frame unchanged. | A9 and the save contract | L |
| A11 | **Burns, for the player's ship first** | Burns on a ship, run in phase 5, delivering a set delta-v in a direction fixed at the start, as one impulse per tick until done or out of propellant. Per tick: propellant to `propellant_exhaust` by the rocket equation, a new orbit by A9, and the thruster as a power and heat load while burning. Leaving a frame and joining one (11.2). `check` returns the predicted orbit after a planned burn, so the client can draw it before the player commits. | A10 | L |
| A12 | **Spheres of influence** | Hyperbolic orbits, with an integer `sinh`/`cosh` built from the A9 rocket-equation exponential. Exact detection of the tick an orbit leaves or enters a sphere of influence, by bounded integer bisection on the rails function, so the result never depends on step size. Re-parenting on that tick. Needed for any trip between the cluster's parent and a planet. | A11 | L |
| A13 | **Core autopilot: the transfer planner** | `quote(unit, target, depart_tick)` and `next_window(unit, target, from_tick, cap)` as [orbital_automation.md](orbital_automation.md) uses them. Hohmann and same-ring phasing transfers in closed form, the `waiting` operation, and atomic transfers. `move_to` across frames, planets and orbits places the planned burns through A11's path and reserves their propellant at departure. Inside a frame, `move_to` is unchanged. | A11, A12 | L |
| A14 | **Planet grid and terrain** | `PlanetGrid`: cell IDs, neighbours, integer cell directions and the integer noise from section 8, plus `cell(seed, id)` on demand. Pure functions, with the proof's checks as tests: 12 pentagons, Euler, symmetry and replay. | A9's trig only | M |
| A15 | **Landing and takeoff** | Autopilot operations between an orbit and a cell, with an integer delta-v cost from the body's figures, as in B's planets.md section 3.2. The landed state, and leaving it. The player's ship uses the same operations, because a hand-flown descent isn't proposed. | A10, A11, A14 | M |
| A16 | **Planet shadow** | A solar generator gives nothing while its unit is in a planet's shadow. This is an integer cylinder test from the star direction, in phase 3. C found that this is what stretches laps around a planet. | A10 | S |
| A18 | **Trips across spheres of influence** | Added after A13 by the Lead. The cluster orbits the star, so no core can fly to a planet until the planner handles a trip that changes parent body. That needs patched-conic transfers: from one orbit to an escape or capture hyperbola, with the sphere-crossing tick found by bounded integer search on the rails, and a window from both bodies' positions. Planned after A15. | A12, A13 | L |
| A19 | **Hand-flown landing for the player's own ship** | Added after A15 by the Lead, under the owner's ruling that the player flies their own ship. Atomic `land` stays as the autopilot for cores. A hand-flown descent uses A11's finite burns; it doesn't replace them. The kernel needs: contact with the ground at the height of the cell below, not the datum radius; a touchdown rule, landed below a speed limit and crashed above it; that limit from a landing-gear capability (B's data); and lift-off by burns from the landed place. D builds the descent screen on `predict` and the cell heights. Not built yet. | A15 | M |
| A17 | **Performance and limits** | Re-measure [perf_budget.md](perf_budget.md) with rails, burns and window searches at 20 times the slice, measure the top speed of time warp at slice size, and update the budget's rules. | A13 | S |

**Order and why:**
- **A9 to A11 come first,** because the player has to fly their own ship before anything else.
- **A14 has no state and only needs A9's trig,** so it can run beside A10 and A11, which puts D's planet renderer on real data early.
- **A12 and A13 are the core-flown half.** C's cycle work waits for A13's queries, not for the whole chain (11.6).
- **Total:** about 4 L, 3 M and 2 S. The proposal's estimate of 4 to 5 tasks was too low, because manual burns and spheres of influence are now in it.

**Not in the plan,** each for the Lead to schedule later if wanted:
- Lambert transfers: a chosen flight time, so a core can pay more to leave between windows.
- Inclined and eccentric targets for the planner. The first planner assumes near-circular orbits in one plane, and refuses anything else with a reason.
- A coast-skip mode for time warp above the tick rate's limit.
- Planet rotation.

### 11.4 Contract changes for the Lead to approve

**contracts.md**

| Section | Change |
| ------- | ------ |
| 1, Units and ranges | New rows, as changed by A9:<br>- Angle in binary angle units, **2^48** per turn, stored masked to 0..2^48-1. At 2^32 one unit is 220 km at 1 AU.<br>- Ratio in Q30, where 2^30 is 1.0, for eccentricity and direction vectors<br>- Speed and delta-v in **µm/s** inside orbits, within ±10^12, so repeated conversions don't add up rounding. Commands and the view may still use mm/s.<br>- Gravitational parameter in **1000 m³/s²**, 0 to 9 x 10^18. The star's 1.327e20 m³/s² doesn't fit in m³/s². Data gives `gm_km3_s2`.<br>- An orbit's period in 1/65536 ticks.<br>Position keeps its range. |
| 1, Coordinates | Orbits use the simulation axes, so a planet's north pole and the reference plane's normal are **+Y**, not +Z as I told B. B's page needs that one-word fix. A local `pos_mm` is relative to its frame. |
| 3, Public API | `check` of a burn returns the orbit after it. `predict(unit, from_tick, ticks, step)` returns derived positions for drawing a path, read-only, like `view()`. `quote` gains `depart_tick`. `next_window` is new. |
| 4, Tick order | Phase 5 runs burns, then frame and sphere-of-influence changes, in ascending unit ID. Phase 3 applies planet shadow to solar supply. |
| 5, Commands | `plan_burn` places a burn: `{unit, tick, prograde_mm_s, normal_mm_s, radial_mm_s}`. The tick must be in the future, and "burn now" is the next tick. `cancel_burn {unit, burn}` removes one. `move_to` keeps its form. Outside a frame it waits for a window, then flies an atomic transfer. `land {unit, body, cell}` and `take_off {unit}` are new. |
| 6, Events | `burn_started`, `burn_done` (with delta-v delivered and propellant spent), `burn_short` (out of propellant), `frame_joined`, `frame_left`, `soi_changed`, `landed` and `took_off`. |
| 6, Reason codes | `burn_in_past`, `not_flying` (landed or docked), `no_window` (nothing under the cap), `unsupported_orbit` (the planner's limits), `too_fast_to_join` (only in a `check` that previews a frame join) and `not_over_cell`. |
| 7, State view | Per body, frame and unit: one of `orbit`, `frame` with `local_mm`, or `cell`. Planned burns per unit. Operations gain `burning` and `waiting`, each with their ticks. |
| 8, Canonical serialization | The new fields above. Derived positions are not saved. **A save version bump:** older saves fail to load with `data_mismatch`, as already accepted for the parts-drone change. |

**Other pages:**
- **networks.md section 6** is rewritten by me in A10 to A13. Inside a frame it stays word for word. Outside a frame it gains burns, transfers, frames and landing.
- **schemas.md:**
  - The thruster capability gains `exhaust_m_s` and `thrust_kn`. A burn's per-tick delta-v is thrust over mass, so it needs thrust. `speed_m_s`, `propellant_kg_per_s` and `rated_mass_kg` stay, because in-frame `move_to` trips still read them (corrected after B asked).
  - Bodies gain `gm_km3_s2` (held as `gm` in 1000 m³/s²) and an orbit, and planets also gain a seed. The sphere of influence is derived at load (11.11), so there is no `soi_m`.
  - Scenarios gain frames.
  - All of these are B's data. I need them before A10's loader and A11's burns.
- **accounting.md:**
  - Propellant still leaves only through `propellant_exhaust`.
  - A player's burn pays per tick while it runs, and an autopilot transfer reserves at departure and pays per tick as its burns run.
  - A trip under way can't run short, because the reservation covers it. A player's burn can, which fires `burn_short`.
- **autonomy.md** (C): the `waiting` operation, atomic transfers, and the lap-gate propellant check C proposed.

### 11.5 Save format and state hash

- **New saved fields:**
  - per body, its orbit, or its frame and local position;
  - per frame, its orbit;
  - per unit, `orbit`, `frame` with `pos_mm`, or `cell`;
  - per unit, planned burns, and the running burn with its delivered delta-v and remainder;
  - the transfer record of [orbital_automation.md](orbital_automation.md).

  All are integers, encoded by today's `Canon`, so the hash rule doesn't change.
- **Not saved:** the sine table, derived positions, planet cells and the neighbour table. They are rebuilt on load, as the proof did.
- **Data hash:** body figures and thruster figures are read by the simulation, so they join the data hash. A planet's visual settings stay out, like `visual` today.
- **Tests:** in every task from A10, a save and load midway through a burn, a transfer, a frame join and a sphere-of-influence change must give a byte-identical save and the same hash as an unbroken run. 8x adds nothing to test, because it runs the same ticks.

### 11.6 What C and D need from me, and when

| Who | Needs | When |
| --- | ----- | ---- |
| C | The signatures of `quote` and `next_window`, and the `waiting` operation's fields | With the contract approval, before A10. C can write against a stub from then on. |
| C | The working planner | A13. C's cycle and tier 3 work on planets starts then. Cycles inside the cluster need nothing new, because the frame keeps them as they are. |
| C | A test helper that puts a unit on a given orbit or in a frame | A10 |
| D | The view shape: orbit elements, frame and cell, planned burns, `burning` and `waiting` | With the contract approval, before A10, so the map can start on a stub |
| D | A float reference for drawing an orbit from its elements, with test vectors the client must match within 1 m | A9 |
| D | `check` of a planned burn and `predict` for path lines, which the manual flight screen is built on | A11. **This is the critical handover.** Manual flight is D's largest new screen, and the player can't fly without it. |
| D | `PlanetGrid` and the integer height function, called from the client for hex centres | A14, early, beside A10 |
| D | Sphere-of-influence and landing events for the map and camera | A12 and A15 |
| B | The schema fields in 11.4, before A10. The +Y north fix in planets.md. Body figures for B10's start. | Before A10 |

### 11.7 Risks

- **Elements to position and velocity and back** is bounded (11.8). The periapsis is measured in the orbit's own plane from the current position, so circular and equatorial orbits need no special case. Per-tick finite burns stay, and the fallback isn't needed.
- **A burn runs one conversion per tick,** 65 µs measured. That is cheap for a few ships, but A17 must check many cores burning at once.
- **Positions at 1 AU are good to about 300 m,** from the Q30 sines. This is why 11.2 converts at the frame's radius, not at the first burn. Planet-scale orbits are good to millimetres.
- **Time warp.** The player flying a 20 to 40 minute transfer by hand will want more than 8x. The slice's real size should allow far more than the 11x limit at 20 times the slice, but that's unmeasured until A17.

### 11.8 A9 results: the orbit maths library

`sim/kernel/orbit_math.gd` and `tests/sim/kernel/test_orbit_math.gd`. Measured in Godot 4.7.2, headless.

| Measure | Result |
| ------- | ------ |
| Sine and cosine | Within 2.2 units of 2^-30, from a 4096-entry table built by integer CORDIC plus the angle-addition rule |
| `angle_of` (integer atan2) | Within 6.5 units of 2^-48 of a turn, for inputs from 1 to 2^61 |
| Positions against the float reference | Within 9 parts per billion of the orbit's size, from a 250 km moon orbit to 1 AU. That is 3 mm at 700 km and about 400 m at 1 AU. |
| **Round trip, position and velocity to an orbit and back**, worst gap over the next whole period | 0.2 m for a low moon orbit, 0.2 m at 700 km, 7 m at 40,000 km (e up to 0.3). At e = 0.9 it reaches 630 m at 40,000 km. At 1 AU it is 38 km over a year. |
| 600 conversions in a row (a one-minute burn with no thrust) | 22 m over the next period at 700 km |
| Prograde burn from 700 km | Apoapsis at 760 km within 1 m of the Hohmann formula |
| No drift | An orbit is exactly where it started after a whole number of periods, and an orbit record saves byte-exact through `Canon` |
| Rocket equation | Within 0.9 parts per million |
| Cost | Position 14 µs, position and velocity 26 µs, position and velocity to an orbit 65 µs |

**The error bound,** asserted per case: 2 m plus 3e-7 of the orbit's size, times ((1 + e) / (1 - e))^1.5. It comes from Q30 sines and ratios. Vis-viva magnifies a speed error in an orbit's size, more so at high eccentricity, and a size error becomes a gap along the path a period later.

**Choices A9 made that change 11.4,** already edited above:
- Angles use 2^48 to a turn, not 2^32.
- Speeds inside orbits are in µm/s.
- GM is in 1000 m³/s².
- Everything rounds to nearest. Rounding down biased every converted orbit slightly small.

**For D, the float reference** is `position_float` in the test file: Kepler's equation in floats, from the stored orbit record. A client drawing an orbit this way matches the simulation within 9 parts per billion, well inside 1 m at planet scale. Use 64-bit floats, not Godot's Vector3, which is 32-bit and only good to about 1 part in 10^7.

**Not done in A9:**
- Hyperbolic orbits, in A12.
- Positions at 1 AU better than about 300 m. That would need Q40 trigonometry and roughly twice the cost. It isn't needed while frames convert at their radius.

### 11.9 A10 results: rails, frames and places in state

- **State:**
  - Bodies gain `frame`, `orbit` and `gm`.
  - Units gain `frame` and `orbit`.
  - A new `frames` table holds each frame's orbit, `radius_mm` and derived `pos_mm`.
  - A docked unit's place is its host's, worked out by `RailSystem.unit_place` rather than stored, so a newly built unit needs no extra step.
- **Frames are their own table, not bodies of a new kind.** They take IDs from the same counter, after the bodies and their deposits. Kept apart, a frame never appears where code or the client lists targetable bodies.
- **`RailSystem` is registered first.** In phase 2 it sets `pos_mm` on every orbiting body and frame from the tick. Those positions are saved, which contracts.md section 8 now allows as the one exception to the no-derived-caches rule, because they are a pure function of the stored orbit and the tick.
- **Travel inside a frame is unchanged,** and the reference scenario has no frames, so all its figures hold. A `move_to` to a target on an orbit or in another frame is refused with `unsupported_orbit` until A13.
- **The view** gains `frames`, plus `frame`, `orbit` and `world_mm` per body and unit, and `gm` per body.
- **Scenario data**, in sim units after loading:
  - Bodies may have `gm_km3_s2`, `orbit` and `frame`.
  - Frames are `{ key, name, radius_mm, orbit }`.
  - Units may have `frame`.
  - An orbit is `{ parent, a_mm, e_ppm, inclination_mdeg, node_mdeg, periapsis_mdeg, mean_anomaly_mdeg }`, all whole numbers, so no float is involved. Only `parent` and `a_mm` are required.
  - A body on an orbit needs no `pos_mm`.
- **The loader:**
  - `gm_km3_s2` becomes `gm` in 1000 m³/s².
  - `thrust_kn` becomes `thrust_n`.
  - Whole numbers now convert by integer multiplication, so the star's GM stays exact beyond 2^53.
- **The contract is version 3.** An older save is refused with `version_mismatch`, because the version is now checked before the shape. contracts.md also lists what A11 to A15 will add, so C and D can work against it.
- **Tests:** tests/sim/kernel/test_rails.gd, 13 tests. They cover:
  - positions on rails;
  - world positions through the chain;
  - a docked unit's frame;
  - a trip inside a frame identical to the reference figures;
  - refusal of trips across places;
  - a byte-exact save and load midway through a trip, running on identically;
  - strict ranges;
  - the view;
  - bad scenarios;
  - old saves;
  - the loader's exact GM.

### 11.10 A11 results: burns for the player's ship

- **`BurnSystem`** (sim/networks/burn_system.gd) is registered after `RailSystem` and `UnitSystem`, and before `PowerSystem`. contracts.md sections 3, 5, 6 and 7 hold the commands, events, `check` detail, `predict` and view fields as built. D has had the shape since the start of A11.
- **The thruster:** a burn uses the healthy thruster with the most `thrust_n`, which must also have `exhaust_mm_s`.
- **Each tick's delta-v** is thrust over the unit's mass at the start of the tick, with a carried remainder.
- **Propellant** flows at thrust / exhaust speed, also with a remainder. It is claimed against reservations and leaves in phase 6 through `propellant_exhaust`, so the matter ledger holds.
- **Drift:** in a frame, a burn changes `vel_um_s`, and the unit drifts in a straight line, with a carry in tenths of a micrometre so the drift is exact. A `move_to` in a frame stops the drift.
- **Frame margins,** a change from 11.2: a drifting unit leaves at the frame's radius + **2000 km**, and joins at radius + 1000 km under 1 m/s. The gap stops a slow unit at the edge flapping in and out. A26 shrinks both inside a small sphere of influence, and a unit drifting over 2 m/s leaves at once (11.20).
- **Measured:**
  - The first Hohmann burn from 700 km (45.7 m/s), flown as a finite burn of 844 ticks, gives an apoapsis of 759.3 km, against 760 km for an instant impulse.
  - The delta-v delivered matches the request within the rounding of its direction.
  - Leaving the cluster frame at 1 AU puts the unit 304 m from where the frame plus its drift would have, which is the integer precision at 1 AU that A9 predicted.
  - A save and load midway through two burns, one on an orbit and one in a frame, is byte-exact and runs on identically.
- **Tests:** tests/sim/networks/test_burns.gd, 13 tests. They patch B13's thruster figures (3 kN, 3000 m/s) into the cached data until B13 is on main.

### 11.11 A12 results: hyperbolic orbits and spheres of influence

- **Hyperbolic orbits** are a second kind of record in `OrbitMath`, as contracts.md section 1 describes.
  - `from_state` now returns one for anything past escape speed. Only an exactly parabolic state is refused, which rounding makes vanishingly rare.
  - Kepler's equation for a hyperbola, e sinh H − H = M, is solved by Newton's method in integers.
  - The hyperbolic anomaly is clamped at 20, by which point a unit is millions of radii out.
- **New integer functions:**
  - `exp_q30`: an exact table of e^0 to e^20, plus a series for the fraction.
  - `ln`: by powers of 2, then 2 atanh.
  - `sinh_cosh`.
  - `soi_mm`: Laplace's a (m / M)^(2/5), checked against Kerbin's public sphere of influence of about 84,159 km to within 1e-5.
- **Spheres of influence:**
  - The scenario builder gives each orbiting body with gravity a `soi_mm`.
  - In phase 5, `BurnSystem` moves a unit's orbit up to its parent's parent when it passes its parent's sphere, or down into a child body's.
  - It is checked every tick, so the change comes on the first tick past the boundary at any speed, with no search.
- **The A11 follow-up D found:** `BurnSystem` now runs after `TaskSystem`, so a burn planned for the tick after an undock starts on time instead of being dropped as `part_busy`.
- **Measured:**
  - Hyperbolic positions are within 100 parts per billion of the distance, against a float reference.
  - The state-to-orbit round trip on a hyperbola is within 40 mm over 1000 s.
  - A unit leaving a planet at 5 km/s crosses the 279,240 km sphere with a world-position step of one tick's motion and no jump. One falling in changes parent the same way.
  - A save and load on a hyperbola is byte-exact.
- **For D:** `position_float` in tests/sim/kernel/test_orbit_math.gd now draws hyperbolic records too. The view gives each body its `soi_mm`, for drawing spheres on the map.
- **Not done:**
  - Crashing into a body. A unit whose path goes through a planet passes through it until landing exists in A15.
  - Predicting a sphere change ahead of time. `predict` still follows the current orbit only. A13's planner will need the crossing tick, found by bounded integer search on the rails function.

### 11.12 A13 results: the autopilot planner

- **`Transfer`** (sim/networks/transfer.gd) plans trips between orbits around the same parent body.
  - A unit's orbit is its own, its frame's or its host's.
  - A target's orbit is its frame's or its own. A body with gravity is a place to orbit or land on, so it isn't a rendezvous target, and landing is A15.
  - Both orbits must be near-circular (e ≤ 0.01) and in one plane (within 1°). Anything else is `unsupported_orbit`.
- **Hohmann transfers** between different radii.
  - The window is closed form. The target must lead by half a turn less its motion during the flight, and the phase gap closes at a constant rate, so the wait is one long division on the two periods.
  - The flight is half the transfer orbit's period. Both burns are priced by the rocket equation and paid at departure.
- **Phasing** within one ring (radii within 1/15, where windows would be ten or more orbits apart).
  - It leaves at once on an orbit whose period brings it back to its start just as the target arrives there.
  - That takes one or more turns, changing the period by at most a tenth per turn.
- **The `move_to` step** (MoveStep, CargoSystem) works as contracts.md sections 3 and 7 describe.
  - It waits with op `waiting` until the window. Nothing is paid, and `stop` cancels freely.
  - At the stored window it pays and rides the transfer orbit on rails. The transfer is atomic.
  - On arrival it parks at the stand-off beside a target in a frame, joining the frame, or takes a target unit's orbit.
  - A wait whose task is held over its window takes the next window instead of leaving late.
  - A player's order that finds no propellant at its window ends with `no_propellant`, as a route does. A cycle's step is held, and `MoveStep.retry` quotes the next window once the propellant is there.
  - Inside one frame, a `move_to` is still today's route, so every slice figure holds.
- **Queries for C:** `Travel.quote_trip`, `Travel.next_window` and `Travel.quote_leg`. The last prices a lap leg from another place at any mass, for the lap gate. `Sim.quote` and `Sim.next_window` are the read-only versions.
- **A change from the plan:** the autopilot's burns are paid as impulses at departure, and the flight rides the transfer orbit on rails. It doesn't place finite burns through A11. That makes the arrival tick exact, and it matches the trip record agreed with C. A finite burn of a few minutes against a flight of 20 minutes or more changes little. The thruster isn't a power or heat load during an autopilot trip, as with today's routes.
- **Measured:**
  - Hohmann from 700 km to 900 km: 11,962 ticks, matching half the transfer period to two ticks. It lands within a kilometre of the target frame before parking.
  - The window is within two ticks of relative motion of exact.
  - Phasing 20° ahead in one ring: 0.94 of an orbit at 88 m/s.
  - Save and load while waiting and in flight is byte-exact, and the run goes on to the same arrival.
- **Not done:**
  - Lambert transfers, which leave between windows at a higher cost.
  - Eccentric or inclined targets.
  - Trips that change sphere of influence.
  - A transfer that passes through the planet isn't checked, which is A15.

### 11.13 A15 results: landing, takeoff and collisions

- **`LandingSystem`** (sim/networks/landing_system.gd) adds `land { body, cell }` and `take_off { altitude_mm }` as atomic autopilot operations, `landing` and `taking_off`, with an integer delta-v cost and no simulated descent. That is planets.md section 3.2's model.
- **The cost**, paid at the start:
  - the burn down half an ellipse from the current radius to the surface;
  - plus killing the speed left at the surface, with a 3% gravity loss;
  - priced by the rocket equation.
  - The op lasts the half ellipse. Takeoff is the reverse, onto a circular orbit through the cell's direction, moving east around +Y.
- **Landed** is a fourth place, beside an orbit, a frame and the old world.
  - The unit's `landed { body, cell }` sets its `pos_mm` to the cell's centre at its integer height, from the body's `planet { seed, height_range_m }` through `PlanetGrid`.
  - A landed unit never moves, can't burn, and can't `move_to`.
- **Collisions:** every tick, a unit on an orbit below its parent's radius crashes.
  - It comes down on the cell below. That is the nearest cell centre, found by walking downhill from the nearest icosahedron corner.
  - Its burn or transfer ends, and `crashed` fires. Damage isn't modelled.
  - This also catches transfers that pass through a planet, which A13 left open.
- **Measured:** landing from a 700 km orbit on the 600 km planet costs 2681 m/s, about 9.8 t of propellant for the starter ship, over 8760 ticks. That is just above section 7's 2.3 to 2.6 km/s, because a ship on the descent ellipse meets the surface at 2.5 km/s, not at circular speed.
- **What the starter ship can land on and return from.** This assumes 4.58 t dry and 2 t of propellant at 3000 m/s exhaust speed, which is about 1090 m/s in all. Each case lands from, and returns to, an orbit at a tenth of the radius up, by this model:
  - At Kerbin's density, a body up to about **120 km** radius. Surface gravity there is about 2 m/s², and the trip costs about 1045 m/s.
  - A Minmus-sized moon, 60 km at Minmus's density (half Kerbin's), uses about 370 m/s, leaving about 1.2 t of propellant. At Kerbin's density it is 523 m/s (11.19).
  - A Mun-sized moon, 200 km, needs about 1230 m/s, so it's short by about 210 kg.
  - The 600 km planet needs about 5.2 km/s for the round trip, beyond any single ship without refuelling.
  - None of these include the trip from the cluster to the moon. B has these figures for the new start.
  - B10's probe is heavier, at 6.78 t dry, so it has about 775 m/s. At a fixed density the round trip scales with the radius, so it can land on and return from a body of about **90 km** at Kerbin's density, and still from a Minmus-sized one.
- **Not done:**
  - Surface types and slope limits on landing, which need planets.md's rule tables in `data/`.
  - Damage on a crash.
  - Planet rotation.
  - Planetary deposits and scanning a patch of cells, which are B's and C's.

### 11.14 A16 results: planet shadow

- **`RailSystem.in_shadow(state, unit)`** is an integer cylinder test.
  - The unit is in shadow if a body with gravity on an orbit is between it and the body of kind `star`.
  - That means the unit is behind the body as seen from the star, and closer to the star-to-body line than the body's radius.
  - It uses world positions, so it works for units on orbits, in frames, landed and docked.
- **In phase 3 `PowerSystem` gives a shadowed unit no supply,** because every generator in the data is solar. A later non-solar generator, such as a reactor, needs a field saying so.
  - Batteries then carry the loads, and anything left is shed by the existing rules, which is what C described for laps around a planet.
  - The power view's `supply_w` follows, and `in_shadow` shows why.
- **Tests** (in test_landing.gd):
  - behind the planet, in front, behind but beside the shadow;
  - landed on the day and night sides;
  - supply 0 in shadow after a tick.

### 11.15 A17 results: performance and limits

perf_budget.md section 5a has the figures.
- **Orbital load at 20 times the slice:** 14.9 ms mean and 30.8 ms at the 99th percentile for step and view, inside the 16 and 33 ms budget.
- **Before two fixes it was 26 ms:** the frame-join check now tests positions before velocities, and planet-shadow casters are worked out once per tick.
- **Burn previews:** a burn's flown preview costs about 0.2 ms per burn tick in `check`, so the client calls it on an edit, not every frame. Phase 1 no longer runs it, which removed 185 ms spikes when a burn was applied.
- **Time warp:** at the slice's real size a tick costs 0.23 ms, so one core can run about 440x. At 20 times the slice it is about 7x.

### 11.16 A18 results: trips across spheres of influence

- **`SoiTransfer`** (sim/networks/soi_transfer.gd) plans `move_to` trips one level across spheres, as patched conics. That covers out from an orbit around a body to a ring around its child, and back. A trip two levels apart is refused with `unsupported_orbit`.
  - The ship's and target's orbits must be near-circular, as for A13. A planet's own orbit may be eccentric up to 0.1.
  - All the orbits must be in one plane with the planet's.
- **Out:**
  - A Hohmann ellipse around the parent, timed by A13's window to meet the planet.
  - The tick it enters the planet's sphere, found by a coarse walk back from the expected arrival, then integer bisection.
  - From there, a hyperbola around the planet that keeps the speed at the sphere's edge but is shaped to reach the target's ring at periapsis. The small change of direction stands for a correction burn.
  - A capture burn at periapsis onto that ring, then A13's phasing to the target.
- **Back:**
  - An escape hyperbola from the parking orbit. Its asymptote lies along the planet's motion, or against it for an inward trip, on the Hohmann window. It is burned when the ship passes the periapsis direction nearest that window, and the exit time from the sphere is closed form.
  - At the sphere's edge, a small correction sets the coast's far side at exactly the target's radius.
  - There it circles and phases round to the target, because the wait for the parking orbit puts the exit up to half a parking orbit off the window.
- **How it runs:** the trip is a list of legs, each an orbit and the tick it starts, kept in `transfer.legs` and ridden on rails by `RailSystem`. While waiting, the op keeps the whole plan, so the departure flies exactly the quoted legs, including after a save. All burns are paid at departure, by the rocket equation on their sum.
- **Measured** on a compact test system: a central body of 1e17 m³/s², a home frame at 20,000 km, and a moon of 1e13 m³/s² at 30,000 km with a sphere of about 750 km.
  - Out to a 300 km ring around the moon: 27,098 ticks and 10.1 km/s. The largest step between ticks is 7 km, with no jump at the leg changes, and the arrival parks 78 km from where the path ends.
  - Back: 31,510 ticks and 14.7 km/s, with the same smoothness, parking 31 km away.
  - A save mid-flight is byte-exact and runs on identically. Quotes are deterministic.
  - The speeds here are high because the test system is compact. At the game's scale the same shapes cost what section 5's table gives.
- **Costs to know:**
  - Phasing at the far end is expensive on a fast ring: it adds up to a fifth of the orbital speed. Lambert transfers would remove most of it, and they are still not planned.
  - The arrival parks the ship within about a hundred kilometres of where its path ends. That is a visible but small jump at star scale.
- **Not done:**
  - Trips two levels apart, such as a moon of another planet. A22 added these (11.18).
  - Inclined targets.
  - Lambert transfers.

### 11.17 A19 results: hand-flown landing

- **Low flight** (sim/networks/low_flight.gd) is a fifth place, near a planet's surface.
  - Orbit records can't hold the near-vertical paths a landing uses, so below 20 km above the datum a unit flies as a position and velocity relative to the body. Gravity, GM / r², is applied each tick in integers, with the frame's tenth-of-a-micrometre carry.
  - Above 30 km it converts back to an orbit, with the gap to stop flapping.
  - A unit on an orbit that dips below 20 km switches in automatically.
- **Ground and touchdown:**
  - The ground is the cell below at its real height, from the planet's settings through PlanetGrid.
  - Touching it at or under the unit's touchdown limit lands. Over it crashes. Both leave the unit landed on the cell, with `speed_um_s` in the event.
  - The limit comes from B15's `landing_gear.max_touchdown_m_s` capability: the best healthy part's, and 0 without gear.
  - The autopilot's atomic `land` now needs gear too (`no_landing_gear`), per the Lead.
- **Burns:**
  - They work landed, which is a lift-off into low flight, and in low flight.
  - The basis there is level prograde, normal, and radial straight up, so the axes stay steady on a vertical descent.
  - A lift-off whose thrust is under the ship's weight settles back and lands again at near-zero speed.
- **`predict` in low flight** runs the same integration and reports where and how fast the path meets the ground. The test checks that the predicted contact tick, cell and speed equal what the flight then does.
- **The ground test is cheap where it can be** (D's finding).
  - Nothing is looked up above the body's own highest possible ground (its `height_range_m`, plus 1 km).
  - Below that, each tick's search for the cell starts from the last tick's cell, and each cell's ground height is kept once found.
  - Predict keeps these for one path. A flying unit keeps them in the context, which is derived and never saved, so a loaded game simply starts its next search cold (A24).
  - A hinted search ends at the same cell as a cold one, so the drawn path still meets the ground where the flight does.
  - A 670-tick hop skimming the ground used to take about 2 s to predict and now takes about 0.1 s.
- **Tests:** in test_landing.gd: gentle and hard touchdowns, contact at the real height, prediction against the flight, entering and leaving low flight from a dipping orbit, lift-off with and without enough thrust, gear for the autopilot, and a byte-exact save in low flight. They give the starter hull landing gear in the cached data until B15's legs are on main.
- **Not done:** crash damage, slope limits (B reserved `max_slope_mdeg` for later), and planet rotation.

### 11.18 A22 results: trips two levels apart

- **What it covers:** a `move_to` from an orbit around a star to a ring around a moon of one of its planets, and back. That is the trip the new start's first landing needs: from the cluster, which circles the star, to a moon. Trips three levels apart, and trips across to another planet's moon, are still refused with `unsupported_orbit`.
- **How:** it chains A18's crossing twice through a parking circle around the middle body.
  - The circle is halfway between the middle body's surface and the inner edge of the moon's sphere, and at least 60 km above the surface.
  - Going out, it lies in the planet's own orbit plane, which the first crossing arrives in. Coming back, it lies in the moon's orbit plane, which the first crossing leaves.
  - The first crossing stops on the circle without phasing, since nothing waits there. The second starts from that circle at the tick the first arrives, waits for its own window, and ends with the usual phasing to the target.
  - The legs are A18's, six in all: Hohmann, hyperbola and circle, then the next three. `transfer.legs` and `op.plan` hold them as before.
- **Arriving below escape speed:** the second crossing outward reaches the moon slower than the moon's escape speed at the sphere's edge. So the approach to the moon is an ellipse, not a hyperbola. The approach shaping now handles both, and the time to periapsis is worked out for either.
- **Price:** every burn is in the delta-v and paid at departure by the rocket equation. That means two Hohmann burns, two captures, the escape from the parking circle, and the phasing at the end. The wait on the parking circle for the second window is free in propellant but counts in the trip's ticks.
- **Measured** on a compact test system:
  - The system: a star of 4e17 m³/s² with the home frame at 20,000 km, and a planet of 4e13 m³/s² at 30,000 km with a sphere of about 750 km. The moon is 4e11 m³/s² at 400 km from the planet, with a sphere of about 63 km. The target ring is 30 km round the moon.
  - Out: 10,199 ticks and 32.0 km/s, with 26.1 km/s to the planet's circle and 5.9 km/s from it to the moon ring. It parks 12 km from where the path ends, against about 10.6 km of motion a tick, so within 1.1 ticks.
  - Back: 22,248 ticks and 35.3 km/s, parking 33 km away against 14.2 km a tick, so within 2.3 ticks.
  - The tests hold both under A21's tolerance of 5 ticks of motion.
  - There are no jumps at leg changes.
  - The speeds are high because the system is compact. The test ship carries 1,000 t of propellant, because a 4.6 t dry ship at this exhaust speed needs a mass ratio of about 128,000 for 35 km/s. At the game's scale the same shape costs what section 5's table gives, plus the parking circle's capture and escape.
- **Not done:** inclined targets, Lambert transfers, and a direct trip that skips the parking circle. Skipping it would save the capture and escape burns around the planet (the second crossing's Hohmann start), but it would need a three-body window.

### 11.19 A23 results: can the probe reach a first planet's moon?

*Superseded for the new start by 11.20. The landings here used the flat 3% gravity loss that A27 replaced, so they are cheaper than the game now charges.*

All figures are measured by two scripts, which fly nothing and change nothing:
- `tools/reach_run.gd` quotes real-planner trips (A13, A18, A22). It works out landings with LandingSystem's own sums and samples shadow with A16's test.
- `tools/moon_power_run.gd` runs B's ReferenceBot over today's reference game, with the cluster moved round a moon.

The world:
- The probe is B10's at 6.88 t dry, which includes B15's 100 kg legs. It carries 2 t of propellant at 3000 m/s exhaust, so it has **766 m/s** on a full tank.
- The first planet is the agreed 600 km planet at Kerbin's density.
- Its moon is 60 km at the same density (GM 3.53e9 m³/s²), 12,000 km from the planet, with a sphere of 757 km.

**A correction to 11.13's moon figure.** Landing on a 60 km moon at Kerbin's density from a ring 66 km from its centre, and going back up, costs **523 m/s**. 11.13's 370 m/s is for a moon at half that density, Minmus's real one. Section 1.1 of start_and_build.md uses the 370.

#### The cluster round the star at 1 AU: out of reach

| Planet at | Out | Back | Round trip with landing | Probe propellant | In flight out | Windows every |
| --------- | --- | ---- | ----------------------- | ---------------- | ------------- | ------------- |
| 0.70 AU | 5,636 m/s | 5,515 m/s | 11,674 m/s | 330 t | 144 days | 1.4 years |
| 0.90 AU | 1,692 m/s | 1,718 m/s | 3,933 m/s | 18.6 t | 170 days | 5.8 years |
| 1.05 AU | 1,026 m/s | 1,094 m/s | 2,643 m/s | 9.7 t | 190 days | 14.2 years |
| 1.20 AU | 2,532 m/s | 2,534 m/s | 5,589 m/s | 37.4 t | 212 days | 4.2 years |
| 1.52 AU | 5,349 m/s | 5,329 m/s | 11,201 m/s | 281 t | 259 days | 2.1 years |

- **Even the cheapest case is beyond the tank one way.** Just matching the planet's orbit round the star costs 718 m/s each way at 1.05 AU, before any capture.
- **Closer planets are cheaper but their windows are rarer.** That is the synodic period, which no planner can shorten.
- **Time rules it out on its own.** A trip is 5 to 9 months of game time, which is 18 to 32 days of play at 8x. A trip home also waits at the planet for the next window round the star: 15 years at 1.05 AU. To play it, the game would need a coast warp of about 10,000x (section 5), which isn't planned.
- **What would make 1.05 AU work on propellant:** a tank of about 9.7 t, before counting the tank's own mass, or an exhaust of about 10,300 m/s on today's tank. Neither helps the time.

#### The cluster round the planet: just out of reach

| Cluster at | Its orbit | Behind the planet | Out | Back | Round trip with landing | Probe propellant | In flight out, back | Windows every |
| ---------- | --------- | ----------------- | --- | ---- | ----------------------- | ---------------- | ------------------- | ------------- |
| 3,000 km | 4.8 h | 6.4% | 474 m/s | 494 m/s | 1,491 m/s | 4.4 t | 11 h, 15 h | 11 to 17 h |
| 8,000 km | 21 h | 2.4% | 196 m/s | 235 m/s | 954 m/s | 2.6 t | 14 h, 37 h | 46 h |
| 20,000 km | 83 h | 1.0% | 190 m/s | 233 m/s | 946 m/s | 2.55 t | 31 h, 115 h | 72 to 144 h |
| 30,000 km | 153 h | 0.6% | 226 m/s | 260 m/s | 1,009 m/s | 2.75 t | 46 h, 200 h | 50 to 207 h |

- **The best case misses by about 25%.** A 2.6 t tank, or a moon at half the density, would close it.
- **The trips are long:** 14 to 37 hours of game time, or 2 to 5 hours of play at 8x.

#### The cluster round the moon: in reach, just

The probe lands straight from the cluster's orbit and comes back up to it. On the way back it may be up to half a turn from the cluster. The rejoin is A13's phasing from there, which is cheap but slow.

| Cluster at | Its orbit | Down, and up again | Rejoin, worst case | Round trip | Of the 2 t tank | Spare | At half the density | Shadow | Longest eclipse |
| ---------- | --------- | ------------------ | ------------------ | ---------- | --------------- | ----- | ------------------- | ------ | --------------- |
| 300 km | 4.8 h | 368 m/s each, 67 min each | 8 m/s, 22 h | 745 m/s | 1.94 t | 21 m/s | 521 m/s + rejoin | 7.6% | 48 min |
| 400 km | 7.4 h | 376 m/s each, 97 min each | 7 m/s, 33 h | 758 m/s | 1.98 t | 8 m/s | 531 m/s + rejoin | 6.2% | 53 min |
| 600 km | 13.7 h | 381 m/s each, 167 min each | 6 m/s, 61 h | 768 m/s | 2.01 t | -2 m/s | 539 m/s + rejoin | 4.6% | 43 min |

- **At Kerbin's density the trip takes the whole tank.**
  - Going lower is cheaper, because the landing pays the full surface speed from any height.
  - A moon at half the density leaves about 230 m/s spare.
  - A 2.3 t tank leaves about 100 m/s spare.
  - A smaller moon also helps, since the cost scales with radius times the square root of density.
- **The rejoin is slow:** up to 61 hours at worst. A take-off timed for when the cluster passes overhead would rejoin within one cluster orbit at no cost. That is a planner change, not yet made.
- **Shadow** is sampled every 3 s over ten orbits of the moon, with every orbit in one plane, which is the worst case.
  - Behind the moon: 6.4%, 4.8% and 3.2% of the time at 300, 400 and 600 km.
  - Behind the planet: about 1.5%.
  - The longest single eclipse, 43 to 53 minutes, comes when the planet's shadow runs straight into the moon's.

**Power, from today's parts:**
- **Mean solar** falls by the shadow share: 4.6% to 7.6%.
- **The probe** has two battery banks, 720 MJ in all, discharging up to 300 kW.
  - It covers the longest eclipse with mining (150 kW) and the core: 80 minutes at that load.
  - It cannot cover mining with the compact refinery (250 kW). That lasts 48 minutes, just short of the 53-minute worst case.
  - It recharges in about 1.9 hours at its 120 kW charge rate.
- **The station** has one battery bank: 360 MJ, discharging up to **150 kW**.
  - The 200 kW refinery cannot run at all in shadow, however full the battery is, because of the discharge limit.
  - The fabricator (100 kW), with the hub and core, runs through any eclipse: about 56 minutes at its 107 kW.
- **The drone** has a 30 kW panel and no battery, so in shadow its core goes offline and it stops dead.

**The reference chain round the moon:** today's chain (ReferenceBot) is run with the station, ship and rocks in a cluster frame round the moon. It is tried at four starting phases of the cluster, with the moon either just short of the planet's shadow or far from it.
- **Laps don't change** (5,356, 5,340 and 5,340 ticks) whenever the drone isn't caught in shadow. Trips inside the frame are the same straight lines as today.
- **The handover slips** by 0 to 37 minutes against today's 140 minutes at the bot's pace. The worst cases are where the planet's eclipse meets the moon's.
  - At 300 km: 0 to 37 min, with the moon far from the planet's shadow up to 19 min.
  - At 400 km: 0 to 23 min, and 0 with the moon far away.
  - At 600 km: 0 to 30 min.
  - All of it is the refinery paused for power. The pause counts match the slip exactly.
- **The drone stalls in shadow:** two of 24 runs fail through it.
  - At 300 km, set_cycle is refused with core_offline when the order lands in an eclipse.
  - At 600 km, a lap runs past the bot's limit.
- **A fix in data, which is B's:** a second station battery bank, or a 300 kW discharge, lets the refinery run through eclipses. A small battery on the drone keeps its core alive. With both, the chain should be as today, but that has not been measured.
- **A gap this run found, reported to C:** a craft built at a station in a frame starts outside the frame (ConstructionSystem gives it frame 0), so the drone could not run its cycle. The script moves it into the frame and says so. C has the fix ready.

#### Recommendation

The cluster round the moon is the only placement where the probe's first landing fits one tank. Do it at 300 to 400 km, and use any one of these to make room:
- a moon a little lighter or smaller than Kerbin's density at 60 km;
- a 2.3 t tank;
- accept that the landing uses all of today's tank.

Then add station battery capacity and a drone battery in data, so the chain is as quick as today's.

Planets round the star are a later goal. They need propellant made on the surface, and a coast warp before they are playable at all.

### 11.20 A26 results: frames in a small sphere of influence, and the new start's figures

#### Frame margins

A frame has no gravity. A unit drifting in one moves in a straight line until it passes the leave margin, then becomes an orbit. Round the star the 2000 km margin is tiny against the orbit. Round Frost, whose sphere of influence is 573 km, it reached four times past the sphere.

The rule now:
- **Leave margin:** 2000 km, or half the room left in the parent's sphere, whichever is less. The room is the sphere less the frame's apoapsis and radius. The margin is never under 2 km.
- **Join margin:** always half the leave margin, so a slow unit at the edge still can't flap in and out.
- **No sphere:** a frame round the star keeps 2000 km and 1000 km.
- **Refused at load:** a frame whose apoapsis, radius and twice the 2 km floor reach past its parent's sphere. ScenarioBuilder refuses it, so the floor never puts the leave point outside the sphere.
- **new_start's cluster:** 300 km from Frost's centre and 60 km in radius. It leaves 106 km past its edge and joins 53 km past it. The floor is not used.

**Leaving at speed.** Capping the margin was not enough near Frost.
- In D's D25 run, a 20 m/s retrograde burn from the cluster would still drift about 2.3 hours to the capped leave point, in a straight line with no gravity.
- A 31 m/s burn, as for a landing, drifted 90 minutes (22% of a cluster orbit). It then left on an orbit with its periapsis 25 km from Frost's centre, under the surface. The same burn made on an orbit gives 65 km.
- The cluster is 120 km across, 40% of its orbit's radius, so no margin fixes that.

The rule now:
- A unit drifting in a frame faster than **2 m/s** (`LEAVE_SPEED_UM_S`, twice the join speed) leaves it on that tick, even mid-burn, onto the orbit the frame's motion plus its own velocity give.
- The rest of the burn is flown on that orbit, in the direction the burn started with.
- Only a nudge under 2 m/s still drifts in a straight line, and leaves by the margin.
- The hysteresis is unchanged: a unit joins under 1 m/s and leaves over 2 m/s.
- `tests/slow/test_new_start_landing.gd` flies D's case on new_start. It moves to a rock, burns 20 m/s retrograde, leaves on the burn's first ticks onto an orbit round Frost, and lands with the land command.

#### The probe on new_start

Measured on the sim from new_start.json:
- **Mass:** the probe is **5,480 kg dry** with 2,000 kg of propellant, so **933 m/s** on a full tank. That is not the 7.38 t in the A26 brief. At 7.38 t dry the tank gives 719 m/s.
- **Thruster:** 10 kN at 3000 m/s exhaust, so 1.34 to 1.8 m/s² as the tank empties. Frost's surface gravity is 0.49 m/s².
- **Legs:** four, with a 6 m/s touchdown limit.

`tools/frost_run.gd` flies the landing as a player would. Every second it places a short burn: level thrust against the level speed, plus enough vertical thrust to follow a descent rate it can still stop. It starts on the cluster's orbit, half a turn from the cluster, which is what leaving at speed now gives.

| | Flown | Impulsive | Quoted by the command |
| --- | --- | --- | --- |
| Deorbit and land, careful (20% of thrust held for stopping vertically) | 333 m/s, landed at 1.4 m/s | 242 m/s | `land`: 261 m/s |
| The same, bolder (40%) | 323 m/s, landed at 1.5 m/s | 242 m/s | |
| Bolder still (60%) | 311 m/s, **crashed** at 8.7 m/s | 242 m/s | |
| Take off and circle at the cluster's height | 302 m/s | about 242 m/s | `take_off`: 261 m/s |
| Rejoin the cluster from that circle | 3 m/s, 62 h | | |

- **A flown landing loses 33 to 38%,** not the 3% the land and take_off commands allowed. The burns are long against the descent: about 2.5 minutes at full thrust to stop 211 m/s, while gravity pulls.
- **The round trip flown is about 630 to 640 m/s,** leaving about **295 m/s spare** on that 5.48 t probe. At B11b's 7.43 t, 2.5 t tank and 15 kN, rerun the figures with `tools/frost_run.gd`.

**B11b's probe** (7.43 t dry, 2.5 t of propellant, 15 kN, so 870 m/s on a full tank), from `tools/frost_run.gd` with A27's command costs:

| | Flown, careful | Commands |
| --- | --- | --- |
| Land from the cluster's orbit | 295 m/s, landed at 1.5 m/s | 302 m/s |
| Take off to the cluster's height | 295 m/s | 280 m/s |
| Rejoin the cluster | 3 m/s, 7.6 h | 3 m/s |
| **Round trip** | **593 m/s, 277 m/s spare** | **585 m/s, 285 m/s spare** |

Leaving the cluster with the landing's 32 m/s burn now gives the orbit gravity gives: a periapsis of 62.5 km, both ways. A bolder pilot crashed at 11.2 m/s.

#### Gravity loss by thrust over weight (A27)

The land and take_off commands now charge what a good pilot loses, not a flat 3%. `tools/frost_run.gd -- --sweep` flies B11b's probe down from the cluster and back up at thrusts from 6 to 45 kN. That is n, thrust over weight at Frost's datum, from 1.2 to 9. For each thrust it keeps the cheapest safe flight: a landing touching down at no more than 3 m/s, half the legs' limit, and a take-off reaching the cluster's height. The factor is what that flight cost, less the impulsive burn at the top, over the command's surface speed.

| n | Landing, flown | 1 + 0.66/n | Take-off, flown | 1 + 0.32/n + 0.26/n² |
| --- | --- | --- | --- | --- |
| 1.23 | 1.49 | 1.54 | 1.41 | 1.43 |
| 1.64 | 1.39 | 1.40 | 1.21 | 1.29 |
| 2.05 | 1.30 | 1.32 | 1.15 | 1.22 |
| 2.46 | 1.24 | 1.27 | 1.12 | 1.17 |
| 3.08 | 1.21 | 1.21 | 1.13 | 1.13 |

- **The rule:** the surface speed is paid times 1 + A/n + B/n², with n worked out when the command is checked, from the unit's mass then and its best thruster.
  - land: A = 0.66, B = 0.
  - take_off: A = 0.32, B = 0.26.
  - About 30% for a landing at n = 2.2.
  - The command is never cheaper than the best safe flight from n = 1.2 to 3. The autopilot flies well, and a hand pilot may do worse.
- **Above n = 3** the sweep's one-second burns are too coarse to trust: its landings cost 1.21 to 1.35 there. The formula keeps falling towards no loss, as physics allows with a hard enough burn.
- **`thrust_too_low`:** at n of 1 or less, land and take_off are refused, since the craft can't hold itself up.
- **Transfers are unchanged.** A burn in space loses only by the arc it sweeps. `tools/frost_run.gd -- --transfer` measures it through BurnSystem's own finite-burn preview, prograde from the cluster's orbit at B11b's 1.51 m/s², as the instant burn's extra energy over the finite one's:
  - 10 to 30 m/s: nothing measurable;
  - 100 m/s over 65 s: 0.002 m/s, 0.002%;
  - 300 m/s over 189 s: 0.046 m/s, 0.015%.
  This is the tightest orbit in the game. Round the planet or the star the arc is smaller still.

#### The belt

The planner's trip, using A22's two-level route, from the cluster round Frost to a belt field at 2.7 AU, and back:

| | Delta-v | In flight |
| --- | --- | --- |
| Out | 10,650 m/s | 475 days to the belt's orbit, then about 1,620 days catching up with the field |
| Back | 10,828 m/s | 461 days, leaving on day 232 |
| Both ways | 21,478 m/s | |

- **Mass ratio:** 1,286 at 3000 m/s exhaust and 2.05 at 30,000 m/s. One way is a mass ratio of 35 at 3000 m/s, which matches belt.md's 39 from the planet's orbit, less the Oberth gain from leaving Frost and the planet low.
- **The out trip's time is mostly the catch-up.** A22's two-level route doesn't time the departure to where the field will be (it phases at the planet's level only). It arrives on the field's orbit at the wrong place and rides a slightly larger orbit round to it.
  - With many fields, a trip can go to whichever is near on arrival, about 475 days.
  - Timing the departure to the field is a planner change, not made.

### 11.21 A30 design: timing a belt trip to its field

A design note, so no code yet. It is for the Lead to approve before A31 builds it.

#### What happens today

A trip from the cluster round Frost to a belt field is A22's two-level route in reverse, through `SoiTransfer._two_levels`:
- It climbs from Frost to a parking circle round the planet, escapes the planet at the first chance, and flies a Hohmann ellipse to the field's distance from the star.
- Nothing times the departure to where the field will be. The last leg, `Transfer._phasing`, then catches the field up along its own orbit. It does that on an orbit only slightly larger than the field's, because a faster catch-up costs a lot of delta-v.
- At 2.7 AU, from today's start, that is 475 days to the field's orbit, then about **1,620 days** catching up (11.20).

A faster catch-up at the belt is out:
- Gaining a phase φ in one orbit of 4.4 years needs a period change of φ/2π, and that costs about v·(φ/2π)/3 in two burns, where v is 18.1 km/s at 2.7 AU.
- Half a turn is therefore about **3 km/s**. Spread over N orbits it is 3/N km/s, but each orbit takes 4.4 years.

So the phase has to be right on departure.

#### The windows

A Hohmann trip from the planet's orbit to a field arrives on time only if it leaves when the field leads the planet by the right angle. That angle is π(1 − ((1 + r)/2r)^1.5), for a field at r AU. Such windows come once every synodic period of the planet and the field.

| Field at | Field's year | Window every | Wait, average and worst | In flight | To the field, average and worst | Today, untimed |
| --- | --- | --- | --- | --- | --- | --- |
| 2.2 AU | 1,192 d | 527 d | 263 d, 527 d | 370 d | 633 d, 896 d | |
| 2.7 AU | 1,621 d | 472 d | 236 d, 472 d | 460 d | 696 d, 931 d | 2,096 d (A26) |
| 3.2 AU | 2,091 d | 443 d | 221 d, 443 d | 556 d | 777 d, 998 d | |

- **Getting to the escape point** adds hardly anything. The climb from Frost to the parking circle takes under a day, and the parking circle comes round in hours.
- **Belt.md's six fields** sit at their own distances and phases, so their windows are spread out. If they are spread evenly through the window cycle, the nearest window to *some* field is on average about S/7, where S is the synodic period: about **65 days** at 2.7 AU.
- **The trip home** is timed already. The planner waits at the field for the planet's window and arrives at Frost's cluster through A13's cheap phasing round the moon. That is 232 days of waiting plus 462 in flight in A26's run.
- **The coast warp:** these are years of game time either way. Belt.md's coast warp is what makes them playable, not this design.

#### The planner change (A31)

For an outward trip whose target is a frame round the star:

1. **Find the departure.** Find the first tick t_d at or after the earliest the probe can reach the parking circle, when the star-level Hohmann from the planet's position arrives at the field's position.
   - The angle between the planet and the field changes steadily, so the window is found in closed form and then refined by bisection on the tick.
   - Each try runs the real patched-conic legs, so the escape from the planet's sphere is included.
2. **Hit the field, not just its orbit.** A day's error in leaving is about 0.77° of the field's orbit, which is 5 million km at 2.7 AU, and a frame is joined only within 1,000 km of its edge. So the escape burn is refined twice.
   - **Burn pass:** the burn's tick is moved to the parking circle's nearest pass of the escape point.
   - **Burn size:** its size is adjusted by bisection until the miss at arrival is under the join margin. A slightly faster or slower ellipse arrives a little sooner or later, for a few m/s.
   - At about 6 km of miss per tick, refining to the tick is enough.
3. **Leave the cluster late, not early.** The probe stays in the cluster, working, until the latest departure that still reaches the parking circle before t_d. In between, its op is `waiting`, as for any windowed trip (contracts section 7). There is no new op, and stop still cancels freely.
4. **Fallback.** If no refined trip hits the field within one synodic period, the planner falls back to today's untimed route and catch-up phasing, and says so with `phased: true` in the quote.

All of this is integer and deterministic like the rest of the planner. It changes only what `quote` and `move_to` choose, not the leg format, so no contract change is needed.

Tests:
- arrival within the join margin of a field at 2.7 AU;
- the wait is under one synodic period;
- the delta-v is no more than today's less the catch-up's, plus 10 m/s;
- a quote and the flight agree to the tick;
- save and load while waiting.

#### The player rule

**"Go to whichever field is near on arrival" is the right default, but the player chooses it rather than having it applied silently.** Belt.md makes each field lean one way (native metals, or zinc and nickel, or ammonia and carbon), so a silent switch could take the player somewhere they did not mean to go.

- **The planner** always times a trip to the field it was given.
- **The client (D)** lists each known field's next trip: depart, arrive, delta-v and what it leans to. It sorts them by arrival and marks the earliest. That is a `quote` per field, the same call it makes today.
- **A core's autopilot** (tier 3, which chooses and re-plans) picks the earliest arrival among the fields that hold what its order needs.

#### Open points for the Lead

- (a) Should the quote's wait be shown with the coast warp's speed, so 236 days reads as hours of play? That is D's, and it waits for the warp.
- (b) Whether the fallback to untimed phasing should exist at all, or the quote should simply say `no_window`. I'd keep it, since a field that can't be timed is a bug to see, not a trip to refuse.

### 11.22 A32 design: the coast time warp

A design note, so no code yet. It is for the Lead to approve before the kernel and client tasks start. It replaces 11.3's "not proposed": the new start and the belt both need it.

**What needs it:**
- the new start's gravity-field lap of about 42 minutes;
- a landing half-ellipse of about 2 hours;
- refinery and lab queues of hours;
- the belt's 460-day coasts.

At today's 8×, those take 5 minutes, 15 minutes, hours and 57 days of play.

#### The ladder

| Speed | How the sim runs | When it's allowed |
| --- | --- | --- |
| 1×, 2×, 4×, 8× | One `step` per tick, as today | Always |
| 50× | **Batch:** `step(n)` many ticks per frame, one `view()` per frame | Always, unless the measured step cost would break the frame budget (below) |
| 1,000×, 10,000×, 100,000× | **Coast:** `Sim.coast(max_ticks)` jumps to the next tick where anything can happen, in closed form | Only while every unit and system can coast. Otherwise it runs as 50× |

100,000× is there for the belt. A 460-day coast is about 6.6 minutes of play at that speed, against 66 minutes at 10,000×. A coast jump costs the same however many ticks it skips, so the top rung is nearly free when nothing happens.

#### Determinism: a coast is exactly a run of steps

`Sim.coast(max_ticks)` returns having advanced k ticks, with 1 ≤ k ≤ max_ticks:
- **The jump:** the kernel asks every system for its **horizon**, the ticks until something discrete could happen, and takes h as the smallest.
  - It advances every continuous quantity to tick now + h − 1 in closed form.
  - It then runs tick now + h as a normal `step`, so every event fires on the tick and in the order stepping gives.
- **The contract:** after a coast, the state, its hash, its save and the events are bit-identical to `step(k)`. Nothing that would happen is skipped. A coast may only stop early, which costs speed, never correctness.
- **Two hooks** on SimSystem:
  - `horizon(ctx) -> int`, the ticks this system can safely skip, with 0 meaning it can't coast now;
  - `coast(ctx, ticks)`, its closed-form advance.
  The default horizon is **0**, so any system not yet given a closed form blocks coasting: safe by default.
- **Closed forms exist because every rate in the sim is integer with a carried remainder** (`Rate.amount` and `Rate.carry`). For k ticks of rate r and remainder c, the total is (k·r + c) / 10, and the new remainder is (k·r + c) mod 10. That is exactly the sum of k single ticks.
- **Positions:** rails, bodies, frames and units on orbits are already functions of the tick.

**What each system needs.** A horizon may be conservative: early is fine, late never is.

| System | Coasts when | Horizon |
| --- | --- | --- |
| Rails, orbits | always | none of its own, but see the SOI, frame, ground and shadow rows |
| SOI crossing (BurnSystem) | a unit on an orbit | the crossing tick, from A18's `_entry_tick`, or never if the orbit stays inside |
| Frame join | orbiting units far from every frame | a bound: the gap to the join distance over the largest relative speed |
| Low-flight entry | periapsis above `ENTER_MM`, otherwise never | otherwise the tick it drops below, from the orbit |
| Shadow (power) | always | the next entry or exit of any unit with solar panels. Bounded per unit from its angular rate, then bisected, as A16 samples |
| Transfers, `waiting` | always | the next leg's `from_tick`, `depart_tick` or `arrive_tick` |
| `landing`, `taking_off`, measuring, scanning ops | always | the op's end tick |
| Planned burns | not while one runs | the burn's tick |
| Jobs | steady power | the next run's last tick, ceil(work_left / work_per_tick), or the next queue start |
| Power and batteries | supply and loads steady | a battery full or empty, from the linear stored_j, or the shadow horizon |
| Heat | steady | the store reaching a part's limit or the clear threshold, from the linear heat_stored_j |
| Low flight, a running burn, routes and drift in a frame, docking, loading, mining, cycle tasks | **not in the first version** | 0, so the world runs as 50× |

The last row is what the Lead listed as "a frame with moving units". Mining and loading are linear too and can join later.

**RNG:** the only draw is research discovery, at a bench test's delivery, which is a horizon tick and so stepped. Nothing draws per tick.

**Proof by harness, not argument.** A test runs scenarios each way and compares the state hash and the save bytes at every horizon, plus the event lists:
- strictly stepped;
- coasted, not strict.
The scenarios: the new start's measure, land and job queue; a transfer; a belt leg; eclipses with batteries; a heat limit. Every new coastable system joins the harness before its horizon may be non-zero.

#### Strict checks stay every tick

In strict mode, used only by tests, `coast` runs `step` for every tick. It gives the same result by the contract, so the per-tick invariants and ledgers run on every tick, as you ruled. The harness is what proves the non-strict coast matches. So nothing about strict mode changes.

#### What forces a drop or a cap

The kernel caps; the client drops.

- **The kernel caps to batch speed** while any horizon is 0:
  - a burn is running;
  - a unit is in low flight;
  - something moves inside a frame (a route, drift, docking);
  - a mining, loading or cycle task is under way;
  - any system without a closed form yet.
  `coast` then steps one tick at a time to max_ticks, so it is never wrong, only slow. It reports the cap's reason in its return as `{ ticks, capped_by }` for the client to show.
- **The client drops to 1×** on events that need attention. That is D's list. I'd suggest:
  - burn tick reached;
  - arrived;
  - landed or crashed;
  - entering low flight;
  - job_finished at a facility the player is watching, and any job_paused;
  - power_shed and fault;
  - theory_proven, design_qualified and idea_discovered;
  - a window opening for a queued move;
  - every refusal.
  Since a coast always stops on the tick of a horizon, the client sees each event on its own tick and can drop before anything further happens.

#### The client (D)

- **The ladder control:** 1, 2, 4, 8, 50, 1k, 10k, 100k. It shows the requested speed and the speed actually achieved, with `capped_by` in plain words ("burning", "landing gear down", "ships moving in the cluster").
- **Drop to 1× on attention events,** with an option to keep warping through job_finished.
- **Above 8×, hand-flying controls are disabled:** burn planning stays, burn execution forces a drop at its tick.
- **A clock readout in days and hours.**
- **One `view()` per frame, not per tick,** and interpolation across a whole jump. Orbits draw from their records, so a 1,000-tick jump still animates smoothly.
- **Saves:** the save is identical either way, so a save made mid-warp needs nothing special.

#### Performance budget (perf_budget.md)

- **Batch, 50×:** 500 ticks a second. At the slice's real size a tick costs about 0.23 ms with a view every 8 ticks (A17), so about 115 ms of CPU a real second, or 1.9 ms in a 60 fps frame. At 20 times the slice the same measurement gives about 7× in total, so the bridge must measure its step time. It caps batch speed to keep step and view inside one frame (16 ms), and shows "capped: busy world".
- **Coast:** a jump's cost is one horizon pass, one closed-form pass over units and parts, and one normal step.
  - The budget is **2 ms a jump at slice size and 8 ms at 20 times the slice**. A new `test_perf` line measures it.
  - Horizons come from eclipses (twice per 6.8-hour cluster orbit), job runs and transfer legs. A 460-day belt coast with nothing else running is a few dozen jumps.
- **Queries are unchanged.** `quote` and `predict` are not per-tick work.

#### Tasks

- **A33 (kernel):**
  - `Sim.coast`, the two SimSystem hooks, and the horizons and closed forms for the coastable rows above;
  - the equivalence harness and the perf line;
  - contracts §3 (`coast`) and §4 (the coast rule).
  - Size: L. It touches every network system, through the hooks, by agreement with each owner where the system is C's.
- **D (client):** the ladder, `capped_by` and attention drops, a view per frame, the clock and the disabled controls. Size: M.
- **Later:** mining, loading and routes inside frames as coastable rows, then low flight is the last that never coasts.

#### Open points for the Lead

- (a) Is 100,000× wanted now, or with the belt?
- (b) Should the client's attention list be owned in contracts (as event types), or is it D's call?
- (c) The systems that are C's (jobs, construction, tasks): should their closed forms be A33's, with C reviewing, or C's own small task beside A33?

### 11.23 A33 results: the coast in the kernel

`Sim.coast(max_ticks)` is built as 11.22 designed, with two changes found while testing:
- **It returns just after any tick with events.** On a landing's last tick, power worked out its figures before the probe was set down in the shadow. Repeating them would have left the batteries wrong. Every change late in a tick fires an event, so after one the next tick is stepped. Returning there also gives the client each event on its own tick.
- **Shadow bounds use the relative speed** of the unit and the caster, counted only below the first body both hang from. The planet's 30 km/s round the star moves both alike. Counting it made a lap round Frost take 5,421 coast calls; with it left out, the lap takes 21.

**What coasts now:**
- **Systems with closed forms:** rails (positions as functions of the tick), BurnSystem (bounds on spheres of influence, frame joins and low flight), LandingSystem (atomic landing and takeoff), CargoSystem (flown transfers and waits), PowerSystem (shadow bounds and battery regimes) and HeatSystem (cold and warm loops).
- **C's systems** have an idle-only horizon, with C reviewing:
  - JobSystem and TaskSystem can't be skipped while any job or task exists;
  - ConstructionSystem acts only on a job's delivery;
  - FitCopySystem, FittingSystem and UnitSystem act only on commands.
- **C17** gives jobs, tasks, mining and cycles their closed forms. Until then a `move_to` (a task) and any job cap the world at batch speed.

**Proof:** `tests/sim/kernel/test_coast.gd` steps one copy and coasts another, then compares their saves byte for byte and their events one for one.
- **The cases:**
  - a 38,000-tick lap round a Frost-sized moon, through its shadow, with half-charged batteries;
  - a warm heat loop cooling;
  - an atomic landing;
  - a planned burn: the coast returns on the burn's tick, then caps at `burning`;
  - an undock task, which caps at `tasks`;
  - strict mode, which steps every tick.
- **Measured:** the lap takes 21 coast calls, at 1.85 ms a call, or 39 ms for the lap. That is inside the 2 ms budget, and about 100,000× real time for that case.
