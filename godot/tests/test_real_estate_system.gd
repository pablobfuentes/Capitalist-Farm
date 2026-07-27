extends GutTest

const _RealEstate := preload("res://core/systems/real_estate_system.gd")


func before_all() -> void:
	Content.load_farm_content()
	_RealEstate.load_improvements()


func _farm_state() -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)
	return state


func _make_re_asset(template_id: String, asset_id: String = "re-1") -> Dictionary:
	var tmpl := Content.get_template(template_id)
	return {
		"id": asset_id,
		"templateId": template_id,
		"name": tmpl.name if tmpl else template_id,
		"rentPerTurn": 8000,
		"operatingExpenses": 2400,
		"vacancyRisk": 0.1,
		"valuation": 100000,
		"markedValue": 100000,
		"purchasePrice": 95000,
		"assetClass": "real_estate",
		"improvementsApplied": [],
	}


func _make_dairy_business() -> BusinessInstance:
	var biz := BusinessInstance.new()
	biz.id = "dairy-1"
	biz.template_id = "dairy_barn"
	biz.name = "Test Dairy"
	biz.revenue_per_turn = 15000
	biz.operating_costs = 9000
	biz.layer = "primary_production"
	return biz


func test_improvements_filtered_by_template() -> void:
	var delivery: Dictionary = _make_re_asset("delivery_cold_storage")
	var repair: Dictionary = _make_re_asset("equipment_repair", "re-2")
	var state := _farm_state()
	var delivery_ids: Array = []
	for imp_variant in _RealEstate.improvements_for_asset(state, delivery):
		delivery_ids.append(str((imp_variant as Dictionary).get("id", "")))
	assert_true("cold" in delivery_ids)
	assert_true("bay" in delivery_ids)
	assert_false("gate" in delivery_ids)
	var repair_ids: Array = []
	for imp_variant in _RealEstate.improvements_for_asset(state, repair):
		repair_ids.append(str((imp_variant as Dictionary).get("id", "")))
	assert_true("gate" in repair_ids)
	assert_false("cold" in repair_ids)


func test_apply_improvement_increases_valuation_and_rent() -> void:
	Game.state = _farm_state()
	var asset: Dictionary = _make_re_asset("equipment_repair")
	Game.state.portfolio.real_estate.append(asset)
	Game.state.action_points = 2
	Game.state.cash = 50000
	var result: Dictionary = Game.apply_command(GameCommand.improve_real_estate("re-1", "gate"))
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_gt(int(asset.get("valuation", 0)), 100000)
	assert_gt(int(asset.get("rentPerTurn", 0)), 8000)
	assert_eq(Game.state.action_points, 1)
	assert_true("gate" in (asset.get("improvementsApplied", []) as Array))


func test_improvement_cannot_be_applied_twice() -> void:
	Game.state = _farm_state()
	var asset: Dictionary = _make_re_asset("equipment_repair")
	Game.state.portfolio.real_estate.append(asset)
	Game.state.action_points = 3
	Game.state.cash = 100000
	assert_true(bool(Game.apply_command(GameCommand.improve_real_estate("re-1", "gate")).get("ok", false)))
	var second: Dictionary = Game.apply_command(GameCommand.improve_real_estate("re-1", "gate"))
	assert_false(bool(second.get("ok", false)))


func test_repair_shed_synergy_with_owned_dairy() -> void:
	var state := _farm_state()
	state.portfolio.businesses.append(_make_dairy_business())
	state.portfolio.real_estate.append(_make_re_asset("equipment_repair"))
	var synergies: Array = SynergySystem.compute_synergies(state)
	var found := false
	for syn_variant in synergies:
		if typeof(syn_variant) != TYPE_DICTIONARY:
			continue
		var syn: Dictionary = syn_variant
		if str(syn.get("supplierTemplateId", "")) == "equipment_repair" and str(syn.get("customerTemplateId", "")) == "dairy_barn":
			found = true
			break
	assert_true(found, "Expected equipment_repair → dairy_barn synergy")


func test_improvement_does_not_change_synergy_count() -> void:
	Game.state = _farm_state()
	Game.state.portfolio.businesses.append(_make_dairy_business())
	Game.state.portfolio.real_estate.append(_make_re_asset("equipment_repair"))
	var before: int = SynergySystem.compute_synergies(Game.state).size()
	Game.state.action_points = 2
	Game.state.cash = 50000
	Game.apply_command(GameCommand.improve_real_estate("re-1", "gate"))
	var after: int = SynergySystem.compute_synergies(Game.state).size()
	assert_eq(before, after)


func test_downstream_link_count() -> void:
	var state := _farm_state()
	state.portfolio.businesses.append(_make_dairy_business())
	assert_eq(_RealEstate.downstream_link_count(state, "equipment_repair"), 1)
