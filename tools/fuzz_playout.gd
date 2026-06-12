extends SceneTree
## Standalone Phase 1 acceptance harness: play many random *legal* rounds across
## all seat counts and confirm every one terminates with no rejected intent.
##
## Run:  godot --headless -s tools/fuzz_playout.gd -- --rounds=10000
## (defaults to 10000). Exits 0 on success, 1 on any failure.

const DEFAULT_ROUNDS := 10000
const MAX_STEPS := 300


func _initialize() -> void:
	var rounds := DEFAULT_ROUNDS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rounds="):
			rounds = arg.substr("--rounds=".length()).to_int()

	print("[fuzz] running %d random legal rounds (2/3/4 players)..." % rounds)
	var domino := 0
	var blocked := 0

	for i in range(rounds):
		var num_players := 2 + (i % 3)
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
				push_error("[fuzz] round %d (N=%d) rejected a legal intent: %s" % [i, num_players, res["error"]])
				quit(1)
				return

		if g.state.phase != GameState.Phase.ROUND_OVER:
			push_error("[fuzz] round %d (N=%d) did not terminate in %d steps" % [i, num_players, MAX_STEPS])
			quit(1)
			return

		if g.state.end_reason == GameState.EndReason.DOMINO:
			domino += 1
		elif g.state.end_reason == GameState.EndReason.BLOCKED:
			blocked += 1

	print("[fuzz] PASS — %d rounds terminated cleanly (%d by domino, %d blocked)." % [rounds, domino, blocked])
	quit(0)
