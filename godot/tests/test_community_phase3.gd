extends GutTest


func before_all() -> void:
	Content.load_farm_content()
	CommunityConfig.load_config()
	CommunityChainCatalog.load_catalog()
	CommunitySocialEffects.load_effects()
	CommunityFeatureFlags.reset_overrides()
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, true)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_CHAT, true)
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


func _first_community_business(state: RunState) -> Dictionary:
	var district: Dictionary = state.community["districts"]["meadowgate_commons"]
	var businesses: Dictionary = district.get("businesses", {})
	assert_gt(businesses.size(), 0)
	return (businesses.values()[0] as Dictionary).duplicate(true)


func test_sync_parcel_assignments_links_community_businesses() -> void:
	var state := _community_state(550011)
	var business: Dictionary = _first_community_business(state)
	var parcel_id := str(business.get("parcelId", ""))
	assert_false(parcel_id.is_empty())
	var assignment: Dictionary = state.parcel_assignments.get(parcel_id, {})
	assert_eq(str(assignment.get("community_business_id", "")), str(business.get("id", "")))


func test_get_business_for_parcel_roundtrip() -> void:
	var state := _community_state(550022)
	var business: Dictionary = _first_community_business(state)
	var found: Dictionary = CommunityGenerator.get_business_for_parcel(
		state,
		str(business.get("parcelId", "")),
		"meadowgate_commons",
	)
	assert_eq(str(found.get("id", "")), str(business.get("id", "")))


func test_can_open_chat_blocks_when_feature_disabled() -> void:
	var state := _community_state(550033)
	var business: Dictionary = _first_community_business(state)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_CHAT, false)
	var gate: Dictionary = CommunityChatRuntime.can_open_chat(state, business)
	assert_false(bool(gate.get("allowed", true)))


func test_can_open_chat_blocks_under_negotiation_and_available() -> void:
	var state := _community_state(550044)
	var business: Dictionary = _first_community_business(state).duplicate(true)
	business["saleState"] = "under_negotiation"
	var blocked: Dictionary = CommunityChatRuntime.can_open_chat(state, business)
	assert_false(bool(blocked.get("allowed", true)))

	business["saleState"] = "available"
	var listed: Dictionary = CommunityChatRuntime.can_open_chat(state, business)
	assert_false(bool(listed.get("allowed", true)))

	business["saleState"] = "not_for_sale"
	AiClient.ai_available = true
	var allowed: Dictionary = CommunityChatRuntime.can_open_chat(state, business)
	assert_true(bool(allowed.get("allowed", false)))


func test_start_session_creates_greeting_and_limits() -> void:
	var state := _community_state(550055)
	var business: Dictionary = _first_community_business(state)
	AiClient.ai_available = true
	var npc_id := str(business.get("ownerNpcId", ""))
	var result: Dictionary = CommunityChatRuntime.start_session(
		state,
		npc_id,
		str(business.get("id", "")),
		str(business.get("parcelId", "")),
		"meadowgate_commons",
	)
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	var session: Dictionary = result.get("session", {})
	assert_eq(str(session.get("status", "")), "active")
	assert_eq(int(session.get("playerMessagesSent", -1)), 0)
	assert_eq(int(session.get("maxPlayerMessages", 0)), CommunityConfig.chat_max_player_messages())
	var messages: Array = session.get("messages", [])
	assert_gt(messages.size(), 0)


func test_process_validated_turn_applies_social_effects_and_ledger() -> void:
	var state := _community_state(550066)
	var business: Dictionary = _first_community_business(state)
	var npc_id := str(business.get("ownerNpcId", ""))
	AiClient.ai_available = true
	var started: Dictionary = CommunityChatRuntime.start_session(
		state,
		npc_id,
		str(business.get("id", "")),
		str(business.get("parcelId", "")),
		"meadowgate_commons",
	)
	var session: Dictionary = started.get("session", {})
	session["playerMessagesSent"] = 1
	var validated := {
		"dialogue": "Good to see a friendly face around here.",
		"tone": "warm",
		"social_action": "small_talk",
		"fact_disclosures": [],
		"gift": null,
		"promise_proposal": null,
		"interaction_classification": {
			"sincerity": "high",
			"respectfulness": "high",
			"manipulation_signal": "none",
			"repetition": "new",
		},
		"new_fact_proposals": [],
	}
	var events_before := (state.community.get("interactionEvents", []) as Array).size()
	var outcome: Dictionary = CommunityChatRuntime.process_validated_turn(
		state,
		npc_id,
		session,
		validated,
	)
	assert_true(bool(outcome.get("ok", false)))
	assert_eq(str(outcome.get("dialogue", "")), validated["dialogue"])
	var events_after := (state.community.get("interactionEvents", []) as Array).size()
	assert_gt(events_after, events_before)


func test_message_limit_dismisses_session() -> void:
	var state := _community_state(550077)
	var business: Dictionary = _first_community_business(state)
	var npc_id := str(business.get("ownerNpcId", ""))
	AiClient.ai_available = true
	var started: Dictionary = CommunityChatRuntime.start_session(
		state,
		npc_id,
		str(business.get("id", "")),
		str(business.get("parcelId", "")),
		"meadowgate_commons",
	)
	var session: Dictionary = started.get("session", {})
	session["playerMessagesSent"] = CommunityConfig.chat_max_player_messages()
	var outcome: Dictionary = CommunityChatRuntime.process_validated_turn(
		state,
		npc_id,
		session,
		{
			"dialogue": "Alright, that's enough for today.",
			"tone": "neutral",
			"social_action": "none",
			"fact_disclosures": [],
			"gift": null,
			"promise_proposal": null,
			"interaction_classification": {
				"sincerity": "medium",
				"respectfulness": "medium",
				"manipulation_signal": "none",
				"repetition": "new",
			},
			"new_fact_proposals": [],
		},
	)
	assert_true(bool(outcome.get("dismissed", false)))
	var active: Dictionary = CommunityChatRuntime.get_active_session(state, npc_id)
	assert_eq(str(active.get("status", "")), "dismissed")


func test_context_builder_includes_allowed_fact_ids() -> void:
	var state := _community_state(550088)
	var business: Dictionary = _first_community_business(state)
	var npc_id := str(business.get("ownerNpcId", ""))
	var session := {
		"npcId": npc_id,
		"businessId": str(business.get("id", "")),
		"parcelId": str(business.get("parcelId", "")),
		"districtId": "meadowgate_commons",
		"sessionId": "sess_test",
		"messages": [],
		"maxPlayerMessages": CommunityConfig.chat_max_player_messages(),
		"playerMessagesSent": 0,
	}
	var context: Dictionary = CommunityContextBuilder.build(state, session)
	assert_eq(str(context.get("npc", {}).get("id", "")), npc_id)
	assert_true(context.has("allowedFactIds"))
	assert_true(context.has("eligibleFacts"))
