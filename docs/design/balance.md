# Balance Report

Status: task B6, report stage. The owner chooses a pacing option, then B6 applies it. All figures are from the slice's first-pass data with the drone built from parts ([drone_from_parts.md](drone_from_parts.md)), measured on `main` at d5ad250. Section 9 measures the new start, task B23.

## 1. Summary

- **A first full run takes 87 to 105 minutes at 1x and 14 to 28 minutes at 8x.** That is from a fresh start to all ten checks, for a person who makes no mistakes.
- **The first module arrives in 15 to 34 minutes at 1x, and 2.4 to 6 at 8x.** The low end is the iron-only Ore Container. A player following the goal order builds a Heat Radiator instead, which needs copper, so it takes over twice as long.
- **The fabricator sets the pace, not the rocks.** It runs for 65 of the 87 minutes, and one block of 24 processors takes 24 minutes. Halving rock distance saves only 5 minutes. Taking processors from 60 s to 20 s saves 16.
- **At 8x the limit is the person.** A first-timer spends about 19 of their 28 minutes giving orders, so no data change helps much there. A Basic Core takes one order at a time, and a trip is six orders.
- **Propellant is not a problem.** A run to all ten checks burns 354 to 476 kg of the 5000 kg. One drone can then run for about 32 game hours, or 4 real hours at 8x.
- **Recommendation: Option A,** faster refining and materials only. It takes about a third off the 1x time and cuts the longest wait from 7.5 minutes to 5. It leaves hauling, the drone lap and propellant as they are, and it is the smallest change to the reference chain.

## 2. How this was measured

`tools/balance_run.gd` prints every figure here, and takes about 15 minutes. It drives the real `Sim` and scores progress with the client's `GoalTracker`, so a check means what it means on the player's screen. Options are applied in memory.

The reference bot runs one step at a time and gives orders instantly, so it does not show a person's time. `tools/person_run.gd` plays as a person does: the ship, the refinery and the fabricator all run at once, but one pair of hands gives one command at a time. Each command takes a think time, and the game keeps running at the chosen speed meanwhile.

| Player | Think time per command | Plan |
| ------ | ---------------------- | ---- |
| **Practised** | 4 s | Reads the recipes ahead. Three trips, one per ore. Builds the Ore Container first. Expands the station with a second container. |
| **First-time** | 15 s | Uses the reference chain's shopping list. Four trips. Builds the radiator and laser first. Expands with Ore Storage. |

**Treat these as lower bounds for a real person.** The think times are guesses. Neither player makes a mistake, explores the screens or reads anything, and each keeps one speed throughout. A real run at mixed speeds falls somewhere between the two speed columns, and the owner's playtest is the real test.

## 3. Time to each check

Minutes of real time from a fresh start. The bot has no think time and runs one step at a time.

| # | Check | Practised 1x | Practised 8x | First-time 1x | First-time 8x | Bot 1x | Bot 8x |
| - | ----- | ------------ | ------------ | ------------- | ------------- | ------ | ------ |
| 1 | Scan | 2.5 | 0.5 | 3.1 | 1.0 | 2.3 | 0.3 |
| 2 | Mine | 2.6 | 0.6 | 3.3 | 1.3 | 4.0 | 0.5 |
| 3 | Haul | 6.4 | 1.2 | 7.7 | 2.5 | 6.6 | 0.8 |
| 4 | Refine | 8.2 | 1.5 | 9.6 | 3.0 | 25.8 | 3.2 |
| 5 | Fabricate | 8.7 | 1.6 | 10.4 | 3.1 | 70.3 | 8.8 |
| 6 | Install | 20.0 | 4.3 | 61.0 | 21.2 | 122.8 | 15.4 |
| 9 | Expand | 14.8 | 2.4 | 34.6 | 6.3 | 127.8 | 16.0 |
| 10 | Fitting limit fixed | 46.3 | 7.4 | 61.2 | 21.4 | 122.8 | 15.4 |
| 7 | Drone working | 60.7 | 10.2 | 76.8 | 22.8 | 132.9 | 16.6 |
| 8 | Handover, first lap done | **87.1** | **14.0** | **105.0** | **27.8** | 148.8 | 18.6 |

Checks 9 and 10 are listed where a person reaches them. Check 8 is always last, and includes the drone's first lap of 8.9 minutes at 1x.

