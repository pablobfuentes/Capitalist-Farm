extends GutTest


func before_all() -> void:
	Content.load_farm_content()


func _grain_biz() -> BusinessInstance:
	var b := BusinessInstance.new()
	b.id = "g1"
	b.template_id = "grain_farm"
	b.name = "Test Grain"
	b.revenue_per_turn = 15000
	b.operating_costs = 9000
	b.upgrades = UpgradeSystem.default_upgrades()
	return b


func _arcade_state() -> RunState:
	var s := RunState.create_new(RunState.CAPITAL_FARM_MODE)
	s.farm_upgrade_v2 = true
	return s


func test_upgrades_active_in_capital_farm() -> void:
	assert_true(UpgradeSystem.is_active(_arcade_state()))
	var sim := RunState.create_new("simulator")
	assert_false(UpgradeSystem.is_active(sim))


func test_hire_tiers_increase_capacity_mult() -> void:
	var b := _grain_biz()
	UpgradeSystem.ensure_business_upgrades(b)
	assert_eq(float(b.upgrade_stats.get("capacityMult", 0.0)), 1.0)
	b.upgrades["hire"] = 3
	UpgradeSystem.recompute_upgrade_stats(b)
	assert_almost_eq(float(b.upgrade_stats.get("capacityMult", 0.0)), 1.24, 0.001)


func test_manager_bundle_mult() -> void:
	var b := _grain_biz()
	b.upgrades["hire"] = 3
	b.upgrades["manager"] = true
	UpgradeSystem.recompute_upgrade_stats(b)
	assert_almost_eq(float(b.upgrade_stats.get("capacityMult", 0.0)), 1.24 * 1.03, 0.01)


func test_compute_upgrade_preview_does_not_mutate_upgrades() -> void:
	var state := _arcade_state()
	var b := _grain_biz()
	state.portfolio.businesses.append(b)
	var before: Dictionary = b.upgrades.duplicate(true)
	for track_id: String in ["hire", "marketing", "automation", "care", "manager"]:
		UpgradeSystem.compute_upgrade_preview(state, b.id, track_id)
	assert_eq(int(b.upgrades.get("hire", 0)), int(before.get("hire", 0)))
	assert_eq(int(b.upgrades.get("marketing", 0)), int(before.get("marketing", 0)))
	assert_eq(int(b.upgrades.get("automation", 0)), int(before.get("automation", 0)))
	assert_eq(int(b.upgrades.get("care", 0)), int(before.get("care", 0)))
	assert_eq(bool(b.upgrades.get("manager", false)), bool(before.get("manager", false)))


func test_apply_upgrade_command_spends_cash() -> void:
	var state := _arcade_state()
	var b := _grain_biz()
	b.marked_value = 80000
	state.portfolio.businesses.append(b)
	state.cash = 100000
	var cost: int = UpgradeSystem.business_improve_cost(b, "hire", state)
	assert_gt(cost, 0)
	var result: Dictionary = UpgradeSystem.apply_upgrade_command(state, b.id, "hire")
	assert_true(bool(result.get("ok", false)))
	assert_eq(int(b.upgrades.get("hire", 0)), 1)
	assert_eq(state.cash, 100000 - cost)


func test_synergy_capacity_respects_hire_upgrade() -> void:
	var state := _arcade_state()
	var grain := _grain_biz()
	grain.upgrades["hire"] = 3
	UpgradeSystem.ensure_business_upgrades(grain)
	var bakery := BusinessInstance.new()
	bakery.id = "b1"
	bakery.template_id = "bakery"
	bakery.name = "Bakery"
	bakery.revenue_per_turn = 28000
	bakery.operating_costs = 22400
	bakery.upgrades = UpgradeSystem.default_upgrades()
	state.portfolio.businesses.append(grain)
	state.portfolio.businesses.append(bakery)
	var cap_base: int = int(SynergySystem._effective_capacity(state, "grain_farm"))
	assert_gt(cap_base, 75)
