extends GutTest


func before_all() -> void:
	Content.load_farm_content()
	CommunityConfig.load_config()
	CommunityChainCatalog.load_catalog()
	CommunityRenegotiationTemplates.load_templates()
	CommunityFeatureFlags.reset_overrides()
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, true)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, true)


func after_all() -> void:
	CommunityFeatureFlags.reset_overrides()


func _community_state(seed_value: int) -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = seed_value
	RunBootstrap.prepare_new_run(state)
	ParcelOwnershipSystem.ensure_seeded(state, ParcelOwnershipSystem.load_district_for_state(state))
	CommunityGenerator.sync_parcel_assignments(state, "meadowgate_commons")
	return state


func _supplier_with_major_client(state: RunState) -> Dictionary:
	var district: Dictionary = state.community["districts"]["meadowgate_commons"]
	var edges: Array = district.get("supplyRelationships", [])
	for edge_variant in edges:
		var edge: Dictionary = edge_variant
		if float(edge.get("dependence", 0.0)) >= CommunityRenegotiationTemplates.major_client_dependence_min():
			var supplier_id := str(edge.get("supplierBusinessId", ""))
			var businesses: Dictionary = district.get("businesses", {})
			if businesses.has(supplier_id):
				return (businesses[supplier_id] as Dictionary).duplicate(true)
	return {}


func test_acquisition_transfers_supply_contracts() -> void:
	var state := _community_state(770011)
	var community_business: Dictionary = _supplier_with_major_client(state)
	assert_false(community_business.is_empty(), "fixture needs a major-client supply edge")
	var parcel_id := str(community_business.get("parcelId", ""))
	var opp_id := "opp_acquire_test"
	state.parcel_assignments[parcel_id] = {
		"owner": ParcelOwnershipSystem.OWNER_OPPORTUNITY,
		"business_id": "",
		"community_business_id": str(community_business.get("id", "")),
		"opportunity_id": opp_id,
		"npc_label": str(community_business.get("displayName", "")),
	}

	var player_biz := BusinessInstance.new()
	player_biz.id = "player_biz_test"
	player_biz.template_id = str(community_business.get("templateId", ""))
	player_biz.name = "Acquired Test Co"
	state.portfolio.businesses.append(player_biz)

	var result: Dictionary = CommunityAcquisitionService.on_player_business_acquired(
		state,
		player_biz,
		{
			"id": opp_id,
			"parcelId": parcel_id,
			"districtId": "meadowgate_commons",
			"templateId": player_biz.template_id,
		},
	)
	assert_true(bool(result.get("ok", false)))
	assert_gt(int(result.get("transferredContracts", 0)), 0)
	assert_true(CommunityAcquisitionService.player_business_link(state, player_biz.id).has("communityBusinessId"))

	var stored: Dictionary = CommunityGenerator.get_business(state, str(community_business.get("id", "")))
	assert_eq(str(stored.get("saleState", "")), "acquired_by_player")


func test_major_client_schedules_renegotiation() -> void:
	var state := _community_state(770022)
	var community_business: Dictionary = _supplier_with_major_client(state)
	assert_false(community_business.is_empty(), "fixture needs a major-client supply edge")
	var parcel_id := str(community_business.get("parcelId", ""))
	var player_biz := BusinessInstance.new()
	player_biz.id = "player_biz_reneg"
	player_biz.template_id = str(community_business.get("templateId", ""))
	player_biz.name = "Reneg Test Co"
	state.portfolio.businesses.append(player_biz)

	var result: Dictionary = CommunityAcquisitionService.on_player_business_acquired(
		state,
		player_biz,
		{
			"id": "opp_reneg",
			"parcelId": parcel_id,
			"districtId": "meadowgate_commons",
			"templateId": player_biz.template_id,
		},
	)
	assert_gt(int(result.get("scheduledRenegotiations", 0)), 0)
	var pending: Array = state.community.get("pendingClientRenegotiations", [])
	assert_gt(pending.size(), 0)


func test_renegotiation_fires_after_delay() -> void:
	var state := _community_state(770033)
	var community_business: Dictionary = _supplier_with_major_client(state)
	assert_false(community_business.is_empty(), "fixture needs a major-client supply edge")
	var player_biz := BusinessInstance.new()
	player_biz.id = "player_biz_fire"
	player_biz.template_id = str(community_business.get("templateId", ""))
	player_biz.name = "Fire Test Co"
	state.portfolio.businesses.append(player_biz)

	CommunityAcquisitionService.on_player_business_acquired(
		state,
		player_biz,
		{
			"id": "opp_fire",
			"parcelId": str(community_business.get("parcelId", "")),
			"districtId": "meadowgate_commons",
			"templateId": player_biz.template_id,
		},
	)

	var pending: Array = state.community.get("pendingClientRenegotiations", [])
	assert_gt(pending.size(), 0)
	var due_turn := int((pending[0] as Dictionary).get("dueTurn", 0))
	state.turn = due_turn
	var fired: Array = CommunityRenegotiationService.process_turn(state)
	assert_gt(fired.size(), 0)
	assert_gt(state.community.get("activeClientRenegotiations", []).size(), 0)
	assert_gt(CommunityState.notebook_entries_for(state, "chat").size(), 0)


func test_template_reflects_personal_relationship() -> void:
	CommunityRenegotiationTemplates.load_templates()
	var strained_good: Dictionary = CommunityRenegotiationTemplates.pick_template(0.45, 4)
	assert_eq(str(strained_good.get("id", "")), "strained_but_willing")
	var strained_bad: Dictionary = CommunityRenegotiationTemplates.pick_template(0.40, -4)
	assert_eq(str(strained_bad.get("id", "")), "strict_termination_ultimatum")
