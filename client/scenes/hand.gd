class_name Hand
extends Control
## The local player's fanned hand (PHASE_2_PLAN.md §6/§7). Renders 1–5 tiles on
## a shallow arc; playable tiles are enabled, the rest desaturated. Emits
## tile_clicked when an enabled tile is pressed.

signal tile_clicked(tile_id: int)

const FAN_DEG := 16.0
const SPACING := 56.0
const LIFT := 18.0

var _tiles: Array = []   # TileFace nodes, left→right


## tile_ids: the hand in display order. playable: a Set-like Dictionary
## {tile_id: true} of tiles that have at least one legal move.
func set_hand(tile_ids: Array, playable: Dictionary) -> void:
	for t in _tiles:
		t.queue_free()
	_tiles.clear()
	for tid: int in tile_ids:
		var tile := Tile.from_id(tid)
		var tf := TileFace.new()
		tf.interactive = true
		tf.setup(tile.low, tile.high, true, false)
		tf.set_vis(TileFace.Vis.NORMAL if playable.get(tid, false) else TileFace.Vis.DISABLED)
		tf.pressed.connect(_on_tile_pressed)
		tf.mouse_entered.connect(_on_hover.bind(tf, true))
		tf.mouse_exited.connect(_on_hover.bind(tf, false))
		add_child(tf)
		_tiles.append(tf)
	_layout()


func _on_tile_pressed(tile_id: int) -> void:
	tile_clicked.emit(tile_id)


func _on_hover(tf: TileFace, entering: bool) -> void:
	if tf.vis == TileFace.Vis.DISABLED:
		return
	var base: float = tf.get_meta("base_y", tf.position.y)
	create_tween().tween_property(tf, "position:y", base - (LIFT if entering else 0.0), 0.08)


func _layout() -> void:
	var n := _tiles.size()
	if n == 0:
		return
	var cx := size.x * 0.5
	var base_y := size.y - TileFace.LONG
	for i in range(n):
		var tf: TileFace = _tiles[i]
		var offset := float(i) - (n - 1) / 2.0
		var frac := 0.0 if n == 1 else float(i) / float(n - 1)
		tf.pivot_offset = Vector2(TileFace.SHORT * 0.5, TileFace.LONG)
		tf.rotation_degrees = lerpf(-FAN_DEG, FAN_DEG, frac)
		tf.position = Vector2(cx + offset * SPACING - TileFace.SHORT * 0.5, base_y)
		tf.set_meta("base_y", base_y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
