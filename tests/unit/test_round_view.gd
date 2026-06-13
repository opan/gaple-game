extends GutTest
## RoundView — the shared event→wire + announce logic (PHASE_3_PLAN.md §9).


func test_passthrough_event_just_restamps() -> void:
	var g := GapleGame.new_round(2, 1)
	var ev := {"type": "tile_played", "seat": 0, "tile_id": 5, "end": "L",
		"new_left_end": 3, "new_right_end": 4, "remaining_count": 4}
	var msg := RoundView.to_wire(g, ev, [0, 0])
	assert_eq(msg["t"], "tile_played")
	assert_eq(msg["v"], Protocol.VERSION)
	assert_eq(msg["remaining_count"], 4)


func test_turn_started_gets_deadline() -> void:
	var g := GapleGame.new_round(2, 1)
	var ev := {"type": "turn_started", "seat": 1}
	var msg := RoundView.to_wire(g, ev, [0, 0], 123456)
	assert_eq(msg["t"], "turn_started")
	assert_eq(msg["deadline_unix_ms"], 123456)


func test_round_over_computes_scores_and_accumulates() -> void:
	# A finished DOMINO state: seat 0 empty (winner), seat 1 holds 3|4 = 7.
	var g := GapleGame.new()
	var s := GameState.new()
	s.num_players = 2
	s.hands = [[], [Tile.new(3, 4)]]
	s.phase = GameState.Phase.ROUND_OVER
	s.end_reason = GameState.EndReason.DOMINO
	s.winner_seat = 0
	g.state = s

	var scoreboard := [10, 5]   # carried from previous rounds
	var ev := {"type": "round_over", "reason": "DOMINO", "winner_seat": 0}
	var msg := RoundView.to_wire(g, ev, scoreboard)

	assert_eq(msg["pip_counts"], [0, 7], "pip counts from current hands")
	assert_eq(msg["scores"], [0, 7], "winner 0, loser their pips")
	assert_eq(msg["scoreboard"], [10, 12], "accumulated onto the prior totals")
	assert_eq(scoreboard, [10, 12], "caller's scoreboard is mutated in place")


func test_announce_bundles_messages_and_all_hands() -> void:
	var g := GapleGame.new_round(3, 42)
	var a := RoundView.announce(g, 999)

	assert_eq(a["game_started"]["t"], Protocol.S_GAME_STARTED)
	assert_eq(a["game_started"]["opener_seat"], g.state.current_seat)
	assert_eq(a["public_state"]["t"], Protocol.S_PUBLIC_STATE)
	assert_false(a["public_state"]["state"].has("hands"), "public state hides hands")
	assert_eq(a["turn_started"]["deadline_unix_ms"], 999)

	assert_eq(a["hands"].size(), 3, "a hand entry per seat")
	for seat in range(3):
		assert_eq(a["hands"][seat]["tile_ids"], g.state.hand_dict(seat),
			"hand for seat %d matches the engine" % seat)
