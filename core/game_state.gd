class_name GameState
extends RefCounted

const Tile = preload("res://core/tile.gd")
## Full state of one Gaple round. Pure value object (ADR-003): no engine deps.
##
## Seats are contiguous logical indices 0..num_players-1; all of them are
## occupied (whether a seat is human or bot is a server concern, not a rules
## concern). The 4-physical-seat table and empty-seat skipping live in the
## client/server layers — see docs/GAME_RULES.md §8. The line is stored left→
## right (index 0 = left end); left_end/right_end are the open pip values.

const HAND_SIZE := 7            ## Tiles dealt per player (GAME_RULES R4). Single source of truth.
const TURN_TIMEOUT_SEC := 30    ## Server turn timer (GAME_RULES §8); unused by the pure engine.

enum Phase { DEALT, PLAYING, ROUND_OVER }
enum EndReason { NONE, DOMINO, BLOCKED, ABORTED }

var rng_seed: int = 0
var num_players: int = 0
var hands: Array = []                  ## hands[seat] = Array of Tile
var boneyard: Array = []               ## undealt tiles; drawn from when a player has no legal move (GAME_RULES §5.6)
var line: Array = []                   ## Array of Tile, index 0 = left end
var left_end: int = -1                 ## open pip value at the left end (-1 before first tile)
var right_end: int = -1
var current_seat: int = 0
var consecutive_passes: int = 0
var phase: int = Phase.DEALT
var winner_seat: int = -1
var end_reason: int = EndReason.NONE
var last_placer_seat: int = -1         ## last seat to place a tile (blocked tie-break, §6.2)
var forced_opening_tile: int = -1      ## tile id the opener MUST play first, or -1 for a free open


## True while moves are accepted (DEALT = dealt, opener to move; PLAYING = under way).
func is_active() -> bool:
	return phase == Phase.DEALT or phase == Phase.PLAYING


## Full serialization (server-side only — contains every hand). Round-trips
## exactly via from_dict. Tiles are stored as integer ids.
func to_dict() -> Dictionary:
	var hand_ids: Array = []
	for h in hands:
		hand_ids.append(_ids(h))
	return {
		"rng_seed": rng_seed,
		"num_players": num_players,
		"hands": hand_ids,
		"boneyard": _ids(boneyard),
		"line": _ids(line),
		"left_end": left_end,
		"right_end": right_end,
		"current_seat": current_seat,
		"consecutive_passes": consecutive_passes,
		"phase": phase,
		"winner_seat": winner_seat,
		"end_reason": end_reason,
		"last_placer_seat": last_placer_seat,
		"forced_opening_tile": forced_opening_tile,
	}


static func from_dict(d: Dictionary) -> GameState:
	var s = load("res://core/game_state.gd").new()
	s.rng_seed = int(d["rng_seed"])
	s.num_players = int(d["num_players"])
	s.hands = []
	for ids in d["hands"]:
		s.hands.append(_tiles(ids))
	s.boneyard = _tiles(d.get("boneyard", []))
	s.line = _tiles(d["line"])
	s.left_end = int(d["left_end"])
	s.right_end = int(d["right_end"])
	s.current_seat = int(d["current_seat"])
	s.consecutive_passes = int(d["consecutive_passes"])
	s.phase = int(d["phase"])
	s.winner_seat = int(d["winner_seat"])
	s.end_reason = int(d["end_reason"])
	s.last_placer_seat = int(d["last_placer_seat"])
	s.forced_opening_tile = int(d["forced_opening_tile"])
	return s


## Redacted view safe to broadcast: public board + per-seat tile COUNTS only,
## never hand contents (ADR-002 hidden information).
func public_dict() -> Dictionary:
	var counts: Array = []
	for h in hands:
		counts.append(h.size())
	return {
		"num_players": num_players,
		"line": _ids(line),
		"left_end": left_end,
		"right_end": right_end,
		"current_seat": current_seat,
		"tile_counts": counts,
		"boneyard_count": boneyard.size(),
		"phase": phase,
		"winner_seat": winner_seat,
		"end_reason": end_reason,
	}


## Tile ids held by one seat (sent only to that seat's client).
func hand_dict(seat: int) -> Array:
	return _ids(hands[seat])


static func _ids(tiles: Array) -> Array:
	var out: Array = []
	for t: Tile in tiles:
		out.append(t.to_id())
	return out


static func _tiles(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		out.append(Tile.from_id(int(id)))
	return out
