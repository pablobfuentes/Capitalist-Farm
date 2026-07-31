extends GutTest


func before_all() -> void:
	Content.load_farm_content()
	CommunityConfig.load_config()
	CommunityChainCatalog.load_catalog()
	CommunitySocialEffects.load_effects()
	NegotiationArchetypes.ensure_loaded()
	CommunityFeatureFlags.reset_overrides()
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, true)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, true)


func after_all() -> void:
	CommunityFeatureFlags.reset_overrides()


func _community_state(seed_value: int) -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = seed_value
	RunBootstrap.prepare_new_run(state)
	return state


func test_disclosure_score_increases_with_trust() -> void:
	var state := _community_state(440011)
	var facts: Dictionary = state.community.get("facts", {})
	assert_gt(facts.size(), 0)
	var fact_id := str(facts.keys()[0])

	var npc_id := ""
	for edge_variant in state.community["districts"]["meadowgate_commons"]["supplyRelationships"]:
		var edge: Dictionary = edge_variant
		var supplier_id := str(edge.get("supplierBusinessId", ""))
		var businesses: Dictionary = state.community["districts"]["meadowgate_commons"]["businesses"]
		if businesses.has(supplier_id):
			npc_id = str(businesses[supplier_id].get("ownerNpcId", ""))
			break
	assert_false(npc_id.is_empty())

	var score_before := CommunityKnowledgeService.compute_disclosure_score(state, npc_id, fact_id)
	var social: Dictionary = CommunityState.get_social_state(state, npc_id)
	social["trust"] = 85
	social["familiarity"] = 70
	CommunityState.set_social_state(state, npc_id, social)
	var score_after := CommunityKnowledgeService.compute_disclosure_score(state, npc_id, fact_id)
	assert_gt(score_after, score_before)


func test_disclose_fact_records_player_and_notebook() -> void:
	var state := _community_state(440022)
	var district: Dictionary = state.community["districts"]["meadowgate_commons"]
	var businesses: Dictionary = district.get("businesses", {})
	var business_id := str(businesses.keys()[0])
	var npc_id := str(businesses[business_id].get("ownerNpcId", ""))
	var eligible: Array = CommunityKnowledgeService.get_eligible_facts(state, npc_id, {"questionQuality": 1.0})
	if eligible.is_empty():
		var social: Dictionary = CommunityState.get_social_state(state, npc_id)
		social["trust"] = 90
		social["familiarity"] = 80
		CommunityState.set_social_state(state, npc_id, social)
		eligible = CommunityKnowledgeService.get_eligible_facts(state, npc_id, {"questionQuality": 1.0})
	assert_gt(eligible.size(), 0, "expected at least one eligible fact after trust boost")

	var fact_id := str((eligible[0] as Dictionary).get("factId", ""))
	var result: Dictionary = CommunityKnowledgeService.disclose_fact_to_player(
		state, npc_id, fact_id, "direct", "certain"
	)
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_true(CommunityKnowledgeService.player_knows(state, fact_id))
	assert_gt(CommunityState.notebook_entries_for(state, "chat").size(), 0)


func test_social_rules_apply_capped_deltas() -> void:
	var state := _community_state(440033)
	var npc_id := str(state.community.get("npcs", {}).keys()[0])
	var validated := {
		"social_action": "gift_offer",
		"gift": {"preference_match": true, "accepted": true},
		"interaction_classification": {
			"sincerity": "high",
			"respectfulness": "high",
			"repetition": "new",
		},
	}
	var result: Dictionary = CommunitySocialRules.apply_validated_turn(
		state, npc_id, validated, {"firstTimeGift": true}
	)
	var deltas: Dictionary = result.get("deltas", {})
	for key in deltas.keys():
		assert_lte(abs(int(deltas[key])), CommunitySocialEffects.max_delta_per_interaction())
	var social: Dictionary = CommunityState.get_social_state(state, npc_id)
	assert_gt(int(social.get("warmth", 0)), 0)
	assert_ne(int(social.get("personalRelationshipScore", 0)), 0)


func test_interaction_ledger_appends_events() -> void:
	var state := _community_state(440044)
	var npc_id := str(state.community.get("npcs", {}).keys()[0])
	var event: Dictionary = CommunityInteractionLedger.append_event(state, {
		"eventType": "small_talk",
		"npcId": npc_id,
		"payload": {"text": "hello"},
		"effects": {},
	})
	assert_false(str(event.get("id", "")).is_empty())
	var recent: Array = CommunityInteractionLedger.recent_events_for_npc(state, npc_id, 5)
	assert_eq(recent.size(), 1)


func test_investigate_records_notebook_entries() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = 440055
	OpportunitySystem.refresh_opportunities(state)
	state.action_points = 2
	var opp_id := str(state.opportunities[0].get("id", ""))
	var before: int = state.community.get("notebookEntries", []).size()
	var result: Dictionary = DiligenceSystem.investigate_opportunity(state, opp_id)
	assert_true(bool(result.get("ok", false)))
	assert_gt(state.community.get("notebookEntries", []).size(), before)
	var investigate_entries: Array = CommunityState.notebook_entries_for(state, "investigate")
	assert_gt(investigate_entries.size(), 0)


func test_notebook_format_includes_investigate_section() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = 440066
	OpportunitySystem.refresh_opportunities(state)
	state.action_points = 2
	var opp: Dictionary = state.opportunities[0]
	DiligenceSystem.investigate_opportunity(state, str(opp.get("id", "")))
	opp = OpportunitySystem.find_opportunity(state, str(opp.get("id", "")))
	var neg := {
		"intelUnlocked": true,
		"counterparty": opp.get("counterparty", {}),
		"context": {"price": int(opp.get("price", 0)), "opp": opp},
	}
	var block := CommunityNotebookService.format_community_intel_block(state, neg)
	assert_true(block.contains("NOTEBOOK — INVESTIGATE"))
