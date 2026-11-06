extends GutTest
## The land check's way back (A36, A39). It prices the take-off to LowFlight.LEAVE_MM plus Transfer's
## leg to the nearest frame round the body, at the landed mass. It flags cannot_return when the
## propellant left after landing is short of that.
## The cases are B's human Frost landing on the new start (B23): the probe leaves the cluster with a
## 20 m/s retrograde burn, then checks a landing on the cell below. Flown in full, the prices
## matched the propellant the flights burned: 803 kg in case A and 826 kg in case B.

const PROBE := NewStartBot.PROBE
const FROST := NewStartBot.FROST
const CLUSTER := 12


## The probe just out of the cluster on its way down to Frost, and its land check.
func _check_after_leaving(bot: NewStartBot) -> Dictionary:
	bot._command("plan_burn", PROBE, { "tick": bot.sim.current_tick() + 1, "prograde_um_s": -20_000_000,
		"normal_um_s": 0, "radial_um_s": 0 })
	bot._until("burn_done", PROBE, 1000)
	var cell := LandingSystem.cell_below(bot.sim._ctx, FROST, bot.sim._state["units"][PROBE]["pos_mm"])
	var checked := bot.sim.check({ "type": "land", "unit": PROBE, "args": { "body": FROST, "cell": cell } })
	assert_true(checked["ok"], str(checked))
	var detail: Dictionary = checked["detail"]
	gut.p("land %d kg, back to %d for %d kg, cannot_return %s" % [detail["propellant_g"] / 1000,
		detail["return_target"], detail["return_propellant_g"] / 1000, detail["cannot_return"]])
	assert_eq(detail["return_target"], CLUSTER, "the way back is to the cluster")
	return detail


## The probe at the station after the lab stage, its goods taken off, moved to White Rock, where the
## old stage 3's ice top-up left it, and undocked. Then its tank is set to `propellant_g`, so that is
## what leaves for Frost.
func _from_the_station(propellant_g: int) -> NewStartBot:
	var bot := NewStartBot.from_snapshot(NewStartBot.STAGE_LAB)
	var inventory: Dictionary = bot.sim._state["units"][PROBE]["inventory"]
	var items: Dictionary = bot.sim.defs()["items"]
	var keys := inventory.keys()
	keys.sort()
	for item: String in keys:
		if items[item]["cargo_class"] == "goods":
			Units.remove_stock(inventory, item, inventory[item])
	bot.sim._state["matter_start_g"] = bot.sim.ledger()["matter"]["total_g"]
	bot.sim._ctx.index.clear()
	bot._order("move_to", PROBE, { "target": NewStartBot.WHITE_ROCK })
	bot._order("undock", bot.station, {})
	var held: int = inventory.get("propellant", 0)
	if held > propellant_g:
		Units.remove_stock(inventory, "propellant", held - propellant_g)
	else:
		Units.add_stock(inventory, "propellant", propellant_g - held)
	bot.sim._state["matter_start_g"] = bot.sim.ledger()["matter"]["total_g"]
	bot.sim._ctx.index.clear()
	return bot


func test_a_full_tank_from_the_start_can_get_back() -> void:
	var bot := NewStartBot.new()
	bot.sim = Sim.new_game("new_start", NewStartBot.SEED)
	var detail := _check_after_leaving(bot)
	assert_false(detail["cannot_return"])
	assert_between(detail["return_propellant_g"], 790_000, 820_000, "about 803 kg, as flown")


func test_the_hint_case_with_the_ice_top_up_can_get_back() -> void:
	var detail := _check_after_leaving(_from_the_station(2_477_626))
	assert_false(detail["cannot_return"])
	# 826 kg was flown from the old stage 3, which had topped up with ice at White Rock. The C18b
	# route leaves the probe lighter, and the check prices it at about 800 kg; not flown again.
	assert_between(detail["return_propellant_g"], 785_000, 815_000, "about 800 kg, the check's price")


