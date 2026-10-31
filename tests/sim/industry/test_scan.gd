extends GutTest
## Scanning and deposits (check 1), on the reference scenario's ship at Red Rock.

const SHIP := 23
const LIDAR := 36
const ROCK := 2
const DEPOSIT := 3
const OTHER_ROCK := 4
const OTHER_DEPOSIT := 5
const STAR := 1
const SCAN_TICKS := 300

## Sheds the LIDAR in phase 4, after phase 2 has run, as the power allocator would.
class ShedOnAllocate:
	extends SimSystem

	func allocate(ctx: SimContext) -> void:
		ctx.state["parts"][LIDAR]["shed"] = true


var sim: Sim
var state: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	_place_at(ROCK)


## Puts the ship at a body. Travel arrives with A6.
func _place_at(body: int) -> void:
	var unit: Dictionary = state["units"][SHIP]
	unit["dock"] = {}
	unit["at_target"] = body


func _scan(target: int = ROCK) -> Dictionary:
	return { "type": "scan", "unit": SHIP, "args": { "target": target } }


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


func _assert_refused(command: Dictionary, reason: String) -> void:
	assert_eq(sim.check(command)["reason"], reason)
	sim.submit(command)
	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["command_rejected"], reason)
	assert_eq(events[0]["data"]["reason"], reason)
	assert_eq(state["tasks"].size(), 0, "no task made")


func test_deposits_are_hidden_until_scanned() -> void:
	assert_eq(sim.view()["deposits"].size(), 0)
	assert_false(sim.view()["bodies"][ROCK]["scanned"])


func test_a_scan_takes_its_data_time_and_reveals_the_deposit() -> void:
	sim.submit(_scan())
	sim.step(SCAN_TICKS - 1)
	assert_eq(sim.view()["deposits"].size(), 0, "not on the last tick but one")
	assert_eq(sim.view()["units"][SHIP]["op"]["type"], "scanning")
	assert_eq(sim.view()["units"][SHIP]["op"]["part"], LIDAR)
	assert_eq(_types(sim.take_events()), ["task_started"])

	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["deposit_found", "scan_finished"])
	assert_eq(events[0]["data"], { "deposit": DEPOSIT, "item": "hematite", "grams": 200000000 })
	assert_eq(events[1]["data"], { "target": ROCK, "deposits": [DEPOSIT] })
	var view := sim.view()
	assert_true(view["bodies"][ROCK]["scanned"])
	assert_eq(view["deposits"][DEPOSIT], {
		"body": ROCK, "item": "hematite", "remaining_g": 200000000, "hardness": 6,
	})
	assert_false(view["deposits"].has(OTHER_DEPOSIT), "other bodies stay hidden")


func test_the_task_finishes_on_the_next_tick_and_the_unit_goes_idle() -> void:
	sim.submit(_scan())
	sim.step(SCAN_TICKS)
	sim.take_events()
	sim.step()
	assert_eq(_types(sim.take_events()), ["task_finished"])
	var unit: Dictionary = sim.view()["units"][SHIP]
	assert_eq(unit["op"]["type"], "idle")
	assert_eq(unit["task"], 0)
	assert_eq(sim.view()["tasks"].size(), 0)


func test_scanning_again_finds_nothing_new() -> void:
	sim.submit(_scan())
	sim.step(SCAN_TICKS + 1)
	sim.take_events()
	sim.submit(_scan())
	sim.step(SCAN_TICKS)
	var events := sim.take_events()
	assert_eq(_types(events), ["task_started", "scan_finished"])
	assert_eq(events[1]["data"]["deposits"], [])


func test_a_scan_changes_no_matter() -> void:
	sim.submit(_scan())
	sim.step(SCAN_TICKS + 1)
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
	assert_eq(ledger["violations"], PackedStringArray())


func test_a_scan_is_refused_while_docked() -> void:
	state["units"][SHIP]["dock"] = { "port": 28, "target_unit": 8, "target_port": 12 }
	_assert_refused(_scan(), "docked")


func test_a_scan_is_refused_away_from_the_body() -> void:
	_assert_refused(_scan(OTHER_ROCK), "out_of_range")


func test_a_scan_needs_an_asteroid() -> void:
	_assert_refused(_scan(STAR), "invalid_target")
	_assert_refused(_scan(9999), "invalid_target")


func test_a_scan_needs_a_target_of_the_right_type() -> void:
	_assert_refused({ "type": "scan", "unit": SHIP, "args": { "target": "rock" } }, "malformed_command")


func test_a_scan_needs_a_healthy_scanner() -> void:
	state["parts"][LIDAR]["fault"] = "test_fault"
	_assert_refused(_scan(), "module_fault")


func test_a_scan_needs_a_scanner() -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["lidar_mk1"]["capabilities"].erase("scan")
	_assert_refused(_scan(), "module_missing")


func test_a_scan_needs_the_module_tier() -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["lidar_mk1"]["min_ai_tier"] = 2
	_assert_refused(_scan(), "tier_too_low")


func test_a_cancelled_scan_starts_again_from_nothing() -> void:
	sim.submit(_scan())
	sim.step(SCAN_TICKS - 1)
	sim.submit({ "type": "stop", "unit": SHIP, "args": {} })
	sim.step()
	assert_eq(sim.view()["deposits"].size(), 0)
	sim.submit(_scan())
	sim.step(SCAN_TICKS - 1)
	assert_eq(sim.view()["deposits"].size(), 0)
	sim.step()
	assert_eq(sim.view()["deposits"].size(), 1)


func test_a_part_shed_on_the_last_tick_finds_nothing() -> void:
	sim.submit(_scan())
	sim.step(SCAN_TICKS - 1)
	sim._register_system(ShedOnAllocate.new())
	sim.step()
	assert_eq(sim.view()["deposits"].size(), 0)
	sim.step()
	assert_eq(sim.take_events().back()["data"]["reason"], "no_power")


func test_a_save_midway_finishes_identically() -> void:
	sim.submit(_scan())
	sim.step(100)
	var loaded := Sim.from_save(sim.to_save())
	assert_not_null(loaded)
	sim.step(SCAN_TICKS - 100 + 1)
	loaded.step(SCAN_TICKS - 100 + 1)
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_true(loaded.view()["deposits"].has(DEPOSIT))
