extends GutTest
## PlanetGrid (task A14): the Goldberg grid, its IDs and neighbours, and integer terrain.

const ONE := OrbitMath.ONE
const WEIGHTS := [4, 2, 1]
## SHA-256 of every cell's height, moisture and roll on the n = 33 planet with seed 48213.
## Any change to generation changes this, so it is a deliberate, reviewed change.
const GOLDEN_33 := "90653cd8c79739b58f8ea55eed7e35dcca1ffab0e06bca9fee5e2f90e67e0132"


## Neighbours built the slow way, from every lattice triangle of every diamond's chart.
func _triangle_neighbours(n: int) -> Dictionary:
	var links := {}
	var faces := {}
	for d in PlanetGrid.DIAMONDS:
		for i in n:
			for j in n:
				var a := PlanetGrid.cell_at(d, i, j, n)
				var b := PlanetGrid.cell_at(d, i + 1, j, n)
				var c := PlanetGrid.cell_at(d, i, j + 1, n)
				var e := PlanetGrid.cell_at(d, i + 1, j + 1, n)
				for tri: Array in [[a, b, c], [b, e, c]]:
					var sorted := tri.duplicate()
					sorted.sort()
					faces[sorted] = true
					for s in 3:
						links.get_or_add(tri[s], {})[tri[(s + 1) % 3]] = true
						links.get_or_add(tri[(s + 1) % 3], {})[tri[s]] = true
	return { "links": links, "faces": faces.size() }


func test_n_follows_the_radius_so_hexes_stay_about_7_km() -> void:
	assert_eq(PlanetGrid.n_for_radius(600_000_000), 100)
	assert_eq(PlanetGrid.n_for_radius(200_000_000), 33)
	assert_eq(PlanetGrid.n_for_radius(1_200_000_000), 200)
	assert_eq(PlanetGrid.n_for_radius(1_000_000), 1)
	assert_eq(PlanetGrid.cell_count(100), 100_002)


func test_every_chart_point_is_listed_by_its_cell() -> void:
	for n in [1, 2, 3, 5, 8]:
		var seen := {}
		for d in PlanetGrid.DIAMONDS:
			for i in n + 1:
				for j in n + 1:
					seen.get_or_add(PlanetGrid.cell_at(d, i, j, n), []).append([d, i, j])
		assert_eq(seen.size(), PlanetGrid.cell_count(n), "every cell reached, n = %d" % n)
		for cell: int in seen:
			var expected: Array = seen[cell]
			var listed := PlanetGrid.chart_points(cell, n)
			expected.sort()
			listed.sort()
			assert_eq(listed, expected, "cell %d, n = %d" % [cell, n])


func test_shared_chart_points_are_the_same_place() -> void:
	var n := 8
	var place := {}
	for d in PlanetGrid.DIAMONDS:
		for i in n + 1:
			for j in n + 1:
				var cell := PlanetGrid.cell_at(d, i, j, n)
				var point := PlanetGrid._flat_point(d, i, j, n)
				if place.has(cell):
					assert_eq(point, place[cell], "cell %d" % cell)
				place[cell] = point


func test_neighbours_match_the_triangles_and_form_a_sphere() -> void:
	for n in [1, 2, 3, 7, 33]:
		var built := _triangle_neighbours(n)
		var links: Dictionary = built["links"]
		var count := PlanetGrid.cell_count(n)
		var pentagons := 0
		var edges := 0
		var mismatched := 0
		for cell in count:
			var mine := PlanetGrid.neighbours(cell, n)
			var theirs: Array = links[cell].keys()
			theirs.sort()
			if mine != theirs:
				mismatched += 1
			if mine.size() == 5:
				pentagons += 1
			else:
				assert_eq(mine.size(), 6, "cell %d, n = %d" % [cell, n])
			edges += mine.size()
		edges /= 2
		assert_eq(mismatched, 0, "n = %d" % n)
		assert_eq(pentagons, 12, "n = %d" % n)
		assert_eq(count - edges + int(built["faces"]), 2, "Euler, n = %d" % n)


