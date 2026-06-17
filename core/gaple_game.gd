class_name GapleGame
extends RefCounted

const GameState  = preload("res://core/game_state.gd")
const DominoSet  = preload("res://core/domino_set.gd")
const Tile       = preload("res://core/tile.gd")
const Legal      = preload("res://core/legal.gd")
## Authoritative Gaple rules engine (ADR-003). Pure: no Node/scene/net/UI, all
## randomness via a seeded RNG. The server and client share this exact code.
##
## Usage (driver loop — Room or test):
##   var g := GapleGame.new_round(num_players, seed)
##   while g.state.is_active():
##       var seat := g.state.current_seat
##       var moves := g.legal_moves(seat)
##       if moves.is_empty():
##           g.apply({"type": "pass", "seat": seat})
##       else:
##           g.apply({"type": "play", "seat": seat, ...moves[i]})
##
## See docs/GAME_RULES.md for the rules this implements.

var state: GameState

## Doubles a single hand may hold before the deal is rejected (GAME_RULES R6).
const MAX_DOUBLES_ALLOWED := 5
## Safety cap on redeals; far beyond what any seed needs in practice.
const MAX_REDEALS := 100


## Start a fresh round. `opener_override` = the previous round's winner seat for
## a "play again" (free open, GAME_RULES §4.2); leave -1 for round 1 (forced
## opener: highest double, else highest-pip tile, §4.1).
static func new_round(num_players: int, rng_seed: int, opener_override: int = -1) -> GapleGame:
	assert(num_players >= 2 and num_players <= 4, "Gaple supports 2..4 players (R2)")

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	# Deal, redealing on an unfair hand (>5 doubles, GAME_RULES R6/§3.4). Each
	# reshuffle is drawn from the same seeded rng, so a seed yields a fixed final
	# deal; the cap guarantees termination in the astronomically rare worst case.
	var hands: Array = []
	var deck: Array = []
	for _attempt in range(MAX_REDEALS):
		deck = DominoSet.shuffled(rng)
		hands = _deal(deck, num_players)
		if not _needs_redeal(hands):
			break

	var s := GameState.new()
	s.rng_seed = rng_seed
	s.num_players = num_players
	s.hands = hands
	s.boneyard = deck.slice(GameState.HAND_SIZE * num_players)
	s.phase = GameState.Phase.DEALT

	if opener_override >= 0:
		s.current_seat = opener_override
		s.forced_opening_tile = -1            # winner may open with any tile
	else:
		var opener := determine_opener(hands)
		s.current_seat = opener["seat"]
		s.forced_opening_tile = opener["tile_id"]

	var g = load("res://core/gaple_game.gd").new()
	g.state = s
	return g


## Round-1 opener (GAME_RULES §4.1): highest double if any player holds one,
## else the single highest-pip tile (tie: higher `high`, then lowest seat).
## Returns { "seat": int, "tile_id": int }.
static func determine_opener(hands: Array) -> Dictionary:
	for d in range(6, -1, -1):
		var double_id := Tile.new(d, d).to_id()
		for seat in range(hands.size()):
			for t: Tile in hands[seat]:
				if t.to_id() == double_id:
					return {"seat": seat, "tile_id": double_id}

	var best_seat := -1
	var best: Tile = null
	for seat in range(hands.size()):
		for t: Tile in hands[seat]:
			if best == null or _opener_better(t, best):
				best = t
				best_seat = seat
	return {"seat": best_seat, "tile_id": best.to_id()}


## Strictly-better comparison for no-doubles opener selection. Strictness keeps
## the lowest-seat tile on a full tie (we scan seats ascending).
static func _opener_better(a: Tile, b: Tile) -> bool:
	if a.pips() != b.pips():
		return a.pips() > b.pips()
	return a.high > b.high


## Deal HAND_SIZE tiles per seat, one at a time clockwise (GAME_RULES §3.3).
static func _deal(deck: Array, num_players: int) -> Array:
	var hands: Array = []
	for _i in range(num_players):
		hands.append([])
	var idx := 0
	for _round in range(GameState.HAND_SIZE):
		for seat in range(num_players):
			hands[seat].append(deck[idx])
			idx += 1
	return hands


