# Real orbits: removing the flight shortcuts (A53)

A design for the owner to read before anything is built. Agent A (simulation kernel), 2026-11-07.

The owner's rule: "Shortcuts are not welcome in my game if it loses out on what I have asked for."
Three shortcuts break it today, and this document says how each one goes:

1. **The cluster frame.** The rock cluster and the station sit in a patch of space with no gravity,
   where things move in straight lines.
2. **Autopilot trips.** They are priced with a formula and paid for as instant kicks at departure.
   The ship's engines never actually fire.
3. **Land and take-off.** These are priced with a formula and done in one step. Nothing is flown.

After them comes a list of every other simplification in `sim/`, what each one loses, and what the
real version would cost. The last part covers what breaks and the order of work.

Where this says "measured", the figure was timed on this machine for this document. Where it says
"estimate", it was worked out by hand and still needs checking. Stage 0 checks the estimates.

---

## 1. The short version

- **Every rock, station and ship is on its own real orbit.** Nothing sits in a gravity-free patch.
  The rocks stay together because they are given orbits of the same size around Frost, so they
  return to the same places relative to each other every orbit. That is exact for two-body
  gravity, not an approximation.
- **The autopilot flies.** A trip becomes a list of real burns, fired tick by tick with the ship's
  own thrust, its mass falling as fuel is used. These are the same burns as a hand-flown one. A
  price is no longer a formula: the sim flies the plan ahead on a copy of the ship and reports
  what that flight used and when it arrived.
- **Landing and take-off are flown,** with real gravity, thrust and fuel, on the same engine
  physics as a hand-flown landing.
- **Docking, mining and cargo depend on real distance and speed,** not on a flag that says
  "is at". A ship has to come close and slow to dock, and docking or undocking really changes
  orbits.
- **Determinism and warp keep working.** Coasting between burns still skips in one jump, because
  an orbit with no thrust has an exact closed form. Burns are stepped tick by tick, and high warp
  slows down while something is burning, as it does in KSP.
- **The biggest gameplay change is trip time between rocks.** Today a trip of tens of kilometres
  takes about a minute and a modest amount of fuel. Done for real, it takes tens of minutes to
  hours of game time to be affordable. A fast trip costs a lot of fuel (section 3.3). The owner
  should decide how big the cluster is and how fast trips should feel, because B balances fuel
  around that answer.

---

## 2. What the world is made of after this

Every body and unit is in exactly one of these states:

| State | What it means | How it moves |
|---|---|---|
| **Coasting** | On an orbit around one parent body | The exact closed-form orbit, as today, so it can be skipped ahead in one jump |
| **Powered** | Thrust is on, or the path is too close to straight up and down for an orbit record | Position and velocity stepped every tick with gravity plus thrust, in integers |
| **Landed** | On a planet's surface, or anchored to a rock | Rides with the body |
| **Docked** | Latched to another unit | Rides with its host, at a fixed offset |

The cluster "frame" and the old "frame 0" world, where nothing moves, are removed.

### One integrator for powered flight (B's 20/30 km seam)

Today there are two ways to move a unit near a planet. Above 20 km it is on an orbit record, and
below that it switches to stepped position and velocity ("low flight"), switching back above
30 km. The switch is by altitude.

After this, the switch is by state, not by altitude:
- Any unit that is **thrusting**, anywhere, is stepped as position plus velocity, with gravity and
  thrust each tick.
- A unit **coasting** on a path an orbit record can't hold (nearly straight down or up, near a
  surface) is stepped the same way.
- Otherwise a coasting unit is on its orbit record and can be skipped ahead.

The change between the two forms is one exact conversion, made when thrust stops or starts. There
is one stepping method for all powered flight, near a planet or far from one.

**Measured.** One stepped tick costs 10.4 µs. Rebuilding an orbit record every tick, which is how
burns work today, costs 86 µs. So stepping is also about 8 times cheaper during burns.

The stepping method today is semi-implicit Euler. For long unpowered stretches it gains or loses
a little energy. A symplectic version, velocity Verlet, costs about the same and keeps energy
honest, so that is part of this work.

