extends GutTest
## Deal: 28 unique tiles, 7 per player, deterministic by seed. (PLAN.md §4)


func test_full_set_is_28_unique() -> void:
	var tiles := DominoSet.all_tiles()
	assert_eq(tiles.size(), 28)
	var ids := {}
	for t in tiles:
		ids[t.to_id()] = true
	assert_eq(ids.size(), 28, "no duplicate tiles in the set")


func test_deal_gives_seven_each_for_2_3_4_players() -> void:
	for n in [2, 3, 4]:
		var g := GapleGame.new_round(n, 12345)
		var dealt := {}
		for seat in range(n):
			assert_eq(g.state.hands[seat].size(), GameState.HAND_SIZE,
				"seat %d holds 7 tiles in a %d-player game" % [seat, n])
			for t in g.state.hands[seat]:
				dealt[t.to_id()] = true
		assert_eq(dealt.size(), GameState.HAND_SIZE * n,
			"%d dealt tiles are all distinct" % (GameState.HAND_SIZE * n))


func test_boneyard_size_is_28_minus_dealt() -> void:
	for n in [2, 3, 4]:
		var g := GapleGame.new_round(n, 999)
		assert_eq(g.state.boneyard.size(), 28 - GameState.HAND_SIZE * n,
			"boneyard has 28 - 7N tiles for N=%d" % n)
		# Boneyard tiles must not overlap with dealt tiles.
		var dealt_ids := {}
		for seat in range(n):
			for t in g.state.hands[seat]:
				dealt_ids[t.to_id()] = true
		for t in g.state.boneyard:
			assert_false(dealt_ids.has(t.to_id()),
				"boneyard tile %d not in any hand (N=%d)" % [t.to_id(), n])


func test_no_hand_holds_more_than_five_doubles() -> void:
	# R6: the redeal guarantees no seat is dealt >5 balak, across many seeds.
	for seed in range(200):
		for n in [2, 3, 4]:
			var g := GapleGame.new_round(n, seed)
			for seat in range(n):
				assert_lte(GapleGame.count_doubles(g.state.hands[seat]), 5,
					"seat %d ≤5 doubles (seed %d, N=%d)" % [seat, seed, n])


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
