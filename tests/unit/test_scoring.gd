extends GutTest
## Per-round scoring: winner 0, others their own pips, aborted scores nobody.
## (GAME_RULES §7)


func _hand(pairs: Array) -> Array:
	var h: Array = []
	for p in pairs:
		h.append(Tile.new(p[0], p[1]))
	return h


func _finished(reason: int, winner: int, hands_pairs: Array) -> GameState:
	var s := GameState.new()
	s.num_players = hands_pairs.size()
	s.hands = []
	for hp in hands_pairs:
		s.hands.append(_hand(hp))
	s.phase = GameState.Phase.ROUND_OVER
	s.end_reason = reason
	s.winner_seat = winner
	return s


func test_domino_winner_zero_others_pips() -> void:
	var s := _finished(GameState.EndReason.DOMINO, 0, [[], [[3, 4]], [[1, 1]]])
	assert_eq(GapleGame.round_scores(s), [0, 7, 2])


func test_blocked_winner_scores_zero_despite_holding_tiles() -> void:
	# Seat 1 wins the blocked game but still holds tiles -> scores 0 anyway.
	var s := _finished(GameState.EndReason.BLOCKED, 1, [[[3, 4]], [[0, 1]], [[2, 2]]])
	assert_eq(GapleGame.round_scores(s), [7, 0, 4])


func test_aborted_round_scores_nobody() -> void:
	var s := _finished(GameState.EndReason.ABORTED, -1, [[[3, 4]], [[1, 1]]])
	assert_eq(GapleGame.round_scores(s), [], "aborted round records no scores")
