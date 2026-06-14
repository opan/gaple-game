class_name GameTable
extends Control
## Assembles the whiteboard table and drives the human's interaction against a
## LocalGameDriver or NetworkConnection (PHASE_4_PLAN.md §5). The client keeps a
## local view of the public board, updated from driver events — never by reading
## the engine — so the same code works against both sources.

signal returned_to_menu

enum Ui { WAITING, IDLE, PICKED }

const SEAT_RECT := {
	"TOP": Rect2(490, 16, 300, 130),
	"LEFT": Rect2(24, 250, 170, 220),
	"RIGHT": Rect2(1086, 250, 170, 220),
}
const BOARD_RECT := Rect2(330, 250, 620, 200)
const HAND_RECT := Rect2(330, 470, 620, 240)

## Bot "thinking" delay, applied to the local driver. Tests/screenshots set ZERO.
var bot_delay := Vector2(0.8, 2.0)

var _client: Node                    # a GameClient: LocalGameDriver or NetworkConnection
var _my_seat: int = -1               # learned from the `hand` message
var _host_seat: int = -1             # learned from `room_state`; -1 in local play
var _board: BoardLine
var _hand: Hand
var _seats: Dictionary = {}          # logical seat -> OpponentSeat
var _banner: Label
var _status: Label
var _overlay: Control
var _end_game_btn: Button            # host-only; null in local play
var _play_again_btn: Button          # round-over overlay; null when not showing
var _countdown_label: Label          # turn deadline ticker; null when no deadline
var _deadline_unix_ms: int = -1      # -1 = no countdown (local play)

# Local view of public state, rebuilt from events.
var _num_players: int = 0
var _human_hand: Array = []
var _line: Array = []
var _left_end: int = -1
var _right_end: int = -1
var _opening_tile_id: int = -1

# Interaction.
var _ui: int = Ui.WAITING
var _moves: Array = []
var _picked_tile: int = -1
var _seat_names: Dictionary = {}   # seat -> name String, populated from room_state


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_board = BoardLine.new()
	_board.position = BOARD_RECT.position
	_board.size = BOARD_RECT.size
	_board.end_clicked.connect(_on_end_clicked)
	add_child(_board)

	_hand = Hand.new()
	_hand.position = HAND_RECT.position
	_hand.size = HAND_RECT.size
	_hand.tile_clicked.connect(_on_hand_tile_clicked)
	add_child(_hand)

	_status = _make_label(Rect2(490, 160, 300, 30), Color(0.8, 0.85, 0.9))
	_banner = _make_label(Rect2(340, 360, 600, 40), Color(1.0, 0.84, 0.27))
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.visible = false

	# Turn countdown (top-right corner).
	_countdown_label = _make_label(Rect2(1100, 8, 160, 30), Color(1.0, 0.6, 0.3))
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_countdown_label.visible = false

	# Host-only End game button (top-left corner); hidden by default.
	_end_game_btn = Button.new()
	_end_game_btn.text = "End game"
	_end_game_btn.position = Vector2(16, 8)
	_end_game_btn.custom_minimum_size = Vector2(110, 44)
	_end_game_btn.visible = false
	_end_game_btn.pressed.connect(_on_end_game_pressed)
	add_child(_end_game_btn)

	# Mute toggle (top-right, next to countdown).
	var mute_btn := Button.new()
	mute_btn.text = "🔇" if (has_node("/root/Sfx") and Sfx.muted) else "🔊"
	mute_btn.position = Vector2(1240, 8)
	mute_btn.custom_minimum_size = Vector2(44, 44)
	mute_btn.pressed.connect(func() -> void:
		if has_node("/root/Sfx"):
			Sfx.toggle_mute()
			mute_btn.text = "🔇" if Sfx.muted else "🔊")
	add_child(mute_btn)


## Practice entry point: create a local driver, bind, and deal the first round.
func start_game(num_players: int, game_seed: int = -1) -> void:
	var driver := LocalGameDriver.new()
	driver.bot_delay = bot_delay
	add_child(driver)
	bind(driver)
	driver.start(num_players, 0, game_seed)


## Network entry point: bind to an already-connected client (the menu/lobby owns
## starting it). The table is source-agnostic — it only consumes wire events.
func bind(client: Node) -> void:
	_client = client
	_client.event_received.connect(_on_event)


func get_driver() -> Node:
	return _client


