class_name AppRoot
extends Control
## Screen manager: menu ↔ lobby ↔ game_table, plus the local practice path.
## Phase 4 replaces the Phase 2 minimal shell (PHASE_4_PLAN.md §7).

var _net: NetworkConnection   # = Net autoload; injected here for testability
var _overlay: Control         # connection-status banner (non-blocking)
var _current: Control         # the active screen


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Grab the Net autoload; fall back gracefully when absent (headless tests).
	if has_node("/root/Net"):
		_net = get_node("/root/Net")
		_net.event_received.connect(_on_net_event)
		_net.connection_changed.connect(_on_connection_changed)
	_show_menu()


# --- screens -------------------------------------------------------------

func _show_menu() -> void:
	_clear()
	var screen := _bg_screen()
	_current = screen

	var box := _center_box(screen, Vector2(440, 160), Vector2(400, 380))

	var title := Label.new()
	title.text = "GAPLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	box.add_child(title)

	# ── Name field ──
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = "Name: "
	name_row.add_child(name_lbl)

	var name_field := LineEdit.new()
	name_field.custom_minimum_size = Vector2(200, 36)
	name_field.placeholder_text = "Your name"
	name_field.text = _net.get_player_name() if _net else ""
	name_row.add_child(name_field)

	# ── Practice ──
	var sep := _make_label(box, "— or play online —")
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var practice_row := HBoxContainer.new()
	practice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	practice_row.add_theme_constant_override("separation", 12)
	box.add_child(practice_row)
	for bots in [1, 2, 3]:
		var b := Button.new()
		b.text = "Practice vs %d bot%s" % [bots, "" if bots == 1 else "s"]
		b.custom_minimum_size = Vector2(160, 40)
		b.pressed.connect(_start_practice.bind(bots + 1, name_field))
		practice_row.add_child(b)

	# ── Online buttons ──
	var create_btn := Button.new()
	create_btn.text = "Create room"
	create_btn.custom_minimum_size = Vector2(200, 44)
	create_btn.pressed.connect(_on_create_room.bind(name_field))
	box.add_child(create_btn)

	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 8)
	box.add_child(join_row)

	var code_field := LineEdit.new()
	code_field.custom_minimum_size = Vector2(120, 36)
	code_field.placeholder_text = "Room code"
	code_field.max_length = 5
	join_row.add_child(code_field)

	var join_btn := Button.new()
	join_btn.text = "Join room"
	join_btn.custom_minimum_size = Vector2(120, 36)
	join_btn.pressed.connect(_on_join_room.bind(name_field, code_field))
	join_row.add_child(join_btn)

	_rebuild_overlay()


func _show_lobby(room_msg: Dictionary) -> void:
	_clear()
	var lobby := LobbyScreen.new()
	_current = lobby
	add_child(lobby)
	lobby.setup(_net, room_msg)
	lobby.game_started.connect(_on_lobby_game_started)
	lobby.left_room.connect(_show_menu)
	_rebuild_overlay()


func _show_table_online() -> void:
	_clear()
	var table := GameTable.new()
	_current = table
	add_child(table)
	table.returned_to_menu.connect(_show_menu)
	table.bind(_net)
	_rebuild_overlay()


func _start_practice(num_players: int, name_field: LineEdit) -> void:
	_save_name(name_field)
	_clear()
	var table := GameTable.new()
	_current = table
	add_child(table)
	table.returned_to_menu.connect(_show_menu)
	table.start_game(num_players)
	_rebuild_overlay()


# --- network actions ------------------------------------------------------

func _on_create_room(name_field: LineEdit) -> void:
	if not _net:
		return
	_save_name(name_field)
	if _net._state == "open":
		_net.create_room()
		return
	_net.connect_to_server()
	var fn := func(m: Dictionary) -> void:
		if m.get("t") == Protocol.S_WELCOME:
			_net.create_room()
	_net.event_received.connect(fn, CONNECT_ONE_SHOT)


func _on_join_room(name_field: LineEdit, code_field: LineEdit) -> void:
	if not _net:
		return
	var code := code_field.text.strip_edges().to_upper()
	if code.length() != 5:
		return
	_save_name(name_field)
	if _net._state == "open":
		_net.join_room(code)
		return
	_net.connect_to_server()
	var fn := func(m: Dictionary) -> void:
		if m.get("t") == Protocol.S_WELCOME:
			_net.join_room(code)
	_net.event_received.connect(fn, CONNECT_ONE_SHOT)


# --- inbound events -------------------------------------------------------

func _on_net_event(msg: Dictionary) -> void:
	match msg.get("t", ""):
		Protocol.S_ROOM_STATE:
			# Arriving here means we're not yet in the lobby screen.
			if not (_current is LobbyScreen):
				_show_lobby(msg)
			# If already in the lobby, it handles its own updates.
		Protocol.S_ERROR:
			var code: String = msg.get("code", "")
			match code:
				Protocol.E_ROOM_NOT_FOUND, Protocol.E_ROOM_FULL, \
				Protocol.E_ROOM_IN_PROGRESS, Protocol.E_UPDATE_REQUIRED:
					_toast("Error: %s" % code.replace("_", " ").to_lower())


func _on_lobby_game_started() -> void:
	_show_table_online()


func _on_connection_changed(state: String) -> void:
	_rebuild_overlay()


# --- overlay / helpers ----------------------------------------------------

func _rebuild_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null
	var state: String = ""
	if _net:
		state = _net._state
	if state == "connecting" or state == "reconnecting":
		_overlay = Control.new()
		_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lbl := Label.new()
		lbl.text = "Reconnecting…" if state == "reconnecting" else "Connecting…"
		lbl.add_theme_color_override("font_color", Color(1, 0.84, 0.27))
		lbl.position = Vector2(10, 10)
		_overlay.add_child(lbl)
		add_child(_overlay)
	elif state == "closed" and _current != null and not (_current is GameTable and not (_current as GameTable).is_round_over()):
		pass  # closed but idle — no banner needed


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	lbl.position = Vector2(440, 680)
	lbl.size = Vector2(400, 30)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)
	var t := get_tree().create_timer(3.0)
	t.timeout.connect(lbl.queue_free)


func _save_name(field: LineEdit) -> void:
	if not _net:
		return
	var name_text := field.text.strip_edges()
	if name_text.length() > 0:
		_net.hello(name_text)


func _bg_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)
	return screen


func _center_box(parent: Control, pos: Vector2, min_size: Vector2) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.position = pos
	box.custom_minimum_size = min_size
	box.add_theme_constant_override("separation", 14)
	parent.add_child(box)
	return box


func _make_label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_current = null
	_overlay = null
