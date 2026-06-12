extends GutTest
## Opening rules (GAME_RULES §4): forced highest double, no-doubles fallback,
## and free open for "play again". (PLAN.md §4)


func _hand(pairs: Array) -> Array:
	var h: Array = []
	for p in pairs:
		h.append(Tile.new(p[0], p[1]))
	return h


func test_highest_double_opens() -> void:
	var hands := [
		_hand([[3, 3], [1, 2]]),
		_hand([[5, 5], [0, 4]]),
	]
	var o := GapleGame.determine_opener(hands)
	assert_eq(o["seat"], 1, "seat with the 5|5 opens")
	assert_eq(o["tile_id"], Tile.new(5, 5).to_id(), "must open with the highest double")


func test_no_doubles_uses_highest_pip_sum() -> void:
	var hands := [
		_hand([[1, 2], [0, 4]]),
		_hand([[3, 5], [1, 6]]),
	]
	var o := GapleGame.determine_opener(hands)
	assert_eq(o["seat"], 1)
	assert_eq(o["tile_id"], Tile.new(3, 5).to_id(), "3|5 (sum 8) is the highest tile")


func test_no_doubles_tie_breaks_on_higher_end() -> void:
	# Both tiles sum to 6; the one with the higher single end wins.
	var hands := [
		_hand([[2, 4]]),
		_hand([[1, 5]]),
	]
	var o := GapleGame.determine_opener(hands)
	assert_eq(o["seat"], 1, "1|5 (higher end = 5) beats 2|4 (higher end = 4)")
	assert_eq(o["tile_id"], Tile.new(1, 5).to_id())


func test_forced_opener_has_exactly_one_legal_move() -> void:
	var g := GapleGame.new_round(4, 777)
	var opener := g.state.current_seat
	var forced := g.state.forced_opening_tile
	assert_true(forced >= 0, "round 1 sets a forced opening tile")
	var moves := g.legal_moves(opener)
	assert_eq(moves.size(), 1, "opener may only play the forced tile")
	assert_eq(moves[0]["tile_id"], forced)


func test_non_current_seat_has_no_moves() -> void:
	var g := GapleGame.new_round(4, 777)
	var other := (g.state.current_seat + 1) % 4
	assert_eq(g.legal_moves(other).size(), 0, "only the current seat has moves")


func test_play_again_winner_opens_freely() -> void:
	var g := GapleGame.new_round(3, 555, 2)   # seat 2 won last round
	assert_eq(g.state.current_seat, 2)
	assert_eq(g.state.forced_opening_tile, -1, "free open, no forced tile")
	var moves := g.legal_moves(2)
	assert_eq(moves.size(), GameState.HAND_SIZE, "any of the 5 tiles may open")
