extends GutTest

const _LevelUp := preload("res://core/systems/level_up_system.gd")


func before_all() -> void:
	Content.load_farm_content()


func _farm_state() -> RunState:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	state.farm_upgrade_v2 = true
	return state


func _biz_with_upgrades(hire: int = 0, marketing: int = 0, automation: int = 0, care: int = 0, manager: bool = false) -> BusinessInstance:
	var biz := BusinessInstance.create_from_template("grain_farm", "Test Farm", 12000, 7000)
	biz.id = "biz-test"
	biz.level = 1
	biz.upgrades = {
		"hire": hire,
		"marketing": marketing,
		"automation": automation,
		"care": care,
		"manager": manager,
	}
	biz.marked_value = 80000
	return biz


func test_level_one_requires_four_improvements() -> void:
	var biz := _biz_with_upgrades(1, 1, 1, 0)
	assert_false(_LevelUp.is_eligible_for_level_up(biz))
	biz.upgrades["care"] = 1
	assert_true(_LevelUp.is_eligible_for_level_up(biz))


func test_level_two_requires_ten_improvements() -> void:
	var biz := _biz_with_upgrades(3, 3, 3, 0)
	biz.level = 2
	assert_false(_LevelUp.is_eligible_for_level_up(biz))
	biz.upgrades["care"] = 3
	biz.upgrades["manager"] = true
	assert_true(_LevelUp.is_eligible_for_level_up(biz))


func test_level_three_never_eligible() -> void:
	var biz := _biz_with_upgrades(3, 3, 3, 3, true)
	biz.level = 3
	assert_false(_LevelUp.is_eligible_for_level_up(biz))


func test_apply_level_up_keeps_upgrades_and_steps_revenue() -> void:
	var state := _farm_state()
	var biz := _biz_with_upgrades(2, 2, 2, 2, true)
	state.portfolio.businesses.append(biz)
	var rev_before: int = biz.revenue_per_turn
	var tmpl: Dictionary = _LevelUp.LEVEL_UP_TEMPLATES[0].duplicate(true)
	_LevelUp.apply_level_up_effects(biz, tmpl, state)
	assert_eq(biz.level, 2)
	assert_gt(biz.revenue_per_turn, rev_before)
	assert_eq(int(biz.upgrades.get("hire", 0)), 2)
	assert_true(bool(biz.upgrades.get("manager", false)))


func test_ensure_opportunity_spawns_when_eligible() -> void:
	var state := _farm_state()
	var biz := _biz_with_upgrades(1, 1, 1, 1)
	state.portfolio.businesses.append(biz)
	var opp: Dictionary = _LevelUp.ensure_opportunity_for_business(state, biz.id)
	assert_false(opp.is_empty())
	assert_eq(str(opp.get("assetType", "")), "levelup")
	assert_eq(str(opp.get("businessId", "")), biz.id)
	assert_eq(state.opportunities.size(), 1)


func test_level_one_level_up_is_direct_buy() -> void:
	var state := _farm_state()
	var biz := _biz_with_upgrades(1, 1, 1, 1)
	state.portfolio.businesses.append(biz)
	var opp: Dictionary = _LevelUp.ensure_opportunity_for_business(state, biz.id)
	assert_false(bool(opp.get("requiresNegotiation", true)))
	assert_true(int(opp.get("price", 0)) > 0)


func test_do_level_up_spends_cash_and_advances_level() -> void:
	var state := _farm_state()
	var biz := _biz_with_upgrades(1, 1, 1, 1)
	state.portfolio.businesses.append(biz)
	state.cash = 200000
	state.action_points = 2
	var opp: Dictionary = _LevelUp.ensure_opportunity_for_business(state, biz.id)
	var result: Dictionary = _LevelUp.do_level_up(state, str(opp.get("id", "")))
	assert_true(bool(result.get("ok", false)))
	assert_eq(biz.level, 2)
	assert_eq(state.action_points, 1)
