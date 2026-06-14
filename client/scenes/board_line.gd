class_name BoardLine
extends Control
## The played-tile chain with two highlightable open ends (PHASE_2_PLAN.md §7).
## Tiles lie horizontally in a centered row that scales down if the chain gets
## wide. End "drop zones" glow to show where the picked tile can go and are
## clickable when highlighted (to choose an end for a both-ends tile).

signal end_clicked(which: String)

const TILE_SCALE := 0.62
const GAP := 4.0

var _row: Control
var _left_zone: Panel
var _right_zone: Panel


func _ready() -> void:
	_row = Control.new()
	add_child(_row)
	_left_zone = _make_zone()
	_right_zone = _make_zone()
	_left_zone.gui_input.connect(_on_zone_input.bind("L"))
	_right_zone.gui_input.connect(_on_zone_input.bind("R"))
	add_child(_left_zone)
	add_child(_right_zone)
	highlight_ends(false, false)


func _on_zone_input(event: InputEvent, which: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		end_clicked.emit(which)


## line_ids: played tiles left→right. Ends are the open pip values (for labels).
## played_end: "L", "R", or "" (empty = initial deal / resync, no slide animation).
func set_line(line_ids: Array, _left_end: int, _right_end: int, played_end: String = "") -> void:
	for c in _row.get_children():
		c.queue_free()
	var tile_w := TileFace.LONG * TILE_SCALE
	var tile_h := TileFace.SHORT * TILE_SCALE
	var count := line_ids.size()
	var total_w := count * (tile_w + GAP)
	# Scale the whole row down if it would overflow 70% of our width.
	var max_w := size.x * 0.7
	var s := 1.0 if total_w <= max_w or total_w == 0.0 else max_w / total_w
	_row.scale = Vector2(s, s)

	var x := 0.0
	for tid: int in line_ids:
		var tile := Tile.from_id(tid)
		var tf := TileFace.new()
		tf.setup(tile.low, tile.high, true, true)   # horizontal (lying down)
		tf.position = Vector2(x, 0)
		_row.add_child(tf)
		x += tile_w + GAP

	# Center the (scaled) row vertically and horizontally.
	var shown_w := (count * (tile_w + GAP)) * s
	_row.position = Vector2((size.x - shown_w) * 0.5, (size.y - tile_h * s) * 0.5)

	# Park the end zones just beyond each end of the row.
	_left_zone.position = Vector2(_row.position.x - _left_zone.size.x - 2, (size.y - _left_zone.size.y) * 0.5)
	_right_zone.position = Vector2(_row.position.x + shown_w + 2, (size.y - _right_zone.size.y) * 0.5)

	# Slide the newly played tile in from outside the board edge.
	if played_end != "" and count > 0:
		var children := _row.get_children()
		var new_tile: TileFace = children[0] if played_end == "L" else children[children.size() - 1]
		var final_x: float = new_tile.position.x
		var offscreen_x: float = (size.x / s + tile_w) if played_end == "R" else (-tile_w * 2.0)
		new_tile.position.x = offscreen_x
		create_tween().tween_property(new_tile, "position:x", final_x, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func highlight_ends(left_on: bool, right_on: bool) -> void:
	_left_zone.visible = left_on
	_right_zone.visible = right_on


func _make_zone() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(44, TileFace.SHORT * TILE_SCALE)
	p.size = p.custom_minimum_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.84, 0.27, 0.5)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	return p
