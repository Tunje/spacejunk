# Fictional Physics Rules

Status: draft for Lead approval (task B2). Changes after approval go through the Lead.

This gives the game's fictional technology stated laws, as section 5 of [spec.md](spec.md) requires. **Nothing here is in the slice.** No item, module or capability below goes into `data/` until the post-slice steps in workplan section 9 reach it, and any capability it needs is then a schema change through the Lead.

Numbers are starting points for later balance. The form of each rule is what this page fixes.

## 1. Principles

- **Declared, not implied.** Every technology here has `realism: fictional`. Real physics does not support any of it, and the game does not pretend otherwise.
- **The ledgers still hold.** Fictional technology obeys the matter, energy and heat ledgers. It moves matter and spends energy, and it never creates either.
- **Limits are engineering limits.** A capability is bought with hardware, power, cooling and materials, not by unlocking a level.
- **Failure has a reason.** Each threshold refuses with a stated reason or fails in a defined way, with the numbers shown.

## 2. Wormholes

A wormhole opens only if three thresholds are met at once: energy, stability and accuracy. Each depends on different hardware, so a strong reactor alone never makes a ship jump-capable.

### 2.1 Quantities

| Symbol | Meaning |
| ------ | ------- |
| `m` | Total mass passing through, in grams |
| `d` | Distance in whole light-years, at least 1 |
| `window` | Seconds the throat takes to open, a property of the Jump Coils |

### 2.2 Energy

```
jump_energy_j = m * d * JUMP_J_PER_G_LY
peak_power_w  = jump_energy_j / window
```

`JUMP_J_PER_G_LY` starts at 1000. The energy must be held in storage before the jump begins, and must be delivered within `window`. That makes three separate limits: stored energy, discharge rate and charging time. Supercapacitors earn their place here, since batteries hold the energy but cannot release it fast enough.

`JUMP_HEAT_PPM` of the energy, starting at 200000, enters the heat loop during the window, so radiators and heat capacity are a jump limit too.

The whole energy is spent once the window starts, whether or not the jump succeeds. It is consumed on the energy ledger, and the heat share is added on the heat ledger.

**Worked example.** A 100 t ship (10^8 g) jumping 10 light-years needs 10^12 J, about 278 MWh. A 60 s window needs about 17 GW of discharge. A 100 MW reactor takes about 2.8 hours to charge it, and 200 GJ of heat arrives within a minute. All of this fits the contract ranges of 10^15 J per store and 10^12 W.

### 2.3 Stability

```
required_stability = m * d / STABILITY_DIVISOR
```

Wormhole Stabilizers supply a summed rating at the entry, and Exit Stabilizers supply a summed rating at the exit. Each sum must meet `required_stability` on its own. Too little at the entry means the throat never forms. Too little at the exit means the ship cannot leave cleanly.

Stabilizers draw continuous power and produce heat throughout the jump, so power shedding or a fault can drop the rating partway through. Their `priority` matters.

### 2.4 Accuracy

```
exit_error_mm = d * BASE_ERROR_MM_PER_LY * ACCURACY_UNIT / navigation_rating
```

`navigation_rating` is the summed rating of navigation instruments and Wormhole Sensors, reduced as the destination fix ages. Exit error must not exceed `MAX_EXIT_ERROR_MM`, starting at 1 astronomical unit, measured from the target point. A jump is refused above that limit. Below it, the ship arrives offset from the target by a seeded amount up to `exit_error_mm`, drawn from a named RNG stream, so a better fix means a closer arrival and a shorter flight afterwards.

### 2.5 The six stages

| Stage | Hardware | Threshold | If it fails |
| ----- | -------- | --------- | ----------- |
| 1 Calculate destination | Navigation, Wormhole Sensors | Accuracy | Refused, nothing spent |
| 2 Charge | Reactor, storage | Energy, stored | Refused, charge kept |
| 3 Establish | Jump Coils, Wormhole Stabilizers | Energy delivered, entry stability | Throat collapses, energy spent, ship stays put |
| 4 Monitor transit | Wormhole Sensors, Inertial Dampeners, Time Compensation | Stability held | Ship exits early, offset and damaged |
| 5 Stabilize exit | Exit Stabilizers | Exit stability | Ship exits, damaged |
| 6 Verify arrival | Navigation | None | Position unknown until a new fix is taken |

Opening a wormhole gives off a gamma-ray burst, which is a radiation hazard for anything close to the entry or exit. Damage and hazard rules wait for the systems they depend on (workplan section 9).

### 2.6 Supporting hardware

- **Jump Coils** initiate the throat and set `window`. They do not navigate.
- **Wormhole Sensors** measure stability, resonance and nearby gravitational anomalies. Mass concentrations near the entry or exit raise `required_stability`.
- **Inertial Dampeners** have a rated mass. Transit stresses anything above that mass, and they protect the ship only, since there is no crew. This law applies during transit alone. They give no benefit in normal flight.
- **Time Compensation Systems** keep ship systems in step through transit. Without them, Stage 6 takes longer, because every clock on board needs resynchronizing. The simulation has one clock, and no unit ever runs ahead or behind it.

### 2.7 Three scales

The same laws give three roles.

| Role | Fits because |
| ---- | ------------ |
| Small ship | Low `m` keeps energy and stability cheap, so short hops are reachable. It can carry little storage, which limits `d`. |
| Dedicated jump vessel | Built around storage, coils and radiators to move heavy cargo or fleets. |
| Gateway station | Stationary, with a paired gateway at the destination. See below. |

**Gateways.** A pair holds a throat open, paying a large cost once to open it and a continuous power draw to keep it, in place of a per-ship energy charge. The entry and exit stabilizers are in the stations, so ships passing through need none. The far gateway has to be carried there first, by a jump vessel or the slow way, so a network grows outward one system at a time. Exit error does not apply between a paired gateway.

## 3. Entanglement comms

**Declared fiction.** Real quantum entanglement cannot carry a message. Measuring one half of an entangled pair shows nothing about what was done to the other half until an ordinary signal arrives. Quantum Entanglement Comms uses an invented mechanism that the game does not attribute to known physics. The player-facing description should say it is an unexplained property of a manufactured material, not standard quantum mechanics.

**Rules**

- **Made in pairs.** Both units come from one fabrication run and share one exotic resonator. A broken pair cannot be repaired or re-paired.
- **Carried by hardware.** Each unit must be physically transported to its endpoint, by normal flight or wormhole. Nothing reaches a place before hardware does, so this never gives faster-than-light exploration.
- **One to one.** A pair links exactly two points, with no broadcast. Reaching many sites takes many pairs, or relays between them.
- **Instant and narrow.** A message arrives on the same tick regardless of distance, but bandwidth is low. A pair carries orders and short status reports, not continuous telemetry.
- **Finite.** Each pair holds a fixed message budget. Every message spends some, and a spent pair is dead. Channel use is therefore a resource to plan.
- **Exotic cost.** A pair needs exotic Stage 4 materials. The exact inputs are set when it enters `data/`.

If the light-delay suggestion in workplan section 10 is adopted, this device is what lifts delay on one chosen link. It should stay rare enough that delay still shapes how the player organizes distant sites.

## 4. Handed on

| When | What |
| ---- | ---- |
| Workplan section 9, step 4 | These rules become capabilities, items and tests. Constants are set there. |
| Same step | Interstellar positions use a star-system ID plus local coordinates (workplan section 5). Transit changes the ID, and exit error is applied in local coordinates. |
| Same step | Jump energy, stability and heat are checked against contract ranges, including at gateway scale. |
