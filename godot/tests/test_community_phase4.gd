extends GutTest

const _V2Profile := preload("res://core/systems/negotiation_v2_profile.gd")


func before_all() -> void:
	Content.load_farm_content()
	CommunityConfig.load_config()
	CommunityChainCatalog.load_catalog()
	CommunitySocialEffects.load_effects()
	CommunityFeatureFlags.reset_overrides()
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, true)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_NEGOTIATION_PERSONAL_RELATIONSHIP, true)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, true)


func after_all() -> void:
	CommunityFeatureFlags.reset_overrides()


func _community_state(seed_value: int) -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = seed_value
	state.reputation = 12
	RunBootstrap.prepare_new_run(state)
	return state


func test_neutral_personal_relationship_contributes_zero_gauge() -> void:
	var state := _community_state(660011)
	var business: Dictionary = _first_business(state)
	var npc_id := str(business.get("ownerNpcId", ""))
	var cp := {
		"speciesId": "sheep",
		"businessSituation": "stable_position",
		"leverageScore": 0.5,
		"communityNpcId": npc_id,
		"relationshipMemory": {},
	}
	var rng := SeededRng.new(101)
	var profile: Dictionary = _V2Profile.build(50000, cp, state, {}, rng)
	assert_eq(int(profile.get("personalRelationshipGaugeAdj", -1)), 0)
	assert_eq(int(profile.get("gaugeStart", -1)), 50)


func test_trusted_sheep_relationship_boosts_starting_gauge() -> void:
	var state := _community_state(660022)
	var business: Dictionary = _first_business(state)
	var npc_id := str(business.get("ownerNpcId", ""))
	var social: Dictionary = CommunityState.get_social_state(state, npc_id)
	social["personalRelationshipScore"] = 5
	CommunityState.set_social_state(state, npc_id, social)

	var cp := {
		"speciesId": "sheep",
		"businessSituation": "stable_position",
		"leverageScore": 0.5,
		"communityNpcId": npc_id,
		"relationshipMemory": {},
	}
	var profile: Dictionary = _V2Profile.build(50000, cp, state, {}, SeededRng.new(202))
	assert_eq(int(profile.get("personalRelationshipGaugeAdj", 0)), 20)
	assert_eq(int(profile.get("gaugeStart", 0)), 70)
	assert_eq(str(profile.get("personalRelationshipLabel", "")), "Trusted")


func test_chat_intel_increases_leverage_score() -> void:
	var state := _community_state(660033)
	var business: Dictionary = _first_business(state)
	var npc_id := str(business.get("ownerNpcId", ""))
	CommunityState.add_notebook_entry(state, {
		"source": "chat",
		"category": "leverage",
		"displaySummary": "Supplier is overextended",
		"relatedNpcId": npc_id,
		"confirmationState": "confirmed",
		"discoveryTurn": state.turn,
	})

	var cp := {"leverageScore": 0.5, "communityNpcId": npc_id}
	var opp := {"id": "opp_test", "templateId": str(business.get("templateId", ""))}
	var score := CommunityNegotiationBridge.leverage_score_from_intel(state, opp, cp)
	assert_gt(score, 0.5)


func test_resolve_community_npc_from_parcel_assignment() -> void:
	var state := _community_state(660044)
	ParcelOwnershipSystem.ensure_seeded(state, ParcelOwnershipSystem.load_district_for_state(state))
	CommunityGenerator.sync_parcel_assignments(state, "meadowgate_commons")
	var business: Dictionary = _first_business(state)
	var parcel_id := str(business.get("parcelId", ""))
	var opp_id := "opp_bridge_test"
	state.parcel_assignments[parcel_id] = {
		"owner": ParcelOwnershipSystem.OWNER_OPPORTUNITY,
		"business_id": "",
		"opportunity_id": opp_id,
		"npc_label": str(business.get("displayName", "")),
	}
	var opp := {
		"id": opp_id,
		"districtId": "meadowgate_commons",
		"templateId": str(business.get("templateId", "")),
	}
	var npc_id := CommunityNegotiationBridge.resolve_community_npc_id(state, opp)
	assert_eq(npc_id, str(business.get("ownerNpcId", "")))


func test_modifier_snapshot_lists_personal_relationship() -> void:
	var state := _community_state(660055)
	var business: Dictionary = _first_business(state)
	var npc: Dictionary = CommunityGenerator.get_npc(state, str(business.get("ownerNpcId", "")))
	var cp := {
		"communityNpcId": str(business.get("ownerNpcId", "")),
		"speciesId": str(npc.get("speciesId", "sheep")),
		"leverageScore": 0.5,
	}
	var profile: Dictionary = _V2Profile.build(50000, cp, state, {}, SeededRng.new(303))
	var snapshot := CommunityNegotiationBridge.format_modifier_snapshot(state, profile, cp)
	assert_true(snapshot.contains("Personal relationship"))
	assert_true(snapshot.contains("Starting gauge"))


func _first_business(state: RunState) -> Dictionary:
	var district: Dictionary = state.community["districts"]["meadowgate_commons"]
	var businesses: Dictionary = district.get("businesses", {})
	assert_gt(businesses.size(), 0)
	return (businesses.values()[0] as Dictionary).duplicate(true)
