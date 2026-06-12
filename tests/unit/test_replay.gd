extends GutTest
## Determinism: same seed + same intent log reproduces the same final state.
## (PLAN.md §4) — this is the property that lets server and client agree.


func test_replay_reproduces_final_state() -> void:
	var num_players := 4
	var game_seed := 246813

	# First playthrough — record every intent applied.
	var g := GapleGame.new_round(num_players, game_seed)
	var picker := RandomNumberGenerator.new()
	picker.seed = 9001
	var intent_log: Array = []
	var guard := 0
	while g.state.is_active() and guard < 500:
		guard += 1
		var seat := g.state.current_seat
		var moves := g.legal_moves(seat)
		var intent: Dictionary
		if moves.is_empty():
			intent = {"type": "pass", "seat": seat}
		else:
			var m: Dictionary = moves[picker.randi_range(0, moves.size() - 1)]
			intent = {"type": "play", "seat": seat, "tile_id": m["tile_id"], "end": m["end"]}
		intent_log.append(intent)
		var res := g.apply(intent)
		assert_true(res["ok"], "recorded intent applied cleanly")

	assert_eq(g.state.phase, GameState.Phase.ROUND_OVER, "first playthrough finished")
	var final_a := g.state.to_dict()

	# Replay the same intents on a fresh game with the same deal.
	var g2 := GapleGame.new_round(num_players, game_seed)
	for intent in intent_log:
		var res := g2.apply(intent)
		assert_true(res["ok"], "replayed intent applied cleanly")

	assert_eq(g2.state.to_dict(), final_a, "replay yields an identical final state")
