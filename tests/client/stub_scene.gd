class_name StubScene extends RefCounted
## The client scene on the stub, for tests that need scripted data rather than
## the real reference scenario.


static func build() -> Node:
	var main: Node = load("res://client/main.tscn").instantiate()
	main.scenario = StubSim.SCENARIO_ID
	return main
