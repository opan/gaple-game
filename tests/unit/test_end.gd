extends GutTest
## Round endings: win by emptying hand (DOMINO) and blocked game. (GAME_RULES §6)


func _hand(pairs: Array) -> Array:
	var h: Array = []
	for p in pairs:
		h.append(Tile.new(p[0], p[1]))
	return h


func _game(num_players: int, hands_pairs: Array, left_end: int, right_end: int, current_seat: int) -> GapleGame:
	var s := GameState.new()
	s.num_players = num_players
	s.hands = []
	for hp in hands_pairs:
		s.hands.append(_hand(hp))
	s.line = [Tile.new(0, 0)]
	s.left_end = left_end
	s.right_end = right_end
	s.current_seat = current_seat
	s.phase = GameState.Phase.PLAYING
	s.forced_opening_tile = -1
	s.last_placer_seat = (current_seat - 1 + num_players) % num_players
	var g := GapleGame.new()
	g.state = s
	return g


func _last_event(res: Dictionary) -> Dictionary:
	return res["events"][res["events"].size() - 1]


func test_playing_last_tile_wins_by_domino() -> void:
	var g := _game(2, [[[2, 3]], [[5, 4]]], 2, 5, 0)
	var res := g.apply({"type": "play", "seat": 0, "tile_id": Tile.new(2, 3).to_id(), "end": "L"})
	assert_true(res["ok"])
	assert_eq(g.state.phase, GameState.Phase.ROUND_OVER)
	assert_eq(g.state.winner_seat, 0)
	assert_eq(g.state.end_reason, GameState.EndReason.DOMINO)
	var ev := _last_event(res)
	assert_eq(ev["type"], "round_over")
	assert_eq(ev["reason"], "DOMINO")


func test_full_pass_cycle_blocks_game() -> void:
	# Open ends are 2 and 5; nobody holds a matching tile.
	var g := _game(2, [[[0, 1]], [[3, 4]]], 2, 5, 0)
	assert_eq(g.legal_moves(0).size(), 0, "seat 0 is stuck")
	g.apply({"type": "pass", "seat": 0})
	var res := g.apply({"type": "pass", "seat": 1})
	assert_eq(g.state.phase, GameState.Phase.ROUND_OVER)
	assert_eq(g.state.end_reason, GameState.EndReason.BLOCKED)
	# Lower pip total wins: 0|1 (=1) beats 3|4 (=7).
	assert_eq(g.state.winner_seat, 0)
	var ev := _last_event(res)
	assert_eq(ev["reason"], "BLOCKED")


func test_no_more_intents_after_round_over() -> void:
	var g := _game(2, [[[2, 3]], [[5, 4]]], 2, 5, 0)
	g.apply({"type": "play", "seat": 0, "tile_id": Tile.new(2, 3).to_id(), "end": "L"})
	var res := g.apply({"type": "pass", "seat": 1})
	assert_false(res["ok"], "round is over; further intents are rejected")
	assert_eq(res["error"], "round not active")


func test_host_abort_voids_round() -> void:
	var g := _game(3, [[[2, 3]], [[5, 4]], [[1, 1]]], 2, 5, 0)
	var res := g.apply({"type": "abort", "seat": 0})
	assert_true(res["ok"])
	assert_eq(g.state.phase, GameState.Phase.ROUND_OVER)
	assert_eq(g.state.end_reason, GameState.EndReason.ABORTED)
	assert_eq(g.state.winner_seat, -1, "aborted round has no winner")
