extends GutTest
## Where a built unit docks (C22): a free port of the builder, or failing that of a unit docked with
## it either way. On the new start the station is docked to the probe's one port, so a hull the
## probe builds appears at the station's spare port.

var bot: NewStartBot
var state: Dictionary


func before_each() -> void:
	bot = NewStartBot.from_snapshot(NewStartBot.STAGE_RESEARCH)
	assert_eq(bot.problems, PackedStringArray())
	state = bot.sim._state


func _give(item: String, count: int) -> void:
	Units.add_stock(state["units"][NewStartBot.PROBE]["inventory"], item,
		count * bot.sim.defs()["items"][item]["unit_mass_g"])
	state["matter_start_g"] = bot.sim.ledger()["matter"]["total_g"]


func _free_ports(unit: int) -> Array:
	return Units.ports(state, bot.sim.defs(), unit).filter(func(port: int) -> bool:
		return not Units.port_in_use(state, port))


func test_the_probe_builds_a_hull_at_the_station_it_holds() -> void:
	assert_eq(_free_ports(NewStartBot.PROBE), [], "the probe's one port holds the station")
	var spare: Array = _free_ports(bot.station)
	assert_eq(spare.size(), 1)
	assert_true(state["units"][NewStartBot.PROBE]["dock"].is_empty(), "the station holds the dock record")
	_give("structural_frame", 2)
	_give("wiring", 2)
	var id := bot.sim.submit({ "type": "start_job", "unit": NewStartBot.PROBE,
		"args": { "facility": bot.fabricator, "recipe": "small_craft", "count": 1 } })
	var made := 0
	for i in 3_000:
		bot.sim.step()
		for event in bot.sim.take_events():
			assert_false(event["type"] == "command_rejected" and event["data"]["command"] == id, str(event))
			assert_false(event["type"] == "job_paused", "no %s" % str(event["data"]))
			if event["type"] == "unit_created":
				made = event["data"]["unit"]
		if made != 0:
			break
	assert_ne(made, 0, "the hull was built")
	assert_eq(state["units"][made]["dock"].get("target_port", 0), spare[0], "at the station's spare port")
	assert_eq(state["units"][made]["dock"].get("target_unit", 0), bot.station)
	assert_eq(bot.sim.ledger()["violations"], PackedStringArray())


func test_with_no_free_port_anywhere_the_build_waits() -> void:
	var spare: int = _free_ports(bot.station)[0]
	state["parts"][spare]["claimed_by"] = 999_999
	_give("structural_frame", 2)
	_give("wiring", 2)
	bot.sim.submit({ "type": "start_job", "unit": NewStartBot.PROBE,
		"args": { "facility": bot.fabricator, "recipe": "small_craft", "count": 1 } })
	var paused := ""
	for i in 3_000:
		bot.sim.step()
		for event in bot.sim.take_events():
			if event["type"] == "job_paused":
				paused = event["data"]["reason"]
		if paused != "":
			break
	assert_eq(paused, "no_free_port")
