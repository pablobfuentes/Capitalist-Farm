extends GutTest

const _Debrief := preload("res://core/systems/debrief_system.gd")


func before_all() -> void:
	Content.load_farm_content()


func _farm_state() -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)
	state.supply_shortage_ack_turn = state.turn
	return state


func _add_simple_business(state: RunState) -> void:
	var biz := BusinessInstance.new()
	biz.id = "biz-1"
	biz.template_id = "vegetable_farm"
	biz.name = "Test Vegetable Farm"
	biz.revenue_per_turn = 12000
	biz.operating_costs = 7000
	biz.layer = "production"
	state.portfolio.businesses.append(biz)


func test_snapshot_period_state_matches_run_rates() -> void:
	var state := _farm_state()
	_add_simple_business(state)
	var snap: Dictionary = _Debrief.snapshot_period_state(state)
	var rates: Dictionary = FinanceSystem.compute_quarterly_run_rates(state, false)
	assert_eq(int(snap.get("revenue", 0)), int(rates.get("revenueTotal", 0)))
	assert_eq(int(snap.get("profit", 0)), int(rates.get("profit", 0)))


func test_advance_sets_pending_debrief_with_profit() -> void:
	Game.state = _farm_state()
	_add_simple_business(Game.state)
	var cash_before: int = Game.state.cash
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_false(Game.state.pending_turn_debrief.is_empty())
	assert_false(Game.state.last_advance_report.is_empty())
	var profit: int = int(Game.state.last_advance_report.get("profitQuarterClosed", 0))
	assert_eq(Game.state.cash, cash_before + profit)
	assert_eq(int(Game.state.last_advance_report.get("cashDelta", 0)), profit)


func test_dismiss_turn_debrief_clears_pending() -> void:
	Game.state = _farm_state()
	_add_simple_business(Game.state)
	Game.apply_command(GameCommand.advance_turn())
	assert_false(Game.state.pending_turn_debrief.is_empty())
	var dismiss: Dictionary = Game.apply_command(GameCommand.dismiss_turn_debrief())
	assert_true(bool(dismiss.get("ok", false)))
	assert_true(Game.state.pending_turn_debrief.is_empty())


func test_build_turn_debrief_summary_mentions_cash_flow() -> void:
	var state := _farm_state()
	_add_simple_business(state)
	var before: Dictionary = _Debrief.snapshot_period_state(state)
	state.cash += 5000
	var after: Dictionary = _Debrief.snapshot_period_state(state)
	var report: Dictionary = _Debrief.build_turn_debrief(state, {
		"netCashFlow": 5000,
		"revenueTotal": int(after.get("revenue", 0)),
		"costTotal": int(after.get("costs", 0)),
		"debtService": int(after.get("debtService", 0)),
	}, {
		"beforeSnap": before,
		"afterSnap": after,
		"externalRevenue": 1200,
	})
	assert_true(str(report.get("summary", "")).contains("added"))
	var highlights: Array = report.get("highlights", [])
	var found_external := false
	for item in highlights:
		if str(item).contains("External/export"):
			found_external = true
			break
	assert_true(found_external, "Expected external revenue highlight")


func test_period_snapshot_initialized_on_new_run() -> void:
	var state := _farm_state()
	assert_false(state.period_snapshot.is_empty())
	assert_true(state.pending_turn_debrief.is_empty())
	assert_eq(state.turn_history.size(), 1)
