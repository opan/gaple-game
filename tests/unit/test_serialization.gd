extends GutTest
## (De)serialization and redacted views. (PLAN.md §4, ADR-002 hidden info)


## Play a few legal moves so the state is genuinely mid-game.
func _midgame() -> GapleGame:
	var g := GapleGame.new_round(4, 31337)
	for _step in range(6):
		if not g.state.is_active():
			break
		var seat := g.state.current_seat
		var moves := g.legal_moves(seat)
		if moves.is_empty():
			g.apply({"type": "pass", "seat": seat})
		else:
			var m: Dictionary = moves[0]
			g.apply({"type": "play", "seat": seat, "tile_id": m["tile_id"], "end": m["end"]})
	return g


func test_to_dict_from_dict_roundtrip() -> void:
	var g := _midgame()
	var before := g.state.to_dict()
	var restored := GameState.from_dict(before)
	assert_eq(restored.to_dict(), before, "full state round-trips exactly")


func test_public_dict_hides_hands() -> void:
	var g := _midgame()
	var pub := g.state.public_dict()
	assert_false(pub.has("hands"), "public view must not contain hand contents")
	assert_true(pub.has("tile_counts"), "public view exposes only counts")
	for seat in range(g.state.num_players):
		assert_eq(pub["tile_counts"][seat], g.state.hands[seat].size(),
			"count matches the real hand size for seat %d" % seat)


func test_hand_dict_returns_only_that_seat() -> void:
	var g := _midgame()
	var ids := g.state.hand_dict(1)
	assert_eq(ids.size(), g.state.hands[1].size())
	# The returned ids correspond exactly to seat 1's tiles.
	var expected := {}
	for t in g.state.hands[1]:
		expected[t.to_id()] = true
	for id in ids:
		assert_true(expected.has(id), "id %d belongs to seat 1" % id)
