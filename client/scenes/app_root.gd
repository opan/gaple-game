class_name AppRoot
extends Control
## Phase 2 client shell: a minimal "Practice vs bots" menu that swaps to the
## game table and back. Phase 4 replaces this with the full menu/lobby flow
## (PHASE_2_PLAN.md §10.1).


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_show_menu()


func _show_menu() -> void:
	_clear()
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)

	var box := VBoxContainer.new()
	box.position = Vector2(440, 230)
	box.custom_minimum_size = Vector2(400, 260)
	box.add_theme_constant_override("separation", 14)
	screen.add_child(box)

	var title := Label.new()
	title.text = "GAPLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Practice vs bots — choose your opponents:"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for bots in [1, 2, 3]:
		var b := Button.new()
		b.text = "%d bot%s" % [bots, "" if bots == 1 else "s"]
		b.custom_minimum_size = Vector2(110, 48)
		b.pressed.connect(_start.bind(bots + 1))   # players = bots + the human
		row.add_child(b)


func _start(num_players: int) -> void:
	_clear()
	var table := GameTable.new()
	add_child(table)
	table.returned_to_menu.connect(_show_menu)
	table.start_game(num_players)


func _clear() -> void:
	for c in get_children():
		c.queue_free()
