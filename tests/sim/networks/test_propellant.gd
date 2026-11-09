extends "res://tests/sim/networks/landing_fixture.gd"
## Two-propellant burns (task A61): a thruster's mixture splits every gram a burn, a trip or a landing
## spends across its propellants in ratio, and any one running out stops it, so an excess of the other
## is unusable until rebalanced (the Lead's ruling). The ship's chemical thruster and tank are patched
## here to hydrolox, 1 part hydrogen to 6 of oxygen, as B30b's data will be.

const HYDROLOX := { "hydrogen": 1, "oxygen": 6 }


func _hydrolox(hydrogen_g: int, oxygen_g: int) -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	var modules: Dictionary = sim._ctx.defs["modules"]
	modules["chemical_thruster_mk1"]["capabilities"]["thruster"]["mixture"] = HYDROLOX.duplicate()
	modules["propellant_tank_mk1"]["capabilities"]["storage"] = {
		"fuel": { "mass_g": 200_000_000, "volume_l": 3_000_000 },
		"oxidiser": { "mass_g": 2_000_000_000, "volume_l": 2_000_000 },
	}
	var inventory: Dictionary = _ship()["inventory"]
	inventory.erase("propellant")
	inventory["hydrogen"] = hydrogen_g
	inventory["oxygen"] = oxygen_g
	sim._ctx.index.clear()
	sim._state["matter_start_g"] = sim.ledger()["matter"]["total_g"]


func _burn(dv_um_s: int) -> Dictionary:
	return { "type": "plan_burn", "unit": keys["Ship"], "args": { "tick": sim.current_tick() + 1,
		"prograde_um_s": dv_um_s, "normal_um_s": 0, "radial_um_s": 0 } }


func test_the_split_keeps_the_ratio_and_sums_exactly() -> void:
	assert_eq(Propellant.split(7000, HYDROLOX), { "hydrogen": 1000, "oxygen": 6000 })
	for total: int in [0, 1, 6, 10, 12_345]:
		var shares := Propellant.split(total, HYDROLOX)
		assert_eq(int(shares["hydrogen"]) + int(shares["oxygen"]), total)
		assert_lte(int(shares["hydrogen"]), total / 7 + 1)
	assert_eq(Propellant.split(500, Propellant.LEGACY), { "propellant": 500 })


func test_the_scarcest_propellant_sets_what_is_usable() -> void:
	_hydrolox(100_000, 1_000_000)
	var mixture := Propellant.mixture_of(sim._ctx, keys["Ship"])
	assert_eq(mixture, HYDROLOX)
	assert_eq(Propellant.usable_g(sim._ctx, keys["Ship"], mixture), 700_000, "100 kg of hydrogen allows 700 kg")
	assert_true(Propellant.fits(sim._ctx, keys["Ship"], mixture, 700_000))
	assert_false(Propellant.fits(sim._ctx, keys["Ship"], mixture, 700_007), "the oxygen's excess is unusable")


func test_a_burn_spends_both_in_ratio() -> void:
	_hydrolox(100_000, 600_000)
	sim.submit(_burn(10_000_000))
	var done := _until("burn_done", 3000)
	assert_false(done.is_empty())
	var spent: int = done["data"]["propellant_g"]
	var inventory: Dictionary = _ship()["inventory"]
	var used_h := 100_000 - int(inventory.get("hydrogen", 0))
	var used_o := 600_000 - int(inventory.get("oxygen", 0))
	assert_eq(used_h + used_o, spent)
	assert_almost_eq(used_o, 6 * used_h, 6 * 300, "6 to 1, to within a gram a tick")
	var sink: Dictionary = sim._state["sinks"][Travel.SINK]
	assert_eq(sink["hydrogen"], used_h)
	assert_eq(sink["oxygen"], used_o)
	assert_eq(sim.ledger()["violations"], PackedStringArray(), "matter balances")


## Plenty of oxygen, little hydrogen: the burn ends short when the hydrogen runs out, and the check's
## flight ahead ends it on the same tick.
func test_running_out_of_one_ends_the_burn_and_check_foresees_it() -> void:
	_hydrolox(3_000, 1_000_000)
	var command := _burn(50_000_000)
	var checked := sim.check(command)
	assert_eq(checked["detail"].get("short", ""), "no_propellant")
	sim.submit(command)
	var short := _until("burn_short", 3000)
	assert_eq(short["data"]["reason"], "no_propellant")
	assert_eq(short["data"]["propellant_g"], checked["detail"]["propellant_g"], "the check flew the same burn")
	assert_lt(int(_ship()["inventory"].get("hydrogen", 0)), 3_000 / 7 + 10, "the hydrogen is spent")
	assert_gt(int(_ship()["inventory"].get("oxygen", 0)), 900_000, "most of the oxygen is left, unusable")


func test_without_a_mixture_the_single_item_burns() -> void:
	assert_eq(Propellant.mixture_of(sim._ctx, keys["Ship"]), Propellant.LEGACY)
	var before: int = _ship()["inventory"]["propellant"]
	sim.submit(_burn(5_000_000))
	var done := _until("burn_done", 3000)
	assert_eq(before - int(_ship()["inventory"]["propellant"]), done["data"]["propellant_g"])
