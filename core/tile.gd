class_name Tile
extends RefCounted
## A single domino tile, stored canonically as (low, high) with low <= high.
##
## Tiles (2,5) and (5,2) are the same tile. The wire format for a tile is its
## integer id 0..27 (see to_id/from_id). Pure value type — no engine deps
## (ADR-003). See docs/GAME_RULES.md §2.

var low: int
var high: int


func _init(a: int = 0, b: int = 0) -> void:
	if a <= b:
		low = a
		high = b
	else:
		low = b
		high = a


## Total pip value of the tile (used for scoring and opener selection).
func pips() -> int:
	return low + high


func is_double() -> bool:
	return low == high


## True if either end of the tile shows `end_value`.
func matches(end_value: int) -> bool:
	return low == end_value or high == end_value


## The value left open after playing this tile onto an open end of `end_value`.
## Assumes matches(end_value). For a double, both sides equal `end_value`.
func other_side(end_value: int) -> int:
	if low == end_value:
		return high
	return low


## Canonical 0..27 id. Ordering: (0,0)=0,(0,1)=1,…,(0,6)=6,(1,1)=7,…,(6,6)=27.
func to_id() -> int:
	return _row_base(low) + (high - low)


func equals(other: Tile) -> bool:
	return other != null and other.low == low and other.high == high


## Start id of the row of tiles whose lower pip == `l`.
static func _row_base(l: int) -> int:
	return 7 * l - l * (l - 1) / 2


static func from_id(id: int) -> Tile:
	var l := 0
	var remaining := id
	while remaining >= (7 - l):
		remaining -= (7 - l)
		l += 1
	return load("res://core/tile.gd").new(l, l + remaining)


func _to_string() -> String:
	return "[%d|%d]" % [low, high]