## Play the human's first legal move if it's their turn. Powers an AFK/auto
## fallback and lets headless tests self-drive a full game.
func autoplay_human_turn() -> void:
	if _ui != Ui.IDLE or _moves.is_empty():
		return
	var m: Dictionary = _moves[0]
	_submit(m["tile_id"], m["end"])


## True once the round-over overlay is showing.
func is_round_over() -> bool:
	return is_instance_valid(_overlay)


func _process(_delta: float) -> void:
	if _deadline_unix_ms <= 0 or not is_instance_valid(_countdown_label):
		return
	var remaining := (_deadline_unix_ms - int(Time.get_unix_time_from_system() * 1000)) / 1000.0
	if remaining <= 0.0:
		_countdown_label.text = "0s"
	else:
		_countdown_label.text = "%ds" % int(ceil(remaining))


# --- event handling ------------------------------------------------------

func _on_event(msg: Dictionary) -> void:
	match msg.get("t", ""):
		Protocol.S_ROOM_STATE:
			_host_seat = int(msg.get("host_seat", -1))
			for occ in msg.get("seats", []):
				var s: int = int(occ.get("seat", -1))
				if s >= 0 and occ.get("name", "") != "":
					_seat_names[s] = occ["name"]
			_update_host_controls()
		Protocol.S_GAME_STARTED:
			_on_game_started(msg)
		Protocol.S_HAND:
			var prev_seat := _my_seat
			_my_seat = int(msg.get("seat", _my_seat))
			_human_hand = _to_ints(msg["tile_ids"])
			_update_host_controls()
			if _my_seat != prev_seat and _num_players > 0:
				_build_seats(_num_players)   # re-layout when we learn our true seat
			# Deal animation on the first hand for this round (ui is still WAITING).
			_hand.set_hand(_human_hand, {}, true)
		Protocol.S_PUBLIC_STATE:
			_on_public_state(msg["state"])
		Protocol.S_TILE_PLAYED:
			_on_tile_played(msg)
		Protocol.S_PLAYER_PASSED:
			# The server/driver auto-passes; we react rather than send a pass.
			if has_node("/root/Sfx"):
				Sfx.play("pass")
			var pass_text := "No playable tile — you passed" if int(msg["seat"]) == _my_seat \
				else "Seat %d passed" % int(msg["seat"])
			_show_banner(pass_text)
			var tw := create_tween()
			tw.tween_interval(1.2)
			tw.tween_property(_banner, "modulate:a", 0.0, 0.4)
			tw.tween_callback(_hide_banner)
		Protocol.S_TURN_STARTED:
			_on_turn_started(msg)
		Protocol.S_ROUND_OVER:
			_on_round_over(msg)
		Protocol.S_PLAYER_REPLACED:
			_flash_status("Seat %d left — bot took over" % int(msg.get("seat", -1)))
		Protocol.S_PLAYER_RECLAIMED:
			_flash_status("Seat %d reconnected" % int(msg.get("seat", -1)))
		Protocol.S_ERROR:
			var code: String = msg.get("code", "")
			match code:
				Protocol.E_NOT_YOUR_TURN:
					_toast("Not your turn")
				Protocol.E_ILLEGAL_MOVE:
					_toast("Illegal move")
				Protocol.E_NOT_HOST:
					_toast("Only the host can do that")
				Protocol.E_BAD_INTENT:
					_toast("Internal error — please refresh")
				_:
					_toast("Error: %s" % code.replace("_", " ").to_lower())
			# Re-enable End game button so the host can retry.
			if is_instance_valid(_end_game_btn):
				_end_game_btn.disabled = false


func _on_game_started(msg: Dictionary) -> void:
	_num_players = msg["num_players"]
	_opening_tile_id = msg["opening_tile_id"]
	_line = []
	_clear_overlay()
	_build_seats(_num_players)
	if has_node("/root/Sfx"):
		Sfx.play("deal")


func _on_public_state(s: Dictionary) -> void:
	_line = s["line"].duplicate()
	_left_end = s["left_end"]
	_right_end = s["right_end"]
	_board.set_line(_line, _left_end, _right_end)
	for seat: int in range(_num_players):
		if _seats.has(seat):
			_seats[seat].set_count(s["tile_counts"][seat])


func _on_tile_played(msg: Dictionary) -> void:
	var tid: int = msg["tile_id"]
	var seat: int = msg["seat"]
	if _line.is_empty():
		_line = [tid]
	elif msg["end"] == "L":
		_line.push_front(tid)
	else:
		_line.push_back(tid)
	_left_end = msg["new_left_end"]
	_right_end = msg["new_right_end"]
	_board.set_line(_line, _left_end, _right_end, msg["end"])
	if has_node("/root/Sfx"):
		Sfx.play("place")

	if seat == _my_seat:
		_human_hand.erase(tid)
	elif _seats.has(seat):
		_seats[seat].set_count(msg["remaining_count"])


