extends GutTest
## Builds every real template through the client's layout and placeholder code.
## Reads data/ directly because no real scenario serves defs() yet; layout
## fields are already in millimetres, so no unit conversion is involved.

var modules: Dictionary = {}
var templates: Array = []
var next_id := 0


func before_all() -> void:
	for module: Dictionary in _entries("modules.json"):
		modules[module["id"]] = module
	templates = _entries("templates.json")


func _entries(file_name: String) -> Array:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file_name))
	return parsed["entries"]


## Turns a template tree into the shape the view uses.
func _view_tree(entry: Dictionary) -> Dictionary:
	next_id += 1
	var part: Dictionary = {
		"id": next_id, "def": entry["part"],
		"parent_connector": entry.get("parent_connector", ""), "connector": entry.get("connector", ""),
		"children": [],
	}
	for child: Dictionary in entry["children"]:
		part["children"].append(_view_tree(child))
	return part


func _assert_joins(parent: Dictionary) -> void:
	for child: Dictionary in parent["children"]:
		var a := CraftLayout.find_connector(modules[parent["def"]], child["parent_connector"])
		var b := CraftLayout.find_connector(modules[child["def"]], child["connector"])
		assert_false(a.is_empty(), "%s has %s" % [parent["def"], child["parent_connector"]])
		assert_false(b.is_empty(), "%s has %s" % [child["def"], child["connector"]])
		if not a.is_empty() and not b.is_empty():
			var parent_frame := CraftLayout.connector_transform(a)
			var child_frame := CraftLayout.mate(a, b) * CraftLayout.connector_transform(b)
			assert_almost_eq(child_frame.origin.distance_to(parent_frame.origin), 0.0, 0.0001, child["def"])
			assert_almost_eq(child_frame.basis.z.distance_to(-parent_frame.basis.z), 0.0, 0.0001, child["def"])
			assert_almost_eq(child_frame.basis.y.distance_to(parent_frame.basis.y), 0.0, 0.0001, child["def"])
		_assert_joins(child)


func test_data_is_present() -> void:
	assert_gt(modules.size(), 0)
	assert_gt(templates.size(), 0)


func test_every_template_mates_by_connector_data() -> void:
	for template: Dictionary in templates:
		_assert_joins(_view_tree(template["root"]))


func test_every_template_builds_placeholders() -> void:
	for template: Dictionary in templates:
		var craft := CraftNode.new()
		add_child_autofree(craft)
		var tree := _view_tree(template["root"])
		craft.build(1, tree, modules)
		assert_eq(craft.part_transforms.size(), _count(tree), template["id"])
		assert_gt(craft.fit_radius_m, 0.0)


func test_every_module_has_a_usable_tint_and_collision() -> void:
	for id: String in modules:
		var module: Dictionary = modules[id]
		assert_true(Color.html_is_valid(module["visual"].get("tint", "")), "%s tint" % id)
		assert_true(["box", "cylinder"].has(module["collision"]["shape"]), "%s collision" % id)
		assert_eq(module["collision"]["size_mm"].size(), 3, "%s size" % id)


func _count(part: Dictionary) -> int:
	var total := 1
	for child: Dictionary in part["children"]:
		total += _count(child)
	return total
