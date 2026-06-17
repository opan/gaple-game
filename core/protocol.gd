class_name Protocol
extends RefCounted
## The wire contract shared by the local driver (Phase 2) and the network
## server (Phase 3). Pure (ADR-003): message-type constants, the version stamp,
## builder functions, and the engine-event → wire-message translation.
##
## Every wire message is a Dictionary with "t" (type) and "v" (VERSION). Engine
## events from GapleGame.apply() use "type" instead; from_engine_event bridges
## the two and adds data the pure engine doesn't have. See docs/PHASE_2_PLAN.md
## §3 and PLAN.md §6.

const VERSION := 1

# --- Server → client message types ---------------------------------------
const S_WELCOME := "welcome"
const S_ROOM_STATE := "room_state"
const S_GAME_STARTED := "game_started"
const S_HAND := "hand"
const S_PUBLIC_STATE := "public_state"
const S_TILE_PLAYED := "tile_played"
const S_TILE_DRAWN := "tile_drawn"     ## private: sent only to the drawing player
const S_PLAYER_PASSED := "player_passed"
const S_TURN_STARTED := "turn_started"
const S_ROUND_OVER := "round_over"
const S_PLAYER_REPLACED := "player_replaced_by_bot"
const S_PLAYER_RECLAIMED := "player_reclaimed"
const S_ERROR := "error"

# --- Client → server message types (used by Phase 3/4) -------------------
const C_HELLO := "hello"
const C_CREATE_ROOM := "create_room"
const C_JOIN_ROOM := "join_room"
const C_ADD_BOT := "add_bot"
const C_REMOVE_BOT := "remove_bot"
const C_START_GAME := "start_game"
const C_PLAY_TILE := "play_tile"
const C_PASS := "pass"
const C_END_GAME := "end_game"
const C_PLAY_AGAIN := "play_again"
const C_LEAVE_ROOM := "leave_room"

# --- Error codes (single source; Phase 3 emits them) ---------------------
const E_BAD_INTENT := "BAD_INTENT"
const E_NOT_YOUR_TURN := "NOT_YOUR_TURN"
const E_ILLEGAL_MOVE := "ILLEGAL_MOVE"
const E_NOT_HOST := "NOT_HOST"
const E_ROOM_NOT_FOUND := "ROOM_NOT_FOUND"
const E_ROOM_FULL := "ROOM_FULL"
const E_ROOM_IN_PROGRESS := "ROOM_IN_PROGRESS"
const E_UPDATE_REQUIRED := "UPDATE_REQUIRED"


## Stamp a payload with its type and the protocol version.
static func msg(t: String, payload: Dictionary = {}) -> Dictionary:
	var d := payload.duplicate()
	d["t"] = t
	d["v"] = VERSION
	return d


static func game_started(num_players: int, opener_seat: int, opening_tile_id: int) -> Dictionary:
	return msg(S_GAME_STARTED, {
		"num_players": num_players,
		"opener_seat": opener_seat,
		"opening_tile_id": opening_tile_id,   # -1 for a free open ("play again")
	})


## The recipient's hand. `seat` tells the client which seat it occupies (so it
## can render itself at the bottom and map opponents — GAME_RULES §8).
static func hand(tile_ids: Array, seat: int = -1) -> Dictionary:
	return msg(S_HAND, {"tile_ids": tile_ids, "seat": seat})


static func public_state(public: Dictionary) -> Dictionary:
	return msg(S_PUBLIC_STATE, {"state": public})


static func turn_started(seat: int, deadline_unix_ms: int = -1) -> Dictionary:
	return msg(S_TURN_STARTED, {"seat": seat, "deadline_unix_ms": deadline_unix_ms})


static func round_over(reason: String, winner_seat: int, pip_counts: Array, scores: Array, scoreboard: Array) -> Dictionary:
	return msg(S_ROUND_OVER, {
		"reason": reason,
		"winner_seat": winner_seat,
		"pip_counts": pip_counts,
		"scores": scores,
		"scoreboard": scoreboard,
	})


