extends GutTest
## Blocked-game winner resolution and both tie-breakers. (GAME_RULES §6.2)


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


func test_lowest_pip_total_wins() -> void:
	# Totals: seat0 = 1+2 = 3, seat1 = 6+5 = 11.
	var s := _state(2, [[[0, 1], [0, 2]], [[6, 0], [5, 0]]], 0)
	assert_eq(GapleGame.blocked_winner(s), 0)


func test_tie_breaks_on_lowest_single_tile() -> void:
	# Both seats total 6. seat0 lowest tile = 3, seat1 lowest tile = 1 -> seat1.
	var s := _state(2, [[[1, 2], [0, 3]], [[0, 1], [2, 3]]], 0)
	assert_eq(GapleGame.blocked_winner(s), 1)


func test_full_tie_breaks_clockwise_after_last_placer() -> void:
	# Seats 0 and 2 both total 5 with lowest tile 2; seat 1 is far higher.
	var hands := [
		[[0, 2], [0, 3]],   # seat 0: total 5, min 2
		[[6, 6]],           # seat 1: total 12
		[[1, 1], [1, 2]],   # seat 2: total 5, min 2
	]
	# Last placer = seat 0 -> scan 1,2,0 -> first tied is seat 2.
	assert_eq(GapleGame.blocked_winner(_state(3, hands, 0)), 2)
	# Last placer = seat 2 -> scan 0,1,2 -> first tied is seat 0.
	assert_eq(GapleGame.blocked_winner(_state(3, hands, 2)), 0)
