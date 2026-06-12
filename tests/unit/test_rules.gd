extends GutTest
## Legal moves, end selection, turn order, and intent rejection.
## (GAME_RULES §5, PLAN.md §4)


func _hand(pairs: Array) -> Array:
	var h: Array = []
	for p in pairs:
		h.append(Tile.new(p[0], p[1]))
	return h


## Build an active mid-game state (line already non-empty, ends set explicitly).
func _game(num_players: int, hands_pairs: Array, left_end: int, right_end: int, current_seat: int) -> GapleGame:
	var s := GameState.new()
	s.num_players = num_players
	s.hands = []
	for hp in hands_pairs:
		s.hands.append(_hand(hp))
	s.line = [Tile.new(0, 0)]   # placeholder so the engine isn't in "opening" mode
	s.left_end = left_end
	s.right_end = right_end
	s.current_seat = current_seat
	s.phase = GameState.Phase.PLAYING
	s.forced_opening_tile = -1
	s.last_placer_seat = (current_seat - 1 + num_players) % num_players
	var g := GapleGame.new()
	g.state = s
	return g


func _has_move(moves: Array, tile: Tile, end_side: String) -> bool:
	for m in moves:
		if m["tile_id"] == tile.to_id() and m["end"] == end_side:
			return true
	return false


func test_legal_moves_on_both_ends() -> void:
	var g := _game(2, [[[2, 1], [5, 3], [2, 5], [6, 0]], [[0, 0]]], 2, 5, 0)
	var moves := g.legal_moves(0)
	assert_eq(moves.size(), 4, "two single-end tiles + one both-ends tile (=2)")
	assert_true(_has_move(moves, Tile.new(2, 1), "L"))
	assert_true(_has_move(moves, Tile.new(5, 3), "R"))
	assert_true(_has_move(moves, Tile.new(2, 5), "L"))
	assert_true(_has_move(moves, Tile.new(2, 5), "R"))


func test_equal_open_ends_not_duplicated() -> void:
	var g := _game(2, [[[3, 4]], [[0, 0]]], 3, 3, 0)
	var moves := g.legal_moves(0)
	assert_eq(moves.size(), 1, "when both ends are 3, L and R are not listed twice")
	assert_eq(moves[0]["end"], "L")


func test_double_end_choice_is_honored() -> void:
	var g := _game(2, [[[2, 5], [4, 4]], [[1, 1]]], 2, 5, 0)
	var res := g.apply({"type": "play", "seat": 0, "tile_id": Tile.new(2, 5).to_id(), "end": "R"})
	assert_true(res["ok"], "playing the both-ends tile on the chosen end succeeds")
	assert_eq(g.state.right_end, 2, "right end becomes the tile's other side (2)")
	assert_eq(g.state.left_end, 2, "left end unchanged")


func test_reject_out_of_turn() -> void:
	var g := _game(2, [[[2, 1]], [[5, 3]]], 2, 5, 0)
	var res := g.apply({"type": "play", "seat": 1, "tile_id": Tile.new(5, 3).to_id(), "end": "R"})
	assert_false(res["ok"])
	assert_eq(res["error"], "not your turn")


func test_reject_tile_not_in_hand() -> void:
	var g := _game(2, [[[2, 1]], [[0, 0]]], 2, 5, 0)
	var res := g.apply({"type": "play", "seat": 0, "tile_id": Tile.new(6, 6).to_id(), "end": "L"})
	assert_false(res["ok"])
	assert_eq(res["error"], "tile not in hand")


func test_reject_non_matching_end() -> void:
	# 2|1 only matches the left end (2); playing it on the right (5) is illegal.
	var g := _game(2, [[[2, 1]], [[0, 0]]], 2, 5, 0)
	var res := g.apply({"type": "play", "seat": 0, "tile_id": Tile.new(2, 1).to_id(), "end": "R"})
	assert_false(res["ok"])
	assert_eq(res["error"], "illegal move")


func test_reject_voluntary_pass_with_legal_move() -> void:
	var g := _game(2, [[[2, 1]], [[0, 0]]], 2, 5, 0)
	var res := g.apply({"type": "pass", "seat": 0})
	assert_false(res["ok"])
	assert_eq(res["error"], "cannot pass with a legal move available")


func test_turn_advances_clockwise() -> void:
	for n in [2, 3, 4]:
		# Seat 0 keeps a spare tile so playing 2|1 isn't a round-winning move.
		var hands: Array = [[[2, 1], [6, 6]]]
		for _i in range(n - 1):
			hands.append([[0, 0]])
		var g := _game(n, hands, 2, 5, 0)
		g.apply({"type": "play", "seat": 0, "tile_id": Tile.new(2, 1).to_id(), "end": "L"})
		assert_eq(g.state.phase, GameState.Phase.PLAYING, "round still going (N=%d)" % n)
		assert_eq(g.state.current_seat, 1 % n, "turn passes to next seat (N=%d)" % n)


func test_forced_pass_advances_turn() -> void:
	# Seat 0 holds nothing matching 2 or 5 -> must pass; turn moves on, no block yet.
	var g := _game(3, [[[3, 4]], [[0, 0]], [[1, 6]]], 2, 5, 0)
	var res := g.apply({"type": "pass", "seat": 0})
	assert_true(res["ok"])
	assert_eq(g.state.current_seat, 1)
	assert_eq(g.state.consecutive_passes, 1)
