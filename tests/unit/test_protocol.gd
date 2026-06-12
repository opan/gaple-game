extends GutTest
## Wire-contract builders and engine-event translation. (PHASE_2_PLAN.md §3)


func test_msg_stamps_type_and_version() -> void:
	var m := Protocol.msg("foo", {"a": 1})
	assert_eq(m["t"], "foo")
	assert_eq(m["v"], Protocol.VERSION)
	assert_eq(m["a"], 1)


func test_msg_does_not_mutate_payload() -> void:
	var payload := {"a": 1}
	Protocol.msg("foo", payload)
	assert_false(payload.has("t"), "builder copies the payload, doesn't stamp the caller's dict")


func test_builders_carry_version() -> void:
	for m in [
		Protocol.game_started(4, 2, 27),
		Protocol.hand([1, 2, 3]),
		Protocol.public_state({"x": 1}),
		Protocol.turn_started(1),
		Protocol.round_over("DOMINO", 0, [0, 7], [0, 7], [0, 7]),
		Protocol.error(Protocol.E_ILLEGAL_MOVE, "nope"),
	]:
		assert_eq(m["v"], Protocol.VERSION)
		assert_true(m.has("t"))


func test_game_started_payload() -> void:
	var m := Protocol.game_started(3, 2, 27)
	assert_eq(m["t"], Protocol.S_GAME_STARTED)
	assert_eq(m["opener_seat"], 2)
	assert_eq(m["opening_tile_id"], 27)


func test_turn_started_default_deadline() -> void:
	var m := Protocol.turn_started(1)
	assert_eq(m["deadline_unix_ms"], -1, "no timer in local play")


func test_from_engine_event_renames_type() -> void:
	var ev := {"type": "tile_played", "seat": 0, "tile_id": 5, "end": "L",
		"new_left_end": 3, "new_right_end": 4, "remaining_count": 4}
	var m := Protocol.from_engine_event(ev)
	assert_eq(m["t"], "tile_played")
	assert_false(m.has("type"), "the engine's 'type' key is removed")
	assert_eq(m["v"], Protocol.VERSION)
	assert_eq(m["seat"], 0)
	assert_eq(m["remaining_count"], 4)


func test_from_engine_event_merges_enrichment() -> void:
	var ev := {"type": "round_over", "reason": "BLOCKED", "winner_seat": 1}
	var m := Protocol.from_engine_event(ev, {
		"pip_counts": [5, 0, 9],
		"scores": [5, 0, 9],
		"scoreboard": [5, 0, 9],
	})
	assert_eq(m["t"], "round_over")
	assert_eq(m["reason"], "BLOCKED")
	assert_eq(m["pip_counts"], [5, 0, 9])
	assert_eq(m["scoreboard"], [5, 0, 9])


func test_from_engine_event_does_not_mutate_source() -> void:
	var ev := {"type": "player_passed", "seat": 2}
	Protocol.from_engine_event(ev)
	assert_true(ev.has("type"), "source event is left untouched")
	assert_false(ev.has("t"))
