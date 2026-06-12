extends GutTest
## Integration: GameTable consumes a full round of driver events and self-drives
## the human to completion without errors, then shows the round-over overlay.
## (PHASE_2_PLAN.md §11 — the headless-verifiable parts.)


func _new_table(num_players: int, seed_value: int) -> GameTable:
	var table := GameTable.new()
	table.human_pass_delay = 0.0
	add_child_autofree(table)
	table.start_game(num_players, seed_value)
	table.get_driver().bot_delay = Vector2.ZERO
	return table


func _run_to_end(table: GameTable) -> void:
	var guard := 0
	while not table.is_round_over() and guard < 400:
		guard += 1
		table.autoplay_human_turn()
		await get_tree().process_frame   # lets any 0-delay forced-pass fire
	assert_true(table.is_round_over(), "table reached round-over")
	assert_lt(guard, 400, "no infinite spin")


func test_full_two_player_game_reaches_round_over() -> void:
	var table := _new_table(2, 4242)
	await _run_to_end(table)


func test_full_four_player_game_builds_three_opponent_seats() -> void:
	var table := GameTable.new()
	table.human_pass_delay = 0.0
	add_child_autofree(table)
	table.start_game(4, 99)
	table.get_driver().bot_delay = Vector2.ZERO
	# One OpponentSeat per non-local seat.
	var seats := 0
	for c in table.get_children():
		if c is OpponentSeat:
			seats += 1
	assert_eq(seats, 3, "3 opponent seats for a 4-player game")
	await _run_to_end(table)


func test_seat_mapping_matches_whiteboard() -> void:
	var table := GameTable.new()
	add_child_autofree(table)
	# 4 players: rel 1→RIGHT, 2→TOP, 3→LEFT (GAME_RULES §8).
	assert_eq(table._screen_for(1, 4), "RIGHT")
	assert_eq(table._screen_for(2, 4), "TOP")
	assert_eq(table._screen_for(3, 4), "LEFT")
	# 3 players: RIGHT + LEFT; 2 players: TOP.
	assert_eq(table._screen_for(1, 3), "RIGHT")
	assert_eq(table._screen_for(2, 3), "LEFT")
	assert_eq(table._screen_for(1, 2), "TOP")
