extends GutTest


func before_all() -> void:
	Content.load_farm_content()
	CommunityConfig.load_config()
	CommunityChainCatalog.load_catalog()
	CommunityFeatureFlags.reset_overrides()
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, true)


func after_all() -> void:
	CommunityFeatureFlags.reset_overrides()


func _generated_state(seed_value: int) -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = seed_value
	RunBootstrap.prepare_new_run(state)
	return state


func test_meadowgate_generates_twenty_businesses() -> void:
	var state := _generated_state(120045)
	var district: Dictionary = state.community.get("districts", {}).get("meadowgate_commons", {})
	assert_true(bool(district.get("generated", false)))
	var businesses: Dictionary = district.get("businesses", {})
	assert_eq(businesses.size(), 20)


func test_meadowgate_meets_connected_business_minimum() -> void:
	var state := _generated_state(120045)
	var report: Dictionary = CommunityGenerator.diagnostics_report(state, "meadowgate_commons")
	var validation: Dictionary = report.get("validation", {})
	assert_true(bool(validation.get("valid", false)), str(validation.get("errors", [])))
	assert_gte(int(validation.get("connectedBusinessCount", 0)), 15)


func test_generation_is_deterministic_for_fixed_seed() -> void:
	var state_a := _generated_state(777001)
	var state_b := _generated_state(777001)
	var district_a: Dictionary = state_a.community["districts"]["meadowgate_commons"]
	var district_b: Dictionary = state_b.community["districts"]["meadowgate_commons"]
	assert_eq(district_a.get("businesses", {}).keys(), district_b.get("businesses", {}).keys())
	assert_eq(district_a.get("supplyRelationships", []), district_b.get("supplyRelationships", []))


func test_one_npc_and_operational_fact_per_supply_edge() -> void:
	var state := _generated_state(909090)
	var district: Dictionary = state.community["districts"]["meadowgate_commons"]
	var businesses: Dictionary = district.get("businesses", {})
	var edges: Array = district.get("supplyRelationships", [])
	assert_gte(edges.size(), 1)
	assert_eq(state.community.get("npcs", {}).size(), businesses.size())
	var facts: Dictionary = state.community.get("facts", {})
	assert_gte(facts.size(), edges.size())
	for edge_variant in edges:
		var edge: Dictionary = edge_variant
		var supplier_id := str(edge.get("supplierBusinessId", ""))
		var supplier: Dictionary = businesses.get(supplier_id, {})
		assert_false(str(supplier.get("ownerNpcId", "")).is_empty())


func test_seed_replay_batch_all_valid_for_sample_seeds() -> void:
	var seeds: Array = []
	for i in 50:
		seeds.append(1000 + i * 7919)
	var reports: Array = CommunityGenerator.seed_replay_batch(seeds, "meadowgate_commons")
	assert_eq(reports.size(), seeds.size())
	for report_variant in reports:
		var report: Dictionary = report_variant
		assert_true(bool(report.get("generationOk", false)), "seed %s failed: %s" % [
			report.get("seed", "?"),
			str(report.get("validation", {}).get("errors", [])),
		])
		var validation: Dictionary = report.get("validation", {})
		assert_gte(int(validation.get("connectedBusinessCount", 0)), 15)


func test_generation_skipped_when_feature_disabled() -> void:
	CommunityFeatureFlags.reset_overrides()
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = 555
	RunBootstrap.prepare_new_run(state)
	var districts: Dictionary = state.community.get("districts", {})
	assert_true(districts.is_empty() or not bool(districts.get("meadowgate_commons", {}).get("generated", false)))
