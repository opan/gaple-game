extends GutTest
## Room + GameServer driven with fake peer ids and a recording transport — no
## sockets (PHASE_3_PLAN.md §10). Covers lobby, a full round, R2 (human+bot),
## R3 (join-in-progress), host abort, and the hidden-information guarantee.


class FakeTransport extends Transport:
	var sent: Array = []   # [{peer, msg}]

	func send(peer_id: int, msg: Dictionary) -> void:
		sent.append({"peer": peer_id, "msg": msg.duplicate(true)})

	func to_peer(peer_id: int, t: String) -> Array:
		var out: Array = []
		for e in sent:
			if e["peer"] == peer_id and e["msg"]["t"] == t:
				out.append(e["msg"])
		return out

	func last(peer_id: int, t: String) -> Dictionary:
		var all := to_peer(peer_id, t)
		return all[all.size() - 1] if not all.is_empty() else {}

	func count(t: String) -> int:
		var n := 0
		for e in sent:
			if e["msg"]["t"] == t:
				n += 1
		return n


var _t: FakeTransport
var _server: GameServer


func before_each() -> void:
	_t = FakeTransport.new()
	_server = GameServer.new()
	add_child_autofree(_server)
	_server.room_bot_delay = Vector2.ZERO
	_server.setup(_t)


func _msg(t: String, extra: Dictionary = {}) -> Dictionary:
	var m := {"t": t, "v": Protocol.VERSION}
	m.merge(extra)
	return m


func _create_room(peer: int, name: String) -> String:
	_server.on_message(peer, _msg(Protocol.C_HELLO, {"name": name}))
	_server.on_message(peer, _msg(Protocol.C_CREATE_ROOM))
	return _t.last(peer, Protocol.S_ROOM_STATE)["code"]


func _room(code: String) -> Room:
	return _server._rooms[code]


## Drive the round to completion, the test acting as each human by reading the
## engine for a legal move (white-box; ignorant clients are tested in Step 7).
func _play_out(code: String) -> void:
	var room := _room(code)
	var guard := 0
	while room.phase == Room.Phase.PLAYING and guard < 200:
		guard += 1
		var seat: int = room._game.state.current_seat
		var occ: Dictionary = room.seats[seat]
		var moves: Array = room._game.legal_moves(seat)
		# Drive only stops on a connected human with a move.
		assert_eq(occ["kind"], "human")
		assert_false(moves.is_empty())
		var m: Dictionary = moves[0]
		_server.on_message(occ["peer_id"],
			_msg(Protocol.C_PLAY_TILE, {"tile_id": m["tile_id"], "end": m["end"]}))
	assert_lt(guard, 200, "round finished")


func test_create_and_join_broadcast_room_state() -> void:
	var code := _create_room(1, "Host")
	assert_eq(code.length(), GameServer.CODE_LEN)
	_server.on_message(2, _msg(Protocol.C_HELLO, {"name": "Guest"}))
	_server.on_message(2, _msg(Protocol.C_JOIN_ROOM, {"code": code}))
	var rs := _t.last(2, Protocol.S_ROOM_STATE)
	assert_eq(rs["seats"].size(), 2, "host + guest seated")
	assert_eq(rs["host_seat"], 0)


func test_two_human_full_round() -> void:
	var code := _create_room(1, "Host")
	_server.on_message(2, _msg(Protocol.C_HELLO, {"name": "Guest"}))
	_server.on_message(2, _msg(Protocol.C_JOIN_ROOM, {"code": code}))
	_server.on_message(1, _msg(Protocol.C_START_GAME))
	assert_eq(_room(code).phase, Room.Phase.PLAYING)
	_play_out(code)
	assert_eq(_room(code).phase, Room.Phase.ROUND_OVER)
	assert_eq(_t.count(Protocol.S_ROUND_OVER), 2, "round_over broadcast to both")


