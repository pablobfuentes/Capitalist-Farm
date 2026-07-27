extends GutTest

const _World := preload("res://scenes/farm_map/world_layout_data.gd")


func before_all() -> void:
	Content.load_farm_content()


func test_region_loads_six_districts() -> void:
	var region: Dictionary = _World.load_region()
	assert_eq(_World.district_entries(region).size(), 6)


func test_starter_district_unlocked_only() -> void:
	var state: RunState = RunState.create_new(RunState.FARM_2D_MODE)
	DistrictUnlockSystem.ensure_initialized(state)
	assert_true(DistrictUnlockSystem.is_unlocked(state, "meadowgate_commons"))
	assert_false(DistrictUnlockSystem.is_unlocked(state, "northfield_heights"))


func test_unlock_all_dev_bypass() -> void:
	var state: RunState = RunState.create_new(RunState.FARM_2D_MODE)
	DistrictUnlockSystem.ensure_initialized(state)
	DistrictUnlockSystem.unlock_all_for_testing(state)
	assert_true(DistrictUnlockSystem.is_unlocked(state, "highland_terrace"))


func test_auto_unlock_by_net_worth() -> void:
	var state: RunState = RunState.create_new(RunState.FARM_2D_MODE)
	DistrictUnlockSystem.ensure_initialized(state)
	state.cash = 200000
	DistrictUnlockSystem.refresh_auto_unlocks(state)
	assert_true(DistrictUnlockSystem.is_unlocked(state, "northfield_heights"))