Check 7 finishes when the last part a drone needs is fitted. The first-time player's Install is late because the radiator is held back until the laser has failed its fit. The Install hint now names the Ore Container, so a player who follows it should reach Install sooner than this column, though that is not measured. The bot beats the First-time 8x column because it needs no time to give orders, even though it waits for each step.

### First milestones

| Milestone | Practised 1x | Practised 8x | First-time 1x | First-time 8x |
| --------- | ------------ | ------------ | ------------- | ------------- |
| First module built | 14.7 | 2.4 | 34.3 | 6.1 |
| First small craft docked | 48.5 | 5.4 | 45.7 | 13.7 |
| First drone working | 60.7 | 10.2 | 76.8 | 22.8 |
| First expansion | 14.8 | 2.4 | 34.6 | 6.3 |

### Where the time goes

| Measure | Practised 1x | First-time 1x | Practised 8x | First-time 8x |
| ------- | ------------ | ------------- | ------------ | ------------- |
| Commands given | 73 | 76 | 73 | 76 |
| Time giving commands | 4.9 min | 19.0 min | 4.9 min | 19.0 min |
| Longest wait between commands | 7.5 min | 10.3 min | 1.3 min | 1.5 min |
| Ship's last unload | 20.2 min | 32.1 min | 4.5 min | 18.1 min |
| Fabricator running | 64.9 min | 69.8 min | 8.1 min | 8.7 min |
| Refinery running | 38.9 min | 44.9 min | 4.9 min | 5.6 min |

The station's 300 kW of solar and its battery carry the refinery and fabricator together. No load was shed and no job ran out of goods space in any run.

## 4. Lap yield against station demand

The "6.5 minutes" per lap is the ship's: 6.1 minutes a trip, or 6.6 with a scan. The drone's lap is longer.

| Hauler | Lap | Ticks | 1x | 8x | Load | Ore per minute at 1x | Propellant a lap | Ore per kg of propellant |
| ------ | --- | ----- | -- | -- | ---- | -------------------- | ---------------- | ------------------------ |
| Ship, Red Rock | Trip, no scan | 3668 | 6.1 min | 46 s | 2000 kg | 327 kg | about 127 kg | 15.7 kg |
| Drone, Red Rock | Lap 2 onward | 5340 | 8.9 min | 67 s | 500 kg | 56 kg | 18.2 kg | 27.4 kg |

The ship also costs six commands a trip, so at 4 s each it delivers about 307 kg a minute. The drone costs none.

| Station use, at 1x | Takes in | Gives out |
| ------------------ | -------- | ---------- |
| Refinery, hematite | 100 kg ore a minute | 69 kg iron |
| Refinery, chalcopyrite | 100 kg ore a minute | 34 kg copper |
| Refinery, olivine | 67 kg ore a minute | 12.7 kg silicon |
| Fabricator, frames | 100 kg iron a minute | 2 frames |
| Fabricator, wiring | 30 kg copper a minute | 3 wiring |
| Fabricator, processors | 4 kg silicon, 1 kg copper a minute | 1 processor |

- **The ship outruns the refinery threefold.** Ore piles up, so the refinery is the first limit on supply and the fabricator is the last.
- **One drone feeds 56% of one refinery.** It gives 39 kg of iron a minute, or 0.78 frames. It takes two drones to keep the refinery busy on hematite.
- **One refinery cannot keep the fabricator busy on frames,** at 69 kg of iron against 100.
- **A drone repays its frames in 1.2 laps,** about 10 minutes at 1x. It brings no copper or silicon on this cycle, so the rest of its cost must come from the ship or a cycle to another rock.

## 5. Propellant runway

Figures for the end of a run, on the tick of the first `task_cycle_done`.

| | Practised | First-time |
| | --------- | ---------- |
| Ship burn | 335 kg | 458 kg |
| Drone burn, one lap | 18 kg | 18 kg |
| Depot left | 3895 kg | 3895 kg |
| Ship tank left | 665 kg | 542 kg |

From a depot of 3895 kg, with no more hand trips:

| Drones running | Burn per game hour | Game hours to empty | Real hours at 8x |
| -------------- | ------------------ | ------------------- | ---------------- |
| 1 | 123 kg | 31.7 | 4.0 |
| 2 | 246 kg | 15.8 | 2.0 |
| 4 | 492 kg | 7.9 | 1.0 |

Propellant runs out before the ore does: one drone would bring back about 107 t of the 200 t of hematite. The allowance in [reference_scenario.md](reference_scenario.md) section 5 stays sound, since a run used 354 to 476 kg against the 3092 kg set aside, and **no propellant change is needed**. The one case to watch is several drones left at 8x. The slice cannot make more propellant, so that run ends with `no_propellant` in about an hour with four drones.

