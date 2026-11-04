class_name PlanetReceiver extends RefCounted
## Stands in for a BodyNode when testing PlanetMesh.request: counts deliveries.

var received := 0


func planet_built(_built: Dictionary) -> void:
	received += 1
