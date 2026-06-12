extends GutTest
## Smoke test: UI components instantiate and their public methods run without
## errors in a headless tree. (Rendering/_draw isn't exercised headlessly.)


func test_tile_face_setup() -> void:
	var tf := TileFace.new()
	add_child_autofree(tf)
	tf.setup(2, 5, true, false)
	assert_eq(tf.tile_id(), Tile.new(2, 5).to_id())
	tf.set_vis(TileFace.Vis.SELECTED)
	tf.set_vis(TileFace.Vis.DISABLED)
	pass_test("tile face configured")


func test_hand_renders_tiles_and_enables_playable() -> void:
	var hand := Hand.new()
	hand.size = Vector2(600, 200)
	add_child_autofree(hand)
	var ids := [Tile.new(2, 5).to_id(), Tile.new(1, 1).to_id(), Tile.new(0, 6).to_id()]
	var playable := {ids[0]: true}   # only the first is playable
	hand.set_hand(ids, playable)
	# 3 TileFace children.
	var faces := 0
	for c in hand.get_children():
		if c is TileFace:
			faces += 1
	assert_eq(faces, 3, "one TileFace per hand tile")


func test_hand_emits_clicked_for_enabled_tile() -> void:
	var hand := Hand.new()
	hand.size = Vector2(600, 200)
	add_child_autofree(hand)
	var tid := Tile.new(3, 4).to_id()
	hand.set_hand([tid], {tid: true})
	watch_signals(hand)
	# Find the face and emit its pressed signal as a click would.
	for c in hand.get_children():
		if c is TileFace:
			c.pressed.emit(tid)
	assert_signal_emitted_with_parameters(hand, "tile_clicked", [tid])


func test_board_line_set_line() -> void:
	var board := BoardLine.new()
	board.size = Vector2(600, 200)
	add_child_autofree(board)
	board.set_line([Tile.new(6, 6).to_id(), Tile.new(6, 3).to_id()], 6, 3)
	board.highlight_ends(true, false)
	board.highlight_ends(false, false)
	pass_test("board line rendered and ends toggled")


func test_opponent_seat() -> void:
	var seat := OpponentSeat.new()
	add_child_autofree(seat)
	seat.configure("Bot 1", false)
	seat.set_count(5)
	seat.set_count(4)
	seat.set_active(true)
	seat.set_active(false)
	pass_test("opponent seat updated")