func test_human_plus_bot_round() -> void:
	# R2 minimum: 1 human + 1 bot.
	var code := _create_room(1, "Host")
	_server.on_message(1, _msg(Protocol.C_ADD_BOT))
	assert_eq(_room(code).seats.size(), 2)
	assert_eq(_room(code).seats[1]["kind"], "bot")
	_server.on_message(1, _msg(Protocol.C_START_GAME))
	_play_out(code)
	assert_eq(_room(code).phase, Room.Phase.ROUND_OVER)


func test_join_in_progress_rejected() -> void:
	# R3: no joining once the game starts.
	var code := _create_room(1, "Host")
	_server.on_message(1, _msg(Protocol.C_ADD_BOT))
	_server.on_message(1, _msg(Protocol.C_START_GAME))
	_server.on_message(3, _msg(Protocol.C_HELLO, {"name": "Latecomer"}))
	_server.on_message(3, _msg(Protocol.C_JOIN_ROOM, {"code": code}))
	var err := _t.last(3, Protocol.S_ERROR)
	assert_eq(err["code"], Protocol.E_ROOM_IN_PROGRESS)


func test_non_host_cannot_start() -> void:
	var code := _create_room(1, "Host")
	_server.on_message(2, _msg(Protocol.C_HELLO, {"name": "Guest"}))
	_server.on_message(2, _msg(Protocol.C_JOIN_ROOM, {"code": code}))
	_server.on_message(2, _msg(Protocol.C_START_GAME))
	assert_eq(_t.last(2, Protocol.S_ERROR)["code"], Protocol.E_NOT_HOST)
	assert_eq(_room(code).phase, Room.Phase.LOBBY)


func test_host_end_game_aborts_with_no_scores() -> void:
	# Two humans so the round deterministically waits in PLAYING (humans are
	# never auto-played) until the host ends it.
	var code := _create_room(1, "Host")
	_server.on_message(2, _msg(Protocol.C_HELLO, {"name": "Guest"}))
	_server.on_message(2, _msg(Protocol.C_JOIN_ROOM, {"code": code}))
	_server.on_message(1, _msg(Protocol.C_START_GAME))
	assert_eq(_room(code).phase, Room.Phase.PLAYING)
	_server.on_message(1, _msg(Protocol.C_END_GAME))
	assert_eq(_room(code).phase, Room.Phase.ROUND_OVER)
	var ro := _t.last(1, Protocol.S_ROUND_OVER)
	assert_eq(ro["reason"], "ABORTED")
	assert_eq(ro["winner_seat"], -1)
	assert_eq(ro["scoreboard"], [0, 0], "aborted round records no score")


func _start_human_plus_bot(seed_value: int) -> Room:
	_server.room_seed = seed_value
	var code := _create_room(1, "Host")
	_server.on_message(1, _msg(Protocol.C_ADD_BOT))
	_server.on_message(1, _msg(Protocol.C_START_GAME))
	return _room(code)


func test_turn_timeout_autoplays_for_the_human() -> void:
	var room := _start_human_plus_bot(123)
	# Two-player game: if still playing, the only human (seat 0) is to move.
	if room.phase != Room.Phase.PLAYING:
		pass_test("round resolved immediately; nothing to time out")
		return
	assert_eq(room._game.state.current_seat, 0)
	var tiles_before: int = room._game.state.hands[0].size()
	room._handle_turn_timeout(0)
	assert_eq(room.seats[0]["timeouts"], 1, "one timeout recorded")
	# The server played for them: their hand shrank or the round ended.
	var advanced: bool = room._game.state.hands[0].size() < tiles_before or room.phase == Room.Phase.ROUND_OVER
	assert_true(advanced, "server auto-played for the timed-out human")


func test_three_consecutive_timeouts_convert_seat_to_bot() -> void:
	# Time out the human on every turn; in a game that lasts at least three of
	# their turns, the seat converts to a bot. Search seeds for such a game
	# (short rounds where someone wins first simply don't reach the 3rd timeout).
	var converted := false
	for seed in range(60):
		var room := _start_human_plus_bot(seed)
		var guard := 0
		while room.phase == Room.Phase.PLAYING and room.seats[0]["kind"] == "human" and guard < 12:
			guard += 1
			if room._game.state.current_seat == 0:
				room._handle_turn_timeout(0)
			else:
				break
		if room.seats[0]["kind"] == "bot":
			converted = true
			break
	assert_true(converted, "3 consecutive timeouts convert the seat (within searched seeds)")
	assert_gte(_t.count(Protocol.S_PLAYER_REPLACED), 1, "replacement was announced")