## True if any seat holds more than MAX_DOUBLES_ALLOWED doubles (GAME_RULES R6).
static func _needs_redeal(hands: Array) -> bool:
	for hand in hands:
		if count_doubles(hand) > MAX_DOUBLES_ALLOWED:
			return true
	return false


## Number of doubles (balak) in a hand.
static func count_doubles(hand: Array) -> int:
	var n := 0
	for t: Tile in hand:
		if t.is_double():
			n += 1
	return n


## Legal moves for `seat` right now. Each move: { "tile_id": int, "end": "L"|"R" }.
## Empty ⇒ the seat has no playable tile and must pass (GAME_RULES §5.6).
func legal_moves(seat: int) -> Array:
	if not state.is_active() or seat != state.current_seat:
		return []
	# Delegate to the pure helper shared with the client (PHASE_4_PLAN.md §4).
	return Legal.moves_for(
		state.left_end, state.right_end, state.line.is_empty(),
		state.forced_opening_tile, state.hand_dict(seat))


## Apply one intent, mutating state. Returns
## { "ok": bool, "error": String, "events": Array }.
## Intents: {"type":"play","seat","tile_id","end"}, {"type":"pass","seat"}
## (forced only), {"type":"abort","seat"} (host manual end, GAME_RULES §6.3).
func apply(intent: Dictionary) -> Dictionary:
	var itype = intent.get("type", "")

	if itype == "abort":
		if not state.is_active():
			return _err("round not active")
		state.phase = GameState.Phase.ROUND_OVER
		state.end_reason = GameState.EndReason.ABORTED
		state.winner_seat = -1
		return _ok([{"type": "round_over", "reason": "ABORTED", "winner_seat": -1}])

	if not state.is_active():
		return _err("round not active")

	var seat = int(intent.get("seat", -1))
	if seat != state.current_seat:
		return _err("not your turn")

	if itype == "pass":
		if not legal_moves(seat).is_empty():
			return _err("cannot pass with a legal move available")
		return _do_pass(seat)
	elif itype == "play":
		return _do_play(seat, intent)
	return _err("unknown intent type")


func _do_play(seat: int, intent: Dictionary) -> Dictionary:
	var tile_id := int(intent.get("tile_id", -1))
	var end_side = intent.get("end", "")

	var idx := _hand_index(seat, tile_id)
	if idx < 0:
		return _err("tile not in hand")

	var legal := legal_moves(seat)
	var allowed := false
	for m in legal:
		if m["tile_id"] == tile_id and m["end"] == end_side:
			allowed = true
			break
	if not allowed:
		return _err("illegal move")

	var tile: Tile = state.hands[seat][idx]
	if state.line.is_empty():
		state.line.append(tile)
		state.left_end = tile.low
		state.right_end = tile.high
		state.forced_opening_tile = -1
	elif end_side == "L":
		state.left_end = tile.other_side(state.left_end)
		state.line.push_front(tile)
	else:
		state.right_end = tile.other_side(state.right_end)
		state.line.push_back(tile)

	state.hands[seat].remove_at(idx)
	state.last_placer_seat = seat
	state.consecutive_passes = 0
	state.phase = GameState.Phase.PLAYING

	var events: Array = [{
		"type": "tile_played",
		"seat": seat,
		"tile_id": tile_id,
		"end": end_side,
		"new_left_end": state.left_end,
		"new_right_end": state.right_end,
		"remaining_count": state.hands[seat].size(),
	}]

	if state.hands[seat].is_empty():
		state.phase = GameState.Phase.ROUND_OVER
		state.winner_seat = seat
		state.end_reason = GameState.EndReason.DOMINO
		events.append({"type": "round_over", "reason": "DOMINO", "winner_seat": seat})
		return _ok(events)

	_advance_turn(events)
	return _ok(events)