## 6. What each lever does on its own

Minutes to all ten checks, each lever changed alone.

| Lever | Practised 1x | First-time 1x | Practised 8x | First-time 8x |
| ----- | ------------ | ------------- | ------------ | ------------- |
| No change | 87.1 | 105.0 | 14.0 | 27.8 |
| Scan 30 s to 10 s | 86.8 | 105.0 | 13.9 | 27.7 |
| Refining at half time | 84.7 | 99.2 | 13.8 | 27.6 |
| Rocks at half distance | 82.1 | 100.3 | 13.6 | 26.6 |
| Drone parts and cores at half time | 81.1 | 99.3 | 13.0 | 27.3 |
| Processor 60 s to 20 s | 71.2 | 89.0 | 12.0 | 25.8 |
| Processor 20 s, frame 15 s, wiring 10 s | 67.5 | 83.4 | 10.8 | 25.8 |

Scan time barely matters. Refining alone achieves little because the fabricator is still the limit, but it adds up once the fabricator is faster: Option A beats the sum of its parts.

## 7. Options

| Change | No change | A: materials | B: materials and modules | C: B plus nearer rocks |
| ------ | --------- | ------------ | ------------------------ | ---------------------- |
| Refining: hematite, chalcopyrite, olivine | 60, 60, 90 s | **30, 30, 45 s** | 30, 30, 45 s | 30, 30, 45 s |
| Frame, wiring, processor | 30, 20, 60 s | **15, 10, 20 s** | 15, 10, 20 s | 15, 10, 20 s |
| Drone parts in all, Basic Core, Assisted Core | 300, 120, 300 s | same | **150, 60, 150 s** | 150, 60, 150 s |
| Ore Storage, laser, radiator, Ore Container | 300, 180, 90, 120 s | same | **150, 90, 45, 60 s** | 150, 90, 45, 60 s |
| Scan | 30 s | same | **10 s** | 10 s |
| Red, Brass and Green Rock distance | 50, 50, 32 km | same | same | **25, 25, 16 km** |

| Result, in minutes | No change | A | B | C |
| ------------------ | --------- | - | - | - |
| All ten checks, practised, 1x | 87.1 | **59.1** | 48.7 | 43.7 |
| All ten checks, practised, 8x | 14.0 | **10.5** | 9.8 | 9.0 |
| All ten checks, first-time, 1x | 105.0 | **72.6** | 63.4 | 56.9 |
| All ten checks, first-time, 8x | 27.8 | **25.6** | 24.6 | 23.6 |
| First module, practised, 1x | 14.7 | **12.0** | 10.6 | 9.0 |
| First module, first-time, 1x | 34.3 | **24.1** | 21.3 | 19.6 |
| First drone working, practised, 1x | 60.7 | **39.2** | 32.3 | 30.8 |
| First drone working, first-time, 1x | 76.8 | **51.2** | 45.5 | 42.3 |
| First expansion, first-time, 1x | 34.6 | **24.4** | 21.4 | 19.9 |
| Longest wait, practised, 1x | 7.5 | **5.1** | 3.4 | 3.4 |
| Longest wait, first-time, 1x | 10.3 | **5.3** | 3.6 | 3.6 |

| Effect | No change | A | B | C |
| ------ | --------- | - | - | - |
| Ship round trip to Red Rock | 6.1 min | same | same | 4.5 min |
| Drone lap | 8.9 min | same | same | 5.6 min |
| Drone ore per minute at 1x | 56 kg | same | same | 90 kg |
| Drone share of a refinery on hematite | 56% | 28% | 28% | 45% |
| Propellant, ship over the chain | 458 kg | same | same | 229 kg |
| Propellant, drone lap | 18.2 kg | same | same | 9.0 kg |
| Game hours of depot for one drone | 31.7 | same | same | 40.2 |

### Recommendation: Option A

Option A goes after the actual bottleneck, and is enough to bring the longest wait down to about 5 minutes at 1x. It keeps the laser, the drone and the cores as long builds that feel like milestones, and it does not touch the hauling that M4 asks about.

Option B goes further but makes the big builds trivial: at 8x a practised player sees all ten checks in under 10 minutes. Option C changes the most and saves the least for what it costs. It shortens the hauling the owner needs to judge, halves a propellant burn that is not a problem, and rewrites the trip table and end state. Rock distance should wait until the owner has judged hauling.

