# Stage 3: the autopilot flies (plan, A63)

Stage 3 of [real_orbits.md](real_orbits.md) section 10. Today a `move_to` between places pays a
formula price and rides orbit legs on rails, then snaps to the target. After stage 3 it flies burns
through BurnSystem, exactly as a hand-placed burn flies, and its quote is that flight played ahead.
Frames stay until stage 4, so targets in a frame are still reached at the frame's place; stage 4
moves the same machinery onto real rock orbits.

Contents:
1. A Lambert solver that always hits (3a)
2. Plans are burn lists (3b)
3. Quotes are flights ahead (3b)
4. Trips across spheres, flown (3c)
5. Arrive modes and the quote chain, for C (3d)
6. What changes for others
7. Order, tests and costs

## 1. A Lambert solver that always hits (3a)

**Why.** A47's solver shoots on two in-plane velocity components with a finite-difference
Jacobian. Stage 0 found it misses 1 to 89 km on the rendezvous stage 4 needs most: 50 km along the
cluster's own circle in 5 to 100 minutes. Shooting from a circular guess on a short arc is badly
conditioned, and the step cap stops it before it converges.

**What replaces it.** A universal-variable Lambert solver: given r1, r2, the time of flight and the
sense of motion, it solves directly for the departure and arrival velocities.
- The unknown is z (the square of the universal anomaly). Newton's method finds the z whose time of
  flight matches, using the Stumpff functions C(z) and S(z).
- Those come in integers: a power series near 0, and OrbitMath's sin_cos or sinh_cosh beyond it, in
  Q30 with a fixed number of iterations, so every machine gives the same bits.
- **Multiple revolutions.** For N whole turns there are two solutions for each N ≥ 1. The planner
  asks for N = 0, then, if the trip is longer than a turn, the cheaper of each N's two up to the
  time allowed.
- **Planes.** The transfer plane comes from r1 × r2, oriented by the craft's motion. Within about
  1° of 0° or 180° the plane is undefined, so the craft's own orbit normal is used instead. Trips
  across planes keep A41's choice of the plane change at the start, at a node, or joined to a burn,
  priced as now.
- **Exactness.** The closed-form answer is then refined by up to three shooting steps with the same
  integer propagation the rails use (OrbitMath.from_state, then position_at), until it misses by
  1 m or less. So the orbit planned is the one flown.

