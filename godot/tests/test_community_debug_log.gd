extends GutTest


func before_all() -> void:
	Content.load_farm_content()
	CommunityConfig.load_config()
	CommunityFeatureFlags.reset_overrides()


func after_each() -> void:
	CommunityFeatureFlags.reset_overrides()


func test_debug_log_formats_generated_district() -> void:
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, true)
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)

	var body := CommunityDebugLogService.format_mental_map(state)
	assert_true(body.contains("COMMUNITY MENTAL MAP"))
	assert_true(body.contains("SUPPLY WEB"))
	assert_true(body.contains("ALL BUSINESSES"))
	assert_true(body.contains("OPERATIONAL FACTS"))

	var district: Dictionary = state.community.get("districts", {}).get(CommunityConfig.mvp_district_id(), {})
	var business_count := int((district.get("businesses", {}) as Dictionary).size())
	assert_true(body.contains("Businesses:   %d" % business_count))

	var write_result: Dictionary = CommunityDebugLogService.write_from_state(state)
	assert_true(bool(write_result.get("ok", false)))
	assert_true(CommunityDebugLogService.has_log())
	var saved := CommunityDebugLogService.read_latest()
	assert_eq(saved, body)
