extends GutTest
## Tile value type — normalization, id round-trip, matching. (PLAN.md §4)


func test_normalization_orders_low_high() -> void:
	var t := Tile.new(5, 2)
	assert_eq(t.low, 2, "low end is the smaller pip")
	assert_eq(t.high, 5, "high end is the larger pip")


func test_double_detection() -> void:
	assert_true(Tile.new(4, 4).is_double())
	assert_false(Tile.new(3, 4).is_double())


func test_pips() -> void:
	assert_eq(Tile.new(2, 5).pips(), 7)
	assert_eq(Tile.new(0, 0).pips(), 0)


func test_id_anchors() -> void:
	assert_eq(Tile.new(0, 0).to_id(), 0, "(0,0) is id 0")
	assert_eq(Tile.new(0, 6).to_id(), 6, "(0,6) is id 6")
	assert_eq(Tile.new(1, 1).to_id(), 7, "(1,1) is id 7")
	assert_eq(Tile.new(6, 6).to_id(), 27, "(6,6) is id 27")


func test_id_roundtrip_and_uniqueness_for_all_28() -> void:
	var seen := {}
	for id in range(28):
		var t := Tile.from_id(id)
		assert_eq(t.to_id(), id, "from_id(%d).to_id() round-trips" % id)
		assert_true(t.low <= t.high, "tile %d is normalized" % id)
		seen[id] = true
	assert_eq(seen.size(), 28, "all 28 ids are distinct")


func test_matches_and_other_side() -> void:
	var t := Tile.new(2, 5)
	assert_true(t.matches(2))
	assert_true(t.matches(5))
	assert_false(t.matches(3))
	assert_eq(t.other_side(2), 5, "playing onto a 2 leaves the 5 open")
	assert_eq(t.other_side(5), 2, "playing onto a 5 leaves the 2 open")


func test_double_other_side_stays_same() -> void:
	var d := Tile.new(4, 4)
	assert_eq(d.other_side(4), 4, "a double leaves the same value open")


func test_equals() -> void:
	assert_true(Tile.new(2, 5).equals(Tile.new(5, 2)))
	assert_false(Tile.new(2, 5).equals(Tile.new(2, 6)))
