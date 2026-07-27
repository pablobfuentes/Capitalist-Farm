extends GutTest


func before_all() -> void:
	Content.load_farm_content()


func test_save_load_roundtrip_preserves_net_worth() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	OpportunitySystem.refresh_opportunities(state)
	var nw_before: int = FinanceSystem.net_worth(state)
	var cash_before: int = state.cash
	var turn_before: int = state.turn
	var opp_count: int = state.opportunities.size()

	var saved: Dictionary = state.to_dict()
	var loaded: RunState = RunState.from_dict(saved)

	assert_eq(FinanceSystem.net_worth(loaded), nw_before)
	assert_eq(loaded.cash, cash_before)
	assert_eq(loaded.turn, turn_before)
	assert_eq(loaded.opportunities.size(), opp_count)


func test_acquire_business_reduces_cash_and_adds_to_portfolio() -> void:
	Game.state = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	OpportunitySystem.refresh_opportunities(Game.state)
	assert_gt(Game.state.opportunities.size(), 0)

	var opp: Dictionary = Game.state.opportunities[0]
	var opp_id: String = str(opp.get("id", ""))
	var price: int = int(opp.get("price", 0))
	Game.state.cash = price + 5000

	var result: Dictionary = Game.apply_command(GameCommand.acquire_business(opp_id))
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_eq(Game.state.portfolio.businesses.size(), 1)
	assert_eq(Game.state.cash, 5000)


func test_set_supply_policy_persists_in_save() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	Game.state = state
	var result: Dictionary = Game.apply_command(
		GameCommand.set_supply_policy("grain_farm", "balanced")
	)
	assert_true(bool(result.get("ok", false)))
	assert_eq(str(Game.state.supply_policies.get("grain_farm", "")), "balanced")

	var reloaded: RunState = RunState.from_dict(Game.state.to_dict())
	assert_eq(str(reloaded.supply_policies.get("grain_farm", "")), "balanced")
