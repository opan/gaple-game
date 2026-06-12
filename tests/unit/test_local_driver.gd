extends GutTest
## LocalGameDriver event flow with bots, run synchronously (bot_delay = 0).
## (PHASE_2_PLAN.md §5)


var _driver: LocalGameDriver
var _events: Array


func before_each() -> void:
	_driver = LocalGameDriver.new()
	_driver.bot_delay = Vector2.ZERO
	add_child_autofree(_driver)
	_events = []
	_driver.event_received.connect(func(m): _events.append(m))


func _types() -> Array:
	var out: Array = []
	for e in _events:
		out.append(e["t"])
	return out


func _count(t: String) -> int:
	var n := 0
	for e in _events:
		if e["t"] == t:
			n += 1
	return n


func _find(t: String) -> Dictionary:
	for e in _events:
		if e["t"] == t:
			return e
	return {}


## Drive a full game: every time control returns to the human, play a legal
## move (or pass). With zero bot delay everything runs synchronously, so when no
## round_over has arrived it must be the human's turn.
func _play_to_completion(num_players: int, seed_value: int) -> void:
	_driver.start(num_players, 0, seed_value)
	var guard := 0
	while _count(Protocol.S_ROUND_OVER) == 0 and guard < 200:
		guard += 1
		var moves := _driver.legal_moves_for_human()
		if moves.is_empty():
			_driver.submit_pass()
		else:
			var m: Dictionary = moves[0]
			_driver.submit_play(m["tile_id"], m["end"])
	assert_lt(guard, 200, "game finished without spinning")


func test_round_starts_with_setup_messages() -> void:
	_driver.start(2, 0, 4242)
	var t := _types()
	assert_eq(t[0], Protocol.S_GAME_STARTED, "first message announces the round")
	assert_eq(t[1], Protocol.S_HAND, "then the human's hand")
	assert_eq(t[2], Protocol.S_PUBLIC_STATE, "then the public board")
	assert_true(Protocol.S_TURN_STARTED in t, "and a turn_started")
	var hand := _find(Protocol.S_HAND)
	assert_eq(hand["tile_ids"].size(), GameState.HAND_SIZE, "human dealt 5 tiles")


func test_two_player_game_completes_with_one_round_over() -> void:
	_play_to_completion(2, 4242)
	assert_eq(_count(Protocol.S_ROUND_OVER), 1, "exactly one round_over")
	var ro := _find(Protocol.S_ROUND_OVER)
	assert_true(ro["winner_seat"] in [0, 1], "a real winner (not aborted)")
	assert_eq(ro["pip_counts"].size(), 2)
	assert_eq(ro["scores"].size(), 2)
	assert_eq(ro["scoreboard"].size(), 2)


func test_four_player_game_completes() -> void:
	_play_to_completion(4, 99)
	assert_eq(_count(Protocol.S_ROUND_OVER), 1)
	var ro := _find(Protocol.S_ROUND_OVER)
	assert_eq(ro["scoreboard"].size(), 4)


func test_winner_scores_zero_on_scoreboard_entry() -> void:
	_play_to_completion(3, 7)
	var ro := _find(Protocol.S_ROUND_OVER)
	var winner: int = ro["winner_seat"]
	assert_eq(ro["scores"][winner], 0, "the round winner scores 0 this round")


func test_illegal_human_intent_emits_error_not_crash() -> void:
	_driver.start(2, 0, 4242)
	# A wildly invalid tile id the human can't hold.
	_driver.submit_play(999, "L")
	assert_true(_count(Protocol.S_ERROR) >= 1, "illegal intent yields an error message")