---

## 3. The cluster without a frame

### 3.1 How a cluster of rocks stays together

Around a planet or moon, an object's orbit period depends only on the orbit's size (its
semi-major axis). Two rocks with the same semi-major axis take exactly the same time to go round.
So, seen from one of them, the other traces a closed loop and comes back to the same place every
orbit. A rock even slightly higher or lower on average has a different period, and drifts away
for good.

So the new start's cluster is built from orbits that all share **one semi-major axis**, with small
differences in shape, tilt and phase:
- A small difference in eccentricity makes a rock trace a loop round the station's orbit. The loop
  is about twice as long along the direction of travel as it is up and down. The station is the
  reference orbit.
- A small difference in tilt makes the rock bob above and below the station's plane once per
  orbit.
- B chooses the elements so the loops don't cross each other, and lists them in the scenario data.

With two-body gravity (patched conics) this repeats exactly, forever. Integer orbits keep it
exact, because every rock is on rails and nothing accumulates.

**Today's numbers, honestly** (estimates from the scenario):
- The cluster orbits Frost 300 km from its centre. One orbit takes about 6.8 hours, at about 77 m/s.
- The rocks are 30 to 50 km from the cluster's centre. That is a large spread for a 300 km orbit.
- Placed the way they are today, with no frame, they would separate by hundreds of kilometres
  within one orbit.
- On shared-size orbits they stay, but each traces a loop up to about 50 km by 100 km around the
  station every 6.8 hours. The distances between rocks change by tens of kilometres over an orbit.

**Owner's choice.** A tighter cluster, with rocks within a few kilometres, behaves more like the
picture of "a cluster", and trips are cheap. The current spread makes the cluster a slowly
swirling field.

### 3.2 Relative position and velocity: the state everything else uses

For any two things around the same parent, the sim computes exactly, in integers, at any tick:

- **Relative position and velocity**: target minus craft, in mm and µm/s.
- **Range**: the distance between them.
- **Closing speed**: how fast the range is shrinking, the relative velocity along the line between
  them.
- **Lateral speed**: the rest of the relative velocity, across that line.

Both orbits are closed-form, so these come straight from the two positions and velocities. No
frame and no approximation is involved.

**Precision (estimate, checked in stage 0).** At 300 km the orbit maths resolves positions to
under 1 mm. A 1 cm/s nudge is about a ten-thousandth of orbital speed, far above the rounding.
Docking at centimetre-per-second speeds is within reach.

C builds its own rules on this state (section 6): mining range, scan range, cycle placement, and
cargo only between docked units.

### 3.3 Flying between rocks

A trip between two rocks is a real rendezvous, in four parts:

1. **Transfer burn.** Its direction and size come from solving for a path that meets the target at
   a chosen arrival time, round the shared parent. That is the Lambert solver from A47, already in
   the sim. The burn starts half its duration before the ideal instant (the "lead time"), so a
   finite burn lands where the ideal kick would.
2. **Mid-course correction.** Partway there, the autopilot re-solves from the real state and fires
   a small correction. The correction points are fixed ticks in the saved plan, so the result is
   deterministic.
3. **Braking burn.** This brings the relative speed close to zero at a standoff distance, say a few
   hundred metres, never on top of the target.
4. **Final approach.** Slow closing, at walking pace or less, with small burns, until the capture
   condition holds (section 3.4).

**What it costs (estimates).** For a quick trip over a distance d in a time t, much shorter than an
orbit, the fuel is roughly speeding up and then slowing down: about 2 × d / t of delta-v. For
50 km:

