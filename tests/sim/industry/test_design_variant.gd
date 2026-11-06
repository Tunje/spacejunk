extends GutTest
## design_variant (C12): the player designs a variant with unit 0, it is prototyped and bench-tested
## like any design, a variant's bench test may discover a hidden idea, and copy_fit copies the
## exact variant. On the reference station with a research lab added.

const STATION := 8
const HUB := 9
const FABRICATOR := 14
const RUN_TICKS := 3
const FULL_RATE := 100
const LASER := "mining_laser_mk1"
const SOLAR := "small_solar_panel_mk1"
const FREE_PORT := 11

var sim: Sim
var state: Dictionary
var defs: Dictionary
var lab := 0


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	defs = sim._ctx.defs
	defs["modules"][SOLAR]["ideas"] = [{ "id": "thin_cells", "name": "Thin Cells", "points": 5, "complexity": 1,
		"deltas": { "capabilities.generate.power_w": 100_000, "durability": -200_000 } }]
	lab = Units.add_part(sim._ctx, STATION, "research_lab_mk1", HUB, "side_d_px", "mount")
	state["parts"][HUB]["children"].append(lab)
	sim._ctx.index.clear()
	_count_matter()


func _count_matter() -> void:
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]


func _design(base: String, ideas: Array, unit: int = 0) -> Dictionary:
	return { "type": "design_variant", "unit": unit, "args": { "base": base, "ideas": ideas } }


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


## Designs a variant, makes its recipes quick, and returns its ID.
func _designed(base: String, ideas: Array) -> String:
	sim.submit(_design(base, ideas))
	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["variant_designed"])
	var id: String = events[0]["data"]["variant"]
	for recipe in [id, ResearchDefs.prototype_id(id), ResearchDefs.qualify_id(id)]:
		defs["recipes"][recipe]["work"] = RUN_TICKS * FULL_RATE
	return id


func _give(recipe: String, skip: String = "") -> void:
	for input: Dictionary in defs["recipes"][recipe]["inputs"]:
		if input["item"] != skip:
			Units.add_stock(state["units"][STATION]["inventory"], input["item"], input["grams"])
	_count_matter()


func _earn(points: int) -> void:
	state["science"]["points"] += points
	state["science"]["earned"] += points


func _run(recipe: String, facility: int) -> Array[Dictionary]:
	sim.submit({ "type": "start_job", "unit": STATION, "args": { "facility": facility, "recipe": recipe, "count": 1 } })
	var events: Array[Dictionary] = []
	for i in RUN_TICKS * 2 + 1:
		sim.step()
		events.append_array(sim.take_events())
	assert_eq(sim.ledger()["violations"], PackedStringArray())
	return events


## Prototypes and bench-tests a designed variant, and returns the bench test's events.
func _qualify(id: String) -> Array[Dictionary]:
	_give(ResearchDefs.prototype_id(id))
	_earn(defs["recipes"][ResearchDefs.prototype_id(id)].get("points", 0))
	_run(ResearchDefs.prototype_id(id), FABRICATOR)
	_give(ResearchDefs.qualify_id(id), ResearchDefs.prototype_id(id))
	return _run(ResearchDefs.qualify_id(id), lab)


func test_a_designed_variant_is_recorded_and_its_recipes_appear_in_defs() -> void:
	sim.submit(_design(LASER, ["light_frame", "focused_beam"]))
	sim.step()
	var event: Dictionary = sim.take_events()[0]
	var id := "mining_laser_mk1+focused_beam+light_frame"
	assert_eq(event["type"], "variant_designed")
	assert_eq(event["unit"], 0, "the player, not a unit")
	assert_eq(event["data"], { "variant": id, "base": LASER, "ideas": ["focused_beam", "light_frame"] })
	assert_eq(state["research"]["variants"][id], { "base": LASER, "ideas": ["focused_beam", "light_frame"], "complexity": 3 })
	assert_eq(state["research"]["designs"][id], "prototype")
	assert_true(sim.defs()["modules"].has(id))
	assert_true(sim.defs()["recipes"].has(ResearchDefs.prototype_id(id)))
	assert_eq(sim.view()["research"]["variants"].keys(), [id])
	assert_eq(sim.check({ "type": "start_job", "unit": STATION,
		"args": { "facility": FABRICATOR, "recipe": id, "count": 1 } })["reason"], "design_unqualified")


func test_design_variant_refuses_what_it_must() -> void:
	assert_eq(sim.check(_design(LASER, ["no_such_idea"]))["reason"], "malformed_command")
	assert_eq(sim.check(_design(LASER, ["focused_beam"], 23))["reason"], "malformed_command", "unit 0 only")
	assert_eq(sim.check(_design(LASER, ["cast_housing"]))["reason"], "idea_locked", "hidden, not discovered")
	state["research"]["theories"].erase("photovoltaic_arrays")
	assert_eq(sim.check(_design("solar_panel_mk1", ["high_efficiency_cells"]))["reason"], "idea_locked")
	state["research"]["designs"].erase("assisted_core")
	state["research"]["theories"].erase("autonomous_navigation")
	defs["modules"]["assisted_core"]["ideas"] = defs["modules"][SOLAR]["ideas"].duplicate(true)
	defs["modules"]["assisted_core"]["ideas"][0]["deltas"] = { "power_w": 100_000, "durability": -100_000 }
	assert_eq(sim.check(_design("assisted_core", ["thin_cells"]))["reason"], "design_unqualified")
	var variant := _designed(LASER, ["focused_beam"])
	assert_eq(sim.check(_design(LASER, ["focused_beam"]))["reason"], "variant_exists")
	state["research"]["designs"][variant] = "qualified"
	assert_eq(sim.check(_design(variant, ["light_frame"]))["reason"], "malformed_command",
		"a variant of a variant: design the base with both ideas instead")
	assert_true(sim.check(_design(LASER, ["focused_beam", "light_frame"]))["ok"])
	defs["modules"][LASER]["ideas"].append({ "id": "no_beam", "name": "No Beam", "points": 1, "complexity": 1,
		"deltas": { "capabilities.mine.rate_g_per_s": -1_000_000, "mass_g": -100_000 } })
	assert_eq(sim.check(_design(LASER, ["no_beam"]))["reason"], "stat_out_of_range")


