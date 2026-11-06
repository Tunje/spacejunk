extends GutTest
## ResearchDefs (C12a): the prototype, bench test and variant definitions research derives. Built on
## today's real modules and recipes, with B19's draft theories, bench test and ideas added in sim
## units, as the loader will give them.

const AUTONOMOUS_NAVIGATION := "autonomous_navigation"
const LASER := "mining_laser_mk1"
const CORE := "assisted_core"

var defs: Dictionary


func before_each() -> void:
	defs = DataLoader.load_defs().duplicate(true)
	defs["theories"] = {
		AUTONOMOUS_NAVIGATION: { "id": AUTONOMOUS_NAVIGATION, "era": 2, "requires": [], "evidence": [],
			"test": "prove_autonomous_navigation", "unlocks": [CORE] },
	}
	defs["bench_test"] = { "inputs": [_count("processor", 10)], "work": 300_000, "power_w": 100_000 }
	defs["modules"][LASER]["ideas"] = [
		{ "id": "focused_beam", "name": "Focused Beam", "points": 30, "complexity": 2,
			"deltas": { "capabilities.mine.rate_g_per_s": 250_000, "power_w": 200_000, "heat_w": 250_000 } },
		{ "id": "light_frame", "name": "Light Frame", "points": 20, "complexity": 1,
			"deltas": { "mass_g": -200_000, "durability": -300_000 } },
		{ "id": "simple_optics", "name": "Simpler Optics", "points": 10, "complexity": -2, "simplifies": true,
			"deltas": { "capabilities.mine.rate_g_per_s": -100_000, "heat_w": -50_000 } },
		{ "id": "cast_housing", "name": "Cast Housing", "points": 0, "complexity": -1, "simplifies": true,
			"hidden": true, "discover_ppm": 200_000, "deltas": { "mass_g": 100_000, "durability": 200_000 } },
		{ "id": "heavy_mount", "name": "Heavy Mount", "points": 5, "complexity": 0,
			"deltas": { "mass_g": 600_000, "durability": 500_000 } },
		{ "id": "no_beam", "name": "No Beam", "points": 5, "complexity": 1,
			"deltas": { "capabilities.mine.rate_g_per_s": -1_000_000, "mass_g": -100_000 } },
	]


func _count(item: String, count: int) -> Dictionary:
	return { "item": item, "count": count, "grams": count * defs["items"][item]["unit_mass_g"] }


func _counts(entries: Array) -> Dictionary:
	var found := {}
	for entry: Dictionary in entries:
		found[entry["item"]] = entry.get("count", entry["grams"])
	return found


## Every derived recipe turns its inputs into exactly as many grams of outputs.
func _assert_balanced(recipes: Dictionary) -> void:
	for id: String in recipes:
		var made := 0
		for output: Dictionary in recipes[id]["outputs"]:
			made += output.get("grams", 0)
		var used := 0
		for input: Dictionary in recipes[id]["inputs"]:
			used += input["grams"]
		assert_eq(made, used, "%s balances" % id)


func test_ids_are_prefixed_and_a_variant_sorts_its_ideas() -> void:
	assert_eq(ResearchDefs.prototype_id(CORE), "prototype:assisted_core")
	assert_eq(ResearchDefs.qualify_id(CORE), "qualify:assisted_core")
	assert_eq(ResearchDefs.variant_id(LASER, ["light_frame", "focused_beam"]),
		"mining_laser_mk1+focused_beam+light_frame")