**Acceptance (3a's tests).**
- The 50 km trip in 30 minutes in the cluster hits within 1 m, with Δv within 1% of the float
  answer.
- Every trip today's Transfer tests plan hits within 1 m.
- The planner's existing `timed` quotes give the same or a cheaper cost.
- Cost: under 1 ms a solve. A47's arc search costs about 2 ms at most today.

## 2. Plans are burn lists (3b)

A trip's plan becomes saved state on the unit's op, replacing `transfer.legs`:

```
op.plan = {
  target, prefer, arrive,            # arrive: "standoff" (default) or "contact" (section 5)
  burns: [ { tick, dv_um_s: [x, y, z], steer, throttle_ppm } ],   # world-frame velocity changes
  corrections: [ tick, ... ],        # where the plan is solved again from the real state
  arrive_tick, standoff_mm,
}
```

- **Building it.** The planners stay: Hohmann, phasing, plane changes, the timed arc (Lambert), and
  SoiTransfer's legs. Each plan's orbits are turned into burns: at each leg boundary, the velocity
  change from the orbit before to the orbit after.
  - A burn of duration d starts d/2 before the ideal instant (the lead time, A54), and is placed
    with `steer: "orbit"` so it holds its direction against the motion through a long burn.
  - The plan is solved at the unit's actual mass, and is flown ahead (section 3) before it is
    accepted. A plan whose flown arrival misses by more than the correction can recover is refused
    as `unsupported_orbit`, as unflyable plans are now.
- **Flying it.** At departure the move_to step places the plan's burns on the unit as planned burns.
  - BurnSystem flies them as it flies any burn. The engine is a power and heat load, fuel is spent
    as it burns, and a burn ends early if the propellant runs out.
  - The op stays `moving`, with `plan` in it.
- **Corrections.** By default there are two correction points: halfway, and at 90% of the coast to
  arrival.
  - At each, the step solves again from the unit's real state to the plan's arrival point at
    arrive_tick, with Lambert, and replaces the remaining burns with the result.
  - The correction ticks are saved in the plan, so a loaded save corrects on the same ticks with
    the same answer.
- **What goes.**
  - The transfer stops being atomic. Stopping a trip cancels the remaining burns. What has burned
    is spent, and the unit coasts where it is. The price is no longer paid up front.
  - `transfer.legs` on rails goes, along with the arrival snap at the end. Arrival is section 5's
    arrive condition.
  - The thruster fields `speed_m_s`, `propellant_kg_per_s` and `rated_mass_kg` stay only for
    routes inside a frame until stage 4.

## 3. Quotes are flights ahead (3b)

`quote`, `next_window` and `Travel.quote_leg` build the plan (section 2) and fly it with
FlightAhead from the unit's state. The result keeps today's fields:
- `depart_tick` is the first burn's start;
- `arrive_tick` is the tick the arrive condition first holds in the flight;
- `cost_g` is the propellant the flight burned;
- `dv_um_s` is the Δv it delivered.

New fields:
- `burns: [{ tick, dv_um_s, burn_ticks }]`, for the client's plan panel;
- `closest: { tick, range_mm, speed_um_s }` at arrival.

- **FlightAhead from any start.** It gains a start from a description instead of only from a unit:
  { orbit or stepped state, mass_g, propellant_g, thruster stats }. Then quote_leg can price a leg
  from somewhere the unit hasn't reached yet, at a given mass, as C's laps need.
  - Corrections are played ahead too. The flight solves again at each correction tick exactly as
    the real step will, so the quote is the trip.
- **Cache.** Quotes are cached on the context, keyed by the start description, the target's track
  and the plan parameters. A51 and A55 cache the same way.
  - A client asks at most every 250 ms, as now. A cached quote costs one dictionary lookup.
- **Costs** (worked out from stage 0's figures):
  - a probe trip in the cluster: about 460 stepped ticks at about 14 µs, plus 3 Lambert solves
    (about 1.5 ms), so about 8 ms;
  - a drone's: about 3,400 ticks, so about 50 ms;
  - a sphere-crossing trip: its coasts are on rails and its burns stepped, so a few ms more than
    today's quote.
  - The cheap and fast pair is two flights.
  - Cores and cycles never ask for `compare`, as now.

## 4. Trips across spheres, flown (3c)

SoiTransfer's leg chains become burn lists in the same way:
- the departure burn;
- the capture burn at the periapsis of the hyperbola;
- the circularising or phasing burns.

The sphere crossing itself needs no burn. A coasting orbit crosses by `_cross_soi`, and a stepped
one by `LowFlight.cross_sphere` (A55). The correction points include one just after each sphere
entry, where errors from the patched-conic hand-off show first.

## 5. Arrive modes and the quote chain, for C (3d)

**Arrive modes** (agreed with C, stage4_gameplay_rules.md):
- `"standoff"` (the default): the trip ends when the craft is within standoff_mm of the target, at a
  relative speed of 0.1 m/s or less, station-keeping. The final braking burn is placed with
  `steer: "target_retrograde"`, so it ends when the relative speed is nulled.
  - standoff_mm comes from data, on the target's kind. The default is 300 m.
- `"contact"`: from the standoff, a final approach of small burns closes at the target's approach
  speed, steered `"target"`, then brakes to the capture condition.
  - For a unit target, that is the stricter port's capture_range_mm and capture_speed_mm_s (A54).
  - For a rock, it is touching within B30a's miner contact limits.
  - `dock` and `anchor` then capture as stage 4 sets out. Until then, `dock` keeps today's rule.
- `arrived` fires when the mode's condition first holds.

**The quote chain.** `Travel.quote_chain(ctx, unit, legs, from_tick)`, where legs is
`[{ target, prefer, arrive, mass_change_g, propellant_change_g, wait_ticks }]`. It plays each leg on
one copy of the unit, in order:
- the copy's state, mass and propellant carry on from one leg to the next;
- a stop's cargo change and refuelling apply at arrival, after `wait_ticks`.

It gives `{ legs: [quote per leg], arrive_tick, cost_g, short_at }`, where `short_at` is the first
leg the propellant runs short, or -1. C's lap gate (stage4_gameplay_rules.md section 6) prices a
lap with one call.

**Refuelling mixture** (with the mixture item): two propellants are taken in the engine's mixture
ratio. With several engines, it is the ratio of the engine the plan burns with, which is the burn
thruster (BurnSystem.thruster). The Lead's off-ratio rule applies: the excess of either stays unusable
until it is rebalanced.

## 6. What changes for others

**Contract.**
- §3 quote fields: add `burns` and `closest`. `kind: "transfer"` becomes `"flight"`, keeping
  "transfer" as an alias until D moves.
- §5 move_to: `arrive`, non-atomic trips, and the stop behaviour.
- §7 op.plan replaces unit.transfer.legs.
- §6 events: departed and arrived keep their shapes. A new `plan_corrected { tick, dv_um_s }`.
- A new contract version, through the Lead.

**C.**
- Cycles price laps with quote_chain.
- Cargo and mining read arrival from `arrived`, as now.
- move_to steps keep their names and gain `arrive`.
- The bot's timings move.

**D.**
- The plan panel shows `burns`.
- ETAs come from the flown quote.
- The trip arc is drawn from predict with with_burns, which already flies planned burns.

**B.** None for 3a to 3c. Standoff distances per target kind come in 3d.

**Tests.**
- The transfer tests change from legs to burns.
- Prices move from formula to flown. They should be close to today's for impulsive-looking burns,
  and higher where long burns lose to gravity, which is the point.
- Snapshots and the playthrough are regenerated.

## 7. Order, tests and costs

| Step | What | Test it must pass |
|---|---|---|
| 3a | Universal-variable Lambert, multi-rev, plane handling, integer refine | 50 km in 30 min hits ≤ 1 m; all Transfer cases hit; under 1 ms |
| 3b | Plans as burn lists, corrections, quotes flown ahead, FlightAhead from a description, the quote cache | A trip's quote equals its flight, tick for tick and gram for gram; the save is exact mid-trip and across a correction |
| 3c | SOI trips flown | Today's SOI test trips arrive, and quote equals flight |
| 3d | Arrive modes, quote_chain, refuel mixture | Standoff and contact end inside their conditions; a chain equals its legs flown in turn |

Each step is its own branch with its own gate. 3a stands alone and can merge first. 3b to 3d change
the trip contract, so the matching C and D work lands with each, as A55 did with D50.

**The honest risk** is the bot's pace. Flown trips cost what they cost, including gravity losses and
corrections, so B's fuel balance and C's bot timings will move, mostly at 3b. B23's human-pace rule
still governs: a run must last a human player to the M4 judgement.
