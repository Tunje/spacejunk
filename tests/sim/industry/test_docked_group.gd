extends GutTest
## C21: attach_part and copy_fit take parts from any unit in the docked group, the units joined
## through dock records followed both ways. Part E's case: the probe and a bare drone both docked at
## the station, with the drone's parts in the probe's hold.

const STATION := 8
const SHIP := 23
const FREE_PORT := 11
const SOLAR := "small_solar_panel_mk1"
const DRONE_FITS: Array[Array] = [
	["small_solar_panel_mk1", "side_a_px", "hull"], ["small_heat_radiator_mk1", "side_a_nx", "hull"],
	["small_propellant_tank_mk1", "stack_bottom", "hull"],
	["small_chemical_thruster_mk1", "stack_bottom", "small_propellant_tank_mk1"],
	["small_ore_container_mk1", "side_a_pz", "hull"], ["small_mining_laser_mk1", "side_a_nz", "hull"],
	["assisted_core", "core", "hull"],
]

var sim: Sim
var state: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state


func _count_matter() -> void:
	sim._ctx.index.clear()
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]


func _give(unit: int, item: String) -> void:
	Units.add_stock(state["units"][unit]["inventory"], item, sim._ctx.defs["items"][item]["unit_mass_g"])
	_count_matter()


## A bare drone docked at the station's free port.
func _drone() -> int:
	var id := Units.create(sim._ctx, "small_craft", "Drone", state["units"][STATION]["pos_mm"])
	state["units"][id]["dock"] = { "port": Units.ports(state, sim._ctx.defs, id)[0],
		"target_unit": STATION, "target_port": FREE_PORT }
	state["units"][id]["at_target"] = STATION
	_count_matter()
	return id


## A unit with a hand-set dock record, enough for the group walk.
func _bare(target: int = 0) -> int:
	var id := Units.create(sim._ctx, "small_craft", "Bare", [0, 0, 0])
	if target != 0:
		state["units"][id]["dock"] = { "port": 0, "target_unit": target, "target_port": 0 }
	_count_matter()
	return id


func _attach(unit: int, from: int) -> Dictionary:
	return { "type": "attach_part", "unit": unit, "args": { "item": SOLAR, "from": from,
		"parent_part": state["units"][unit]["root"], "parent_connector": "side_a_px", "part_connector": "mount" } }


func _run(command: Dictionary) -> Array[Dictionary]:
	sim.submit(command)
	sim.step()
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"], "matter balances")
	assert_eq(ledger["violations"], PackedStringArray())
	return sim.take_events()


func test_the_group_follows_dock_records_both_ways_sorted() -> void:
	var drone := _drone()
	var group: Array[int] = [STATION, SHIP, drone]
	group.sort()
	for member: int in group:
		assert_eq(Units.docked_group(state, member), group, "from %d" % member)
	var b := _bare()
	var a := _bare(b)
	var c := _bare(b)
	var d := _bare(c)
	var chain: Array[int] = [a, b, c, d]
	chain.sort()
	assert_eq(Units.docked_group(state, d), chain, "up to the hub and down the other branch")
	assert_eq(Units.docked_group(state, a), chain, "A docked to B and C docked to B: one group")
	assert_eq(Units.docked_group(state, _bare()).size(), 1, "an undocked unit is a group of one")


func test_a_drone_takes_a_part_from_the_probe_through_the_station() -> void:
	var drone := _drone()
	_give(SHIP, SOLAR)
	var events := _run(_attach(drone, SHIP))
	assert_eq(events.map(func(event: Dictionary) -> String: return event["type"]), ["part_attached"])
	assert_false(state["units"][SHIP]["inventory"].has(SOLAR), "the probe's hold gave it")
	var fitted: int = events[0]["data"]["part"]
	assert_eq(state["parts"][fitted]["unit"], drone)
	var reloaded := Sim.from_save(sim.to_save())
	assert_not_null(reloaded, Sim.last_error())
	assert_eq(reloaded.to_save(), sim.to_save(), "the save after a group attach round-trips")
	assert_eq(reloaded.ledger()["violations"], PackedStringArray())


func test_a_unit_outside_the_group_is_still_refused() -> void:
	var drone := _drone()
	var other_hub := _bare()
	var docked_elsewhere := _bare(other_hub)
	var loose := _bare()
	for from: int in [docked_elsewhere, loose]:
		_give(from, SOLAR)
		assert_eq(sim.check(_attach(drone, from))["reason"], "not_docked")
		var events := _run(_attach(drone, from))
		assert_eq(events.size(), 1)
		assert_eq(events[0]["data"].get("reason"), "not_docked")


func test_copy_fit_takes_parts_from_the_group() -> void:
	var drone := _drone()
	var source := Units.create(sim._ctx, "small_craft", "Source", [0, 0, 0])
	var made := { "hull": state["units"][source]["root"] }
	for fit: Array in DRONE_FITS:
		var parent: int = made[fit[2]]
		var part := Units.add_part(sim._ctx, source, fit[0], parent, fit[1], "mount")
		state["parts"][parent]["children"].append(part)
		made[fit[0]] = part
		Units.add_stock(state["units"][SHIP]["inventory"], fit[0], sim._ctx.defs["items"][fit[0]]["unit_mass_g"])
	_count_matter()
	var command := { "type": "copy_fit", "unit": drone, "args": { "source": source, "from": SHIP } }
	assert_true(sim.check(command)["ok"], str(sim.check(command)))
	var events := _run(command)
	var copied: Dictionary = events.filter(func(event: Dictionary) -> bool: return event["type"] == "fit_copied")[0]
	assert_eq(copied["data"]["missing"], {})
	assert_eq(copied["data"]["refused"], [])
	assert_eq(copied["data"]["attached"].size(), DRONE_FITS.size())