Leaving the data alone is a fair choice too, if the owner expects to play mostly at 4x and 8x, where a first run is already short.

### What a change touches

Every option changes the data hash, so existing saves fail to load with `data_mismatch`.

| Option | `data/` | `reference_scenario.md` | Tests |
| ------ | ------- | ----------------------- | ----- |
| A | 6 recipes | Parts B and C run ticks and totals. End state unchanged. | `test_job_durations_match_the_page` |
| B | 19 recipes, LIDAR | As A, plus Parts C to E and the scan steps. End state unchanged. | As A, plus `test_order_durations_match_the_page` |
| C | As B, plus `reference.json` | As B, plus the trip tables, stop points, lap ticks, end state and section 5 | As B, plus the checks on laps, propellant and end state, `test_reference_scenario.gd`, and the trip figures pinned in `tests/sim/networks/test_cargo.gd` |

## 8. Not fixed by any option

These are for the owner and the Lead. None of them is a data change.

- **The drone arrives after the hauling is over.** The ship's last unload is at 20 to 32 minutes of a run of 87 to 105, and from then on nothing flies. At handover the station already holds spare ore, up to 1900 kg of hematite, 1000 kg of chalcopyrite and 1400 kg of olivine. So the drone takes over a job the player stopped doing an hour earlier, and its ore is not yet needed. Option A shortens that gap but does not close it. This bears on M4's question of whether the handover is satisfying.
- **Giving orders is the main cost at 8x.** Each trip needs six orders, and each drone at least 12 for its jobs and fits, with no way to repeat them. Data cannot change that, but pausing to think would, as would an order queue or letting a Basic Core repeat a route. Those are design changes for after M4.

## 9. The new start

Sections 1 to 8 measure `reference.json`, the station fixture. This section measures `new_start.json`, where the player starts with only the probe ([new_start_chain.md](new_start_chain.md)). Measured on `design/B23` with C22 on `main`, at seed 12345 (task B23).

### 9.1 How this was measured

`tools/new_start_pace.gd` plays C's `NewStartBot` route through all six stages on the real `Sim`.
- It records the tick of each of the route's 114 commands.
- It records each goal's tick, scored by the client's `GoalTracker` with the new-start goal list.
- `NewStartPace.pace()` then prices that record for a person.
- `tools/new_start_balance.gd` prints every figure below in about 90 seconds.
- `tests/tools/test_new_start_pace.gd` tests the pricing.

The pricing has three parts:
- **Think time.** Each command takes `think_s` real seconds, and the game keeps running meanwhile. When the bot gave its next order sooner than a person could, the chain slips by the difference. The bot runs one step at a time, so its game time is a floor, and the slips are added on top.
- **Speed.** The game runs at the chosen speed between orders.
- **Warp.** A wait that has lasted `warp_after_s` real seconds past the think time is warped at 1000× for the rest, as C17's coast lets a person do. "No warp" never does.

**Treat these as lower bounds,** as in section 2. The person follows the bot's route exactly, never makes a mistake and never explores. The client also drops out of warp on events that need attention, and that isn't modelled.

### 9.2 Time to each goal

Minutes of real time from a fresh start.

| # | Goal | Practised 8x, warps | First-time 8x, warps | First-time 1x, warps | Practised 8x, no warp | Bot, 1x |
| - | ---- | ------------------- | -------------------- | -------------------- | --------------------- | ------- |
| 1 | Scan a rock | 0.3 | 0.6 | 1.5 | 0.3 | 2.1 |
| 2 | First science points | 0.3 | 0.6 | 1.5 | 0.3 | 2.1 |
| 3 | Mine ore | 0.3 | 0.8 | 1.5 | 0.3 | 2.1 |
| 4 | Refine ore | 0.8 | 1.5 | 3.3 | 0.9 | 5.8 |
| 5 | Fabricate a component | 0.8 | 1.6 | 3.3 | 1.0 | 6.8 |
| 6 | Build a station | 3.2 | 8.6 | 12.9 | 13.1 | 96.2 |
| 7 | Install a part on something built | 3.3 | 8.8 | 13.2 | 15.2 | 112.2 |
| 8 | Hit a fitting limit and fix it | 3.7 | 10.0 | 14.7 | 15.8 | 115.2 |
| 9 | Haul ore to the station | 4.0 | 10.7 | 15.7 | 16.3 | 119.2 |
| 10 | Prove a new tech | 9.4 | 23.9 | 33.8 | 92.0 | 715.8 |
| 11 | Build a mining drone | 12.2 | 32.5 | 44.4 | 104.5 | 802.0 |
| 12 | Hand the job to an AI core | 12.8 | 34.5 | 46.4 | 106.4 | 814.3 |
| 13 | Expand the station | **13.3** | **36.3** | **48.2** | **111.3** | **851.6** |

