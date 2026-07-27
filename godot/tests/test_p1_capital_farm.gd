extends GutTest


func before_all() -> void:
	Content.load_farm_content()
	NegotiationArchetypes.ensure_loaded()


func _farm_state(seed: int = 4242) -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = seed
	state.supply_shortage_ack_turn = state.turn
	return state


func _add_business(state: RunState, template_id: String, id: String = "biz-1") -> BusinessInstance:
	var tmpl := Content.get_template(template_id)
	var biz := BusinessInstance.create_from_template(template_id, tmpl.name if tmpl else template_id, 20000, 12000)
	biz.id = id
	biz.acquired_turn = state.turn
	biz.last_care_turn = state.turn
	state.portfolio.businesses.append(biz)
	return biz


func test_chain_hint_when_portfolio_has_gap() -> void:
	var state: RunState = _farm_state(9001)
	_add_business(state, "grain_farm")
	state.turn = 2
	state.last_chain_hint_turn = 0
	var batch: Array = OpportunitySystem._generate_fresh_batch(state, false)
	var found := false
	for opp_variant in batch:
		if typeof(opp_variant) == TYPE_DICTIONARY and bool((opp_variant as Dictionary).get("chainHintDeal", false)):
			found = true
			break
	assert_true(found, "Expected chain-hint listing when portfolio has supply gap")
	assert_true(SynergySystem.has_critical_chain_gap(state))


func test_external_revenue_with_spare_capacity() -> void:
	var state: RunState = _farm_state()
	_add_business(state, "grain_farm")
	var rates: Dictionary = FinanceSystem.compute_quarterly_run_rates(state, false)
	var export_total: int = int(rates.get("externalRevenueTotal", 0))
	assert_gt(export_total, 0, "Spare upstream capacity should produce export revenue")
	var risk: Dictionary = SynergySystem.portfolio_risk_summary(state)
	assert_eq(int(risk.get("externalRevenueTotal", 0)), export_total)


func test_sell_business_updates_cash_and_net_worth() -> void:
	var state: RunState = _farm_state()
	var biz := _add_business(state, "vegetable_farm", "veg-1")
	biz.marked_value = 50000
	var cash_before: int = state.cash
	var result: Dictionary = PortfolioSystem.sell_asset(state, "business", "veg-1")
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_eq(state.cash, cash_before + int(result.get("proceeds", 0)))
	assert_eq(state.portfolio.businesses.size(), 0)
	assert_gt(int(result.get("proceeds", 0)), 40000)


func test_real_estate_opportunity_roll_produces_listing() -> void:
	var state: RunState = _farm_state(777)
	state.turn = 4
	var found_re := false
	for _i in 20:
		var batch: Array = OpportunitySystem._generate_fresh_batch(state, false)
		for opp_variant in batch:
			if typeof(opp_variant) == TYPE_DICTIONARY and str((opp_variant as Dictionary).get("assetType", "")) == "realestate":
				found_re = true
				break
		if found_re:
			break
	assert_true(found_re, "Expected at least one real estate listing in roll sample")
