class_name GameServer
extends Node
## Connection + session + room dispatch (PHASE_3_PLAN.md §3). Transport-injected,
## so tests drive it with fake peer ids and no sockets; server_main feeds it the
## real WebSocket events. Room registry/codes live here for v1 (the master plan's
## separate RoomManager is folded in).

const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O/1/I
const CODE_LEN := 5

var _transport: Transport
var _sessions: Dictionary = {}   # peer_id -> {name, token, room_code}
var _rooms: Dictionary = {}      # code -> Room
var _rng := RandomNumberGenerator.new()
var room_bot_delay := Vector2(0.8, 2.0)   # propagated to new rooms (tests set ZERO)
var room_seed := -1                       # deterministic deal for tests (-1 = random)


func setup(transport: Transport) -> void:
	_transport = transport
	_rng.randomize()


func on_connect(peer_id: int) -> void:
	_sessions[peer_id] = {"name": "Player", "token": "", "room_code": ""}


func on_disconnect(peer_id: int) -> void:
	var room := _room_of(peer_id)
	if room != null:
		room._do_leave(peer_id)
	_sessions.erase(peer_id)


func on_message(peer_id: int, msg: Dictionary) -> void:
	if not _sessions.has(peer_id):
		on_connect(peer_id)
	var code := Protocol.validate_client(msg)
	if code != "":
		_transport.send(peer_id, Protocol.error(code, code))
		return

	match msg["t"]:
		Protocol.C_HELLO:
			_handle_hello(peer_id, msg)
		Protocol.C_CREATE_ROOM:
			_handle_create(peer_id)
		Protocol.C_JOIN_ROOM:
			_handle_join(peer_id, str(msg["code"]))
		_:
			var room := _room_of(peer_id)
			if room == null:
				_transport.send(peer_id, Protocol.error(Protocol.E_ROOM_NOT_FOUND, "not in a room"))
			else:
				room.handle(peer_id, msg)


# --- handlers ------------------------------------------------------------

func _handle_hello(peer_id: int, msg: Dictionary) -> void:
	var s: Dictionary = _sessions[peer_id]
	s["name"] = str(msg["name"])
	var token := str(msg.get("session_token", ""))

	# Reconnect: a known token matching a disconnected seat reclaims it.
	if token != "":
		for room_code in _rooms:
			var room: Room = _rooms[room_code]
			if room.try_reclaim(peer_id, token) >= 0:
				s["token"] = token
				s["room_code"] = room_code
				_transport.send(peer_id, Protocol.welcome(token))
				return

	if s["token"] == "":
		s["token"] = _new_token()
	_transport.send(peer_id, Protocol.welcome(s["token"]))


func _handle_create(peer_id: int) -> void:
	var s: Dictionary = _sessions[peer_id]
	var room := Room.new()
	var room_code := _new_code()
	add_child(room)
	room.bot_delay = room_bot_delay
	room.setup(room_code, _transport, room_seed)
	room.empty.connect(destroy_room)
	_rooms[room_code] = room
	s["room_code"] = room_code
	if s["token"] == "":
		s["token"] = _new_token()
	room.add_host(peer_id, s["name"], s["token"])


func _handle_join(peer_id: int, room_code: String) -> void:
	var s: Dictionary = _sessions[peer_id]
	if not _rooms.has(room_code):
		_transport.send(peer_id, Protocol.error(Protocol.E_ROOM_NOT_FOUND, "no such room"))
		return
	var room: Room = _rooms[room_code]
	var err := room.add_human(peer_id, s["name"], s["token"])
	if err != "":
		_transport.send(peer_id, Protocol.error(err, err))
		return
	s["room_code"] = room_code


# --- helpers -------------------------------------------------------------

func _room_of(peer_id: int) -> Room:
	if not _sessions.has(peer_id):
		return null
	var room_code: String = _sessions[peer_id]["room_code"]
	return _rooms.get(room_code)


func destroy_room(room_code: String) -> void:
	if _rooms.has(room_code):
		_rooms[room_code].queue_free()
		_rooms.erase(room_code)


func _new_code() -> String:
	while true:
		var c := ""
		for _i in range(CODE_LEN):
			c += CODE_ALPHABET[_rng.randi_range(0, CODE_ALPHABET.length() - 1)]
		if not _rooms.has(c):
			return c
	return ""


func _new_token() -> String:
	return "%08x%08x" % [_rng.randi(), _rng.randi()]
