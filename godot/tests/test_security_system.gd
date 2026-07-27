extends GutTest

const _Debrief := preload("res://core/systems/debrief_system.gd")


func before_all() -> void:
	Content.load_farm_content()


func _farm_state() -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)
	SecuritySystem.init_run(state)
	return state


func test_make_security_opportunity_has_expected_shape() -> void:
	var state: RunState = _farm_state()
	var rng := SeededRng.new()
	var opp: Dictionary = SecuritySystem.make_security_opportunity(state, rng)
	assert_false(opp.is_empty())
	assert_eq(str(opp.get("assetType", "")), "security")
	assert_eq(int(opp.get("expiresIn", 0)), 1)
	assert_false(str(opp.get("ticker", "")).is_empty())
	assert_gt(int(opp.get("price", 0)), 0)


func test_buy_and_sell_security_updates_portfolio_and_cash() -> void:
	var state: RunState = _farm_state()
	var rng := SeededRng.new()
	var opp: Dictionary = SecuritySystem.make_security_opportunity(state, rng)
	assert_false(opp.is_empty())
	state.opportunities = [opp]
	var cash_before: int = state.cash
	state.action_points = 2
	var buy: Dictionary = SecuritySystem.buy_security(state, str(opp.get("id", "")), 10)
	assert_true(bool(buy.get("ok", false)), str(buy.get("error", "")))
	assert_eq(state.portfolio.securities.size(), 1)
	assert_lt(state.cash, cash_before)
	var holding: Dictionary = state.portfolio.securities[0]
	assert_eq(int(holding.get("costBasis", 0)), int(opp.get("price", 0)))
	var ticker: String = str(opp.get("ticker", ""))
	var sell: Dictionary = SecuritySystem.sell_security(state, ticker)
	assert_true(bool(sell.get("ok", false)))
	assert_eq(state.portfolio.securities.size(), 0)
	assert_gt(state.cash, cash_before - int(buy.get("cost", 0)))


func test_security_prices_in_net_worth() -> void:
	var state: RunState = _farm_state()
	state.portfolio.securities.append({"ticker": "TCH", "shares": 10, "price": 120, "costBasis": 100})
	assert_eq(SecuritySystem.securities_market_value(state), 1200)
	assert_eq(FinanceSystem.net_worth(state), state.cash + 1200)


func test_change_indicator_shows_gain_and_loss() -> void:
	assert_true(SecuritySystem.change_indicator_text(110, 100).contains("▲"))
	assert_true(SecuritySystem.change_indicator_text(90, 100).contains("▼"))
	assert_true(SecuritySystem.change_indicator_text(100, 100).is_empty())


func test_format_holding_summary_includes_basis_and_change() -> void:
	var line: String = SecuritySystem.format_holding_summary({
		"ticker": "CNS",
		"shares": 10,
		"price": 115,
		"costBasis": 100,
	})
	assert_true(line.contains("Basis"))
	assert_true(line.contains("▲"))


func test_update_prices_mutates_holding_and_sec_prices() -> void:
	var state: RunState = _farm_state()
	state.run_seed = 424242
	state.portfolio.securities.append({"ticker": "CNS", "shares": 10, "price": 100, "costBasis": 100})
	state.sec_prices = {"CNS": 100}
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 7919 + 17)
	SecuritySystem.update_prices(state, rng)
	var holding: Dictionary = state.portfolio.securities[0]
	var new_price: int = int(holding.get("price", 0))
	assert_gte(new_price, 5)
	assert_eq(int(state.sec_prices.get("CNS", 0)), new_price)


func test_prices_drift_after_advance_turn() -> void:
	Game.state = _farm_state()
	Game.state.run_seed = 98765
	Game.state.supply_shortage_ack_turn = Game.state.turn
	Game.state.portfolio.securities.append({"ticker": "CNS", "shares": 10, "price": 100, "costBasis": 100})
	Game.state.sec_prices = {"CNS": 100}
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	var price_after: int = int(Game.state.portfolio.securities[0].get("price", 0))
	assert_gte(price_after, 5)
	assert_eq(int(Game.state.sec_prices.get("CNS", 0)), price_after)


func test_buy_via_command_from_opportunity_listing() -> void:
	Game.state = _farm_state()
	var opp: Dictionary = SecuritySystem.make_security_opportunity(Game.state, SeededRng.new())
	Game.state.opportunities = [opp]
	Game.state.action_points = 2
	var cash_before: int = Game.state.cash
	var result: Dictionary = Game.apply_command(GameCommand.buy_security(str(opp.get("id", "")), 10))
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_eq(Game.state.portfolio.securities.size(), 1)
	assert_eq(Game.state.opportunities.size(), 0)
	assert_lt(Game.state.cash, cash_before)


func test_debrief_highlights_securities_mark_to_market() -> void:
	var state: RunState = _farm_state()
	var report: Dictionary = _Debrief.build_turn_debrief(state, {
		"netCashFlow": 1000,
		"revenueTotal": 5000,
		"costTotal": 3500,
		"debtService": 500,
	}, {
		"beforeSnap": _Debrief.snapshot_period_state(state),
		"afterSnap": _Debrief.snapshot_period_state(state),
		"securitiesValueBefore": 10000,
		"securitiesValueAfter": 12500,
	})
	var found := false
	for item in report.get("highlights", []):
		if str(item).contains("Securities mark-to-market"):
			found = true
			break
	assert_true(found)


func test_fresh_opportunity_batch_includes_security_over_many_seeds() -> void:
	var found := false
	for seed_value in 200:
		var state: RunState = _farm_state()
		state.run_seed = seed_value
		state.turn = 4
		state.starter_deal_offered = true
		state.opportunities.clear()
		OpportunitySystem.advance_opportunities(state)
		for opp_variant in state.opportunities:
			if typeof(opp_variant) == TYPE_DICTIONARY and str((opp_variant as Dictionary).get("assetType", "")) == "security":
				found = true
				break
		if found:
			break
	assert_true(found, "Expected at least one security listing across sample seeds")


func test_run_stats_export_contains_history() -> void:
	var state: RunState = _farm_state()
	RunStatsSystem.snapshot_turn(state, {"revenueTotal": 1000, "costTotal": 400, "profit": 600})
	var json_text: String = RunStatsSystem.export_json(state)
	assert_true(json_text.find("turnHistory") >= 0)