| | Practised 8x, warps | First-time 8x, warps | First-time 1x, warps | Practised 8x, no warp |
| - | ------------------- | -------------------- | -------------------- | --------------------- |
| Think time per order | 4 s | 15 s | 15 s | 4 s |
| Warp after | 10 s | 30 s | 30 s | never |
| Game time, with slips | 14.8 h | 17.0 h | 14.5 h | 14.8 h |
| Real time warped | 0.8 min | 0.7 min | 0.8 min | 0 |
| Giving orders: 114 × think time | 7.6 min | 28.5 min | 28.5 min | 7.6 min |

### 9.3 What it shows

- **With warp, a first full run takes about 13 to 36 minutes at 8x, and 48 at 1x.** That's from a fresh start to all 13 goals, for a person who makes no mistakes. It's about as long as the station fixture at 8x (section 1: 14 to 28 minutes for ten checks), with three more goals and a whole station to build.
- **Warp is what makes the new start playable.**
  - The gravity lap is 6.8 of the chain's 14.2 game hours. At 8x without warp it's 51 real minutes, and goal 10 comes at 92 minutes, not 9 to 34.
  - With warp the whole lap costs about 25 real seconds.
  - Every long facility wait is warped the same way: the processors' 2.1 hours, and the drone's materials.
- **At 8x with warp, the limit is the person.** 114 orders take 7.6 to 28.5 minutes of think time, most of each run. A first-timer's slower orders also cost 2.8 game hours of slips, because the facilities sit idle while they decide. As section 1 found for the fixture, no data change helps much there. Fewer, bigger orders would: queued jobs, and the Assisted Core's cycles, which already take the drone's 7-step lap off the player.
- **The first station takes 3 to 13 minutes.** That's the seed factory's first big build, 12,000 ticks at compact speed. It's the first real wait, and the first point a person warps.
- **The bot's 14.2 game hours is not a person's time.** At 1x with no warp it's 14 real hours, but nobody plays that way.

### 9.4 Propellant runway

From new_start_chain.md sections 3 to 5:
- **The probe never runs short on the route.** It ends Part C with 2,110 kg, reaches goal 9 with 1,701 kg (C18 measures the gravity field from the cluster, with no landing), and ends with 862 kg after filling the depot. Ice makes any shortfall back: 100 kg of ice is 51 ticks of mining and 1,200 of refining for 90 kg.
- **Landing on Frost is the one propellant risk.** It's optional on this route, and the reason for it is Photovoltaic Arrays (research.md 5.1). Following the hint (ice top-up, goods unloaded, leave from the station) the probe gets back with about 227 m/s spare. Without the top-up it strands. The land check's `cannot_return` warning (A39) catches that case.
- **The drone.** A lap burns 28.8 kg for 500 kg of hematite. At the end of Part F the 337 kg depot would last about 11 laps, about 2.2 game hours.

### 9.5 Does the loop sustain itself?

The owner's premise is that cores automate. Part F2 (new_start_chain.md, planned as C24 then C23) adds:
- a compact refinery on the station, in place of the idle LIDAR;
- two standing jobs on it, ice to propellant and hematite to iron, which C24's starved-queue skip lets one refinery run together;
- an ice leg in the drone's cycle.

Estimated per cycle, to be replaced by C23's measurements:

| | Per cycle |
| - | --------- |
| Cycle length | about 14,500 ticks, 24 game minutes |
| Propellant burned | 28.8 kg hematite leg + about 22 kg ice leg |
| Propellant made | about 166 kg from 184 kg of ice |
| Depot | **about +115 kg**: it fills, and never runs the drone dry |
| Hematite in, iron out | 500 kg in, 345 kg of iron to the goods container |
| Refinery busy | about 2,200 ticks on ice, 6,000 on hematite, before shadow pauses |

**Propellant: sustained.** The ice leg more than pays for both legs.

