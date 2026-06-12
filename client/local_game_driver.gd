class_name LocalGameDriver
extends Node
## Drives an offline round against bots and emits the same wire messages the
## network path will (PHASE_2_PLAN.md §5). The UI listens to `event_received`
## and never touches the engine directly, so Phase 4 swaps this for a real
## connection without changing the UI.
##
## Bot pacing is the driver's job; human turn timing is the UI's. On a human
## turn the driver simply stops and waits for submit_play()/submit_pass().

signal event_received(msg: Dictionary)

## Bot "thinking" delay range, seconds (ADR-004). Tests set Vector2.ZERO to run
## synchronously.
var bot_delay := Vector2(0.8, 2.0)

var _game: GapleGame
var _human_seat: int = 0
var _bots: Dictionary = {}          # seat -> BotPolicy
var _rng: RandomNumberGenerator
var _scoreboard: Array = []
var _driving: bool = false


## Begin a round. `game_seed < 0` picks a random seed.
func start(num_players: int, human_seat: int = 0, game_seed: int = -1) -> void:
	_human_seat = human_seat
	_rng = RandomNumberGenerator.new()
	if game_seed < 0:
		_rng.randomize()
		game_seed = int(_rng.randi())
	_rng.seed = game_seed

	_game = GapleGame.new_round(num_players, game_seed)
	_bots.clear()
	for seat in range(num_players):
		if seat != human_seat:
			_bots[seat] = BotPolicy.new()
	if _scoreboard.size() != num_players:
		_scoreboard = []
		for _i in range(num_players):
			_scoreboard.append(0)

	_announce_round()
	_drive()


## Winner of the last round opens the next; cumulative scoreboard is kept.
func play_again() -> void:
	var n := _game.state.num_players
	var opener := _game.state.winner_seat if _game.state.winner_seat >= 0 else 0
	_game = GapleGame.new_round(n, int(_rng.randi()), opener)
	_announce_round()
	_drive()


func submit_play(tile_id: int, end_side: String) -> void:
	_apply({"type": "play", "seat": _human_seat, "tile_id": tile_id, "end": end_side})
	_drive()


func submit_pass() -> void:
	_apply({"type": "pass", "seat": _human_seat})
	_drive()


## Legal moves for the local player — the UI uses this to highlight tiles/ends.
func legal_moves_for_human() -> Array:
	return _game.legal_moves(_human_seat)


func human_seat() -> int:
	return _human_seat


# --- internals -----------------------------------------------------------

func _announce_round() -> void:
	_emit(Protocol.game_started(_game.state.num_players, _game.state.current_seat, _game.state.forced_opening_tile))
	_emit(Protocol.hand(_game.state.hand_dict(_human_seat)))
	_emit(Protocol.public_state(_game.state.public_dict()))
	_emit(Protocol.turn_started(_game.state.current_seat))


## Play out bot turns until it is the human's turn or the round ends.
func _drive() -> void:
	if _driving:
		return
	_driving = true
	while _game.state.is_active():
		var seat := _game.state.current_seat
		if seat == _human_seat:
			break
		if bot_delay.y > 0.0:
			await get_tree().create_timer(_rng.randf_range(bot_delay.x, bot_delay.y)).timeout
			if not _game.state.is_active():
				break
		var legal := _game.legal_moves(seat)
		if legal.is_empty():
			_apply({"type": "pass", "seat": seat})
		else:
			var m: Dictionary = _bots[seat].choose_move(
				_game.state.public_dict(), _game.state.hand_dict(seat), legal, _rng)
			_apply({"type": "play", "seat": seat, "tile_id": m["tile_id"], "end": m["end"]})
	_driving = false


func _apply(intent: Dictionary) -> void:
	var res := _game.apply(intent)
	if not res["ok"]:
		_emit(Protocol.error(Protocol.E_ILLEGAL_MOVE, res["error"]))
		return
	for ev: Dictionary in res["events"]:
		_emit(_to_wire(ev))


func _to_wire(ev: Dictionary) -> Dictionary:
	match ev["type"]:
		"turn_started":
			return Protocol.from_engine_event(ev, {"deadline_unix_ms": -1})
		"round_over":
			var pip_counts: Array = []
			for seat in range(_game.state.num_players):
				pip_counts.append(_game.pip_count(seat))
			var scores := GapleGame.round_scores(_game.state)
			for seat in range(scores.size()):
				_scoreboard[seat] += scores[seat]
			return Protocol.from_engine_event(ev, {
				"pip_counts": pip_counts,
				"scores": scores,
				"scoreboard": _scoreboard.duplicate(),
			})
		_:
			return Protocol.from_engine_event(ev)


func _emit(msg: Dictionary) -> void:
	event_received.emit(msg)
