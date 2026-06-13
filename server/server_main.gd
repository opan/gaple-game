class_name ServerMain
extends Node
## Headless WebSocket front-end (PHASE_3_PLAN.md §4). Accepts raw WebSocket
## connections via TCPServer + WebSocketPeer.accept_stream (so browsers and any
## standard WS client speak clean JSON), polls them each frame, and feeds
## connect/disconnect/packet events into the transport-agnostic GameServer.
## Single-threaded, no locks (R6).

var server: GameServer

var _tcp := TCPServer.new()
var _clients: Dictionary = {}    # peer_id -> WebSocketPeer
var _open: Dictionary = {}       # peer_id -> bool (connect already announced)
var _next_id := 2                # 1 is conventionally the server itself
var _transport: WsTransport


## Begin listening. Returns OK or a Godot error code.
func start(port: int) -> int:
	var err := _tcp.listen(port)
	if err != OK:
		return err
	_transport = WsTransport.new(_clients)
	server = GameServer.new()
	add_child(server)
	server.setup(_transport)
	set_process(true)
	return OK


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.accept_stream(_tcp.take_connection())
		_clients[_next_id] = ws
		_open[_next_id] = false
		_next_id += 1

	var closed: Array = []
	for id in _clients:
		var ws: WebSocketPeer = _clients[id]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				if not _open[id]:
					_open[id] = true
					server.on_connect(id)
				while ws.get_available_packet_count() > 0:
					_on_packet(id, ws.get_packet())
			WebSocketPeer.STATE_CLOSED:
				closed.append(id)

	for id in closed:
		if _open.get(id, false):
			server.on_disconnect(id)
		_clients.erase(id)
		_open.erase(id)


func _on_packet(from: int, bytes: PackedByteArray) -> void:
	var parsed := Protocol.parse(bytes.get_string_from_utf8())
	if not parsed["ok"]:
		_transport.send(from, Protocol.error(parsed["code"], parsed["code"]))
		return
	server.on_message(from, parsed["msg"])
