class_name Room
extends Node

const GameState  = preload("res://core/game_state.gd")
const Transport  = preload("res://server/transport.gd")
const GapleGame  = preload("res://core/gaple_game.gd")
const BotPolicy  = preload("res://core/bot_policy.gd")
const Protocol   = preload("res://core/protocol.gd")
const RoundView  = preload("res://core/round_view.gd")
## One game room: lobby + round orchestration, authoritative over all state
## (ADR-002). Validates every intent with GapleGame.apply, drives bots and stuck
## seats itself, and broadcasts hidden-information-safe events via the injected
## Transport. Shares the pure event/scoring logic with the local driver through
## RoundView (PHASE_3_PLAN.md §6–§9).

## Emitted when the room has no connected humans left; GameServer destroys it.
signal empty(code: String)

enum Phase { LOBBY, PLAYING, ROUND_OVER }

const MAX_SEATS := 4

## Bot "thinking" delay, seconds. Tests set Vector2.ZERO to run synchronously.
var bot_delay := Vector2(0.8, 2.0)

## Seconds a connected human has to move before the server auto-plays for them.
## Tests trigger timeouts directly via _handle_turn_timeout for determinism.
var turn_timeout_sec := float(GameState.TURN_TIMEOUT_SEC)

const MAX_TIMEOUTS := 3          # consecutive timeouts before the seat becomes a bot

var code: String
var phase: int = Phase.LOBBY
var seats: Array = []            # occupant dicts, index = seat
var _host_seat: int = 0          # which seat is host (migrates if the host leaves)

var _transport: Transport
var _game: GapleGame
var _scoreboard: Array = []
var _rng: RandomNumberGenerator
var _driving := false
var _fallback_bot: BotPolicy     # drives disconnected/timed-out humans' turns
var _turn_gen := 0               # invalidates a stale turn timer once the turn moves on


func setup(room_code: String, transport: Transport, rng_seed: int = -1) -> void:
	code = room_code
	_transport = transport
	_rng = RandomNumberGenerator.new()
	if rng_seed < 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed
	_fallback_bot = BotPolicy.new()


# --- lobby membership (called by GameServer) -----------------------------

func add_host(peer_id: int, name: String, token: String) -> void:
	seats = [_human_occ(peer_id, name, token)]
	_host_seat = 0
	broadcast_room_state()


## Reattach a reconnecting human to its disconnected seat (matched by token).
## Returns the seat reclaimed, or -1 if no match. Resyncs that peer's view.
func try_reclaim(new_peer_id: int, token: String) -> int:
	for seat in range(seats.size()):
		var occ: Dictionary = seats[seat]
		if occ["kind"] == "human" and not occ["connected"] and occ.get("token", "") == token:
			occ["peer_id"] = new_peer_id
			occ["connected"] = true
			occ["timeouts"] = 0
			_broadcast(Protocol.player_reclaimed(seat))
			broadcast_room_state()
			if phase != Phase.LOBBY and _game != null:
				_resync(new_peer_id, seat)
			return seat
	return -1


## Returns "" on success, else an error code (ROOM_IN_PROGRESS / ROOM_FULL).
func add_human(peer_id: int, name: String, token: String) -> String:
	if phase != Phase.LOBBY:
		return Protocol.E_ROOM_IN_PROGRESS
	if seats.size() >= MAX_SEATS:
		return Protocol.E_ROOM_FULL
	seats.append(_human_occ(peer_id, name, token))
	broadcast_room_state()
	return ""


func has_peer(peer_id: int) -> bool:
	return _seat_of_peer(peer_id) >= 0


func connected_human_count() -> int:
	var n := 0
	for occ in seats:
		if occ["kind"] == "human" and occ["connected"]:
			n += 1
	return n


# --- in-room message dispatch (called by GameServer) ---------------------

func handle(peer_id: int, msg: Dictionary) -> void:
	var err := ""
	match msg.get("t", ""):
		Protocol.C_ADD_BOT:
			err = _do_add_bot(peer_id)
		Protocol.C_REMOVE_BOT:
			err = _do_remove_bot(peer_id, int(msg.get("seat", -1)))
		Protocol.C_START_GAME:
			err = _do_start(peer_id)
		Protocol.C_PLAY_TILE:
			err = _do_play(peer_id, int(msg.get("tile_id", -1)), str(msg.get("end", "")))
		Protocol.C_END_GAME:
			err = _do_end_game(peer_id)
		Protocol.C_PLAY_AGAIN:
			err = _do_play_again(peer_id)
		Protocol.C_LEAVE_ROOM:
			_do_leave(peer_id)
		_:
			err = Protocol.E_BAD_INTENT
	if err != "":
		_send(peer_id, Protocol.error(err, err))


# --- host/lobby actions --------------------------------------------------

func _do_add_bot(peer_id: int) -> String:
	if not _is_host(peer_id):
		return Protocol.E_NOT_HOST
	if phase != Phase.LOBBY:
		return Protocol.E_BAD_INTENT
	if seats.size() >= MAX_SEATS:
		return Protocol.E_ROOM_FULL
	seats.append(_bot_occ(seats.size()))
	broadcast_room_state()
	return ""


