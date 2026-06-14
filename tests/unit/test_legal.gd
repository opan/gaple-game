extends GutTest
## core/legal.gd — the client-side legal-move helper must match the engine.
## (PHASE_4_PLAN.md §4)


func test_opening_free_lists_every_tile_on_left() -> void:
	var hand := [Tile.new(2, 5).to_id(), Tile.new(1, 1).to_id()]
	var moves := Legal.moves_for(-1, -1, true, -1, hand)
	assert_eq(moves.size(), 2)
	for m in moves:
		assert_eq(m["end"], "L")


func test_opening_forced_lists_only_the_forced_tile() -> void:
	var forced := Tile.new(6, 6).to_id()
	var hand := [Tile.new(2, 5).to_id(), forced]
	var moves := Legal.moves_for(-1, -1, true, forced, hand)
	assert_eq(moves.size(), 1)
	assert_eq(moves[0]["tile_id"], forced)


func test_both_ends_and_equal_end_dedup() -> void:
	# ends 2 and 5: 2|5 matches both → two moves; 2|1 → left only; 5|3 → right only.
	var hand := [Tile.new(2, 5).to_id(), Tile.new(2, 1).to_id(), Tile.new(5, 3).to_id()]
	assert_eq(Legal.moves_for(2, 5, false, -1, hand).size(), 4)
	# ends 3 and 3: a 3|4 tile lists once (L), not twice.
	var hand2 := [Tile.new(3, 4).to_id()]
	var m2 := Legal.moves_for(3, 3, false, -1, hand2)
	assert_eq(m2.size(), 1)
	assert_eq(m2[0]["end"], "L")


func test_matches_engine_over_random_play() -> void:
	# At every step of many random games, the helper (fed only public info + the
	# current hand) must produce exactly what the engine produces.
	for i in range(300):
		var n := 2 + (i % 3)
		var g := GapleGame.new_round(n, i)
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 6151
		var steps := 0
		while g.state.is_active() and steps < 200:
			steps += 1
			var seat := g.state.current_seat
			var engine_moves := g.legal_moves(seat)
			var client_moves := Legal.moves_for(
				g.state.left_end, g.state.right_end, g.state.line.is_empty(),
				g.state.forced_opening_tile, g.state.hand_dict(seat))
			if engine_moves != client_moves:
				fail_test("mismatch at game %d step %d" % [i, steps])
				return
			if engine_moves.is_empty():
				g.apply({"type": "pass", "seat": seat})
			else:
				var m: Dictionary = engine_moves[rng.randi_range(0, engine_moves.size() - 1)]
				g.apply({"type": "play", "seat": seat, "tile_id": m["tile_id"], "end": m["end"]})
	assert_true(true, "helper matched the engine across 300 random games")