func test_the_grid_at_n_100_has_twelve_pentagons_and_two_way_links() -> void:
	var n := 100
	var corners := [PlanetGrid.NORTH, PlanetGrid.SOUTH]
	for k in 5:
		corners.append(PlanetGrid.cell_at(k, n, 0, n))
		corners.append(PlanetGrid.cell_at(5 + k, n, 0, n))
	for cell: int in corners:
		assert_eq(PlanetGrid.neighbours(cell, n).size(), 5, "corner %d" % cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for sample in 2000:
		var cell := rng.randi_range(0, PlanetGrid.cell_count(n) - 1)
		var around := PlanetGrid.neighbours(cell, n)
		assert_eq(around.size(), 5 if corners.has(cell) else 6)
		for other in around:
			assert_true(PlanetGrid.neighbours(other, n).has(cell), "%d and %d" % [cell, other])


func test_directions_are_unit_vectors_with_north_on_plus_y() -> void:
	assert_eq(PlanetGrid.direction(PlanetGrid.NORTH, 100), [0, ONE, 0])
	assert_eq(PlanetGrid.direction(PlanetGrid.SOUTH, 100), [0, -ONE, 0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var shortest := 1 << 62
	var longest := 0
	for sample in 500:
		var cell := rng.randi_range(0, PlanetGrid.cell_count(100) - 1)
		var dir := PlanetGrid.direction(cell, 100)
		assert_almost_eq(IntMath.dist(dir, [0, 0, 0]), ONE, 2)
		var centre := PlanetGrid.centre_mm(cell, 100, 600_000_000, 0)
		for other in PlanetGrid.neighbours(cell, 100):
			var gap := IntMath.dist(centre, PlanetGrid.centre_mm(other, 100, 600_000_000, 0))
			shortest = mini(shortest, gap)
			longest = maxi(longest, gap)
	print("PLANET neighbour spacing at 600 km: %d to %d m" % [shortest / 1000, longest / 1000])
	assert_gt(shortest, 5_000_000)
	assert_lt(longest, 8_000_000)


func test_terrain_stays_in_range_and_replays() -> void:
	var n := 33
	var low := 1 << 30
	var high := -(1 << 30)
	var wet_low := 1 << 30
	var wet_high := -1
	for cell in PlanetGrid.cell_count(n):
		var dir := PlanetGrid.direction(cell, n)
		var height := PlanetGrid.height_m(48213, dir, WEIGHTS, 8000)
		var wet := PlanetGrid.moisture(48213, dir, WEIGHTS)
		low = mini(low, height)
		high = maxi(high, height)
		wet_low = mini(wet_low, wet)
		wet_high = maxi(wet_high, wet)
		assert_eq(PlanetGrid.height_m(48213, dir, WEIGHTS, 8000), height)
	print("PLANET n = 33: height %d to %d m, moisture %d to %d" % [low, high, wet_low, wet_high])
	assert_between(low, -8000, 0)
	assert_between(high, 0, 8000)
	assert_between(wet_low, 0, 1000)
	assert_between(wet_high, 0, 1000)
	assert_eq(PlanetGrid.height_m(48213, [ONE, 0, 0], WEIGHTS, 0), 0, "a flat world")


func test_noise_cannot_leave_its_range_at_the_extremes() -> void:
	for dir: Array in [[ONE, 0, 0], [-ONE, 0, 0], [0, ONE, 0], [0, -ONE, 0], [0, 0, ONE], [0, 0, -ONE]]:
		for seed in [0, 1, -1, 0x7FFFFFFF, 1 << 40]:
			var value := PlanetGrid.noise(seed, dir, [1, 1, 1, 1, 1, 1])
			assert_between(value, 0, PlanetGrid.NOISE_MAX)


func test_a_fixed_planet_matches_its_golden_hash() -> void:
	var n := 33
	var parts := PackedStringArray()
	for cell in PlanetGrid.cell_count(n):
		var dir := PlanetGrid.direction(cell, n)
		parts.append("%d,%d,%d" % [PlanetGrid.height_m(48213, dir, WEIGHTS, 8000),
			PlanetGrid.moisture(48213, dir, WEIGHTS), PlanetGrid.roll(48213, cell, 1)])
	var digest := ";".join(parts).sha256_text()
	print("PLANET golden n = 33: %s" % digest)
	assert_eq(digest, GOLDEN_33)


func test_cost_per_cell() -> void:
	var n := 100
	var start := Time.get_ticks_usec()
	for cell in range(0, PlanetGrid.cell_count(n), 100):
		var dir := PlanetGrid.direction(cell, n)
		PlanetGrid.height_m(48213, dir, WEIGHTS, 8000)
		PlanetGrid.moisture(48213, dir, WEIGHTS)
		PlanetGrid.roll(48213, cell, 1)
	var cell_us := float(Time.get_ticks_usec() - start) / (PlanetGrid.cell_count(n) / 100)
	start = Time.get_ticks_usec()
	for cell in range(0, PlanetGrid.cell_count(n), 100):
		PlanetGrid.neighbours(cell, n)
	var neighbour_us := float(Time.get_ticks_usec() - start) / (PlanetGrid.cell_count(n) / 100)
	print("PLANET cost: one cell's direction, height, moisture and roll %.1f us; neighbours %.1f us" % [
		cell_us, neighbour_us])
	assert_lt(cell_us, 500.0)
	assert_lt(neighbour_us, 500.0)
