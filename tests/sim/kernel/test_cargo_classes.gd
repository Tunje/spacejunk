extends GutTest
## The chains' cargo classes are checked for room (A56, for B29's production chains): a tank of any
## class can't be overfilled.


func test_every_chain_class_is_checked_for_room() -> void:
	for cargo_class: String in ["water", "fuel", "oxidiser", "acid", "gas"]:
		assert_has(Units.CLASS_ORDER, cargo_class)
		var table := {}
		var entry := Units.class_entry(table, cargo_class)
		entry["cap_g"] = 1000
		entry["cap_l"] = 1000
		entry["used_g"] = 900
		assert_eq(Units.over_capacity(table), {}, "%s with room" % cargo_class)
		entry["reserved_g"] = 200
		assert_eq(Units.over_capacity(table), { "need_g": 1100, "have_g": 1000 }, "%s overfilled" % cargo_class)


func test_the_first_three_classes_keep_their_order() -> void:
	assert_eq(Units.CLASS_ORDER.slice(0, 3), ["goods", "ore", "propellant"])


func test_the_validator_knows_the_same_classes() -> void:
	for cargo_class: String in Units.CLASS_ORDER:
		assert_has(DataValidator.CARGO_CLASSES, cargo_class)
