extends GutTest
## End-to-end over real WebSockets (PHASE_3_PLAN.md §10/§11): two in-process
## clients connect to a live ServerMain, create/join/start, and play a full round
## to completion. Also checks hidden information survives the wire (each client
## only ever receives its own hand).


class WsClient:
	var ws := WebSocketPeer.new()
	var inbox: Array = []

	func open_to(port: int) -> void:
		ws.connect_to_url("ws://127.0.0.1:%d" % port)

	func pump() -> void:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var d = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if typeof(d) == TYPE_DICTIONARY:
				inbox.append(d)

	func is_open() -> bool:
		return ws.get_ready_state() == WebSocketPeer.STATE_OPEN

	func send(msg: Dictionary) -> void:
		ws.send_text(JSON.stringify(msg))

	func last(t: String) -> Dictionary:
		for i in range(inbox.size() - 1, -1, -1):
			if inbox[i].get("t", "") == t:
				return inbox[i]
		return {}

	func count(t: String) -> int:
		var n := 0
		for d in inbox:
			if d.get("t", "") == t:
				n += 1
		return n


func _ints(arr: Array) -> Array:
	var out: Array = []
	for x in arr:
		out.append(int(x))
	return out


func _pump(clients: Array, frames: int) -> void:
	for _i in range(frames):
		for c in clients:
			c.pump()
		await get_tree().process_frame


func test_two_clients_play_a_full_round_over_websocket() -> void:
	var sm := ServerMain.new()
	add_child_autofree(sm)
	var port := 0
	for p in range(9211, 9230):
		if sm.start(p) == OK:
			port = p
			break
	assert_gt(port, 0, "server bound a port")
	sm.server.room_bot_delay = Vector2.ZERO

	var c1 := WsClient.new()
	var c2 := WsClient.new()
	c1.open_to(port)
	c2.open_to(port)
	var guard := 0
	while not (c1.is_open() and c2.is_open()) and guard < 200:
		guard += 1
		await _pump([c1, c2], 1)
	assert_true(c1.is_open() and c2.is_open(), "both clients connected")

	c1.send({"t": Protocol.C_HELLO, "v": 1, "name": "Host"})
	c1.send({"t": Protocol.C_CREATE_ROOM, "v": 1})
	await _pump([c1, c2], 8)
	var code: String = c1.last(Protocol.S_ROOM_STATE).get("code", "")
	assert_ne(code, "", "host received a room code")

	c2.send({"t": Protocol.C_HELLO, "v": 1, "name": "Guest"})
	c2.send({"t": Protocol.C_JOIN_ROOM, "v": 1, "code": code})
	await _pump([c1, c2], 8)
	c1.send({"t": Protocol.C_START_GAME, "v": 1})
	await _pump([c1, c2], 10)

	var room: Room = sm.server._rooms[code]
	# Hidden information survived the wire: each client got exactly its own hand.
	# (JSON numbers decode as floats, so compare as ints.)
	assert_eq(_ints(c1.last(Protocol.S_HAND).get("tile_ids", [])), room._game.state.hand_dict(0), "host = seat 0 hand")
	assert_eq(_ints(c2.last(Protocol.S_HAND).get("tile_ids", [])), room._game.state.hand_dict(1), "guest = seat 1 hand")
	assert_ne(c1.last(Protocol.S_HAND).get("tile_ids"), c2.last(Protocol.S_HAND).get("tile_ids"),
		"the two clients never see the same hand")

	# Play to completion: each client sends its own legal move (move chosen via
	# the server's engine — clients send, server validates and broadcasts).
	var clients := [c1, c2]
	var steps := 0
	while room.phase == Room.Phase.PLAYING and steps < 80:
		steps += 1
		var seat: int = room._game.state.current_seat
		var moves: Array = room._game.legal_moves(seat)
		assert_false(moves.is_empty(), "waiting seat always has a move")
		var m: Dictionary = moves[0]
		clients[seat].send({"t": Protocol.C_PLAY_TILE, "v": 1, "tile_id": m["tile_id"], "end": m["end"]})
		await _pump(clients, 3)

	assert_eq(room.phase, Room.Phase.ROUND_OVER, "round finished over the websocket")
	assert_gte(c1.count(Protocol.S_ROUND_OVER), 1, "host saw round_over")
	assert_gte(c2.count(Protocol.S_ROUND_OVER), 1, "guest saw round_over")
