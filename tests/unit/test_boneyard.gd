extends GutTest
## Boneyard draw mechanic: draw one at a time until playable or exhausted.
## (GAME_RULES §5.6–§5.8)


func _hand(pairs: Array) -> Array:
	var h: Array = []
	for p in pairs:
		h.append(Tile.new(p[0], p[1]))
	return h


## Build an active mid-game state with an explicit boneyard.
func _game(num_players: int, hands_pairs: Array, left_end: int, right_end: int,
		current_seat: int, boneyard_pairs: Array) -> GapleGame:
	var s := GameState.new()
	s.num_players = num_players
	s.hands = []
	for hp in hands_pairs:
		s.hands.append(_hand(hp))
	s.boneyard = _hand(boneyard_pairs)
	s.line = [Tile.new(0, 0)]   # non-empty so the engine is in PLAYING mode
	s.left_end = left_end
	s.right_end = right_end
	s.current_seat = current_seat
	s.phase = GameState.Phase.PLAYING
	s.forced_opening_tile = -1
	s.last_placer_seat = (current_seat - 1 + num_players) % num_players
	var g := GapleGame.new()
	g.state = s
	return g


func test_boneyard_count_in_public_dict() -> void:
	for n in [2, 3, 4]:
		var g := GapleGame.new_round(n, 777)
		var pub := g.state.public_dict()
		assert_true(pub.has("boneyard_count"),
			"public_dict has boneyard_count (N=%d)" % n)
		assert_eq(pub["boneyard_count"], g.state.boneyard.size(),
			"boneyard_count matches actual boneyard size (N=%d)" % n)


func test_four_player_boneyard_empty() -> void:
	var g := GapleGame.new_round(4, 42)
	assert_eq(g.state.boneyard.size(), 0, "4-player: 7×4=28 leaves no boneyard")
	assert_eq(g.state.public_dict()["boneyard_count"], 0)


func test_draw_then_play() -> void:
	# Seat 0 holds [3|4] (no match for ends 2/5). Boneyard: [2|3] (matches left=2).
	# Expected: tile_drawn(2|3), then tile_played(2|3, L), then turn_started(1).
	var g := _game(2, [[[3, 4]], [[0, 0]]], 2, 5, 0, [[2, 3]])
	var res := g.apply({"type": "pass", "seat": 0})
	assert_true(res["ok"])
	var evs: Array = res["events"]
	assert_eq(evs.size(), 3, "tile_drawn + tile_played + turn_started")
	assert_eq(evs[0]["type"], "tile_drawn")
	assert_eq(int(evs[0]["seat"]), 0)
	assert_eq(int(evs[0]["tile_id"]), Tile.new(2, 3).to_id())
	assert_eq(evs[1]["type"], "tile_played")
	assert_eq(int(evs[1]["tile_id"]), Tile.new(2, 3).to_id())
	assert_eq(evs[1]["end"], "L")
	assert_eq(evs[2]["type"], "turn_started")
	assert_eq(int(evs[2]["seat"]), 1)
	# Boneyard exhausted; hand has original tile only.
	assert_eq(g.state.boneyard.size(), 0)
	assert_eq(g.state.hands[0].size(), 1)
	assert_eq(g.state.current_seat, 1)
	assert_eq(g.state.consecutive_passes, 0, "consecutive_passes reset after a play")


func test_draw_multiple_before_playable() -> void:
	# Seat 0 holds [3|4]. Boneyard: [6|6] (no match), then [2|6] (matches left=2).
	# Expected: two tile_drawn events, then tile_played.
	var g := _game(2, [[[3, 4]], [[0, 0]]], 2, 5, 0, [[6, 6], [2, 6]])
	var res := g.apply({"type": "pass", "seat": 0})
	assert_true(res["ok"])
	var evs: Array = res["events"]
	assert_eq(evs[0]["type"], "tile_drawn")
	assert_eq(int(evs[0]["tile_id"]), Tile.new(6, 6).to_id())
	assert_eq(evs[1]["type"], "tile_drawn")
	assert_eq(int(evs[1]["tile_id"]), Tile.new(2, 6).to_id())
	assert_eq(evs[2]["type"], "tile_played")
	assert_eq(int(evs[2]["tile_id"]), Tile.new(2, 6).to_id())
	# [6|6] stays in hand since it was drawn but not playable.
	assert_eq(g.state.hands[0].size(), 2, "original + unplayable drawn tile remain")


func test_draw_then_pass_when_none_playable() -> void:
	# Seat 0 holds [3|4]. Boneyard: [6|6] (no match for 2 or 5).
	# Boneyard exhausted → pass.
	var g := _game(3, [[[3, 4]], [[0, 0]], [[1, 1]]], 2, 5, 0, [[6, 6]])
	var res := g.apply({"type": "pass", "seat": 0})
	assert_true(res["ok"])
	var evs: Array = res["events"]
	assert_eq(evs[0]["type"], "tile_drawn")
	assert_eq(evs[1]["type"], "player_passed")
	assert_eq(evs[2]["type"], "turn_started")
	assert_eq(int(evs[2]["seat"]), 1)
	assert_eq(g.state.consecutive_passes, 1)
	assert_eq(g.state.boneyard.size(), 0)
	# The unplayable drawn tile stays in seat 0's hand.
	assert_eq(g.state.hands[0].size(), 2)


func test_empty_boneyard_pass_no_draw() -> void:
	# Boneyard empty from the start: pass immediately without any tile_drawn.
	var g := _game(2, [[[3, 4]], [[0, 0]]], 2, 5, 0, [])
	var res := g.apply({"type": "pass", "seat": 0})
	assert_true(res["ok"])
	var evs: Array = res["events"]
	assert_eq(evs[0]["type"], "player_passed", "first event is a pass, not a draw")
	assert_eq(evs[1]["type"], "turn_started")


func test_draw_winning_tile_ends_round() -> void:
	# Seat 0's hand is empty (synthetic end-game state) so the drawn tile [2|5]
	# becomes their only tile and, being playable, auto-plays for a DOMINO win.
	var g := _game(2, [[], [[0, 0]]], 2, 5, 0, [[2, 5]])
	var res := g.apply({"type": "pass", "seat": 0})
	assert_true(res["ok"])
	var evs: Array = res["events"]
	assert_eq(evs.size(), 3, "tile_drawn + tile_played + round_over")
	assert_eq(evs[0]["type"], "tile_drawn")
	assert_eq(evs[1]["type"], "tile_played")
	assert_eq(evs[2]["type"], "round_over")
	assert_eq(evs[2]["reason"], "DOMINO")
	assert_eq(int(evs[2]["winner_seat"]), 0)


func test_all_draw_exhausted_leads_to_block() -> void:
	# 2-player game. Boneyard empty. Both seats have non-matching tiles.
	# After two consecutive passes the round is blocked.
	var g := _game(2, [[[3, 4]], [[3, 4]]], 2, 5, 0, [])
	g.apply({"type": "pass", "seat": 0})   # consecutive_passes = 1
	var res := g.apply({"type": "pass", "seat": 1})
	assert_true(res["ok"])
	var evs: Array = res["events"]
	var last: Dictionary = evs[evs.size() - 1]
	assert_eq(last["type"], "round_over")
	assert_eq(last["reason"], "BLOCKED")
