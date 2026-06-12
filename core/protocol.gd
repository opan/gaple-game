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
const S_GAME_STARTED := "game_started"
const S_HAND := "hand"
const S_PUBLIC_STATE := "public_state"
const S_TILE_PLAYED := "tile_played"
const S_PLAYER_PASSED := "player_passed"
const S_TURN_STARTED := "turn_started"
const S_ROUND_OVER := "round_over"
const S_ERROR := "error"
# Phase 3 adds: welcome, room_state, player_replaced_by_bot, player_reclaimed.

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


static func hand(tile_ids: Array) -> Dictionary:
	return msg(S_HAND, {"tile_ids": tile_ids})


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
