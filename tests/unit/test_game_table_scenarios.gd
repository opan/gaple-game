extends GutTest
## Acceptance scenarios driven through the real GameTable + LocalGameDriver:
## a blocked game shows the right winner, and a forced opener only enables the
## forced tile. (PHASE_2_PLAN.md §11)


func _table(num_players: int, seed_value: int) -> GameTable:
	var t := GameTable.new()
	t.bot_delay = Vector2.ZERO
	add_child_autofree(t)
	t.start_game(num_players, seed_value)
	return t


func test_blocked_game_is_reachable_and_names_a_winner() -> void:
	# Drive games synchronously through the driver, the human playing random
	# legal moves so blocked games occur; verify the reported winner holds the
	# fewest pips.
	var rng := RandomNumberGenerator.new()
	var found_blocked := false
	for s in range(200):
		var driver := LocalGameDriver.new()
		driver.bot_delay = Vector2.ZERO
		add_child_autofree(driver)
		var ro := {}
		# NOTE: mutate the shared dict (don't reassign) — GDScript lambdas capture
		# locals by copy, so `ro = m` would not reach this scope.
		driver.event_received.connect(func(m):
			if m["t"] == Protocol.S_ROUND_OVER:
				ro.merge(m, true))
		rng.seed = s
		driver.start(2 + (s % 3), 0, s)
		var guard := 0
		while ro.is_empty() and guard < 200:
			guard += 1
			var moves := driver._game.legal_moves(driver._human_seat)
			if moves.is_empty():
				break  # should not happen: driver only yields when human has moves
			var m: Dictionary = moves[rng.randi_range(0, moves.size() - 1)]
			driver.submit_play(m["tile_id"], m["end"])
		if ro.get("reason", "") == "BLOCKED":
			found_blocked = true
			var pips: Array = ro["pip_counts"]
			var winner: int = ro["winner_seat"]
			var lowest: int = pips.min()
			assert_eq(pips[winner], lowest, "blocked winner holds the fewest pips (seed %d)" % s)
			break
		driver.queue_free()
	assert_true(found_blocked, "a blocked game is reachable within the searched seeds")


func test_table_renders_a_blocked_round_over() -> void:
	# Table-specific: a BLOCKED round_over surfaces the overlay (winner display
	# is core-tested; here we confirm the table handles the reason).
	var t := _table(2, 1)
	t._on_event(Protocol.round_over("BLOCKED", 1, [7, 2], [7, 0], [7, 0]))
	assert_true(t.is_round_over(), "blocked round shows the round-over overlay")


func test_forced_opener_enables_only_the_forced_tile() -> void:
	# Use the engine to find a seed where the human (seat 0) is the round-1
	# opener, then verify the table/driver offers exactly that forced tile.
	var seed_value := -1
	var forced := -1
	for s in range(200):
		var g := GapleGame.new_round(2, s)
		if g.state.current_seat == 0 and g.state.forced_opening_tile >= 0:
			seed_value = s
			forced = g.state.forced_opening_tile
			break
	assert_gte(seed_value, 0, "found a seed where the human opens")

	var t := _table(2, seed_value)
	# After start_game the table has pre-computed _moves for the human opener.
	var moves: Array = t._moves
	assert_eq(moves.size(), 1, "opener may only play the forced tile")
	assert_eq(moves[0]["tile_id"], forced, "and it is the forced opening tile")
