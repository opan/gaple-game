extends GutTest
## Blocked-game (gapleh) winner: fewest tiles, then balak-weighted value, then
## clockwise-after-last-placer. (GAME_RULES §6.2)


func _hand(pairs: Array) -> Array:
	var h: Array = []
	for p in pairs:
		h.append(Tile.new(p[0], p[1]))
	return h


func _state(num_players: int, hands_pairs: Array, last_placer: int) -> GameState:
	var s := GameState.new()
	s.num_players = num_players
	s.hands = []
	for hp in hands_pairs:
		s.hands.append(_hand(hp))
	s.last_placer_seat = last_placer
	return s


func test_fewest_tiles_wins_regardless_of_pips() -> void:
	# seat0 has 1 (heavy) tile, seat1 has 2 (light) tiles. Fewest tiles -> seat0,
	# even though its pip total is higher than seat1's.
	var s := _state(2, [[[6, 6]], [[0, 1], [0, 2]]], 0)
	assert_eq(GapleGame.blocked_winner(s), 0)


func test_tie_on_count_breaks_on_balak_weighted_value() -> void:
	# Equal counts (2 each). seat0: two non-doubles -> value 2.
	# seat1: a double + a non-double, no 0-side tile -> value 2+1 = 3. seat0 wins.
	var s := _state(2, [[[1, 2], [3, 4]], [[5, 5], [3, 4]]], 0)
	assert_eq(GapleGame.blocked_winner(s), 0)


func test_zero_side_tile_makes_doubles_count_one() -> void:
	# Equal counts (2 each).
	# seat0: double 5|5 + plain 3|4, no 0 -> value 2 + 1 = 3.
	# seat1: double 5|5 + 0|6 (has a 0 side) -> double counts 1 -> value 1 + 1 = 2.
	# seat1 wins thanks to the 0-side discount.
	var s := _state(2, [[[5, 5], [3, 4]], [[5, 5], [0, 6]]], 0)
	assert_eq(GapleGame.blocked_winner(s), 1)


func test_full_tie_breaks_clockwise_after_last_placer() -> void:
	# Seats 0 and 2 both: 1 tile, a non-double -> value 1, fully tied. Seat 1 has 2.
	var hands := [
		[[2, 3]],   # seat 0: count 1, value 1
		[[6, 6], [5, 4]],  # seat 1: count 2
		[[1, 4]],   # seat 2: count 1, value 1
	]
	# Last placer = seat 0 -> scan 1,2,0 -> first tied is seat 2.
	assert_eq(GapleGame.blocked_winner(_state(3, hands, 0)), 2)
	# Last placer = seat 2 -> scan 0,1,2 -> first tied is seat 0.
	assert_eq(GapleGame.blocked_winner(_state(3, hands, 2)), 0)
