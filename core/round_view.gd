class_name RoundView
extends RefCounted

const GapleGame = preload("res://core/gaple_game.gd")
const Protocol  = preload("res://core/protocol.gd")
## Pure helper (ADR-003) shared by the local driver and the network Room: turns
## engine events into wire messages and builds the round-start announce set.
## Keeping this in one tested place is what stops local and online play from
## drifting (PHASE_3_PLAN.md §9). It owns no Node, no timers, no routing — the
## caller decides who receives each message.


## Enrich one engine event (from GapleGame.apply().events) into a wire message.
## For round_over it also computes pip_counts + scores and accumulates them into
## the caller-owned `scoreboard` (mutated in place). `deadline_ms` is applied to
## turn_started only (-1 = no timer, e.g. local play).
static func to_wire(game: GapleGame, ev: Dictionary, scoreboard: Array, deadline_ms: int = -1) -> Dictionary:
	match ev["type"]:
		"tile_drawn":
			return Protocol.from_engine_event(ev)
		"turn_started":
			return Protocol.from_engine_event(ev, {"deadline_unix_ms": deadline_ms})
		"round_over":
			var pip_counts: Array = []
			for seat in range(game.state.num_players):
				pip_counts.append(game.pip_count(seat))
			var scores := GapleGame.round_scores(game.state)
			for seat in range(scores.size()):
				scoreboard[seat] += scores[seat]
			return Protocol.from_engine_event(ev, {
				"pip_counts": pip_counts,
				"scores": scores,
				"scoreboard": scoreboard.duplicate(),
			})
		_:
			return Protocol.from_engine_event(ev)


## The round-start messages, ready to route. The caller broadcasts game_started/
## public_state/turn_started and sends each HUMAN seat only its own hands[seat]
## (never broadcast — ADR-002 hidden information). `hands` includes every seat
## so the caller can pick; bots' entries are simply never sent.
static func announce(game: GapleGame, deadline_ms: int = -1) -> Dictionary:
	var hands := {}
	for seat in range(game.state.num_players):
		hands[seat] = Protocol.hand(game.state.hand_dict(seat), seat)
	return {
		"game_started": Protocol.game_started(
			game.state.num_players, game.state.current_seat, game.state.forced_opening_tile),
		"public_state": Protocol.public_state(game.state.public_dict()),
		"turn_started": Protocol.turn_started(game.state.current_seat, deadline_ms),
		"hands": hands,
	}