| Trip time | Delta-v, roughly | Compared with today |
|---|---|---|
| 100 s (today's route speed) | about 1,000 m/s | A third of the fuel's exhaust speed per trip, which is unaffordable |
| 10 min | about 170 m/s | Expensive per lap |
| 30 min | about 55 m/s | Workable |
| about 3 h (half an orbit) | a few m/s | Very cheap, but slow |

The orbit's own motion helps or hurts depending on direction. The flown plan accounts for that,
and the table doesn't.

The player picks fast or cheap, as today's `prefer` does. A cycle uses the cheap choice by default.
Warp makes the slow trips practical.

### 3.4 Arrival, approach and capture (docking)

**Capture condition.** Docking happens when both of these hold, with the limits in the docking
port's data:
- the range between the two ports is at or under `capture_range_m` (for example 2 m);
- the relative speed is at or under `capture_speed_m_s` (for example 0.2 m/s).

**Refusal reasons:**
- `too_far` when the range is outside the limit;
- `too_fast` when the relative speed is over it;
- the existing `port_busy` and `module_missing`.

**On capture**, the two become one body. Their combined velocity conserves momentum (a
mass-weighted average), which gives the joined pair its new orbit. Docking really nudges a
station's orbit, by a little, because a probe is light.

**A docked unit sits at an offset** from its host: the relative position at capture. Today it sits
at its host's centre. There is no rotation in the sim yet (section 7), so the offset is fixed in
space. The client draws it there.

**Undocking** gives both units a push apart, `separation_m_s` in the port data, split by mass.
Each gets its own orbit, close to the other and slowly drifting apart, so a ship really has to
move away before it burns.

**The arrival snap goes.** Today an autopilot trip ends with the ship placed exactly at its
target's place. After this, a trip ends wherever the flown burns put it. If that is inside the
capture condition, it docks. If not, the autopilot fires another small approach burn.

### 3.5 What the player and the client get (D's list)

The client does no physics, so the sim supplies all of this, in the view or from a query:

- **Relative state** to the selected target: range, relative velocity, closing speed and lateral
  speed (section 3.2).
- **Closest approach** over a horizon:
  - for the current path, and for the path with a planned burn;
  - as a tick, a distance and a relative speed;
  - also in `check(plan_burn)`'s detail when the unit has a target.
  - On rails, both paths are closed-form. With burns, the path is flown ahead with the same
    stepping as the real flight, so the prediction is exact.
- **Plane and timing**:
  - relative inclination, the angle between the two orbit planes;
  - the ticks of the next ascending and descending node, where the craft crosses the target's
    plane;
  - the phase angle, and the tick of the next intercept window.
- **Burn duration** at current thrust and mass (the plan check already gives `burn_ticks`), and
  the lead time, half the duration.
- **Docking condition**: the current range and speed against the port's limits, and the refusal
  reason if a dock were ordered now.
- **Predicted path including finite burns,** for drawing. `predict` already draws paths. It is
  extended through planned burns using the same stepping as the flight.

---

## 4. The autopilot flies real burns

### 4.1 Plans are lists of burns

A trip plan becomes saved state: a list of burns, each with
- a start tick,
- a direction rule (for example "hold prograde", or a fixed direction),
- a delta-v target,
- and the correction points.

**Who solves for it.** The same planners as today:
- Hohmann, or a phasing orbit, for orbit-to-orbit trips;
- patched conics across spheres of influence;
- Lambert for "leave now" and for trips between rocks.

**Who flies it.** BurnSystem flies each burn exactly as it flies a hand-placed one:
- thrust is divided by the current mass each tick;
- fuel flow is thrust divided by exhaust speed;
- the engine counts as a power and heat load;
- the burn stops early if the fuel runs out.

**Steering during a burn (new).** A burn can hold "prograde" or "towards the target" each tick,
not just the direction fixed when it started. Long burns need this to be accurate.

**Throttle (new).** Thrust from a minimum fraction up to full, per engine in data. A flown landing
needs it to hover and touch down softly.

### 4.2 What replaces the quotes (D's point)

Every quote, ETA and "you won't get back" warning today is built on formula pricing. After this:

- **A quote is a flight ahead.** The plan is flown on a copy of the unit's own motion, not the
  whole world, since the rocks and planets are on rails and known at every tick:
  - coasting stretches are skipped in one jump;
  - burn stretches are stepped.
  - The quote reports the arrival tick, the fuel used, and the closest approach at arrival.
  - Because the flight uses the same integer steps as the real one, the quote is what the real
    flight uses. That is not an estimate.
- **ETAs** are the quoted arrival tick, refreshed when the plan is re-solved at a correction point.
- **"Can't get back"** (A36) is a flown-ahead return from where the trip ends, at the mass the trip
  leaves. For a landing, that is a flown take-off and the trip back to the station.
- **The fast and cheap choice** is two flown plans, as today's two quotes.

**Cost of a quote (estimate from measured parts).**
- A burn of 100 m/s on today's starter ship takes about 1,100 ticks at 10.4 µs each, about 11 ms.
- A three-burn trip is about 35 ms.
- A landing check that also prices the way back flies a descent and a climb. That is a few
  thousand stepped ticks each, so about 50 to 100 ms.
- That is fine for a click or a check. It is too slow to redo every frame, so quotes are cached
  until the unit's motion or the plan changes. A51 does the same for sunlight.
- Cycles that price a whole lap ahead use the same cache.

### 4.3 Where the autopilot can't solve

Today's planner refuses some trips with `unsupported_orbit`, for example hyperbolic starts and
crossings out of plane between spheres. The flown version keeps those refusals until the planner
learns them. That is a gap in the planner, not a shortcut in the physics, and is listed in
section 7.

---

## 5. Landing and take-off are flown

### 5.1 Landing (the autopilot's `land`)

1. **De-orbit burn.** This lowers the low point of the orbit to just above the chosen hex, timed so
   the path comes down over it.
2. **Coast down,** on rails.
3. **Powered descent.** The sim steps the descent with gravity and thrust. Guidance is in integers
   and decides each tick how hard to brake, aiming to arrive above the hex nearly still at a small
   height. That is the "suicide burn" with a margin.
4. **Final descent** straight down under throttle, to touch down within the gear's speed and slope
   limits (A52).
5. **Touchdown.** The unit lands where it actually touches. This uses the ground height at that
   point, interpolated between hex centres instead of flat across the hex (section 7, item 12).
   The touchdown point is kept, so it no longer snaps to the hex centre.

**Where its fuel goes.** Gravity losses, the extra fuel spent holding the ship up while braking,
come out of the flight itself, not out of a formula. The check is the descent flown ahead.

### 5.2 Take-off

1. Climb straight up, clear of the ground.
2. Pitch over, a gravity turn, while the engine raises the orbit's high point to the target height.
3. Coast up.
4. Circularise at the high point.

Each stage is a burn in the plan, flown like any other.

### 5.3 Hand-flown

Hand-flown landing already works this way (A19), since gravity is stepped each tick. It gains:
- throttle;
- the single powered-flight integrator;
- the real touchdown point.

---

## 6. Proximity rules: dock, mine, scan, transfer

The "is at" flag (`at_target`) goes. Each action has a real condition on the relative state from
section 3.2:

| Action | Condition | Limits in data |
|---|---|---|
| Dock | Range and relative speed under the port's capture limits | Docking port: `capture_range_m`, `capture_speed_m_s`, `separation_m_s` |
| Mine | Anchored to the rock (a capture against its surface: within contact range, slow), so the miner rides the rock | Mining part: contact range and speed |
| Scan, measure | Within the instrument's range of the body, held for the scan's duration | Instrument: `range_m` |
| Cargo, job inputs, fitting from another unit | Docked, as today. Docked means really latched now | none |

C owns how cycles and jobs use these. C fixes its own items on top of this state:
- deposits as pools with no site;
- scans that reveal everything at once;
- instant moves across docks;
- placement by flag.

---

## 7. Every other simplification in `sim/`

The owner asked for all of them, including ones I think are harmless. For each: what it loses and
what the real version costs. Those marked **(this work)** are done by sections 2 to 6. The rest are
for the owner to order.

### Flight and gravity

1. **Patched conics: one body's gravity at a time, switched at a sphere boundary.**
   - Loses: Lagrange points, slow tugs from other moons, and capture without a burn.
   - The cluster at Frost ignores the planet's pull. Real, it would slowly disturb the rock loops
     over days.
   - Real cost: every object stepped every tick with all bodies' gravity. That ends warp by
     skipping, and long warps would cost about as much as playing them out. This is very
     expensive.
   - Stays unless the owner says otherwise; the Lead is asking.
2. **Planets and moons on fixed orbits (rails).** Ships don't move planets. This is real to any
   measurable amount. Harmless.
3. **Gravity as from a point.** No flattening of planets (J2), so orbits don't slowly turn.
   Harmless at this scale. Real cost: moderate, as a known slow drift of the orbit's angles.
4. **Frost and the planets don't rotate.**
   - Loses: landed units don't move under orbiting ones. Day and night on the ground don't cycle,
     because a landed ship stays in sun or shadow all year. Take-off gets no boost from the
     ground's own speed.
   - Real cost: cheap maths, a landed position turned by an angle that grows with time. The knock-on
     work is moderate: sunlight timing for landed units, matching ground speed on landing and
     take-off, and drawing.
   - Recommended soon after stage 5.
5. **No atmospheres.**
   - Loses: drag, aerobraking, parachutes, and re-entry heating, which a KSP-style game is known
     for.
   - The planet is airless today, and so is Frost (correct for a small moon).
   - Real cost: high. Flight in air must be stepped, never skipped, and drag needs a shape and an
     orientation.
   - Owner's call.
6. **No orientation.** A ship has no facing. Thrust points anywhere instantly. Solar panels don't
   need to face the sun. Docking ports don't need lining up.
   - Loses: turning before a burn, reaction wheels and thrusters for turning, and lining up a dock.
   - Real cost: moderate to high, as a facing, a turn rate per ship from its parts, and the
     autopilot turning before it burns.
   - Owner's call.
7. **Full thrust only.** (this work) Throttle is added (4.1).
8. **Burn direction fixed when a burn starts.** (this work) Steering modes are added (4.1).
9. **The thruster fields `speed_m_s`, `propellant_kg_per_s` and `rated_mass_kg`.** These exist only
   to price straight-line trips in the frame. **They go.** Thrust and exhaust speed say everything.
   (this work, with B)
10. **Stepping that drifts in energy** (semi-implicit Euler). (this work) It becomes velocity
    Verlet (2).
11. **The 20/30 km seam.** (this work) One integrator, switched by state (2).
12. **Terrain as flat 7 km hexes.**
    - Loses: real ground under the craft. It touches down at the hex's single height, then snaps
      to the hex centre. The slope is judged from neighbouring hexes, not under the legs.
    - (this work, partly) The ground height is interpolated between hex centres, and the touchdown
      point is kept. That is cheap. Finer terrain than the hex grid is a later choice.
13. **No collisions between units, or with rocks.** Ships pass through rocks, the station and each
    other.
    - Real cost: a rock as a solid sphere is cheap. It is like the ground, and only checked for a
      unit near a rock.
    - Ship-against-ship needs shapes, so it is moderate.
    - Recommended: rocks solid in stage 4. Ship-against-ship comes with damage (item 16).
14. **Rocks have no gravity, shape or spin.**
    - Gravity (estimate, taking rock at 2 g/cm³): a 600 m rock pulls with about 0.0003 m/s² at its
      surface. That is a few times stronger than the difference in Frost's pull across it.
    - So it holds things only within about a kilometre, its Hill sphere, and is tiny beyond that.
      A ship approaching at walking pace barely feels it in the final minutes.
    - Real cost: cheap. It is one extra pull, applied only to a unit stepped within that kilometre.
      Anchoring (6) covers anything resting on the rock either way.
    - Recommended in stage 4, so a slow approach and anchoring are honest.
    - Shape: spheres in the sim, since generated models are visual only. Harmless.
    - Spin: real rocks tumble, which moves anchor points. Real cost: like planet rotation (item 4),
      cheap maths.
    - Owner's call.
15. **The planner's gaps.** Lambert across spheres of influence, and some eccentric or hyperbolic
    starts, are refused, not flown. That is not a physics shortcut, but it means the autopilot
    can't do some trips a player could fly by hand. Planned.

### Damage and structure

16. **No damage. A crash is free.** A crashed ship ends up landed and whole.
    - Real cost: moderate. The impact speed becomes damage to parts, as faults, using the
      durability the parts already have.
    - B and C set the rules. The physics side is only reporting the impact speed, which it
      already does.
17. **No acceleration limits.** Parts don't break under hard thrust or hard landings. Real cost:
    cheap, a check of acceleration each powered tick against a per-part limit in data.

### Power, heat and signals

18. **Solar output doesn't fall with distance from the star,** and panels don't need pointing.
    - Loses: power weaker further out, and stronger closer in.
    - Real cost: cheap, one inverse-square factor per unit when its distance changes. Pointing
      needs item 6.
    - Shadows have no partial shade (penumbra). That lasts seconds at these sizes, so it is
      harmless.
19. **Radiators reject a flat number of kW.**
    - Loses: radiators work better when hot, and worse in sunlight.
    - Real cost: moderate, a temperature per unit and rejection rising steeply with temperature.
      It changes heat balance, so B is involved.
20. **Instant communications, with no range.**
    - Light delay across Frost's system is a few hundredths of a second. Harmless.
    - Range and line of sight (KSP's CommNet) would matter only if control needed a link. Real
      cost: moderate.
    - Owner's call.

### Docking, building and fitting

21. **"At" is a flag, not a distance.** (this work) It becomes ranges (6).
22. **The arrival snap.** (this work) It goes (3.4).
23. **Docking takes fixed ticks once "at". A docked unit sits at its host's centre. Undocking has no
    separation.** (this work) These become the capture condition, an offset, and a separation push
    (3.4).
24. **Built hulls appear docked at a port, sharing the builder's orbit.** Physically that is right
    for something built in a dock. With the offset and the separation push it needs nothing more.
25. **Fitting is instant.** `attach_part` is done in one tick.
    - Loses: time to fit a part.
    - Real cost: small, work points like jobs, in data.
    - Owner's call, with C.
26. **A cycle's lap fuel is priced from the frame's straight-line routes (C18).** (this work) It
    becomes flown-ahead quotes on known future positions (4.2).

### Harmless, listed for completeness

27. **The star is fixed at the origin.** It stands in for the system's centre of mass. Harmless.
28. **Time steps of 0.1 s.** Burns and contacts are resolved to a tenth of a second. Harmless.
29. **Near-parabolic orbits.** These can't be held exactly, so a burn crossing escape speed carries
    a tiny amount forward a few ticks. Harmless.
30. **Bodies without gravity, such as rocks, cast no shadows.** Harmless at their size.

---

## 8. Determinism, integers, coasting and warp

- **Integers stay.** Positions are in mm and velocities in µm/s. The stepping carries its
  sub-millimetre remainders, as low flight does today. Plans, correction points and guidance
  choices are saved state, so a loaded save flies on identically.
- **Coasting skips** whatever is on rails between events, as it does now. The skip stops at:
  - the next planned burn;
  - a sphere boundary;
  - the ground;
  - a shadow edge;
  - a new event: entering a capture range or a closest approach.
  - Proximity is only watched for pairs where one unit has an order involving the other, so it
    doesn't cost every pair. The bound from relative speed works like A50's.
- **Stepped flight** (burns, descents, final approaches) is stepped. Each is 10.4 µs per unit per
  tick (measured).

**How warp feels (estimates):**
- At 100 times speed (1,000 ticks a second), a burning unit costs about 10 ms per real second. Six
  drones burning at once cost about 60 ms. That is fine.
- At 1,000 times speed, the same six drones would need about 0.6 s per real second. So warp drops
  while things burn, and climbs back when they coast. KSP does the same.
- Coasting rocks, stations and drones each cost one orbit position per stepped tick: 5 to 15 µs
  each (measured). For the new start's dozen or so objects that is about 0.2 ms per stepped tick.
  That is fine.
- **The honest risk** is fleets. Many drones running cheap, slow laps mostly coast and skip, which
  is fine. Many drones running fast laps burn often, and warp falls in proportion. Stage 0 times a
  six-drone fleet before stage 4 commits to it.

---

## 9. What breaks downstream

- **Contracts:**
  - frames and `at_target` are removed;
  - the route trip kind and its fields are removed;
  - plans become burn lists, with ops for each phase;
  - `land` and `take_off` become flown orders, with descent and climb ops;
  - quotes' details now come from flown-ahead runs;
  - new view fields for relative state (3.5);
  - the dock condition and its reasons (`too_far`, `too_fast`);
  - separation on undock.
  - A new contract version, through the Lead.
- **Save format.** No frames, and new plan and offset fields. All saves and new-start snapshots are
  regenerated.
- **Data (B):**
  - the thruster route fields go;
  - throttle minimums are added;
  - docking ports gain capture and separation limits;
  - instruments and miners gain ranges;
  - the new start's rocks and station get shared-size orbits round Frost;
  - fuel balance is redone for real trip costs. The run must still last a human player to the M4
    judgement.
- **Bots and playthrough.** The new-start bot's timings all change. Trips get slower, so every
  stage's end tick moves, and the playthrough is re-recorded.
- **Gameplay systems (C):**
  - cycles, mining, scan and measure move from the flag to ranges;
  - lap pricing moves to flown quotes;
  - C's own items (6).
- **Client (D):**
  - the local view is drawn from real relative positions, not a frame;
  - routes are drawn as predicted paths;
  - rendezvous readouts come from 3.5;
  - plan panels show burn lists;
  - quote and ETA text comes from flown quotes.
- **Tests.** The frame, route and join and leave tests are retired. Coast tests are rewritten
  round burns and proximity events. Expect several hundred tests to change.

---

## 10. The order of work

Each stage leaves the gate green and the game playable.

| Stage | What | Who | What changes for the player |
|---|---|---|---|
| **0** | Measure: precision of relative state at docking scale, the cost of a flown quote, and a six-drone fleet's warp. No game change. | A | Nothing |
| **1** | Relative-state tools: range, closing and lateral speed, closest approach, nodes, phase and window, burn duration and lead (3.5). These are additions to today's world. | A, then D | Rendezvous readouts appear |
| **2** | One integrator for powered flight: stepped thrust, steering modes, throttle, velocity Verlet, the 20/30 km seam replaced. | A, then B (throttle data) | Hand burns and landings are a little more exact |
| **3** | The autopilot flies: plans as burn lists, correction points, quotes flown ahead. This covers orbit-to-orbit and sphere-crossing trips first. | A, then C and D | Autopilot trips fire their engines. Prices are what's flown |
| **4** | No frames: rocks and station on real orbits, rendezvous trips between rocks, capture, offsets and separation, solid rocks with their own pull nearby, ranges for mine and scan, the arrival snap gone. | A, B, C and D together | The cluster is real. Trips take real time and fuel |
| **5** | Flown land and take-off, the real touchdown point, interpolated ground. | A, then D | Landing and take-off are flown |
| **6 onward** | In the owner's order, from section 7: planet rotation, damage, acceleration limits, solar falloff, radiator physics, rock spin, orientation, atmospheres, comms, finer terrain, more of the planner. | various | Each as listed |

Stage 4 is the big one: everything that touches the new start moves together. Stages 1 to 3 come
first so that the tools, the integrator and the flying autopilot are proven before the cluster
depends on them.

### Decisions for the owner

1. **The cluster's size, and how fast trips should feel** (3.1, 3.3). B balances fuel around this.
2. **Whether patched conics stay** (item 1). The Lead is asking.
3. **The order of section 7's remaining items,** especially planet rotation, damage, orientation
   and atmospheres.
4. **Mining by anchoring to the rock** (6), versus holding position near it. Anchoring is
   recommended: it is how real proposals work, and it is cheap.