func _on_turn_started(msg: Dictionary) -> void:
	var seat: int = int(msg["seat"])
	_deadline_unix_ms = int(msg.get("deadline_unix_ms", -1))
	if _deadline_unix_ms > 0:
		_countdown_label.visible = true
	else:
		_countdown_label.visible = false
		_countdown_label.text = ""

	for s: int in _seats:
		_seats[s].set_active(s == seat)

	if seat != _my_seat:
		_ui = Ui.WAITING
		_status.text = "Seat %d is thinking…" % seat
		_hand.set_hand(_human_hand, {})   # not our turn: all disabled
		return

	# Compute our own highlights from the local view (server stays authoritative).
	_moves = _legal_moves_for_me()
	if _moves.is_empty():
		# A forced pass is incoming from the driver/server; just wait for it.
		_ui = Ui.WAITING
		_status.text = ""
		_hand.set_hand(_human_hand, {})
		return

	_ui = Ui.IDLE
	_picked_tile = -1
	_status.text = "Your turn"
	var playable := {}
	for m: Dictionary in _moves:
		playable[m["tile_id"]] = true
	_hand.set_hand(_human_hand, playable)
	_board.highlight_ends(false, false)

	if _line.is_empty() and _opening_tile_id >= 0 and playable.has(_opening_tile_id):
		var t := Tile.from_id(_opening_tile_id)
		_show_banner("You must open with [%d|%d]" % [t.high, t.low])


func _on_round_over(msg: Dictionary) -> void:
	_ui = Ui.WAITING
	_deadline_unix_ms = -1
	if is_instance_valid(_countdown_label):
		_countdown_label.visible = false
	if is_instance_valid(_end_game_btn):
		_end_game_btn.visible = false
	_hide_banner()
	for s: int in _seats:
		_seats[s].set_active(false)
	if has_node("/root/Sfx"):
		Sfx.play("win" if msg.get("winner_seat", -1) == _my_seat else "lose")
	_show_round_over(msg)


# --- interaction ---------------------------------------------------------

func _on_hand_tile_clicked(tile_id: int) -> void:
	if _ui != Ui.IDLE and _ui != Ui.PICKED:
		return
	var ends := _ends_for(tile_id)
	if ends.is_empty():
		return
	if ends.size() == 1:
		_submit(tile_id, ends[0])
		return
	# Both ends legal — let the player choose.
	_ui = Ui.PICKED
	_picked_tile = tile_id
	_board.highlight_ends("L" in ends, "R" in ends)
	_status.text = "Pick an end"


func _on_end_clicked(which: String) -> void:
	if _ui != Ui.PICKED:
		return
	if which in _ends_for(_picked_tile):
		_submit(_picked_tile, which)


func _submit(tile_id: int, end_side: String) -> void:
	_ui = Ui.WAITING
	_board.highlight_ends(false, false)
	_hide_banner()
	_client.submit_play(tile_id, end_side)


func _ends_for(tile_id: int) -> Array:
	var ends := []
	for m: Dictionary in _moves:
		if m["tile_id"] == tile_id:
			ends.append(m["end"])
	return ends


## Our legal moves, computed locally from the public view + our hand (the server
## stays authoritative). Source-agnostic — works for local and online play.
func _legal_moves_for_me() -> Array:
	return Legal.moves_for(_left_end, _right_end, _line.is_empty(), _opening_tile_id, _human_hand)


func _to_ints(arr: Array) -> Array:
	var out: Array = []
	for x in arr:
		out.append(int(x))
	return out


# --- layout / chrome -----------------------------------------------------

func _build_seats(n: int) -> void:
	for s in _seats:
		_seats[s].queue_free()
	_seats.clear()
	var my: int = max(_my_seat, 0)   # -1 before hand arrives → default 0
	for seat in range(n):
		if seat == my:
			continue   # the local player (bottom) isn't an OpponentSeat
		var rel: int = (seat - my + n) % n
		var screen := _screen_for(rel, n)
		var horizontal := screen == "LEFT" or screen == "RIGHT"
		var os := OpponentSeat.new()
		var rect: Rect2 = SEAT_RECT[screen]
		os.position = rect.position
		os.size = rect.size
		add_child(os)
		var display_name: String = _seat_names.get(seat, "Seat %d" % seat)
		os.configure(display_name, horizontal)
		os.set_count(GameState.HAND_SIZE)
		_seats[seat] = os


