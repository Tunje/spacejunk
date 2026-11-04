# Orbital Flight

Status: proposal for the owner to decide on (task kernel/orbital-proposal). Nothing in `sim/`, `data/`, `client/` or the contracts has changed. The planet half is in [planets.md](planets.md) by B, and what automation does with orbits is in [orbital_automation.md](orbital_automation.md) by C.

The owner asked: "gravity based movement like in kerbal maybe?" The workplan records order-based flight as owner-confirmed (lines 17 and 79), so this page looks at reversing that decision.

## 1. The short answer

- **It can be done without breaking determinism.** Section 3 has the proof. Orbits are worked out in whole numbers from the tick alone, so they never drift. Positions came out bit-identical after 5.6 hours of play, a save and load, and running at 8x. A position 1000 orbits later, in year 30, was exactly the same.
- **My recommendation is option 3:** real orbits with an autopilot first, and manual manoeuvre planning added later on the same maths. **Start it after the M4 judgement, not before.**
- **It changes nothing in the slice.** The slice's rocks are 30 to 50 km from the station, far from any planet. They drift apart by about 100 m over a whole run. Gravity only starts to matter once there is a planet to orbit, and planets come after the slice. Doing this before M4 would delay M4 for a change the owner couldn't see.
- **Full Kerbal-style flight (option 1) is a bad trade for this game.** The game's main claim is automation. Hand-flown burns can't be repeated by a drone, and Kerbal relies on time warp of 1000x and more, which this simulation can't reach.
- **The real costs are pacing and propellant.** In a gravity well a trip takes about half an orbit, and the right moment to leave can be over an hour away. A trip around a Kerbin-sized planet takes 17 to 44 minutes of game time, and a round trip costs 6 to 44% of a ship's mass in propellant. Today a whole drone lap costs 2.7%. Landing on a 600 km planet and returning to orbit costs well over half the ship's mass.

## 2. The three options

| | 1. Full patched conics | 2. Orbits with autopilot | 3. Option 2 now, manual nodes later |
| - | ---------------------- | ------------------------ | ----------------------------------- |
| What the player does | Plans burns on manoeuvre nodes and flies them | Picks a target and presses Move to. The autopilot waits for the window and flies the transfer. | As option 2, then adds a manual mode for players who want it |
| Integer determinism | Possible, but every burn makes a new orbit from position and speed, which needs more integer maths than I proved (section 9) | Proved: orbits on rails, planned transfers (section 3) | Option 2 first, then the same step as option 1 |
| Automation | Poor. A drone's cycle can't contain hand-flown burns, so automation would need option 2's autopilot anyway. | Good. A cycle step is still "move to target". It waits for a window instead of leaving at once (section 4). | Good. Manual nodes are for the player's own ships. |
| Pacing | Needs huge time warp | Trips and waits of minutes to an hour of game time, and 8x is enough (section 5) | Same as option 2 |
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

| Planet, 600 km radius | Low orbit (700 km) | 700 to 760 km | 700 to 1000 km | 700 to 2000 km | Speed in low orbit |
| --------------------- | ------------------ | ------------- | -------------- | -------------- | ------------------ |
| **Kerbin gravity, 9.81 m/s², GM 3.53e12** | 33 min | 17 min, 90 m/s, window every 4.7 h | 22 min, 364 m/s, every 79 min | 44 min, 860 m/s, every 41 min | 2.2 km/s |
| Compressed, 10-minute low orbit, GM 3.76e13 | 10 min | 5.3 min, 295 m/s, every 86 min | 6.7 min, 1188 m/s, every 24 min | 13 min, 2805 m/s, every 13 min | 7.3 km/s |

The 600 km radius with Kerbin's 9.81 m/s² is already Kerbal's own compression: about ten times Earth's density, so a small world still has real gravity.

**Proposal:**
- **A Kerbin-like planet:** 600 km radius, GM 3.53e12 m³/s², and no rotation, as agreed with B.
- **Don't compress gravity further.** A 10-minute orbit needs 7.3 km/s of orbital speed, so landing and leaving would cost nearly all of a chemical ship's mass.
- **Orbits for stations and moons from 700 km to about 2000 km.**
- **The rock cluster stays a cluster.** Either it is one co-moving frame, with today's trips exact, or every rock in it gets the station's period, so the rocks circle each other and never drift apart. I prefer the co-moving frame, because it keeps every figure in [reference_scenario.md](reference_scenario.md).
- **Planet trips are expeditions, not laps:** 17 to 44 minutes of game time, or 2 to 6 minutes at 8x. A window wait of up to 79 minutes is 10 minutes at 8x, and the autopilot waits on its own. Very close orbits, like 700 to 760 km, should be avoided by design, because their windows are hours apart.

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
