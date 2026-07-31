extends GutTest


func before_all() -> void:
	Content.load_farm_content()
	CommunityConfig.load_config()
	CommunityChainCatalog.load_catalog()
	CommunitySocialEffects.load_effects()
	CommunityFeatureFlags.reset_overrides()
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, true)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_RUMOR_PROPAGATION, true)


func after_all() -> void:
	CommunityFeatureFlags.reset_overrides()


func _community_state(seed_value: int) -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = seed_value
	RunBootstrap.prepare_new_run(state)
	return state


func _edge_with_npcs(state: RunState) -> Dictionary:
	var district: Dictionary = state.community["districts"]["meadowgate_commons"]
	var edges: Array = district.get("supplyRelationships", [])
	assert_gt(edges.size(), 0)
	var edge: Dictionary = edges[0]
	var supplier_id := str(edge.get("supplierBusinessId", ""))
	var client_id := str(edge.get("clientBusinessId", ""))
	var supplier: Dictionary = district["businesses"][supplier_id]
	var client: Dictionary = district["businesses"][client_id]
	return {
		"edge": edge,
		"supplierNpcId": str(supplier.get("ownerNpcId", "")),
		"clientNpcId": str(client.get("ownerNpcId", "")),
	}


func _fact_for_edge(state: RunState, edge: Dictionary) -> String:
	var edge_id := str(edge.get("id", ""))
	for fact_id_variant in state.community.get("facts", {}).keys():
		var fact_id := str(fact_id_variant)
		var fact: Dictionary = state.community["facts"][fact_id]
		if str(fact.get("subjectId", "")) == edge_id:
			return fact_id
	return str(state.community.get("facts", {}).keys()[0])


func test_supply_neighbor_npcs_returns_counterpart() -> void:
	var state := _community_state(880011)
	var pair: Dictionary = _edge_with_npcs(state)
	var supplier_npc := str(pair.get("supplierNpcId", ""))
	var client_npc := str(pair.get("clientNpcId", ""))
	var neighbors: Array = CommunityRumorService.supply_neighbor_npcs(state, supplier_npc)
	assert_true(client_npc in neighbors)


func test_grant_rumor_knowledge_records_rumor_state() -> void:
	var state := _community_state(880022)
	var pair: Dictionary = _edge_with_npcs(state)
	var fact_id := _fact_for_edge(state, pair.get("edge", {}))
	var target_npc := str(pair.get("clientNpcId", ""))
	var source_npc := str(pair.get("supplierNpcId", ""))
	var result: Dictionary = CommunityKnowledgeService.grant_rumor_knowledge(
		state, target_npc, fact_id, source_npc, 0.55, 1
	)
	assert_true(bool(result.get("ok", false)))
	var knowledge: Dictionary = CommunityKnowledgeService.npc_knowledge(state, target_npc, fact_id)
	assert_eq(str(knowledge.get("knowledgeState", "")), "rumor")
	assert_eq(str(knowledge.get("sourceNpcId", "")), source_npc)


func test_rumor_knowledge_can_become_disclosure_eligible() -> void:
	var state := _community_state(880033)
	var pair: Dictionary = _edge_with_npcs(state)
	var fact_id := _fact_for_edge(state, pair.get("edge", {}))
	var target_npc := str(pair.get("clientNpcId", ""))
	var source_npc := str(pair.get("supplierNpcId", ""))
	CommunityKnowledgeService.grant_rumor_knowledge(state, target_npc, fact_id, source_npc, 0.62, 1)
	var social: Dictionary = CommunityState.get_social_state(state, target_npc)
	social["trust"] = 80
	social["familiarity"] = 70
	CommunityState.set_social_state(state, target_npc, social)
	assert_true(CommunityKnowledgeService.is_disclosure_eligible(
		state,
		target_npc,
		fact_id,
		{"questionQuality": 1.0, "topicRelevance": 0.9},
	))


func test_seed_and_process_turn_spreads_along_supply_edge() -> void:
	var spread_ok := false
	for attempt in range(32):
		var state := _community_state(880044 + attempt)
		var pair: Dictionary = _edge_with_npcs(state)
		var fact_id := _fact_for_edge(state, pair.get("edge", {}))
		var source_npc := str(pair.get("supplierNpcId", ""))
		var target_npc := str(pair.get("clientNpcId", ""))

		var npcs: Dictionary = state.community.get("npcs", {})
		npcs[source_npc]["gossipTendency"] = 0.95
		state.community["npcs"] = npcs

		CommunityRumorService.seed_from_disclosure(state, source_npc, fact_id)
		assert_eq(state.community.get("pendingRumorSeeds", []).size(), 1)
		var spreads: Array = CommunityRumorService.process_turn(state)
		assert_eq(state.community.get("pendingRumorSeeds", []).size(), 0)
		if spreads.is_empty():
			continue
		var knowledge: Dictionary = CommunityKnowledgeService.npc_knowledge(state, target_npc, fact_id)
		if knowledge.is_empty() or str(knowledge.get("knowledgeState", "")) != "rumor":
			continue
		spread_ok = true
		break
	assert_true(spread_ok, "Expected at least one seeded rumor to spread along a supply edge")


func test_rumor_propagation_disabled_skips_processing() -> void:
	var state := _community_state(880055)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_RUMOR_PROPAGATION, false)
	var pair: Dictionary = _edge_with_npcs(state)
	var fact_id := _fact_for_edge(state, pair.get("edge", {}))
	CommunityRumorService.seed_from_disclosure(state, str(pair.get("supplierNpcId", "")), fact_id)
	var spreads: Array = CommunityRumorService.process_turn(state)
	assert_eq(spreads.size(), 0)


func test_rumor_does_not_overwrite_higher_confidence() -> void:
	var state := _community_state(880066)
	var pair: Dictionary = _edge_with_npcs(state)
	var fact_id := _fact_for_edge(state, pair.get("edge", {}))
	var target_npc := str(pair.get("clientNpcId", ""))
	var source_npc := str(pair.get("supplierNpcId", ""))
	CommunityKnowledgeService.grant_rumor_knowledge(state, target_npc, fact_id, source_npc, 0.80, 0)
	var weaker: Dictionary = CommunityKnowledgeService.grant_rumor_knowledge(
		state, target_npc, fact_id, "other_npc", 0.45, 1
	)
	assert_false(bool(weaker.get("ok", false)))
	var knowledge: Dictionary = CommunityKnowledgeService.npc_knowledge(state, target_npc, fact_id)
	assert_eq(float(knowledge.get("confidence", 0.0)), 0.80)
