# Balance Report

Status: task B6, report stage. `data/` is unchanged. The owner chooses a pacing option, then B6 applies it. All figures are from the slice's first-pass data, measured on `main` at 9c74767. `data/` and `sim/` have not changed since.

## 1. Summary

- **A first full run takes 86 to 100 minutes at 1x and 13 to 23 minutes at 8x.** That is from a fresh start to all ten checks, for a person who makes no mistakes.
- **The first module arrives in 15 to 34 minutes at 1x, and 2.4 to 6 at 8x.** The low end is the iron-only Ore Container. A player following the goal order builds a Heat Radiator instead, which needs copper, so it takes over twice as long.
- **The fabricator sets the pace, not the rocks.** It runs for 65 of the 86 minutes, and one block of 24 processors takes 24 minutes. Halving rock distance saves only 5 minutes. Taking processors from 60 s to 20 s saves 16.
- **At 8x the limit is the person.** A first-timer spends about 14 of their 23 minutes giving orders, so no data change helps much there. A Basic Core takes one order at a time, and a trip is six orders.
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
| 6 | Install | 20.0 | 4.2 | 61.7 | 16.2 | 122.8 | 15.4 |
| 9 | Expand | 14.8 | 2.4 | 34.6 | 6.3 | 127.8 | 16.0 |
| 10 | Fitting limit fixed | 46.3 | 7.5 | 62.0 | 16.4 | 122.8 | 15.4 |
| 7 | Drone built | 59.5 | 8.8 | 71.5 | 18.0 | 132.8 | 16.6 |
| 8 | Handover, first lap done | **85.9** | **12.6** | **99.8** | **23.0** | 148.8 | 18.6 |

Checks 9 and 10 are listed where a person reaches them. Check 8 is always last, and includes the drone's first lap of 8.9 minutes at 1x.

The first-time player's Install is late because the radiator is held back until the laser has failed its fit. The bot beats the First-time 8x column because it needs no time to give orders, even though it waits for each step.

### First milestones

| Milestone | Practised 1x | Practised 8x | First-time 1x | First-time 8x |
| --------- | ------------ | ------------ | ------------- | ------------- |
| First module built | 14.7 | 2.4 | 34.3 | 6.1 |
| First drone | 59.5 | 8.8 | 71.5 | 18.0 |
| First expansion | 14.8 | 2.4 | 34.6 | 6.3 |

### Where the time goes

| Measure | Practised 1x | First-time 1x | Practised 8x | First-time 8x |
| ------- | ------------ | ------------- | ------------ | ------------- |
| Commands given | 52 | 55 | 52 | 55 |
| Time giving commands | 3.5 min | 13.8 min | 3.5 min | 13.8 min |
| Longest wait between commands | 7.5 min | 10.3 min | 1.3 min | 1.5 min |
| Ship's last unload | 20.2 min | 32.1 min | 4.3 min | 13.1 min |
| Fabricator running | 64.9 min | 69.9 min | 8.1 min | 8.7 min |
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
| No change | 85.9 | 99.8 | 12.6 | 23.0 |
| Scan 30 s to 10 s | 85.6 | 99.7 | 12.5 | 22.9 |
| Refining at half time | 83.3 | 94.0 | 12.3 | 22.8 |
| Rocks at half distance | 80.9 | 95.1 | 12.1 | 21.9 |
| Drone and cores at half time | 79.9 | 93.8 | 11.8 | 22.3 |
| Processor 60 s to 20 s | 70.0 | 83.8 | 10.6 | 21.0 |
| Processor 20 s, frame 15 s, wiring 10 s | 66.3 | 82.3 | 10.4 | 21.0 |

Scan time barely matters. Refining alone achieves little because the fabricator is still the limit, but it adds up once the fabricator is faster: Option A beats the sum of its parts.

## 7. Options

