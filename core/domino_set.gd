class_name DominoSet
extends RefCounted

const Tile = preload("res://core/tile.gd")
## The double-six domino set: 28 unique tiles, plus a deterministic shuffle.
## Pure (ADR-003): all randomness comes from an injected, seeded RNG.


## All 28 tiles in canonical id order (0..27).
static func all_tiles() -> Array:
	var tiles: Array = []
	for id in range(28):
		tiles.append(Tile.from_id(id))
	return tiles


## A shuffled copy of the full set. Deterministic for a given rng state, so the
## same seed reproduces the same order (replay/audit — GAME_RULES §3).
static func shuffled(rng: RandomNumberGenerator) -> Array:
	var tiles := all_tiles()
	# Fisher-Yates using the injected RNG.
	for i in range(tiles.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = tiles[i]
		tiles[i] = tiles[j]
		tiles[j] = tmp
	return tiles