func test_a_variant_is_prototyped_with_its_ideas_points_and_then_qualified() -> void:
	var id := _designed(LASER, ["focused_beam", "light_frame"])
	_give(ResearchDefs.prototype_id(id))
	sim.submit({ "type": "start_job", "unit": STATION,
		"args": { "facility": FABRICATOR, "recipe": ResearchDefs.prototype_id(id), "count": 1 } })
	sim.step()
	assert_eq(state["jobs"].values()[0]["reason"], "missing_points", "50 points of ideas")
	_earn(50)
	for i in RUN_TICKS * 2:
		sim.step()
	assert_eq(state["science"]["spent"], 50)
	_give(ResearchDefs.qualify_id(id), ResearchDefs.prototype_id(id))
	assert_has(_types(_run(ResearchDefs.qualify_id(id), lab)), "design_qualified")
	assert_eq(state["research"]["designs"][id], "qualified")
	_give(id)
	_run(id, FABRICATOR)
	assert_eq(state["units"][STATION]["inventory"].get(id, 0), defs["modules"][id]["mass_g"])


func test_a_variants_bench_test_can_discover_a_hidden_idea() -> void:
	for idea: Dictionary in defs["modules"][LASER]["ideas"]:
		if idea["id"] == "cast_housing":
			idea["discover_ppm"] = 1_000_000
	var events := _qualify(_designed(LASER, ["focused_beam"]))
	var found := events.filter(func(event: Dictionary) -> bool: return event["type"] == "idea_discovered")
	assert_eq(found.size(), 1)
	assert_eq(found[0]["data"], { "base": LASER, "idea": "cast_housing" })
	assert_true(state["research"]["discovered"].has("mining_laser_mk1:cast_housing"))
	assert_true(sim.check(_design(LASER, ["cast_housing"]))["ok"], "now it may be used")
	var rng_before: Dictionary = state["rng"].duplicate(true)
	_qualify(_designed(LASER, ["light_frame"]))
	assert_eq(state["rng"], rng_before, "with nothing hidden left, nothing is drawn")


func test_discovery_is_the_same_in_every_game_with_the_same_seed() -> void:
	var outcomes := []
	for run in 2:
		before_each()
		for idea: Dictionary in defs["modules"][LASER]["ideas"]:
			if idea["id"] == "cast_housing":
				idea["discover_ppm"] = 500_000
		var events := _qualify(_designed(LASER, ["focused_beam"]))
		outcomes.append(_types(events).has("idea_discovered"))
		outcomes.append(state["rng"].duplicate(true))
	assert_eq(outcomes[0], outcomes[2])
	assert_eq(outcomes[1], outcomes[3])


func test_copy_fit_copies_the_exact_variant() -> void:
	var id := _designed(SOLAR, ["thin_cells"])
	var source := Units.create(sim._ctx, "small_craft", "Source", [0, 0, 0])
	var hull: int = state["units"][source]["root"]
	var part := Units.add_part(sim._ctx, source, id, hull, "side_a_px", "mount")
	state["parts"][hull]["children"].append(part)
	var target := Units.create(sim._ctx, "small_craft", "Target", state["units"][STATION]["pos_mm"])
	state["units"][target]["dock"] = { "port": Units.ports(state, defs, target)[0], "target_unit": STATION, "target_port": FREE_PORT }
	state["units"][target]["at_target"] = STATION
	Units.add_stock(state["units"][STATION]["inventory"], SOLAR, defs["modules"][SOLAR]["mass_g"])
	sim._ctx.index.clear()
	_count_matter()
	var copy := { "type": "copy_fit", "unit": target, "args": { "source": source, "from": STATION } }
	sim.submit(copy)
	sim.step()
	var report: Dictionary = sim.take_events()[-1]["data"]
	assert_eq(report["missing"], { id: 1 }, "the base part in stock is not the variant")
	Units.add_stock(state["units"][STATION]["inventory"], id, defs["modules"][id]["mass_g"])
	_count_matter()
	sim.submit(copy)
	sim.step()
	report = sim.take_events()[-1]["data"]
	assert_eq(report["attached"].size(), 1)
	assert_eq(state["parts"][report["attached"][0]]["def"], id)
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_a_saved_game_keeps_its_variants() -> void:
	var id := _designed(LASER, ["focused_beam"])
	var text := sim.to_save()
	var loaded := Sim.from_save(text)
	assert_not_null(loaded)
	assert_true(loaded.defs()["modules"].has(id))
	assert_eq(loaded.to_save(), text)
