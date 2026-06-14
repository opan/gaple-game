class_name GameTable
extends Control
## Assembles the whiteboard table and drives the human's interaction against a
## LocalGameDriver (PHASE_2_PLAN.md §7/§8). The client keeps a local view of the
## public board, updated from driver events — never by reading the engine — so
## the same code works against the network path in Phase 4.

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
var _board: BoardLine
var _hand: Hand
var _seats: Dictionary = {}          # logical seat -> OpponentSeat
var _banner: Label
var _status: Label
var _overlay: Control

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


# --- event handling ------------------------------------------------------

func _on_event(msg: Dictionary) -> void:
	match msg["t"]:
		Protocol.S_GAME_STARTED:
			_on_game_started(msg)
		Protocol.S_HAND:
			_my_seat = int(msg.get("seat", _my_seat))
			_human_hand = _to_ints(msg["tile_ids"])
		Protocol.S_PUBLIC_STATE:
			_on_public_state(msg["state"])
		Protocol.S_TILE_PLAYED:
			_on_tile_played(msg)
		Protocol.S_PLAYER_PASSED:
			# The server/driver auto-passes; we react rather than send a pass.
			if int(msg["seat"]) == _my_seat:
				_flash_status("No playable tile — you passed")
			else:
				_flash_status("Seat %d passed" % int(msg["seat"]))
		Protocol.S_TURN_STARTED:
			_on_turn_started(msg["seat"])
		Protocol.S_ROUND_OVER:
			_on_round_over(msg)
		Protocol.S_ERROR:
			_flash_status("Error: %s" % msg.get("message", ""))


func _on_game_started(msg: Dictionary) -> void:
	_num_players = msg["num_players"]
	_opening_tile_id = msg["opening_tile_id"]
	_line = []
	_clear_overlay()
	_build_seats(_num_players)


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
	_board.set_line(_line, _left_end, _right_end)

	if seat == _my_seat:
		_human_hand.erase(tid)
	elif _seats.has(seat):
		_seats[seat].set_count(msg["remaining_count"])


func _on_turn_started(seat: int) -> void:
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
	_hide_banner()
	for s: int in _seats:
		_seats[s].set_active(false)
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
	for seat in range(n):
		if seat == 0:
			continue   # the local player (bottom) isn't an OpponentSeat
		var screen := _screen_for((seat) % n, n)
		var horizontal := screen == "LEFT" or screen == "RIGHT"
		var os := OpponentSeat.new()
		var rect: Rect2 = SEAT_RECT[screen]
		os.position = rect.position
		os.size = rect.size
		add_child(os)
		os.configure("Bot %d" % seat, horizontal)
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

	var again := Button.new()
	again.text = "Play again"
	again.pressed.connect(_on_play_again)
	box.add_child(again)

	var menu := Button.new()
	menu.text = "Back to menu"
	menu.pressed.connect(func(): returned_to_menu.emit())
	box.add_child(menu)

	add_child(_overlay)


func _on_play_again() -> void:
	_clear_overlay()
	_client.play_again()


func _clear_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null