func _two_human_game() -> String:
	var code := _create_room(1, "Host")
	_server.on_message(2, _msg(Protocol.C_HELLO, {"name": "Guest"}))
	_server.on_message(2, _msg(Protocol.C_JOIN_ROOM, {"code": code}))
	_server.on_message(1, _msg(Protocol.C_START_GAME))
	return code


func test_disconnect_keeps_seat_and_reconnect_reclaims_it() -> void:
	var code := _two_human_game()
	var room := _room(code)

	_server.on_disconnect(2)
	assert_false(room.seats[1]["connected"], "seat marked disconnected")
	assert_eq(room.seats.size(), 2, "seat kept for reclaim")
	assert_gte(_t.count(Protocol.S_PLAYER_REPLACED), 1, "bot takeover announced")

	var token: String = room.seats[1]["token"]
	_server.on_message(7, _msg(Protocol.C_HELLO, {"name": "Guest", "session_token": token}))
	assert_true(room.seats[1]["connected"], "seat reclaimed")
	assert_eq(room.seats[1]["peer_id"], 7, "now owned by the reconnecting peer")
	assert_gte(_t.count(Protocol.S_PLAYER_RECLAIMED), 1, "reclaim announced")
	assert_gte(_t.to_peer(7, Protocol.S_HAND).size(), 1, "reconnecting peer resynced its hand")


func test_host_migrates_when_host_disconnects() -> void:
	var code := _two_human_game()
	var room := _room(code)
	_server.on_disconnect(1)                       # host (seat 0) drops
	assert_eq(room._host_seat, 1, "host migrates to the remaining human")
	# The new host can now act.
	_server.on_message(2, _msg(Protocol.C_END_GAME))
	assert_eq(room.phase, Room.Phase.ROUND_OVER)


func test_room_destroyed_when_last_human_leaves() -> void:
	var code := _create_room(1, "Solo")
	assert_true(_server._rooms.has(code))
	_server.on_disconnect(1)
	assert_false(_server._rooms.has(code), "empty room is destroyed")


func test_lobby_host_leaves_migrates_to_next_human() -> void:
	var code := _create_room(1, "Host")
	_server.on_message(2, _msg(Protocol.C_HELLO, {"name": "Guest"}))
	_server.on_message(2, _msg(Protocol.C_JOIN_ROOM, {"code": code}))
	var room := _room(code)
	_server.on_disconnect(1)                       # host leaves the lobby
	assert_eq(room.seats.size(), 1, "host seat freed")
	assert_eq(room.seats[0]["peer_id"], 2, "guest is now seat 0")
	assert_eq(room._host_seat, 0, "and is the new host")


func test_no_cross_seat_hand_leakage() -> void:
	var code := _create_room(1, "Host")
	_server.on_message(2, _msg(Protocol.C_HELLO, {"name": "Guest"}))
	_server.on_message(2, _msg(Protocol.C_JOIN_ROOM, {"code": code}))
	_server.on_message(1, _msg(Protocol.C_START_GAME))

	var room := _room(code)
	var hand0: Array = room._game.state.hand_dict(0)
	var hand1: Array = room._game.state.hand_dict(1)

	# Each peer received exactly its own opening hand and never the other's.
	assert_eq(_t.last(1, Protocol.S_HAND)["tile_ids"], hand0, "host got seat 0's hand")
	assert_eq(_t.last(2, Protocol.S_HAND)["tile_ids"], hand1, "guest got seat 1's hand")
	for e in _t.sent:
		if e["msg"]["t"] == Protocol.S_HAND:
			var owner_hand: Array = hand0 if e["peer"] == 1 else hand1
			assert_eq(e["msg"]["tile_ids"], owner_hand,
				"a hand message only ever goes to its owner (peer %d)" % e["peer"])
