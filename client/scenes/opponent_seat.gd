class_name OpponentSeat
extends Control
## A non-local seat: name, remaining tile count, and a neat row/column of
## face-down backs (PHASE_2_PLAN.md §7). TOP shows vertical backs in a row;
## LEFT/RIGHT show horizontal (lying) backs in a column. A gold border marks
## the seat whose turn it is.

const BACK_SCALE := 0.5
const LABEL_H := 26.0

var _name_label: Label
var _backs: Control
var _glow: Panel
var _horizontal := false
var _seat_name := "Bot"


func _ready() -> void:
	_glow = Panel.new()
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(3)
	sb.border_color = Color(1.0, 0.84, 0.27)
	sb.set_corner_radius_all(8)
	_glow.add_theme_stylebox_override("panel", sb)
	_glow.visible = false
	add_child(_glow)

	_backs = Control.new()
	_backs.position = Vector2(0, LABEL_H)
	_backs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backs)

	_name_label = Label.new()
	_name_label.size = Vector2(size.x, LABEL_H)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name_label)


func configure(display_name: String, horizontal: bool) -> void:
	_seat_name = display_name
	_horizontal = horizontal
	_refresh_label(0)


func set_count(n: int) -> void:
	for c in _backs.get_children():
		c.queue_free()
	var bw := TileFace.LONG * BACK_SCALE if _horizontal else TileFace.SHORT * BACK_SCALE
	var bh := TileFace.SHORT * BACK_SCALE if _horizontal else TileFace.LONG * BACK_SCALE
	var step := (bh + 4.0) if _horizontal else (bw + 4.0)
	for i in range(n):
		var tf := TileFace.new()
		tf.setup(0, 0, false, _horizontal)
		tf.scale = Vector2(BACK_SCALE, BACK_SCALE)
		if _horizontal:
			# Lying backs stacked vertically, centered horizontally.
			tf.position = Vector2((size.x - bw) * 0.5, i * step)
		else:
			# Vertical backs in a centered row.
			tf.position = Vector2((size.x - n * step) * 0.5 + i * step, 0)
		_backs.add_child(tf)
	_refresh_label(n)


func set_active(active: bool) -> void:
	if _glow:
		_glow.visible = active


func _refresh_label(n: int) -> void:
	if _name_label:
		_name_label.text = "%s  (%d)" % [_seat_name, n]
