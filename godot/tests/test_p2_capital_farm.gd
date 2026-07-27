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
	biz.marked_value = 80000
	state.portfolio.businesses.append(biz)
	UpgradeSystem.ensure_business_upgrades(biz)
	return biz


func test_urgent_unresolved_rep_penalty_on_advance() -> void:
	var state: RunState = _farm_state()
	_add_business(state, "grain_farm")
	state.reputation = 14
	state.urgent_problems = [{
		"id": "urgent-1",
		"type": "client",
		"businessId": "biz-1",
		"text": "Client issue",
	}]
	var result: Dictionary = CommandProcessor.apply(state, GameCommand.advance_turn())
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	var next: RunState = result.get("state")
	assert_eq(next.reputation, 12, "Each unresolved urgent should cost 2 reputation")


func test_milestone_triggers_edge_choice_state() -> void:
	var state: RunState = _farm_state(5555)
	state.cash = 60000
	state.reputation = 20
	_add_business(state, "vegetable_farm")
	var result: Dictionary = CommandProcessor.apply(state, GameCommand.advance_turn())
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	var next: RunState = result.get("state")
	assert_eq(next.milestone_stage, "local_investor")
	assert_true(next.milestones_hit.has("local_investor"))
	assert_gt(next.edge_choices_pending.size(), 0, "Milestone should offer strategic edge choices")


func test_level_up_opportunity_when_business_eligible() -> void:
	var state: RunState = _farm_state()
	var biz := _add_business(state, "bakery")
	biz.upgrades = {"hire": 2, "marketing": 2, "automation": 2, "care": 2, "manager": false}
	UpgradeSystem.recompute_upgrade_stats(biz)
	assert_true(UpgradeSystem.is_eligible_for_major_upgrade(biz))
	var opps: Array = LevelUpSystem.generate_level_up_opportunities(state)
	assert_gt(opps.size(), 0, "Eligible matured business should get a level-up listing")
	var found := false
	for opp_variant in opps:
		if typeof(opp_variant) == TYPE_DICTIONARY:
			var opp: Dictionary = opp_variant
			if str(opp.get("assetType", "")) == "levelup" and str(opp.get("businessId", "")) == biz.id:
				found = true
				break
	assert_true(found)
