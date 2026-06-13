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


# --- inbound parsing/validation -----------------------------------------

func test_parse_rejects_bad_json() -> void:
	var r := Protocol.parse("not json {{")
	assert_false(r["ok"])
	assert_eq(r["code"], Protocol.E_BAD_INTENT)


func test_parse_rejects_non_object() -> void:
	assert_eq(Protocol.parse("[1,2,3]")["code"], Protocol.E_BAD_INTENT)
	assert_eq(Protocol.parse("42")["code"], Protocol.E_BAD_INTENT)


func test_parse_rejects_missing_version() -> void:
	assert_eq(Protocol.parse('{"t":"hello"}')["code"], Protocol.E_BAD_INTENT)


func test_parse_flags_version_mismatch() -> void:
	var r := Protocol.parse('{"t":"hello","v":999}')
	assert_false(r["ok"])
	assert_eq(r["code"], Protocol.E_UPDATE_REQUIRED)


func test_parse_rejects_missing_type() -> void:
	assert_eq(Protocol.parse('{"v":1}')["code"], Protocol.E_BAD_INTENT)


func test_parse_accepts_valid_message() -> void:
	var text := JSON.stringify({"t": Protocol.C_PLAY_TILE, "v": Protocol.VERSION, "tile_id": 5, "end": "L"})
	var r := Protocol.parse(text)
	assert_true(r["ok"])
	assert_eq(r["msg"]["t"], Protocol.C_PLAY_TILE)


func test_validate_play_tile() -> void:
	assert_eq(Protocol.validate_client({"t": Protocol.C_PLAY_TILE, "tile_id": 5, "end": "L"}), "")
	assert_eq(Protocol.validate_client({"t": Protocol.C_PLAY_TILE, "end": "L"}), Protocol.E_BAD_INTENT)
	assert_eq(Protocol.validate_client({"t": Protocol.C_PLAY_TILE, "tile_id": 99, "end": "L"}), Protocol.E_BAD_INTENT)
	assert_eq(Protocol.validate_client({"t": Protocol.C_PLAY_TILE, "tile_id": 5, "end": "X"}), Protocol.E_BAD_INTENT)


func test_validate_hello_and_join() -> void:
	assert_eq(Protocol.validate_client({"t": Protocol.C_HELLO, "name": "Opan"}), "")
	assert_eq(Protocol.validate_client({"t": Protocol.C_HELLO}), Protocol.E_BAD_INTENT)
	assert_eq(Protocol.validate_client({"t": Protocol.C_JOIN_ROOM, "code": "K7Q2F"}), "")
	assert_eq(Protocol.validate_client({"t": Protocol.C_JOIN_ROOM}), Protocol.E_BAD_INTENT)


func test_validate_fieldless_and_unknown() -> void:
	assert_eq(Protocol.validate_client({"t": Protocol.C_START_GAME}), "")
	assert_eq(Protocol.validate_client({"t": "bogus_type"}), Protocol.E_BAD_INTENT)
