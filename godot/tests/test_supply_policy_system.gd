extends GutTest

const _SupplyPolicy := preload("res://core/systems/supply_policy_system.gd")


func before_all() -> void:
	Content.load_farm_content()


func test_default_policy_is_portfolio_first() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	assert_eq(_SupplyPolicy.get_policy(state, "grain_farm"), "portfolio_first")


func test_set_policy_persists_and_logs() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	_SupplyPolicy.set_policy(state, "grain_farm", "balanced")
	assert_eq(_SupplyPolicy.get_policy(state, "grain_farm"), "balanced")
	assert_gt(state.run_log.size(), 0)


func test_advance_succeeds_without_shortage() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	var result: Dictionary = CommandProcessor.apply(state, GameCommand.advance_turn())
	assert_true(bool(result.get("ok", false)))


func test_confirm_shortage_ack_sets_turn() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	state.turn = 4
	_SupplyPolicy.confirm_shortage_ack(state)
	assert_eq(state.supply_shortage_ack_turn, 4)


func test_upgrade_preview_includes_capacity_for_hire() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	OpportunitySystem.refresh_opportunities(state)
	var acquire: Dictionary = AcquisitionSystem.acquire_business(state, str(state.opportunities[0].get("id", "")))
	assert_true(bool(acquire.get("ok", false)))
	var biz: BusinessInstance = state.portfolio.businesses[0]
	var preview: Dictionary = UpgradeSystem.compute_upgrade_preview(state, biz.id, "hire")
	if bool(preview.get("canApply", false)):
		assert_not_null(preview.get("capacityBefore"))
		assert_not_null(preview.get("capacityAfter"))
