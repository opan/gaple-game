class_name WsTransport
extends Transport
## Real transport: sends wire messages as JSON text frames over raw per-client
## WebSocketPeer connections (ADR-002). Raw WebSocket (not WebSocketMultiplayer-
## Peer) so browsers / wscat / any standard client get clean JSON, with no
## Godot multiplayer framing. The peer_id → WebSocketPeer map is owned and
## maintained by ServerMain.

var _clients: Dictionary


func _init(clients: Dictionary = {}) -> void:
	_clients = clients


func send(peer_id: int, msg: Dictionary) -> void:
	if not _clients.has(peer_id):
		return
	var ws: WebSocketPeer = _clients[peer_id]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))
