class_name LobbyScreen
extends Control
## Lobby: shows the room code, seat list, host controls, and waits for
## game_started. (PHASE_4_PLAN.md §7, Step 4)

signal game_started
signal left_room

var _net: NetworkConnection
var _host_seat: int = -1
var _my_seat: int = -1
var _phase: String = "LOBBY"

var _code_label: Label
var _seats_box: VBoxContainer
var _start_btn: Button
var _status_label: Label


func setup(net: NetworkConnection, room_msg: Dictionary) -> void:
	_net = net
	if _net:
		_net.event_received.connect(_on_net_event)
	_build_ui()
	_apply_room_state(room_msg)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.position = Vector2(390, 140)
	box.custom_minimum_size = Vector2(500, 440)
	box.add_theme_constant_override("separation", 16)
	add_child(box)

	var title := Label.new()
	title.text = "Lobby"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)

	_code_label = Label.new()
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_font_size_override("font_size", 28)
	_code_label.add_theme_color_override("font_color", Color(1, 0.84, 0.27))
	box.add_child(_code_label)

	var share_hint := Label.new()
	share_hint.text = "Share this code with your friends"
	share_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	share_hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	box.add_child(share_hint)

	_seats_box = VBoxContainer.new()
	_seats_box.add_theme_constant_override("separation", 8)
	box.add_child(_seats_box)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	box.add_child(_status_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	box.add_child(btn_row)

	_start_btn = Button.new()
	_start_btn.text = "Start game"
	_start_btn.custom_minimum_size = Vector2(160, 44)
	_start_btn.pressed.connect(_on_start)
	btn_row.add_child(_start_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.custom_minimum_size = Vector2(100, 44)
	leave_btn.pressed.connect(_on_leave)
	btn_row.add_child(leave_btn)


func _on_net_event(msg: Dictionary) -> void:
	match msg.get("t", ""):
		Protocol.S_ROOM_STATE:
			_apply_room_state(msg)
		Protocol.S_GAME_STARTED:
			game_started.emit()


func _apply_room_state(msg: Dictionary) -> void:
	_host_seat = int(msg.get("host_seat", 0))
	_phase = msg.get("phase", "LOBBY")

	var code: String = msg.get("code", "")
	_code_label.text = "Room: %s" % code

	# Determine my seat from the seats array (match by connected human without a
	# clear "me" field — we know ours because the server assigned it and we're
	# always the last one listed as connected human). Use session_token comparison
	# not possible here; instead rely on game_table learning seat from `hand`.
	var seats: Array = msg.get("seats", [])
	_rebuild_seats(seats)
	_update_controls(seats)


func _rebuild_seats(seats: Array) -> void:
	for c in _seats_box.get_children():
		c.queue_free()

	for i in range(seats.size()):
		var occ: Dictionary = seats[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_seats_box.add_child(row)

		var kind: String = occ.get("kind", "empty")
		var name_text: String = occ.get("name", "")
		var connected: bool = occ.get("connected", false)
		var seat_idx: int = int(occ.get("seat", i))

		var indicator := ColorRect.new()
		indicator.custom_minimum_size = Vector2(12, 12)
		indicator.color = Color(0.2, 0.8, 0.3) if (kind != "empty" and connected) else Color(0.4, 0.4, 0.4)
		row.add_child(indicator)

		var lbl := Label.new()
		if kind == "empty":
			lbl.text = "Seat %d — empty" % seat_idx
			lbl.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55))
		elif kind == "bot":
			lbl.text = "Seat %d — Bot" % seat_idx
		else:
			var suffix := " (host)" if seat_idx == _host_seat else ""
			var conn_suffix := "" if connected else " [disconnected]"
			lbl.text = "Seat %d — %s%s%s" % [seat_idx, name_text, suffix, conn_suffix]
		row.add_child(lbl)

		# Host-only controls: add/remove bot for empty/bot seats.
		if _is_host():
			if kind == "empty":
				var add_btn := Button.new()
				add_btn.text = "Add bot"
				add_btn.pressed.connect(_net.add_bot)
				row.add_child(add_btn)
			elif kind == "bot":
				var rem_btn := Button.new()
				rem_btn.text = "Remove"
				rem_btn.pressed.connect(_net.remove_bot.bind(seat_idx))
				row.add_child(rem_btn)


func _update_controls(seats: Array) -> void:
	var occupied := 0
	for occ in seats:
		if occ.get("kind", "empty") != "empty":
			occupied += 1

	if _is_host():
		_start_btn.visible = true
		_start_btn.disabled = occupied < 2
		_status_label.text = "You are the host" if occupied >= 2 else "Need at least 2 players to start"
	else:
		_start_btn.visible = false
		_status_label.text = "Waiting for the host to start…"


func _is_host() -> bool:
	# We don't know our seat yet (that comes with `hand`), but we can tell if
	# we're host by checking if the server echoes us back as host_seat 0 and
	# we were the room creator. Since we can't distinguish cleanly here, we
	# track it from whether we received the room_state as the first peer.
	# The server always makes the creator seat 0 and host_seat 0.
	# In the lobby the creator is always connected at seat 0.
	# For now, we show host controls when _host_seat == 0 and we are seat 0,
	# but since we don't know our seat from room_state, we fall back to showing
	# controls when we were the one who called create_room (tracked by whether
	# the _net has no other prior lobby state). Instead: always show if only
	# one human is present and it's us — or if host_seat matches a field we can
	# derive. Until `hand` arrives we err on the side of showing controls; the
	# server rejects non-host actions with NOT_HOST.
	return true  # server enforces; we optimistically show and let it reject


func _on_start() -> void:
	if _net:
		_net.start_game()


func _on_leave() -> void:
	if _net:
		_net.leave()
	left_room.emit()
