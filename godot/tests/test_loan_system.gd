extends GutTest

const _Debrief := preload("res://core/systems/debrief_system.gd")


func before_all() -> void:
	Content.load_farm_content()


func _state_with_loan_opp() -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.opportunities = [{
		"id": "loan-1",
		"kind": "financing",
		"assetType": "loan",
		"name": "Bank Line of Credit Offer",
		"maxAmount": 50000,
		"rate": 0.06,
		"termTurns": 10,
	}]
	return state


func test_compute_loan_terms_matches_mvp_shape() -> void:
	var terms: Dictionary = LoanSystem.compute_loan_terms(50000, 0.06, 10)
	assert_eq(int(terms.get("term", 0)), 10)
	assert_almost_eq(float(terms.get("principalPerTurn", 0.0)), 5000.0, 0.01)
	assert_almost_eq(float(terms.get("paymentPerTurn", 0.0)), 8000.0, 0.01)
	assert_eq(int(terms.get("totalReturn", 0)), 80000)


func test_take_loan_adds_cash_and_removes_opportunity() -> void:
	Game.state = _state_with_loan_opp()
	var cash_before: int = Game.state.cash
	var ap_before: int = Game.state.action_points

	var result: Dictionary = Game.apply_command(GameCommand.take_loan("loan-1"))
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_eq(Game.state.cash, cash_before + 50000)
	assert_eq(Game.state.action_points, ap_before - 1)
	assert_eq(Game.state.loans.size(), 1)
	assert_eq(Game.state.opportunities.size(), 0)

	var loan: Dictionary = Game.state.loans[0]
	assert_eq(int(loan.get("principal", 0)), 50000)
	assert_eq(int(loan.get("turnsRemaining", 0)), 10)
	assert_eq(LoanSystem.total_debt(Game.state), 50000)


func test_debt_service_reduces_profit() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.loans = [{
		"id": "l1",
		"label": "Bank Line of Credit",
		"principal": 50000,
		"rate": 0.06,
		"principalPerTurn": 5000.0,
		"paymentPerTurn": 8000,
		"turnsRemaining": 10,
	}]
	var rates: Dictionary = FinanceSystem.compute_quarterly_run_rates(state, false)
	assert_eq(int(rates.get("debtService", 0)), 8000)


func test_amortize_loans_after_advance() -> void:
	Game.state = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	Game.state.loans = [{
		"id": "l1",
		"label": "Bank Line of Credit",
		"principal": 50000,
		"rate": 0.06,
		"principalPerTurn": 5000.0,
		"paymentPerTurn": 8000,
		"turnsRemaining": 10,
	}]
	Game.state.supply_shortage_ack_turn = Game.state.turn

	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_eq(Game.state.loans.size(), 1)
	var loan: Dictionary = Game.state.loans[0]
	assert_eq(int(loan.get("turnsRemaining", 0)), 9)
	assert_eq(int(loan.get("principal", 0)), 45000)


func test_payoff_loan_removes_debt() -> void:
	Game.state = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	Game.state.cash = 60000
	Game.state.loans = [{
		"id": "l1",
		"label": "Bank Line of Credit",
		"principal": 40000,
		"rate": 0.06,
		"principalPerTurn": 4000.0,
		"paymentPerTurn": 6400,
		"turnsRemaining": 8,
	}]

	var result: Dictionary = Game.apply_command(GameCommand.payoff_loan("l1"))
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_eq(Game.state.loans.size(), 0)
	assert_eq(Game.state.cash, 20000)
	assert_eq(LoanSystem.total_debt(Game.state), 0)


func test_net_worth_subtracts_loan_principal() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.cash = 100000
	state.loans = [{"id": "l1", "principal": 30000}]
	assert_eq(FinanceSystem.net_worth(state), 70000)


func test_financing_opportunity_can_roll() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = 424242
	var found := false
	for turn in range(1, 40):
		state.turn = turn
		OpportunitySystem.refresh_opportunities(state)
		for opp_variant in state.opportunities:
			if typeof(opp_variant) == TYPE_DICTIONARY and str((opp_variant as Dictionary).get("assetType", "")) == "loan":
				found = true
				break
		if found:
			break
	assert_true(found, "Expected at least one financing opportunity in seeded rolls")


func test_financing_injected_when_cash_low_by_turn_4() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)
	state.turn = 3
	state.cash = 8000
	state.starter_deal_offered = true
	state.opportunities.clear()
	OpportunitySystem.advance_opportunities(state)
	var found := false
	for opp_variant in state.opportunities:
		if typeof(opp_variant) == TYPE_DICTIONARY and str((opp_variant as Dictionary).get("assetType", "")) == "loan":
			found = true
			break
	assert_true(found, "Expected injected financing offer when cash is low early in the run")


func test_take_loan_records_taken_turn() -> void:
	Game.state = _state_with_loan_opp()
	Game.apply_command(GameCommand.take_loan("loan-1"))
	assert_eq(int(Game.state.loans[0].get("takenTurn", -1)), Game.state.turn)


func test_turn_history_debt_reflects_loan_after_advance() -> void:
	Game.state = _state_with_loan_opp()
	Game.state.supply_shortage_ack_turn = Game.state.turn
	Game.apply_command(GameCommand.take_loan("loan-1"))
	Game.apply_command(GameCommand.advance_turn())
	var last: Dictionary = Game.state.turn_history[Game.state.turn_history.size() - 1]
	assert_gt(int(last.get("debt", 0)), 0)


func test_debrief_highlights_debt_service_and_new_loan() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.turn = 2
	state.loans = [{
		"id": "l1",
		"label": "Bank Line of Credit",
		"principal": 50000,
		"rate": 0.06,
		"paymentPerTurn": 8000,
		"turnsRemaining": 10,
		"takenTurn": 2,
	}]
	var report: Dictionary = _Debrief.build_turn_debrief(state, {
		"netCashFlow": -2000,
		"revenueTotal": 10000,
		"costTotal": 7000,
		"debtService": 8000,
	}, {
		"beforeSnap": _Debrief.snapshot_period_state(state),
		"afterSnap": _Debrief.snapshot_period_state(state),
	})
	var debt_found := false
	var loan_found := false
	for item in report.get("highlights", []):
		var text := str(item)
		if text.contains("Debt service"):
			debt_found = true
		if text.contains("New credit line"):
			loan_found = true
	assert_true(debt_found)
	assert_true(loan_found)


func test_format_opportunity_and_portfolio_lines() -> void:
	var opp: Dictionary = {
		"name": "Bank Line of Credit Offer",
		"maxAmount": 50000,
		"rate": 0.06,
		"termTurns": 10,
		"expiresIn": 2,
		"blurb": "Bank credit arranged in advance.",
	}
	assert_true(LoanSystem.format_opportunity_line(opp).contains("Receive"))
	var loan: Dictionary = {
		"label": "Bank Line of Credit",
		"principal": 40000,
		"rate": 0.06,
		"paymentPerTurn": 6400,
		"turnsRemaining": 8,
	}
	assert_true(LoanSystem.format_portfolio_line(loan).contains("saves"))