func _do_remove_bot(peer_id: int, seat: int) -> String:
	if not _is_host(peer_id):
		return Protocol.E_NOT_HOST
	if phase != Phase.LOBBY:
		return Protocol.E_BAD_INTENT
	if seat <= 0 or seat >= seats.size() or seats[seat]["kind"] != "bot":
		return Protocol.E_BAD_INTENT
	seats.remove_at(seat)
	broadcast_room_state()
	return ""


func _do_start(peer_id: int) -> String:
	if not _is_host(peer_id):
		return Protocol.E_NOT_HOST
	if phase != Phase.LOBBY or seats.size() < 2:
		return Protocol.E_BAD_INTENT
	_scoreboard = []
	for _i in range(seats.size()):
		_scoreboard.append(0)
	_start_round(GapleGame.new_round(seats.size(), int(_rng.randi())))
	return ""


func _do_play_again(peer_id: int) -> String:
	if not _is_host(peer_id):
		return Protocol.E_NOT_HOST
	if phase != Phase.ROUND_OVER:
		return Protocol.E_BAD_INTENT
	var opener: int = _game.state.winner_seat if _game.state.winner_seat >= 0 else 0
	_start_round(GapleGame.new_round(seats.size(), int(_rng.randi()), opener))
	return ""


func _do_end_game(peer_id: int) -> String:
	if not _is_host(peer_id):
		return Protocol.E_NOT_HOST
	if phase != Phase.PLAYING:
		return Protocol.E_BAD_INTENT
	_apply_and_broadcast({"type": "abort", "seat": 0})
	phase = Phase.ROUND_OVER
	return ""


# --- gameplay ------------------------------------------------------------

func _do_play(peer_id: int, tile_id: int, end_side: String) -> String:
	if phase != Phase.PLAYING:
		return Protocol.E_BAD_INTENT
	var seat := _seat_of_peer(peer_id)
	if seat != _game.state.current_seat:
		return Protocol.E_NOT_YOUR_TURN
	var res := _apply_and_broadcast({"type": "play", "seat": seat, "tile_id": tile_id, "end": end_side})
	if not res["ok"]:
		return Protocol.E_ILLEGAL_MOVE
	seats[seat]["timeouts"] = 0   # a real move resets the consecutive-timeout count
	_turn_gen += 1                # any pending turn timer is now stale
	if phase == Phase.PLAYING:
		_drive()
	return ""


func _start_round(game: GapleGame) -> void:
	_game = game
	phase = Phase.PLAYING
	var a := RoundView.announce(_game, _deadline_ms())
	_broadcast(a["game_started"])
	_broadcast(a["public_state"])
	for seat in range(seats.size()):
		var occ: Dictionary = seats[seat]
		if occ["kind"] == "human" and occ["connected"]:
			_send(occ["peer_id"], a["hands"][seat])
	_broadcast(a["turn_started"])
	_drive()


## Play out every seat the server can act for (bots, stuck seats, disconnected
## humans) until a connected human with a legal move must decide, or the round
## ends.
func _drive() -> void:
	if _driving:
		return
	_driving = true
	while _game != null and _game.state.is_active():
		var seat := _game.state.current_seat
		var legal := _game.legal_moves(seat)
		var occ: Dictionary = seats[seat]
		var human_can_move: bool = occ["kind"] == "human" and occ["connected"] and not legal.is_empty()
		if human_can_move:
			_arm_turn_timer(seat)
			break   # wait for this human's play_tile
		if occ["kind"] == "bot" and bot_delay.y > 0.0:
			await get_tree().create_timer(_rng.randf_range(bot_delay.x, bot_delay.y)).timeout
			if _game == null or not _game.state.is_active():
				break
		if legal.is_empty():
			_apply_and_broadcast({"type": "pass", "seat": seat})
		else:
			var policy: BotPolicy = occ["policy"] if occ["kind"] == "bot" else _fallback_bot
			var m: Dictionary = policy.choose_move(
				_game.state.public_dict(), _game.state.hand_dict(seat), legal, _rng)
			_apply_and_broadcast({"type": "play", "seat": seat, "tile_id": m["tile_id"], "end": m["end"]})
	if _game != null and _game.state.phase == GameState.Phase.ROUND_OVER:
		phase = Phase.ROUND_OVER
	_driving = false


## Arm a one-shot timer for the waiting human; a generation token makes any
## earlier timer a no-op once the turn has moved on.
func _arm_turn_timer(seat: int) -> void:
	_turn_gen += 1
	if turn_timeout_sec <= 0.0 or not is_inside_tree():
		return
	var gen := _turn_gen
	get_tree().create_timer(turn_timeout_sec).timeout.connect(
		func() -> void:
			if gen == _turn_gen:
				_handle_turn_timeout(seat))


