class_name NetworkConnection
extends Node
## Authoritative WebSocket client (PHASE_4_PLAN.md §6, ADR-002).
## Autoloaded as "Net". Manages the connection lifecycle, sends/receives JSON
## frames, emits event_received for every inbound server message, and handles
## auto-reconnect with the stored session_token on unexpected drops.
##
## Also implements the GameClient surface so game_table can bind directly.

# Explicit preloads so class_name globals resolve in Linux headless mode (no
# editor pre-scan) as well as the macOS editor environment.
const Protocol = preload("res://core/protocol.gd")
const NetConfig = preload("res://client/net/config.gd")

signal event_received(msg: Dictionary)
signal connection_changed(state: String)   # "connecting" | "open" | "reconnecting" | "closed"

const MAX_RETRIES    := 3
const BACKOFF_BASE   := 1.0   # seconds; doubles each retry

var _ws: WebSocketPeer
var _state: String = "closed"
var _retry_count: int = 0
var _retry_timer: float = 0.0
var _retrying: bool = false
var _session_token: String = ""
var _player_name: String = ""
var _config: ConfigFile


func _ready() -> void:
	_config = ConfigFile.new()
	_config.load("user://gaple.cfg")
	_session_token = _config.get_value("session", "token", "")
	_player_name   = _config.get_value("player", "name", "")


func _process(delta: float) -> void:
	if _retrying:
		_retry_timer -= delta
		if _retry_timer <= 0.0:
			_retrying = false
			_do_connect()
		return
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_drain()
		WebSocketPeer.STATE_CLOSED:
			if _state == "open" or _state == "reconnecting":
				_on_unexpected_close()


# --- public API (GameClient surface + lobby/menu helpers) -----------------

func connect_to_server() -> void:
	_retry_count = 0
	_do_connect()


func hello(player_name: String) -> void:
	_player_name = player_name
	_config.set_value("player", "name", player_name)
	_config.save("user://gaple.cfg")
	var msg := {"t": Protocol.C_HELLO, "v": Protocol.VERSION, "name": player_name}
	if _session_token != "":
		msg["session_token"] = _session_token
	_send(msg)


func create_room() -> void:
	_send({"t": Protocol.C_CREATE_ROOM, "v": Protocol.VERSION})


func join_room(code: String) -> void:
	_send({"t": Protocol.C_JOIN_ROOM, "v": Protocol.VERSION, "code": code})


func add_bot() -> void:
	_send({"t": Protocol.C_ADD_BOT, "v": Protocol.VERSION})


func remove_bot(seat: int) -> void:
	_send({"t": Protocol.C_REMOVE_BOT, "v": Protocol.VERSION, "seat": seat})


func start_game() -> void:
	_send({"t": Protocol.C_START_GAME, "v": Protocol.VERSION})


func submit_play(tile_id: int, end_side: String) -> void:
	_send({"t": Protocol.C_PLAY_TILE, "v": Protocol.VERSION, "tile_id": tile_id, "end": end_side})


func end_game() -> void:
	_send({"t": Protocol.C_END_GAME, "v": Protocol.VERSION})


func play_again() -> void:
	_send({"t": Protocol.C_PLAY_AGAIN, "v": Protocol.VERSION})


func leave() -> void:
	_send({"t": Protocol.C_LEAVE_ROOM, "v": Protocol.VERSION})


func get_player_name() -> String:
	return _player_name


# --- internals ------------------------------------------------------------

func _do_connect() -> void:
	_set_state("connecting")
	_ws = WebSocketPeer.new()
	var url := NetConfig.server_url()
	var err := _ws.connect_to_url(url)
	if err != OK:
		_schedule_retry()


func _drain() -> void:
	if _state != "open":
		_set_state("open")
		_retry_count = 0
		# Send hello immediately after open; re-hello with token on reconnect.
		hello(_player_name)
	while _ws.get_available_packet_count() > 0:
		var raw := _ws.get_packet().get_string_from_utf8()
		var data = JSON.parse_string(raw)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = data
		_handle_inbound(msg)


func _handle_inbound(msg: Dictionary) -> void:
	match msg.get("t", ""):
		Protocol.S_WELCOME:
			var token: String = msg.get("session_token", "")
			if token != "":
				_session_token = token
				_config.set_value("session", "token", token)
				_config.save("user://gaple.cfg")
	event_received.emit(msg)


func _on_unexpected_close() -> void:
	_schedule_retry()


func _schedule_retry() -> void:
	if _retry_count >= MAX_RETRIES:
		_set_state("closed")
		return
	_set_state("reconnecting")
	_retry_timer = BACKOFF_BASE * pow(2.0, _retry_count)
	_retry_count += 1
	_retrying = true


func _send(msg: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws.send_text(JSON.stringify(msg))


func _set_state(s: String) -> void:
	if _state == s:
		return
	_state = s
	connection_changed.emit(s)