static func error(code: String, message: String) -> Dictionary:
	return msg(S_ERROR, {"code": code, "message": message})


static func welcome(session_token: String) -> Dictionary:
	return msg(S_WELCOME, {"session_token": session_token})


## seats: Array of {seat, name, kind ("human"/"bot"/"empty"), connected}.
static func room_state(code: String, host_seat: int, seats: Array, phase: String, scoreboard: Array) -> Dictionary:
	return msg(S_ROOM_STATE, {
		"code": code,
		"host_seat": host_seat,
		"seats": seats,
		"phase": phase,
		"scoreboard": scoreboard,
	})


static func tile_drawn(seat: int, tile_id: int) -> Dictionary:
	return msg(S_TILE_DRAWN, {"seat": seat, "tile_id": tile_id})


static func player_replaced_by_bot(seat: int) -> Dictionary:
	return msg(S_PLAYER_REPLACED, {"seat": seat})


static func player_reclaimed(seat: int) -> Dictionary:
	return msg(S_PLAYER_RECLAIMED, {"seat": seat})


## Translate one raw engine event (from GapleGame.apply().events) into a wire
## message: rename "type" → "t", stamp "v", and merge `enrich` (e.g. the
## deadline for turn_started, or pip_counts/scores/scoreboard for round_over).
static func from_engine_event(ev: Dictionary, enrich: Dictionary = {}) -> Dictionary:
	var out := ev.duplicate(true)
	out.erase("type")
	out["t"] = ev["type"]
	out["v"] = VERSION
	for k in enrich:
		out[k] = enrich[k]
	return out


# --- inbound (server side) ----------------------------------------------

## Parse one raw text frame from a client. Returns
## { ok: bool, msg: Dictionary, code: String }. On failure `code` is the error
## code to send back; on success `msg` is the decoded object.
static func parse(text: String) -> Dictionary:
	# Use a JSON instance (not parse_string) so malformed input returns an error
	# code instead of pushing a noisy engine error to the log.
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "msg": {}, "code": E_BAD_INTENT}
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "msg": {}, "code": E_BAD_INTENT}
	if not data.has("v") or not _is_number(data["v"]):
		return {"ok": false, "msg": {}, "code": E_BAD_INTENT}
	if int(data["v"]) != VERSION:
		return {"ok": false, "msg": {}, "code": E_UPDATE_REQUIRED}
	if not data.has("t") or typeof(data["t"]) != TYPE_STRING:
		return {"ok": false, "msg": {}, "code": E_BAD_INTENT}
	return {"ok": true, "msg": data, "code": ""}


## Validate a parsed client message's required fields for its type. Returns ""
## when well-formed, otherwise an error code (BAD_INTENT for shape problems).
## Engine-level rejections (turn order, legality) happen later, in the Room.
static func validate_client(msg: Dictionary) -> String:
	match msg.get("t", ""):
		C_HELLO:
			return "" if typeof(msg.get("name")) == TYPE_STRING else E_BAD_INTENT
		C_JOIN_ROOM:
			return "" if typeof(msg.get("code")) == TYPE_STRING else E_BAD_INTENT
		C_PLAY_TILE:
			if not _is_number(msg.get("tile_id")):
				return E_BAD_INTENT
			var tid := int(msg["tile_id"])
			if tid < 0 or tid > 27:
				return E_BAD_INTENT
			return "" if msg.get("end") in ["L", "R"] else E_BAD_INTENT
		C_CREATE_ROOM, C_ADD_BOT, C_REMOVE_BOT, C_START_GAME, \
		C_END_GAME, C_PLAY_AGAIN, C_LEAVE_ROOM:
			return ""   # no required fields (add/remove_bot may carry optional seat)
		_:
			return E_BAD_INTENT


static func _is_number(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
