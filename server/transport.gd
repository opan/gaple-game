class_name Transport
extends RefCounted
## Outbound message sink the Room/GameServer use, so they never touch WebSocket
## APIs directly (PHASE_3_PLAN.md §3/R3). server_main provides a WS-backed impl;
## tests provide a recording fake. This is what makes the whole room layer
## unit-testable without sockets.


## Send one wire message to a single peer.
func send(_peer_id: int, _msg: Dictionary) -> void:
	push_error("Transport.send() not implemented")


## Send the same message to many peers.
func broadcast(peer_ids: Array, msg: Dictionary) -> void:
	for pid in peer_ids:
		send(pid, msg)