**Ore: delayed, not steady.** This is the honest limit.
- The iron job drains the ore stores into the 2,000 kg goods container. That fills in about 5.8 cycles.
- Then the hematite job waits on `output_full`, and the 4,000 kg of ore stores fill in about 8 more cycles.
- At **about 14 cycles, 5.6 game hours** after F2 starts, the drone can't unload, and its cycle stops.
- Without the iron job it would stop after about 8 cycles, 3.2 hours. So the iron job buys about 2.4 hours, but it doesn't hold the loop steady.
- At 8x with warp, 5.6 game hours is about 20 real seconds of warp. So a person meets the full store soon after F2, unless they act.
- **A steady loop needs something to use the iron:** the player hauling it away, or a fabricator on the station. The station has no free side for one, so that's another station or hub module. Running out of room is the push to expand, and it's the player's next decision, not a bug.

### 9.6 Where the orders go (B24)

NewStartPace's record lists each of the route's 114 orders with its type and stage. For a first-timer each order costs about 15 s, so 28.5 of their 36.3 minutes go on giving orders. The orders bunch into five kinds of stretch.

| Stretch | Orders | First-timer think time | What the orders are |
| ------- | ------ | ---------------------- | ------------------- |
| Mining trips | 39 | 9.8 min | 10 `move_to`, 4 `scan`, 3 composition `measure`s, 12 `start_mining`, and 10 `stop` to take a set amount |
| Fabrication queues | 37 | 9.3 min | One `queue_job` per component and part. The biggest burst is the drone's 15 orders at tick 433,655 |
| Refining queues | 13 | 3.3 min | One `queue_job` per ore after each trip |
| Fitting | 15 | 3.8 min | 13 `attach_part` (8 for the drone, 5 for goal 7's fail and fix), 2 `assign_core` |
| Moving goods between docked units | 8 | 2.0 min | 4 `unload_cargo` so the station's lab has its inputs, 2 `load_cargo` of the station's hematite back to the probe's refinery, the depot fill, the first haul |
| Other | 2 | 0.5 min | `set_cycle`, and the gravity-field `measure` |

**Five ways to cut orders, ranked by first-timer saving.** Each saving is the orders removed at 15 s each, and the five overlap a little.

1. **A one-shot trip plan, saving about 7 min.** One order does what a mining trip does now: move to a rock, survey it and take its composition where not yet paid, then mine a set amount. That takes the 39 trip orders down to about 10.
   - **Sim (C):** a cycle that runs once, or a short plan the probe's Basic Core runs, from the same whitelist of steps as `set_cycle`.
   - **Client (D):** a trip panel.
   - **A quick win inside it:** a mine amount on `start_mining` in the client (D's C19 item) removes the 10 `stop` orders alone, saving 2.5 min.
2. **Build a design, saving about 6 min.** One order queues a part, hull or station and every component it needs: frames, wiring, processors and cores, in dependency order, from the recipes. The drone's 15-order burst becomes 1 or 2, and the 37 fabrication orders become about 13.
   - **Client (D):** a "Build with components" button that sends the expanded `queue_job` list, with no sim change.
   - **Data (B):** a `mining_drone` design that lists the drone's eight parts and their connectors. Today `small_craft` is only the hull and port, so the client has nothing to expand.
3. **Refine for the queue, saving about 2.5 min.** The same button also queues the refining its shortfall needs, from ore on hand. That takes the 13 refine orders to about 3.
   - **Client (D)** first, in the same button.
   - **Later, sim (C):** a standing "supply" refinery job, now that C24's queue skip exists.
4. **Fit a design, saving about 2 min.** Each part goes in place on the new hull as it's made, so the drone's 8 `attach_part` orders and its `assign_core` go. The station's fail-and-fix fits stay, since they are goal 7.
   - **Sim (C):** let `install_to` name a hull still in the same queue, or have the build-a-design order carry install targets.
   - **Or client (D):** a "Fit all from the design" button on a new hull, using the data design from item 2.
5. **Jobs draw inputs from the docked group, saving about 1.5 min.** A lab or refinery job takes its inputs from any unit in the docked group, as C21 already lets fitting do. That removes the 4 unloads before the lab's runs and the 2 hematite loads, 6 orders.
   - **Sim (C):** a contract change through the Lead.

**Together, about 19 of the first-timer's 28.5 minutes of orders,** with the route down from 114 orders to about 35. A first-timer's run at 8x with warp would drop from about 36 minutes to about 17, close to a practised player's today. Items 1 and 2 are most of it.

A smaller item: prove, prototype and qualify are three orders at two facilities. A "develop this design" order could make them one, saving 0.5 min. It isn't worth doing before the five above.