## Relative offset (rel) → screen position, per GAME_RULES §8 (local seat = 0).
func _screen_for(rel: int, n: int) -> String:
	if n == 2:
		return "TOP"
	if n == 3:
		return "RIGHT" if rel == 1 else "LEFT"
	# n == 4
	if rel == 1:
		return "RIGHT"
	if rel == 2:
		return "TOP"
	return "LEFT"


func _make_label(rect: Rect2, color: Color) -> Label:
	var l := Label.new()
	l.position = rect.position
	l.size = rect.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	_banner.visible = true


func _hide_banner() -> void:
	_banner.visible = false


func _flash_status(text: String) -> void:
	_status.text = text


func _show_round_over(msg: Dictionary) -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.position = Vector2(440, 220)
	box.custom_minimum_size = Vector2(400, 280)
	_overlay.add_child(box)

	var reason: String = msg["reason"]
	var winner: int = msg["winner_seat"]
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 28)
	if reason == "ABORTED":
		title.text = "Round ended"
	elif winner == _my_seat:
		title.text = "You win! (%s)" % reason.to_lower()
	else:
		title.text = "Seat %d wins (%s)" % [winner, reason.to_lower()]
	box.add_child(title)

	var scoreboard: Array = msg.get("scoreboard", [])
	var scores: Array = msg.get("scores", [])
	for seat in range(scoreboard.size()):
		var row := Label.new()
		var who := "You" if seat == _my_seat else "Seat %d" % seat
		var this_round: int = scores[seat] if seat < scores.size() else 0
		row.text = "%s — this round +%d,  total %d" % [who, this_round, scoreboard[seat]]
		box.add_child(row)

	# Host sees "Play again"; non-host sees a waiting label.
	var is_host := _host_seat < 0 or _my_seat == _host_seat  # -1 = local play
	if is_host:
		_play_again_btn = Button.new()
		_play_again_btn.text = "Play again"
		_play_again_btn.pressed.connect(_on_play_again)
		box.add_child(_play_again_btn)
	else:
		var waiting := Label.new()
		waiting.text = "Waiting for host to start next round…"
		waiting.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		box.add_child(waiting)

	var menu := Button.new()
	menu.text = "Back to menu"
	menu.pressed.connect(func(): returned_to_menu.emit())
	box.add_child(menu)

	add_child(_overlay)

	# Fade the overlay in.
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Post-fade decoration: confetti for a win, "BLOCKED" stamp for a blocked round.
	if reason == "DOMINO" and winner == _my_seat:
		_spawn_confetti()
	elif reason == "BLOCKED":
		_spawn_blocked_stamp()


func _update_host_controls() -> void:
	if not is_instance_valid(_end_game_btn):
		return
	# Show End game button only when we know our seat and we are the host.
	var is_host := _host_seat >= 0 and _my_seat == _host_seat
	_end_game_btn.visible = is_host


func _on_end_game_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "End the current round? No scores will be recorded."
	dialog.title = "End game"
	dialog.confirmed.connect(func():
		_end_game_btn.disabled = true
		if _client:
			_client.end_game() if _client.has_method("end_game") else null
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _on_play_again() -> void:
	if is_instance_valid(_play_again_btn):
		_play_again_btn.disabled = true
	_clear_overlay()
	_client.play_again()


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	lbl.position = Vector2(340, 440)
	lbl.size = Vector2(600, 30)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)
	get_tree().create_timer(3.0).timeout.connect(lbl.queue_free)


func _spawn_confetti() -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(640, 360)
	p.amount = 40
	p.lifetime = 1.0
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2(0, 50)
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 200.0
	p.color = Color(1.0, 0.84, 0.27)
	_overlay.add_child(p)
	p.emitting = true


func _spawn_blocked_stamp() -> void:
	var lbl := Label.new()
	lbl.text = "BLOCKED"
	lbl.add_theme_font_size_override("font_size", 52)
	lbl.add_theme_color_override("font_color", Color(1, 0.25, 0.25))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(390, 160)
	lbl.size = Vector2(500, 70)
	lbl.pivot_offset = Vector2(250, 35)
	lbl.scale = Vector2(2.0, 2.0)
	_overlay.add_child(lbl)
	create_tween().tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _clear_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null
