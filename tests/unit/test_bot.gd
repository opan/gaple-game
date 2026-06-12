extends GutTest
## Bot policy (ADR-004 Greedy+): priorities and the never-illegal guarantee.


var _rng: RandomNumberGenerator


func before_each() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 1234


func _move(t: Tile, end_side: String) -> Dictionary:
	return {"tile_id": t.to_id(), "end": end_side}


func test_takes_winning_move_at_one_tile() -> void:
	var bot := BotPolicy.new()
	var only := Tile.new(2, 3)
	var legal := [_move(only, "L")]
	var chosen := bot.choose_move({}, [only.to_id()], legal, _rng)
	assert_eq(chosen["tile_id"], only.to_id(), "plays the last tile to win")


func test_prefers_dumping_a_double() -> void:
	var bot := BotPolicy.new()
	var dbl := Tile.new(4, 4)
	var plain := Tile.new(2, 3)
	var hand := [dbl.to_id(), plain.to_id()]
	var legal := [_move(dbl, "L"), _move(plain, "R")]
	var chosen := bot.choose_move({}, hand, legal, _rng)
	assert_eq(chosen["tile_id"], dbl.to_id(), "double is the riskiest to hold — dump it")


func test_prefers_highest_pip_sum_without_doubles() -> void:
	var bot := BotPolicy.new()
	var small := Tile.new(2, 3)   # 5
	var big := Tile.new(5, 6)     # 11
	var hand := [small.to_id(), big.to_id()]
	var legal := [_move(small, "L"), _move(big, "R")]
	var chosen := bot.choose_move({}, hand, legal, _rng)
	assert_eq(chosen["tile_id"], big.to_id())


func test_returns_empty_when_no_legal_moves() -> void:
	var bot := BotPolicy.new()
	assert_eq(bot.choose_move({}, [Tile.new(1, 2).to_id()], [], _rng), {})


func test_easy_is_a_legal_move() -> void:
	var bot := BotPolicy.new(BotPolicy.Difficulty.EASY)
	var a := Tile.new(1, 2)
	var b := Tile.new(3, 4)
	var legal := [_move(a, "L"), _move(b, "R")]
	var chosen := bot.choose_move({}, [a.to_id(), b.to_id()], legal, _rng)
	assert_true(chosen in legal, "EASY still returns a member of the legal set")


func test_never_returns_an_illegal_move_over_many_games() -> void:
	# Drive whole games with the bot in every seat; every chosen move must be a
	# member of the engine's current legal set.
	var bot := BotPolicy.new()
	for i in range(1000):
		var n := 2 + (i % 3)
		var g := GapleGame.new_round(n, i)
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 7919
		var steps := 0
		while g.state.is_active() and steps < 300:
			steps += 1
			var seat := g.state.current_seat
			var legal := g.legal_moves(seat)
			if legal.is_empty():
				g.apply({"type": "pass", "seat": seat})
				continue
			var chosen := bot.choose_move(g.state.public_dict(), g.state.hand_dict(seat), legal, rng)
			if not (chosen in legal):
				fail_test("game %d: bot chose a move outside the legal set" % i)
				return
			g.apply({"type": "play", "seat": seat, "tile_id": chosen["tile_id"], "end": chosen["end"]})
		assert_eq(g.state.phase, GameState.Phase.ROUND_OVER, "game %d terminated" % i)
