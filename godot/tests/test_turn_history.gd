extends GutTest


func before_all() -> void:
	Content.load_farm_content()


func _farm_state() -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)
	state.supply_shortage_ack_turn = state.turn
	return state


func _add_business(state: RunState) -> void:
	var biz := BusinessInstance.new()
	biz.id = "biz-1"
	biz.template_id = "vegetable_farm"
	biz.name = "Test Vegetable Farm"
	biz.revenue_per_turn = 12000
	biz.operating_costs = 7000
	state.portfolio.businesses.append(biz)


func test_baseline_recorded_on_new_run() -> void:
	var state := _farm_state()
	assert_eq(state.turn_history.size(), 1)
	assert_eq(int(state.turn_history[0].get("turn", -1)), 0)
	assert_eq(int(state.turn_history[0].get("cash", 0)), state.cash)


func test_turn_history_grows_after_three_advances() -> void:
	Game.state = _farm_state()
	_add_business(Game.state)
	for _i in 3:
		var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
		assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_gte(Game.state.turn_history.size(), 4)


func test_turn_history_includes_profit_field() -> void:
	Game.state = _farm_state()
	_add_business(Game.state)
	Game.apply_command(GameCommand.advance_turn())
	var last: Dictionary = Game.state.turn_history[Game.state.turn_history.size() - 1]
	assert_true(last.has("profit"))
	assert_true(last.has("debt"))


func test_debt_series_reflects_loan_after_advance() -> void:
	Game.state = _farm_state()
	_add_business(Game.state)
	Game.state.opportunities = [{
		"id": "loan-test",
		"assetType": "loan",
		"name": "Bank Line of Credit Offer",
		"maxAmount": 30000,
		"rate": 0.06,
		"termTurns": 10,
		"expiresIn": 2,
	}]
	var loan_result: Dictionary = Game.apply_command(GameCommand.take_loan("loan-test"))
	assert_true(bool(loan_result.get("ok", false)), str(loan_result.get("error", "")))
	var advance: Dictionary = Game.apply_command(GameCommand.advance_turn())
	assert_true(bool(advance.get("ok", false)), str(advance.get("error", "")))
	var last: Dictionary = Game.state.turn_history[Game.state.turn_history.size() - 1]
	assert_gt(int(last.get("debt", 0)), 0)
