class_name BotPolicy
extends RefCounted

const Tile = preload("res://core/tile.gd")
## Server/driver-side bot move selection (ADR-004). Pure (ADR-003): sees only
## what a human in that seat sees — own hand + public state — never hidden info.
##
## v1 ships NORMAL ("Greedy+"). EASY (uniform random) is used to add variety in
## fuzzing. HARD is reserved for a future sampling policy.

enum Difficulty { EASY, NORMAL, HARD }

var difficulty: int


func _init(diff: int = Difficulty.NORMAL) -> void:
	difficulty = diff


## Choose one move from `legal` (an Array of {tile_id, end}). `hand_ids` is the
## bot's own hand. Returns a move dict that is a member of `legal`, or {} when
## `legal` is empty (the caller then passes).
func choose_move(_public_state: Dictionary, hand_ids: Array, legal: Array, rng: RandomNumberGenerator) -> Dictionary:
	if legal.is_empty():
		return {}
	if difficulty == Difficulty.EASY:
		return legal[rng.randi_range(0, legal.size() - 1)]

	# NORMAL — Greedy+.
	var candidates := _unique_tile_ids(legal)

	# 1. Winning move: with one tile left, playing it empties the hand.
	if hand_ids.size() == 1:
		return _first_move_for(legal, candidates[0])

	# Randomize first so full ties resolve uniformly, then keep the best.
	_shuffle(candidates, rng)
	var best: int = candidates[0]
	for tid in candidates:
		if _prefers(tid, best, hand_ids):
			best = tid
	return _first_move_for(legal, best)


## True if tile `a` is preferred over tile `b`: dump doubles, then highest pip
## sum, then whichever keeps the most flexible hand (ADR-004).
func _prefers(a: int, b: int, hand_ids: Array) -> bool:
	var ta := Tile.from_id(a)
	var tb := Tile.from_id(b)
	if ta.is_double() != tb.is_double():
		return ta.is_double()
	if ta.pips() != tb.pips():
		return ta.pips() > tb.pips()
	return _flexibility(a, hand_ids) > _flexibility(b, hand_ids)


## Distinct pip values left in hand after playing `tile_id` (more = more options).
func _flexibility(tile_id: int, hand_ids: Array) -> int:
	var values := {}
	for h in hand_ids:
		if h == tile_id:
			continue
		var t := Tile.from_id(h)
		values[t.low] = true
		values[t.high] = true
	return values.size()


static func _unique_tile_ids(legal: Array) -> Array:
	var ids := []
	var seen := {}
	for m in legal:
		var tid: int = m["tile_id"]
		if not seen.has(tid):
			seen[tid] = true
			ids.append(tid)
	return ids


## First legal move for a tile, preferring the left end (strategically neutral).
static func _first_move_for(legal: Array, tile_id: int) -> Dictionary:
	var fallback := {}
	for m in legal:
		if m["tile_id"] == tile_id:
			if m["end"] == "L":
				return m
			if fallback.is_empty():
				fallback = m
	return fallback


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
