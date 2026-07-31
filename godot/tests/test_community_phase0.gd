extends GutTest

const _Provider := preload("res://core/community/ollama_npc_dialogue_provider.gd")


func before_all() -> void:
	Content.load_farm_content()
	CommunityConfig.load_config()
	CommunityFeatureFlags.reset_overrides()


func after_each() -> void:
	CommunityFeatureFlags.reset_overrides()


func test_community_ids_are_deterministic_for_meadowgate_fixture() -> void:
	var seed := 424242
	var world_a := CommunityIds.world_id(seed)
	var world_b := CommunityIds.world_id(seed)
	assert_eq(world_a, world_b)
	assert_eq(world_a, "world_%08x" % seed)

	assert_eq(CommunityIds.business_id("meadowgate_commons", 7), "business_mg_007")
	assert_eq(CommunityIds.npc_id("meadowgate_commons", 3), "npc_mg_003")
	assert_eq(CommunityIds.fact_id("meadowgate_commons", 42), "fact_mg_0042")
	assert_eq(
		CommunityIds.supply_relationship_id("business_mg_001", "business_mg_007", "grain"),
		"supply_business_mg_001_business_mg_007_grain",
	)
	assert_eq(CommunityIds.interaction_event_id(1839), "event_00001839")


func test_personal_gauge_adj_uses_species_weight() -> void:
	assert_eq(CommunityIds.personal_gauge_adj("sheep", 5), 20)
	assert_eq(CommunityIds.personal_gauge_adj("donkey", 5), 10)
	assert_eq(CommunityIds.personal_gauge_adj("donkey", 0), 0)
	assert_eq(CommunityIds.personal_gauge_adj("donkey", -5), -10)


func test_community_state_initializes_on_new_run() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)
	assert_eq(state.community_schema_version, CommunityMigration.CURRENT_SCHEMA_VERSION)
	assert_eq(str(state.community.get("worldId", "")), CommunityIds.world_id(state.run_seed))
	assert_true(state.community.has("socialStates"))
	assert_true(state.community.has("notebookEntries"))
	assert_eq(int(CommunityConfig.chat_max_player_messages()), 5)


func test_community_state_roundtrips_through_save_dict() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)
	CommunityState.add_notebook_entry(state, {
		"source": "chat",
		"category": "leverage",
		"factId": "fact_mg_0001",
		"displaySummary": "Harold's deliveries run late.",
		"discoveryTurn": state.turn,
	})
	var reloaded: RunState = RunState.from_dict(state.to_dict())
	assert_eq(reloaded.community_schema_version, CommunityMigration.CURRENT_SCHEMA_VERSION)
	assert_eq(reloaded.community.get("worldId"), state.community.get("worldId"))
	var entries: Array = reloaded.community.get("notebookEntries", [])
	assert_eq(entries.size(), 1)
	assert_eq(str((entries[0] as Dictionary).get("displaySummary", "")), "Harold's deliveries run late.")


func test_legacy_save_migrates_community_block() -> void:
	var legacy: Dictionary = {
		"seed": 999001,
		"mode": GameMode.MODE_CAPITAL_FARM,
		"turn": 2,
		"cash": 12000,
		"reputation": 15,
		"actionPoints": 2,
		"portfolio": {"businesses": [], "realEstate": []},
	}
	var migrated := CommunityMigration.migrate_run_dict(legacy)
	assert_eq(int(migrated.get("communitySchemaVersion", 0)), CommunityMigration.CURRENT_SCHEMA_VERSION)
	assert_true(migrated.has("community"))
	var loaded: RunState = RunState.from_dict(migrated)
	assert_eq(loaded.community_schema_version, CommunityMigration.CURRENT_SCHEMA_VERSION)
	assert_eq(str(loaded.community.get("worldId", "")), CommunityIds.world_id(999001))


func test_feature_flags_default_off() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)
	assert_false(CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_CHAT, state))
	assert_false(CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state))


func test_community_chat_gate_blocks_when_feature_disabled() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)
	var gate: Dictionary = AiClient.community_chat_gate(state)
	assert_false(bool(gate.get("allowed", true)))
	assert_eq(str(gate.get("reason", "")), "feature_disabled")


func test_community_chat_gate_requires_ai_when_enabled() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_CHAT, true)
	AiClient.ai_available = false
	var gate: Dictionary = AiClient.community_chat_gate(state)
	assert_false(bool(gate.get("allowed", true)))
	assert_eq(str(gate.get("reason", "")), "ai_offline")


func test_npc_dialogue_validator_accepts_valid_response() -> void:
	var raw := {
		"dialogue": "My grain was due before sunrise.",
		"tone": "irritated",
		"social_action": "disclosure",
		"fact_disclosures": [{
			"fact_id": "fact_mg_0104",
			"mode": "direct",
			"confidence_language": "certain",
		}],
		"gift": null,
		"promise_proposal": null,
		"interaction_classification": {
			"sincerity": "medium",
			"respectfulness": "high",
			"manipulation_signal": "none",
			"repetition": "new",
		},
		"new_fact_proposals": [],
	}
	var result: Dictionary = NpcDialogueValidator.validate(raw, {
		"allowedFactIds": ["fact_mg_0104"],
	})
	assert_true(bool(result.get("ok", false)), str(result.get("errors", [])))
	var normalized: Dictionary = result.get("normalized", {})
	assert_eq(str(normalized.get("dialogue", "")), "My grain was due before sunrise.")


func test_npc_dialogue_validator_rejects_unknown_fact_and_promise() -> void:
	var raw := {
		"dialogue": "Done.",
		"tone": "neutral",
		"social_action": "promise",
		"fact_disclosures": [{"fact_id": "fact_secret", "mode": "direct", "confidence_language": "certain"}],
		"promise_proposal": {"type": "not_a_real_promise", "subject_id": "npc_mg_001", "deadline_turn": 8},
		"interaction_classification": {
			"sincerity": "low",
			"respectfulness": "low",
			"manipulation_signal": "strong",
			"repetition": "excessive",
		},
		"new_fact_proposals": [],
	}
	var result: Dictionary = NpcDialogueValidator.validate(raw, {
		"allowedFactIds": ["fact_mg_0001"],
		"allowedPromiseTypes": CommunityConfig.promise_type_ids(),
		"allowedEntityIds": ["npc_mg_001"],
	})
	assert_false(bool(result.get("ok", true)))
	var errors: Array = result.get("errors", [])
	assert_true("fact_disclosure_not_allowed:fact_secret" in errors)
	assert_true("promise_type_not_allowed:not_a_real_promise" in errors)


func test_promise_catalog_has_expected_entries() -> void:
	var ids: Array = CommunityConfig.promise_type_ids()
	assert_true(ids.size() >= 10)
	assert_true("capacity_commitment_soft" in ids)
	assert_true("renegotiate_after_period" in ids)


func test_ollama_provider_honors_chat_gate() -> void:
	var provider := _Provider.new()
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	RunBootstrap.prepare_new_run(state)
	var result: Dictionary = provider.generate_turn({
		"requestId": "req_test_1",
		"context": {"npcId": "npc_mg_001"},
	})
	assert_false(bool(result.get("ok", true)))
	assert_eq(str(result.get("error", "")), AiClient.community_chat_gate(state).get("message", ""))