func _do_pass(seat: int) -> Dictionary:
	var events: Array = []

	# Draw phase: pull tiles one at a time until a playable one is found or
	# the boneyard is exhausted (GAME_RULES §5.6). Drawing is forced and
	# automatic; the engine resolves it in one apply() call.
	while not state.boneyard.is_empty():
		var drawn: Tile = state.boneyard.pop_front()
		state.hands[seat].append(drawn)
		events.append({"type": "tile_drawn", "seat": seat, "tile_id": drawn.to_id()})

		var moves := legal_moves(seat)
		if not moves.is_empty():
			# Must play the drawn tile immediately (§5.6); pick its first legal end.
			for m in moves:
				if m["tile_id"] == drawn.to_id():
					var play_result := _do_play(seat, {
						"type": "play", "seat": seat,
						"tile_id": m["tile_id"], "end": m["end"],
					})
					events.append_array(play_result["events"])
					return _ok(events)
			# Drawn tile not in moves (shouldn't happen; fall through to keep drawing).

	# Pass phase: boneyard empty, still no playable tile (GAME_RULES §5.7).
	state.consecutive_passes += 1
	events.append({"type": "player_passed", "seat": seat})

	# A full cycle of passes with no tile placed = blocked game (GAME_RULES §6.2).
	if state.consecutive_passes >= state.num_players:
		state.phase = GameState.Phase.ROUND_OVER
		state.end_reason = GameState.EndReason.BLOCKED
		state.winner_seat = blocked_winner(state)
		events.append({"type": "round_over", "reason": "BLOCKED", "winner_seat": state.winner_seat})
		return _ok(events)

	_advance_turn(events)
	return _ok(events)


func _advance_turn(events: Array) -> void:
	state.current_seat = (state.current_seat + 1) % state.num_players
	events.append({"type": "turn_started", "seat": state.current_seat})


## Blocked-game / gapleh winner (GAME_RULES §6.2): fewest tiles in hand; tie →
## lowest balak-weighted value; still tied → first tied seat clockwise after the
## last placer.
static func blocked_winner(s: GameState) -> int:
	var min_count := 1 << 30
	var tied: Array = []
	for seat in range(s.num_players):
		var count: int = s.hands[seat].size()
		if count < min_count:
			min_count = count
			tied = [seat]
		elif count == min_count:
			tied.append(seat)
	if tied.size() == 1:
		return tied[0]

	var min_value := 1 << 30
	var tied2: Array = []
	for seat in tied:
		var value := _blocked_value(s.hands[seat])
		if value < min_value:
			min_value = value
			tied2 = [seat]
		elif value == min_value:
			tied2.append(seat)
	if tied2.size() == 1:
		return tied2[0]

	for step in range(1, s.num_players + 1):
		var seat := (s.last_placer_seat + step) % s.num_players
		if seat in tied2:
			return seat
	return tied2[0]


## Balak-weighted hand value for the gapleh tie-break (GAME_RULES §6.2, rule 8):
## non-doubles count 1; doubles count 2, but only 1 if the hand also holds any
## tile with a 0 side.
static func _blocked_value(hand: Array) -> int:
	var has_zero := false
	for t: Tile in hand:
		if t.low == 0:           # canonical (low, high) → a 0 side means low == 0
			has_zero = true
			break
	var double_weight := 1 if has_zero else 2
	var value := 0
	for t: Tile in hand:
		value += double_weight if t.is_double() else 1
	return value


## Per-round scores (GAME_RULES §7): winner 0, everyone else their own hand pip
## sum. Aborted rounds score nobody (empty array).
static func round_scores(s: GameState) -> Array:
	if s.end_reason == GameState.EndReason.ABORTED:
		return []
	var scores: Array = []
	for seat in range(s.num_players):
		scores.append(0 if seat == s.winner_seat else _hand_pips(s.hands[seat]))
	return scores


func pip_count(seat: int) -> int:
	return _hand_pips(state.hands[seat])


static func _hand_pips(hand: Array) -> int:
	var total := 0
	for t: Tile in hand:
		total += t.pips()
	return total


func _hand_index(seat: int, tile_id: int) -> int:
	var hand: Array = state.hands[seat]
	for i in range(hand.size()):
		if hand[i].to_id() == tile_id:
			return i
	return -1


func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "events": []}


func _ok(events: Array) -> Dictionary:
	return {"ok": true, "error": "", "events": events}
