extends SceneTree
## Headless script WebSocket client for protocol testing (PHASE_3_PLAN.md §10).
## Connects, creates a room, adds a bot, starts, and auto-plays a full round
## against the server-side bot — proving the protocol over real cross-process
## sockets without any UI.
##
## It is deliberately an *ignorant* client: it doesn't compute legality (that's
## Phase 4). On its turn it just tries each held tile on each end until the
## server accepts one — which also exercises the server's validation path.
##
## Run:  godot --headless -s tools/ws_client.gd -- --url=ws://127.0.0.1:9301 --name=Demo

var _ws := WebSocketPeer.new()
var _url := "ws://127.0.0.1:9301"
var _name := "Demo"
var _state := "connecting"     # connecting → lobby → playing → done
var _my_seat := -1
var _hand: Array = []          # my tile ids
var _candidates: Array = []    # pending (tile_id, end) attempts this turn


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--url="):
			_url = arg.substr("--url=".length())
		elif arg.begins_with("--name="):
			_name = arg.substr("--name=".length())
	print("[client] connecting to %s" % _url)
	_ws.connect_to_url(_url)


func _process(_delta: float) -> bool:
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and _state == "connecting":
		_state = "lobby"
		_send({"t": Protocol.C_HELLO, "v": 1, "name": _name})
		_send({"t": Protocol.C_CREATE_ROOM, "v": 1})
		_send({"t": Protocol.C_ADD_BOT, "v": 1})
		_send({"t": Protocol.C_START_GAME, "v": 1})
	elif st == WebSocketPeer.STATE_CLOSED:
		print("[client] connection closed")
		return true   # quit

	while _ws.get_available_packet_count() > 0:
		var d = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
		if typeof(d) == TYPE_DICTIONARY:
			_on_message(d)

	if _state == "done":
		return true
	return false


func _on_message(m: Dictionary) -> void:
	match m.get("t", ""):
		Protocol.S_ROOM_STATE:
			print("[client] room %s, %d seat(s)" % [m.get("code", "?"), m["seats"].size()])
		Protocol.S_HAND:
			_my_seat = int(m.get("seat", -1))
			_hand = _to_ints(m["tile_ids"])
			print("[client] I am seat %d, hand=%s" % [_my_seat, str(_hand)])
		Protocol.S_TURN_STARTED:
			if int(m["seat"]) == _my_seat:
				_begin_my_turn()
		Protocol.S_TILE_PLAYED:
			if int(m["seat"]) == _my_seat:
				_hand.erase(int(m["tile_id"]))   # my move landed
				_candidates.clear()
		Protocol.S_ERROR:
			if m.get("code", "") == Protocol.E_ILLEGAL_MOVE:
				_try_next_candidate()             # that attempt was illegal — try another
		Protocol.S_ROUND_OVER:
			print("[client] round over: %s, winner seat %s, scores %s" % [
				m.get("reason"), str(m.get("winner_seat")), str(m.get("scores"))])
			_state = "done"


func _begin_my_turn() -> void:
	_candidates.clear()
	for tid in _hand:
		_candidates.append([tid, "L"])
		_candidates.append([tid, "R"])
	_try_next_candidate()


func _try_next_candidate() -> void:
	if _candidates.is_empty():
		return   # server will have auto-passed us if truly stuck
	var c: Array = _candidates.pop_front()
	_send({"t": Protocol.C_PLAY_TILE, "v": 1, "tile_id": c[0], "end": c[1]})


func _send(msg: Dictionary) -> void:
	_ws.send_text(JSON.stringify(msg))


func _to_ints(arr: Array) -> Array:
	var out: Array = []
	for x in arr:
		out.append(int(x))
	return out