## The waiting human ran out of time: auto-play for them (forced pass or the bot
## policy), and after MAX_TIMEOUTS consecutive misses convert the seat to a bot
## for the rest of the round (GAME_RULES §8).
func _handle_turn_timeout(seat: int) -> void:
	if phase != Phase.PLAYING or _game.state.current_seat != seat:
		return
	var occ: Dictionary = seats[seat]
	if occ["kind"] != "human":
		return
	occ["timeouts"] = int(occ["timeouts"]) + 1
	if occ["timeouts"] >= MAX_TIMEOUTS:
		# Announce while the peer is still a "human" so the broadcast reaches it,
		# then convert the seat to a bot for the rest of the round.
		_broadcast(Protocol.player_replaced_by_bot(seat))
		occ["kind"] = "bot"
		occ["policy"] = BotPolicy.new()

	var legal := _game.legal_moves(seat)
	if legal.is_empty():
		_apply_and_broadcast({"type": "pass", "seat": seat})
	else:
		var m: Dictionary = _fallback_bot.choose_move(
			_game.state.public_dict(), _game.state.hand_dict(seat), legal, _rng)
		_apply_and_broadcast({"type": "play", "seat": seat, "tile_id": m["tile_id"], "end": m["end"]})
	if phase == Phase.PLAYING:
		_drive()


func _apply_and_broadcast(intent: Dictionary) -> Dictionary:
	var res := _game.apply(intent)
	if not res["ok"]:
		return res
	for ev: Dictionary in res["events"]:
		_broadcast(RoundView.to_wire(_game, ev, _scoreboard, _deadline_ms()))
	if _game.state.phase == GameState.Phase.ROUND_OVER:
		phase = Phase.ROUND_OVER
	return res


func _do_leave(peer_id: int) -> void:
	var seat := _seat_of_peer(peer_id)
	if seat < 0:
		return
	var was_current: bool = phase == Phase.PLAYING and _game != null and seat == _game.state.current_seat
	if phase == Phase.LOBBY:
		seats.remove_at(seat)            # free the seat; lobby has no game yet
	else:
		# Live round: keep the seat (and its hand) for reclaim; the drive loop
		# now bot-plays it. The human can reconnect with their token.
		seats[seat]["connected"] = false
		_broadcast(Protocol.player_replaced_by_bot(seat))

	if connected_human_count() == 0:
		empty.emit(code)                 # GameServer destroys the room
		return
	if not _is_valid_host_seat(_host_seat):
		_host_seat = _first_connected_human_seat()   # host migration (GAME_RULES §8)
	broadcast_room_state()
	if was_current:
		_drive()


func _resync(peer_id: int, seat: int) -> void:
	var a := RoundView.announce(_game, _deadline_ms())
	_send(peer_id, a["game_started"])
	_send(peer_id, a["public_state"])
	_send(peer_id, a["hands"][seat])
	_send(peer_id, a["turn_started"])


# --- room state broadcast ------------------------------------------------

func broadcast_room_state() -> void:
	_broadcast(Protocol.room_state(code, _host_seat, _seat_infos(), _phase_name(), _scoreboard))


func _seat_infos() -> Array:
	var infos: Array = []
	for seat in range(seats.size()):
		var occ: Dictionary = seats[seat]
		infos.append({
			"seat": seat,
			"name": occ["name"],
			"kind": occ["kind"],
			"connected": occ.get("connected", true),
		})
	return infos


# --- helpers -------------------------------------------------------------

func _human_occ(peer_id: int, name: String, token: String) -> Dictionary:
	return {"kind": "human", "peer_id": peer_id, "name": name, "connected": true,
		"token": token, "timeouts": 0}


func _bot_occ(index: int) -> Dictionary:
	return {"kind": "bot", "peer_id": -1, "name": "Bot %d" % index, "connected": true,
		"policy": BotPolicy.new()}


func _is_host(peer_id: int) -> bool:
	return _is_valid_host_seat(_host_seat) and seats[_host_seat]["peer_id"] == peer_id


func _is_valid_host_seat(seat: int) -> bool:
	return seat >= 0 and seat < seats.size() \
		and seats[seat]["kind"] == "human" and seats[seat]["connected"]


func _first_connected_human_seat() -> int:
	for seat in range(seats.size()):
		if seats[seat]["kind"] == "human" and seats[seat]["connected"]:
			return seat
	return -1


func _seat_of_peer(peer_id: int) -> int:
	for seat in range(seats.size()):
		if seats[seat]["kind"] == "human" and seats[seat]["peer_id"] == peer_id:
			return seat
	return -1


func _human_peers() -> Array:
	var peers: Array = []
	for occ in seats:
		if occ["kind"] == "human" and occ["connected"]:
			peers.append(occ["peer_id"])
	return peers


func _send(peer_id: int, msg: Dictionary) -> void:
	_transport.send(peer_id, msg)


func _broadcast(msg: Dictionary) -> void:
	_transport.broadcast(_human_peers(), msg)


func _deadline_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) + GameState.TURN_TIMEOUT_SEC * 1000


func _phase_name() -> String:
	return ["LOBBY", "PLAYING", "ROUND_OVER"][phase]
