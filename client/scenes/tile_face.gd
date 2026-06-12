class_name TileFace
extends Control
## A single domino tile rendered with _draw() — no image assets (PHASE_2_PLAN.md
## §6.1, ADR-001 procedural art). Used for hand tiles (interactive), the board
## chain, and face-down opponent backs.

signal pressed(tile_id: int)

enum Vis { NORMAL, SELECTED, DISABLED }

const SHORT := 60.0     # tile short side
const LONG := 120.0     # tile long side
const PIP_R := 5.0
const MARGIN := 0.18    # body inset for the pip grid, as a fraction of a half

# Dice pip layout on a 3×3 anchor grid (cols/rows at 0.25/0.5/0.75).
const PIPS := {
	0: [],
	1: [Vector2(1, 1)],
	2: [Vector2(0, 0), Vector2(2, 2)],
	3: [Vector2(0, 0), Vector2(1, 1), Vector2(2, 2)],
	4: [Vector2(0, 0), Vector2(2, 0), Vector2(0, 2), Vector2(2, 2)],
	5: [Vector2(0, 0), Vector2(2, 0), Vector2(1, 1), Vector2(0, 2), Vector2(2, 2)],
	6: [Vector2(0, 0), Vector2(2, 0), Vector2(0, 1), Vector2(2, 1), Vector2(0, 2), Vector2(2, 2)],
}

var low: int = 0
var high: int = 0
var face_up: bool = true
var horizontal: bool = false     # true for left/right opponent seats
var vis: int = Vis.NORMAL
var interactive: bool = false


func _ready() -> void:
	_apply_size()
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE


## Configure the tile. Call before adding to the tree, or any time after.
func setup(p_low: int, p_high: int, p_face_up: bool = true, p_horizontal: bool = false) -> void:
	low = p_low
	high = p_high
	face_up = p_face_up
	horizontal = p_horizontal
	_apply_size()
	queue_redraw()


func set_vis(v: int) -> void:
	vis = v
	queue_redraw()


func tile_id() -> int:
	return Tile.new(low, high).to_id()


func _apply_size() -> void:
	custom_minimum_size = Vector2(LONG, SHORT) if horizontal else Vector2(SHORT, LONG)
	size = custom_minimum_size


func _gui_input(event: InputEvent) -> void:
	if not interactive or vis == Vis.DISABLED:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed.emit(tile_id())


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var body := Color(0.95, 0.93, 0.86)
	var ink := Color(0.12, 0.12, 0.14)
	if vis == Vis.DISABLED:
		body = Color(0.62, 0.62, 0.64)
		ink = Color(0.42, 0.42, 0.45)

	if not face_up:
		draw_rect(rect, Color(0.16, 0.22, 0.34), true)
		draw_rect(rect.grow(-4), Color(0.24, 0.34, 0.52), false, 2.0)
		_draw_back_motif(rect, Color(0.24, 0.34, 0.52))
		return

	draw_rect(rect, body, true)
	draw_rect(rect, ink, false, 2.0)

	# Two halves with a divider; orientation depends on `horizontal`.
	if horizontal:
		var lw := rect.size.x * 0.5
		draw_line(Vector2(lw, 6), Vector2(lw, rect.size.y - 6), ink, 2.0)
		_draw_half(Rect2(0, 0, lw, rect.size.y), low, ink)
		_draw_half(Rect2(lw, 0, lw, rect.size.y), high, ink)
	else:
		var lh := rect.size.y * 0.5
		draw_line(Vector2(6, lh), Vector2(rect.size.x - 6, lh), ink, 2.0)
		_draw_half(Rect2(0, 0, rect.size.x, lh), high, ink)
		_draw_half(Rect2(0, lh, rect.size.x, lh), low, ink)

	if vis == Vis.SELECTED:
		draw_rect(rect.grow(-1), Color(1.0, 0.84, 0.27), false, 3.0)


func _draw_half(half: Rect2, value: int, ink: Color) -> void:
	# Inset so pips sit inside the half; anchors 0/1/2 → fractions 0/0.5/1.0.
	var inset := half.grow(-minf(half.size.x, half.size.y) * MARGIN)
	for anchor: Vector2 in PIPS[value]:
		var p := inset.position + Vector2(
			(anchor.x / 2.0) * inset.size.x,
			(anchor.y / 2.0) * inset.size.y)
		draw_circle(p, PIP_R, ink)


func _draw_back_motif(rect: Rect2, c: Color) -> void:
	var cx := rect.size.x * 0.5
	var cy := rect.size.y * 0.5
	var r := minf(rect.size.x, rect.size.y) * 0.22
	draw_line(Vector2(cx - r, cy), Vector2(cx, cy - r), c, 2.0)
	draw_line(Vector2(cx, cy - r), Vector2(cx + r, cy), c, 2.0)
	draw_line(Vector2(cx + r, cy), Vector2(cx, cy + r), c, 2.0)
	draw_line(Vector2(cx, cy + r), Vector2(cx - r, cy), c, 2.0)
