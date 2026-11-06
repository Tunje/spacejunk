extends GutTest
## Frame margins inside a small sphere of influence (task A26, orbital_flight.md 11.20). A frame
## has no gravity, so a unit drifting in one must leave it while still inside the parent's SOI, and
## a frame must fit inside that SOI to be loaded at all. This is new_start's cluster: 60 km across,
## 300 km from the centre of Frost, a 60 km moon at half Kerbin's density.

const AU_MM := 149_597_870_700_000
const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const GM_FROST := 1_765_800
const FROST_A_MM := 12_000_000_000
const ONE := OrbitMath.ONE

var sim: Sim
var keys := {}


func before_each() -> void:
	sim = Sim.new()
	var defs: Dictionary = DataLoader.load_defs()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, _scenario(300_000_000, 60_000_000), {}), "")
	sim._strict = true
	keys = {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id


func _scenario(frame_a_mm: int, frame_radius_mm: int) -> Dictionary:
	return {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM } },
			{ "key": "moon", "name": "Frost", "kind": "planet", "radius_mm": 60_000_000, "visual_seed": 3,
				"deposits": [], "gm": GM_FROST, "orbit": { "parent": "planet", "a_mm": FROST_A_MM } },
		],
		"frames": [
			{ "key": "cluster", "name": "Cluster", "radius_mm": frame_radius_mm,
				"orbit": { "parent": "moon", "a_mm": frame_a_mm } },
			{ "key": "far", "name": "Far", "radius_mm": 1_000_000, "orbit": { "parent": "star", "a_mm": AU_MM } },
		],
		"units": [
			{ "key": "scout", "template": "starter_ship", "name": "Scout", "pos_mm": [0, 0, 0],
				"frame": "cluster", "inventory": [], "dock": null },
		],
	}


func _frame(name: String) -> Dictionary:
	return sim._state["frames"][keys[name]]


func _soi() -> int:
	return sim._state["bodies"][keys["Frost"]]["soi_mm"]


func test_margins_shrink_to_fit_frost_and_stay_full_round_the_star() -> void:
	var soi := _soi()
	assert_almost_eq(soi, 574_000_000, 2_000_000, "Frost's SOI, about 574 km")
	var leave := BurnSystem.leave_margin_mm(sim._ctx, _frame("Cluster"))
	assert_eq(leave, (soi - 300_000_000 - 60_000_000) / 2)
	assert_eq(BurnSystem.join_margin_mm(sim._ctx, _frame("Cluster")), leave / 2)
	assert_lt(300_000_000 + 60_000_000 + leave, soi, "the leave point is inside the SOI")
	print("A26 Frost cluster: SOI %d km, leave at %d km past the edge, join at %d km" % [
		soi / 1_000_000, leave / 1_000_000, leave / 2_000_000])
	assert_eq(BurnSystem.leave_margin_mm(sim._ctx, _frame("Far")), BurnSystem.LEAVE_MARGIN_MM)
	assert_eq(BurnSystem.join_margin_mm(sim._ctx, _frame("Far")), BurnSystem.LEAVE_MARGIN_MM / 2)


func test_a_drifter_leaves_inside_frosts_soi_and_orbits_frost() -> void:
	var scout: Dictionary = sim._state["units"][keys["Scout"]]
	scout["vel_um_s"] = [500_000_000, 0, 0]  # 500 m/s straight out of the cluster
	var left := false
	for i in 6000:
		sim.step()
		if sim.take_events().any(func(e: Dictionary) -> bool: return e["type"] == "frame_left"):
			left = true
			break
	assert_true(left, "left the frame")
	assert_eq(scout["frame"], 0)
	assert_eq(scout["orbit"]["parent"], keys["Frost"], "an orbit round Frost, not past it")
	assert_lt(IntMath.dist(scout["pos_mm"], [0, 0, 0]), _soi())


func test_a_still_unit_just_inside_the_join_margin_joins_and_one_outside_does_not() -> void:
	var join: int = 60_000_000 + BurnSystem.join_margin_mm(sim._ctx, _frame("Cluster"))
	for case: Array in [[join - 2_000_000, true], [join + 2_000_000, false]]:
		before_each()
		var frame := _frame("Cluster")
		var now := OrbitMath.state_at(frame["orbit"], GM_FROST, sim.current_tick())
		var up := OrbitMath.unit(now["r"])
		var r: Array[int] = []
		for axis in 3:
			r.append(int(now["r"][axis]) + OrbitMath.smul_div(up[axis], case[0], ONE))
		var scout: Dictionary = sim._state["units"][keys["Scout"]]
		scout["frame"] = 0
		scout["orbit"] = OrbitMath.from_state(r, now["v"], GM_FROST, sim.current_tick())
		scout["orbit"]["parent"] = keys["Frost"]
		scout["pos_mm"] = r
		sim._ctx.index.clear()
		sim.step()
		assert_eq(scout["frame"] == keys["Cluster"], case[1], "%d km out" % (case[0] / 1_000_000))


func test_a_frame_reaching_past_its_parents_soi_is_refused() -> void:
	for case: Array in [[520_000_000, 60_000_000], [300_000_000, 280_000_000]]:
		var built := Sim.new()
		var defs: Dictionary = DataLoader.load_defs()
		built._setup(Sim._new_state("reference", 7, defs), defs)
		var problem := ScenarioBuilder.populate(built._ctx, _scenario(case[0], case[1]), {})
		assert_string_contains(problem, "frame cluster reaches past the sphere of influence of Frost")
