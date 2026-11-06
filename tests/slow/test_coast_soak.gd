extends GutTest
## The coast soak's fixed gate seeds (task A35): each runs a random game once stepped and once
## coasted and compares them at every coast return. tools/coast_soak.gd runs many more seeds.
## Seed 1 is D's shadow edge case on the new start; 4 and 8 burn, 8 with a hot loop; 6 just laps. Seeds
## that land and take off run 20 to 30 seconds each, so they are left to the deep run.

const CoastSoak := preload("res://tests/sim/kernel/coast_soak.gd")
const SEEDS := [1, 4, 6, 8]
const TICKS := 8_000


func test_the_gate_seeds_coast_exactly_as_they_step() -> void:
	for seed: int in SEEDS:
		var result: Dictionary = CoastSoak.run_seed(seed, TICKS)
		gut.p("seed %d: %d ticks in %d coast calls, capped by %s, events %s" % [seed, result["ticks"], result["calls"], str(result["caps"]), str(result["events"])])
		assert_true(result["ok"], result["message"])
