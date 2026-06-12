extends GutTest
## Random legal playout stress test. Every round, for all seat counts, must
## reach ROUND_OVER with zero rejected intents. (PLAN.md §4 acceptance)
##
## CI runs ROUNDS rounds; a one-off 10,000-round run is done manually at the
## Phase 1 acceptance gate (see PLAN.md / tools/fuzz_playout.gd).

const ROUNDS := 500
const MAX_STEPS := 300   # a domino round is far shorter; guards against a stuck loop


func test_random_playouts_always_terminate() -> void:
	for i in range(ROUNDS):
		var num_players := 2 + (i % 3)          # cycles 2,3,4
		var g := GapleGame.new_round(num_players, i)
		var picker := RandomNumberGenerator.new()
		picker.seed = i * 2654435761

		var steps := 0
		while g.state.is_active() and steps < MAX_STEPS:
			steps += 1
			var seat := g.state.current_seat
			var moves := g.legal_moves(seat)
			var res: Dictionary
			if moves.is_empty():
				res = g.apply({"type": "pass", "seat": seat})
			else:
				var m: Dictionary = moves[picker.randi_range(0, moves.size() - 1)]
				res = g.apply({"type": "play", "seat": seat, "tile_id": m["tile_id"], "end": m["end"]})
			if not res["ok"]:
				fail_test("round %d (N=%d) rejected a legal intent: %s" % [i, num_players, res["error"]])
				return

		if g.state.phase != GameState.Phase.ROUND_OVER:
			fail_test("round %d (N=%d) did not terminate within %d steps" % [i, num_players, MAX_STEPS])
			return

	assert_true(true, "%d random rounds across 2/3/4 players all terminated cleanly" % ROUNDS)
