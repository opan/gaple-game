extends GutTest
## Deal: 28 unique tiles, 5 per player, deterministic by seed. (PLAN.md §4)


func test_full_set_is_28_unique() -> void:
	var tiles := DominoSet.all_tiles()
	assert_eq(tiles.size(), 28)
	var ids := {}
	for t in tiles:
		ids[t.to_id()] = true
	assert_eq(ids.size(), 28, "no duplicate tiles in the set")


func test_deal_gives_five_each_for_2_3_4_players() -> void:
	for n in [2, 3, 4]:
		var g := GapleGame.new_round(n, 12345)
		var dealt := {}
		for seat in range(n):
			assert_eq(g.state.hands[seat].size(), GameState.HAND_SIZE,
				"seat %d holds 5 tiles in a %d-player game" % [seat, n])
			for t in g.state.hands[seat]:
				dealt[t.to_id()] = true
		assert_eq(dealt.size(), 5 * n, "%d dealt tiles are all distinct" % (5 * n))


func test_boneyard_size_is_28_minus_dealt() -> void:
	for n in [2, 3, 4]:
		var g := GapleGame.new_round(n, 999)
		var in_hands := 0
		for seat in range(n):
			in_hands += g.state.hands[seat].size()
		assert_eq(28 - in_hands, 28 - 5 * n, "boneyard = 28 - 5N for N=%d" % n)


func test_same_seed_same_deal() -> void:
	var a := GapleGame.new_round(4, 42)
	var b := GapleGame.new_round(4, 42)
	assert_eq(a.state.to_dict()["hands"], b.state.to_dict()["hands"],
		"identical seed reproduces identical hands")


func test_different_seed_different_deal() -> void:
	var a := GapleGame.new_round(4, 1)
	var b := GapleGame.new_round(4, 2)
	assert_ne(a.state.to_dict()["hands"], b.state.to_dict()["hands"],
		"different seeds (almost surely) differ")