| Change | No change | A: materials | B: materials and modules | C: B plus nearer rocks |
| ------ | --------- | ------------ | ------------------------ | ---------------------- |
| Refining: hematite, chalcopyrite, olivine | 60, 60, 90 s | **30, 30, 45 s** | 30, 30, 45 s | 30, 30, 45 s |
| Frame, wiring, processor | 30, 20, 60 s | **15, 10, 20 s** | 15, 10, 20 s | 15, 10, 20 s |
| Drone, Basic Core, Assisted Core | 300, 120, 300 s | same | **150, 60, 150 s** | 150, 60, 150 s |
| Ore Storage, laser, radiator, Ore Container | 300, 180, 90, 120 s | same | **150, 90, 45, 60 s** | 150, 90, 45, 60 s |
| Scan | 30 s | same | **10 s** | 10 s |
| Red, Brass and Green Rock distance | 50, 50, 32 km | same | same | **25, 25, 16 km** |

| Result, in minutes | No change | A | B | C |
| ------------------ | --------- | - | - | - |
| All ten checks, practised, 1x | 85.9 | **57.7** | 48.3 | 42.4 |
| All ten checks, practised, 8x | 12.6 | **9.8** | 8.6 | 7.9 |
| All ten checks, first-time, 1x | 99.8 | **68.6** | 60.5 | 52.2 |
| All ten checks, first-time, 8x | 23.0 | **20.8** | 19.6 | 18.6 |
| First module, practised, 1x | 14.7 | **12.0** | 10.6 | 9.0 |
| First module, first-time, 1x | 34.3 | **24.1** | 21.3 | 19.6 |
| First drone, practised, 1x | 59.5 | **37.7** | 31.9 | 29.5 |
| First drone, first-time, 1x | 71.5 | **47.5** | 43.0 | 37.6 |
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

Option B goes further but makes the big builds trivial: at 8x a practised player sees all ten checks in under 9 minutes. Option C changes the most and saves the least for what it costs. It shortens the hauling the owner needs to judge, halves a propellant burn that is not a problem, and rewrites the trip table and end state. Rock distance should wait until the owner has judged hauling.

Leaving the data alone is a fair choice too, if the owner expects to play mostly at 4x and 8x, where a first run is already short.

### What a change touches

Every option changes the data hash, so existing saves fail to load with `data_mismatch`.

| Option | `data/` | `reference_scenario.md` | Tests |
| ------ | ------- | ----------------------- | ----- |
| A | 6 recipes | Parts B and C run ticks and totals. End state unchanged. | `test_job_durations_match_the_page` |
| B | 13 recipes, LIDAR | As A, plus Parts C to E and the scan steps. End state unchanged. | As A, plus `test_order_durations_match_the_page` |
| C | As B, plus `reference.json` | As B, plus the trip tables, stop points, lap ticks, end state and section 5 | As B, plus the checks on laps, propellant and end state, `test_reference_scenario.gd`, and the trip figures pinned in `tests/sim/networks/test_cargo.gd` |

## 8. Not fixed by any option

These are for the owner and the Lead. None of them is a data change.

- **The drone arrives after the hauling is over.** The ship's last unload is at 20 to 32 minutes of a run of 86 to 100, and from then on nothing flies. At handover the station already holds spare ore, up to 1900 kg of hematite, 1000 kg of chalcopyrite and 1400 kg of olivine. So the drone takes over a job the player stopped doing an hour earlier, and its ore is not yet needed. Option A shortens that gap but does not close it. This bears on M4's question of whether the handover is satisfying.
- **The Install hint blocks check 10 for a player who follows it.** It says to fit a Heat Radiator. With one fitted, the ship rejects 400 kW, so the second laser's 280 kW fits and the failure the Fix hint describes (280 of 200 kW) never happens. A third laser would then fail on power instead, at 472 kW of 420 kW, and fixing that needs a new power part. This run's first-time player holds the radiator back, so the table above does not show the problem.
- **The Install hint also points away from the cheap first module.** The Ore Container needs only iron, so it can be built from the first haul, while the radiator needs a copper trip. Naming it in the hint would fix the block above too, and should bring a new player's first module down from 34 minutes towards the practised 15, for no data change. That figure is an estimate, since the first-time run was not measured with this plan. The hint text is Agent D's.
- **Giving orders is the main cost at 8x.** Each trip needs six orders. Data cannot change that, but pausing to think would, as would an order queue or letting a Basic Core repeat a route. Those are design changes for after M4.