## The land check, read-only, at this tick and place with `grams` of propellant aboard.
func _check_with(bot: NewStartBot, grams: int) -> Dictionary:
	var inventory: Dictionary = bot.sim._state["units"][PROBE]["inventory"]
	Units.remove_stock(inventory, "propellant", inventory["propellant"])
	Units.add_stock(inventory, "propellant", grams)
	bot.sim._ctx.index.clear()
	var cell := LandingSystem.cell_below(bot.sim._ctx, FROST, bot.sim._state["units"][PROBE]["pos_mm"])
	var checked := bot.sim.check({ "type": "land", "unit": PROBE, "args": { "body": FROST, "cell": cell } })
	assert_true(checked["ok"], str(checked))
	return checked["detail"]


## Self-calibrating, so a route change cannot break it: the least tank the check does not warn about
## is found by halving, and there landing plus the way back must just fit. Both prices fall with
## the tank's own mass, so the edge is found where the check is, not from the full tank's prices.
func test_a_tank_short_of_the_way_back_is_warned() -> void:
	var bot := _from_the_station(2_477_626)
	# Less than the landing itself is refused with no_propellant, so the search starts at the full
	# tank's landing price: the lighter probe can still land on it, but has nothing to get back on.
	var short: int = _check_after_leaving(bot)["propellant_g"]
	var enough := 2_477_626
	assert_false(_check_with(bot, enough)["cannot_return"])
	assert_true(_check_with(bot, short)["cannot_return"])
	while enough - short > 1_000:
		var middle := (short + enough) / 2
		if _check_with(bot, middle)["cannot_return"]:
			short = middle
		else:
			enough = middle
	var at_edge := _check_with(bot, enough)
	gut.p("warned below %d kg: %s" % [enough / 1000, str(at_edge)])
	var need: int = at_edge["propellant_g"] + at_edge["return_propellant_g"]
	assert_between(enough - need, 0, 1_000, "the edge is where landing plus the way back just fit")
	assert_true(_check_with(bot, short)["cannot_return"], "a kilogram short is warned")


## B's crash (A39): a move_to waiting for its window from a unit that then drops into low flight is
## cancelled with unsupported_orbit, not a script error.
func test_a_waiting_move_whose_unit_drops_into_low_flight_is_cancelled() -> void:
	var bot := NewStartBot.new()
	bot.sim = Sim.new_game("new_start", NewStartBot.SEED)
	bot._command("plan_burn", PROBE, { "tick": 1, "prograde_um_s": -20_000_000, "normal_um_s": 0, "radial_um_s": 0 })
	bot._until("burn_done", PROBE, 1000)
	var sim := bot.sim
	sim.take_events()
	# On the circle a 20 km take-off used to give, whose periapsis rounds just under the line, so the
	# probe drops into low flight a few ticks after its move is accepted.
	var unit: Dictionary = sim._state["units"][PROBE]
	var cell := LandingSystem.cell_below(sim._ctx, FROST, unit["pos_mm"])
	unit["orbit"] = LandingSystem.lift_orbit(sim._ctx, FROST, cell, LowFlight.ENTER_MM, sim.current_tick())
	unit["pos_mm"] = OrbitMath.position_at(unit["orbit"], sim.current_tick())
	sim._ctx.index.clear()
	sim.submit({ "type": "move_to", "unit": PROBE, "args": { "target": NewStartBot.RED_ROCK } })
	sim.step()
	assert_eq(unit["op"]["type"], MoveStep.OP_WAITING, "waiting for its window: %s, %s" % [
		str(unit["op"]), str(sim.take_events())])
	if unit["op"]["type"] != MoveStep.OP_WAITING:
		return
	var depart: int = unit["op"]["depart_tick"]
	assert_gt(depart, sim.current_tick() + 1)
	sim.step(20)
	assert_ne(unit["low_flight"], 0, "in low flight before its window")
	sim.step(depart - sim.current_tick() + 2)
	var reasons: Array = []
	for event: Dictionary in sim.take_events():
		if event["unit"] == PROBE and event["type"] in ["task_cancelled", "task_finished"]:
			reasons.append(event["data"].get("reason", ""))
	assert_has(reasons, Transfer.REASON_UNSUPPORTED, "cancelled cleanly: %s" % str(reasons))
	assert_true(unit["transfer"].is_empty(), "it never left")