func test_a_theory_unlock_gets_a_prototype_at_twice_the_cost_and_a_bench_test() -> void:
	var derived := ResearchDefs.derive_static(defs)
	assert_eq(derived["items"].keys(), ["prototype:assisted_core"])
	var item: Dictionary = derived["items"]["prototype:assisted_core"]
	assert_eq(item["unit_mass_g"], defs["modules"][CORE]["mass_g"])
	assert_eq(item["density_g_l"], defs["items"][CORE]["density_g_l"], "the module's volume")
	assert_eq(item["prototype_of"], CORE)
	assert_eq(derived["recipes"].keys(), ["prototype:assisted_core", "qualify:assisted_core"])

	var prototype: Dictionary = derived["recipes"]["prototype:assisted_core"]
	var normal: Dictionary = defs["recipes"][CORE]
	assert_eq(prototype["facility"], "fabricator")
	assert_eq(prototype["work"], normal["work"] * 2)
	assert_eq(prototype["power_w"], normal["power_w"])
	assert_eq(_counts(prototype["inputs"]), { "basic_core": 2, "processor": 12 })
	assert_false(prototype.has("points"), "a base design's prototype takes no points")
	assert_eq(prototype["outputs"][0], { "item": "prototype:assisted_core", "count": 1, "grams": 60_000 })
	for output: Dictionary in prototype["outputs"].slice(1):
		assert_eq(output["sink"], "fab_scrap")

	var bench: Dictionary = derived["recipes"]["qualify:assisted_core"]
	assert_eq([bench["facility"], bench["work"], bench["power_w"]], ["lab", 300_000, 100_000])
	assert_eq(_counts(bench["inputs"]), { "prototype:assisted_core": 1, "processor": 10 })
	assert_eq(bench["outputs"][-1], { "qualifies": CORE })
	for output: Dictionary in bench["outputs"].slice(0, -1):
		assert_eq(output["sink"], "test_consumed")
	_assert_balanced(derived["recipes"])


func test_a_theory_may_replace_the_bench_inputs() -> void:
	defs["theories"][AUTONOMOUS_NAVIGATION]["qualify"] = [_count("wiring", 4)]
	var bench: Dictionary = ResearchDefs.derive_static(defs)["recipes"]["qualify:assisted_core"]
	assert_eq(_counts(bench["inputs"]), { "prototype:assisted_core": 1, "wiring": 4 })
	assert_eq(bench["work"], 300_000, "work and power still come from the bench test")


func test_a_variant_applies_each_delta_once_to_the_base_value() -> void:
	var variant := ResearchDefs.derive_variant(defs, LASER, ["light_frame", "focused_beam"])
	assert_eq(variant["id"], "mining_laser_mk1+focused_beam+light_frame")
	var module: Dictionary = variant["module"]
	assert_eq(module["capabilities"]["mine"]["rate_g_per_s"], 25_000, "20 kg/s + 25%")
	assert_eq(module["capabilities"]["mine"]["hardness_max"], 7, "unchanged")
	assert_eq(module["power_w"], 180_000)
	assert_eq(module["heat_w"], 150_000)
	assert_eq(module["mass_g"], 320_000)
	assert_eq(module["durability"], 700)
	var base: Dictionary = defs["modules"][LASER]
	for field in ["connectors", "collision", "visual", "min_ai_tier", "volume_l"]:
		assert_eq(module.get(field), base.get(field), field)
	assert_eq(module["variant_of"], LASER)
	assert_eq(module["fabrication"], { "recipe": variant["id"] })
	assert_eq(module["ideas"], [], "no variants of a variant")
	assert_eq(variant["complexity"], 3)


func test_complexity_scales_the_recipe_and_the_rest_goes_to_scrap() -> void:
	var variant := ResearchDefs.derive_variant(defs, LASER, ["focused_beam", "light_frame"])
	var recipe: Dictionary = variant["recipes"][variant["id"]]
	assert_eq(_counts(recipe["inputs"]), { "structural_frame": 9, "wiring": 18, "processor": 18 },
		"5, 10 and 10 times 7/4, rounded up")
	assert_eq(recipe["work"], 315_000, "180000 x 7/4")
	assert_eq(recipe["power_w"], defs["recipes"][LASER]["power_w"])
	assert_eq(recipe["outputs"][0], { "item": variant["id"], "count": 1, "grams": 320_000 })
	assert_eq(variant["items"][variant["id"]]["unit_mass_g"], 320_000)
	_assert_balanced(variant["recipes"])


func test_a_heavier_variant_takes_inputs_to_cover_its_mass() -> void:
	var variant := ResearchDefs.derive_variant(defs, LASER, ["heavy_mount"])
	assert_eq(variant["module"]["mass_g"], 640_000)
	var recipe: Dictionary = variant["recipes"][variant["id"]]
	assert_eq(_counts(recipe["inputs"]), { "structural_frame": 8, "wiring": 16, "processor": 16 },
		"complexity 0, but 1.6 times the mass")
	assert_eq(recipe["work"], defs["recipes"][LASER]["work"])
	_assert_balanced(variant["recipes"])


