extends GutTest


func before_all() -> void:
	Content.load_farm_content()


func _farm_state() -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.supply_shortage_ack_turn = state.turn
	return state


func test_turn_one_starts_with_three_ap_via_reset() -> void:
	Game.state = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	ActionPointsSystem.reset_for_turn(Game.state)
	assert_eq(Game.state.action_points, 3)


func test_ap_resets_to_two_after_first_advance() -> void:
	Game.state = _farm_state()
	Game.state.action_points = 0
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_eq(Game.state.turn, 2)
	assert_eq(Game.state.action_points, 2)


func test_opportunity_survives_advance_with_expiry_decrement() -> void:
	Game.state = _farm_state()
	Game.state.opportunities = [{
		"id": "persist-1",
		"assetType": "business",
		"expiresIn": 3,
		"name": "Test Farm",
	}]
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	var found: Dictionary = {}
	for opp_variant in Game.state.opportunities:
		if typeof(opp_variant) == TYPE_DICTIONARY and str((opp_variant as Dictionary).get("id", "")) == "persist-1":
			found = opp_variant
			break
	assert_false(found.is_empty(), "Expected listing to survive advance")
	assert_eq(int(found.get("expiresIn", 0)), 2)


func test_acquire_requires_ap() -> void:
	Game.state = _farm_state()
	OpportunitySystem.refresh_opportunities(Game.state)
	assert_gt(Game.state.opportunities.size(), 0)
	var opp: Dictionary = Game.state.opportunities[0]
	Game.state.action_points = 0
	Game.state.cash = int(opp.get("price", 0)) + 10000
	var result: Dictionary = Game.apply_command(GameCommand.acquire_business(str(opp.get("id", ""))))
	assert_false(bool(result.get("ok", false)))


func test_seller_note_close_finances_remainder() -> void:
	Game.state = _farm_state()
	Game.state.cash = 30000
	Game.state.reputation = 12
	var opp_id := "seller-note-opp"
	Game.state.opportunities = [{
		"id": opp_id,
		"assetType": "business",
		"templateId": "grain_farm",
		"name": "Test Grain Farm",
		"price": 100000,
		"revenue": 20000,
		"cost": 12000,
		"fairValue": 80000,
		"industry": "ag",
		"layer": "primary_production",
	}]
	var offer: Dictionary = {
		"totalPrice": 100000,
		"cashAtClosing": 40000,
		"closingSpeed": "standard",
		"termsOffered": ["seller note"],
	}
	var result: Dictionary = AcquisitionSystem.close_business_acquisition(Game.state, opp_id, offer)
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_eq(Game.state.cash, 0)
	assert_eq(Game.state.loans.size(), 1)
	assert_eq(int((Game.state.loans[0] as Dictionary).get("principal", 0)), 60000)
	assert_eq(Game.state.portfolio.businesses.size(), 1)
	assert_eq(Game.state.reputation, 14)


func test_insolvency_triggers_game_over() -> void:
	var state: RunState = _farm_state()
	state.reputation = 10
	state.cash = -20000
	RunRulesSystem.apply_post_cash_flow_checks(state)
	assert_not_null(state.game_over)
	assert_eq(str((state.game_over as Dictionary).get("reason", "")), "insolvency")


func test_win_at_ten_million_net_worth() -> void:
	var state: RunState = _farm_state()
	state.turn = 5
	state.cash = RunRulesSystem.WIN_NET_WORTH
	RunRulesSystem.apply_turn_increment(state)
	RunRulesSystem.apply_end_of_turn_victory_checks(state)
	assert_not_null(state.game_over)
	assert_eq(str((state.game_over as Dictionary).get("result", "")), "win")
	assert_eq(str((state.game_over as Dictionary).get("reason", "")), "target_reached")


func test_timeout_at_max_turns_without_target() -> void:
	var state: RunState = _farm_state()
	state.turn = 30
	state.cash = 50000
	RunRulesSystem.apply_turn_increment(state)
	RunRulesSystem.apply_end_of_turn_victory_checks(state)
	assert_not_null(state.game_over)
	assert_eq(str((state.game_over as Dictionary).get("result", "")), "timeout")
	assert_eq(str((state.game_over as Dictionary).get("reason", "")), "turn_limit")
