class_name Legal
extends RefCounted
## Legal-move computation from the open board + a hand of tile ids, with no full
## GameState (PHASE_4_PLAN.md §4). The engine and the networked client both call
## this, so their notion of "playable" provably matches. The server stays
## authoritative — this only drives client highlights.


## Moves for `hand_ids` given the board. `is_opening` = the line is empty;
## `forced_tile_id` = the round-1 forced opener, or -1 for a free open / non-open.
## Returns Array of { "tile_id": int, "end": "L"|"R" }, de-duped when both open
## ends show the same pip (mirrors GapleGame.legal_moves exactly).
static func moves_for(left_end: int, right_end: int, is_opening: bool, forced_tile_id: int, hand_ids: Array) -> Array:
	var moves: Array = []

	if is_opening:
		# The first tile goes down on the (conventional) left end.
		for tid in hand_ids:
			if forced_tile_id < 0 or int(tid) == forced_tile_id:
				moves.append({"tile_id": int(tid), "end": "L"})
		return moves

	var ends_equal := left_end == right_end
	for tid in hand_ids:
		var t := Tile.from_id(int(tid))
		if t.matches(left_end):
			moves.append({"tile_id": int(tid), "end": "L"})
		if t.matches(right_end) and not ends_equal:
			moves.append({"tile_id": int(tid), "end": "R"})
	return moves