func test_simplification_never_takes_complexity_below_zero() -> void:
	var variant := ResearchDefs.derive_variant(defs, LASER, ["simple_optics"])
	assert_eq(variant["complexity"], 0)
	var recipe: Dictionary = variant["recipes"][variant["id"]]
	assert_eq(_counts(recipe["inputs"]), _counts(defs["recipes"][LASER]["inputs"]))
	assert_eq(recipe["work"], defs["recipes"][LASER]["work"])


func test_a_variant_prototype_takes_its_ideas_points_and_a_bench_test() -> void:
	var variant := ResearchDefs.derive_variant(defs, LASER, ["focused_beam", "light_frame"])
	var id: String = variant["id"]
	var prototype: Dictionary = variant["recipes"][ResearchDefs.prototype_id(id)]
	assert_eq(prototype["points"], 50)
	assert_eq(prototype["work"], 630_000, "twice the variant's own recipe")
	assert_eq(_counts(prototype["inputs"]), { "structural_frame": 18, "wiring": 36, "processor": 36 })
	assert_eq(variant["items"][ResearchDefs.prototype_id(id)]["unit_mass_g"], 320_000)
	var bench: Dictionary = variant["recipes"][ResearchDefs.qualify_id(id)]
	assert_eq(_counts(bench["inputs"]), { ResearchDefs.prototype_id(id): 1, "processor": 10 })
	assert_eq(bench["outputs"][-1], { "qualifies": id })
	assert_eq(variant["recipes"].size(), 3)
	_assert_balanced(variant["recipes"])


func test_a_variant_of_a_theory_unlocked_base_uses_the_theorys_bench_inputs() -> void:
	defs["modules"][CORE]["ideas"] = [{ "id": "lean", "name": "Lean", "points": 5, "complexity": 1,
		"deltas": { "mass_g": -100_000, "durability": -100_000 } }]
	defs["theories"][AUTONOMOUS_NAVIGATION]["qualify"] = [_count("wiring", 4)]
	var variant := ResearchDefs.derive_variant(defs, CORE, ["lean"])
	var bench: Dictionary = variant["recipes"][ResearchDefs.qualify_id(variant["id"])]
	assert_eq(_counts(bench["inputs"]), { ResearchDefs.prototype_id(variant["id"]): 1, "wiring": 4 })


func test_a_malformed_variant_is_refused() -> void:
	for ideas: Array in [[], ["focused_beam", "focused_beam"], ["unknown"], [7],
			["focused_beam", "light_frame", "simple_optics", "cast_housing", "heavy_mount"]]:
		assert_eq(ResearchDefs.derive_variant(defs, LASER, ideas), { "reason": "malformed_command" }, str(ideas))
	assert_eq(ResearchDefs.derive_variant(defs, "no_such_part", ["focused_beam"]), { "reason": "malformed_command" })
	assert_eq(ResearchDefs.derive_variant(defs, "small_hull", ["focused_beam"]).get("reason"), "malformed_command")


func test_a_stat_at_zero_or_below_is_refused() -> void:
	assert_eq(ResearchDefs.derive_variant(defs, LASER, ["no_beam"]), { "reason": "stat_out_of_range" })


func test_four_ideas_are_allowed() -> void:
	var variant := ResearchDefs.derive_variant(defs, LASER,
		["focused_beam", "light_frame", "simple_optics", "cast_housing"])
	assert_false(variant.has("reason"))
	assert_eq(variant["complexity"], 0, "2 + 1 - 2 - 1")


func test_derivation_changes_nothing_it_reads() -> void:
	var before := defs.duplicate(true)
	ResearchDefs.derive_static(defs)
	ResearchDefs.derive_variant(defs, LASER, ["focused_beam", "light_frame"])
	ResearchDefs.derive_variant(defs, CORE, ["nothing"])
	assert_eq(defs, before)
