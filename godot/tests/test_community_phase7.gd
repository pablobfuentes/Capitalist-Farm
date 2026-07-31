extends GutTest


func before_all() -> void:
	Content.load_farm_content()
	CommunityConfig.load_config()
	CommunityChainCatalog.load_catalog()
	CommunitySocialEffects.load_effects()
	CommunityFeatureFlags.reset_overrides()
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, true)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, true)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_PROMISE_FULFILLMENT, true)


func after_all() -> void:
	CommunityFeatureFlags.reset_overrides()


func _community_state(seed_value: int) -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = seed_value
	RunBootstrap.prepare_new_run(state)
	return state


func _npc_with_fact(state: RunState) -> Dictionary:
	var district: Dictionary = state.community["districts"]["meadowgate_commons"]
	var edges: Array = district.get("supplyRelationships", [])
	assert_gt(edges.size(), 0)
	var edge: Dictionary = edges[0]
	var supplier_id := str(edge.get("supplierBusinessId", ""))
	var supplier: Dictionary = district["businesses"][supplier_id]
	var npc_id := str(supplier.get("ownerNpcId", ""))
	var fact_id := ""
	for fact_id_variant in state.community.get("facts", {}).keys():
		var candidate := str(fact_id_variant)
		var fact: Dictionary = state.community["facts"][candidate]
		if str(fact.get("subjectId", "")) == str(edge.get("id", "")):
			fact_id = candidate
			break
	if fact_id.is_empty():
		fact_id = str(state.community.get("facts", {}).keys()[0])
	return {"npcId": npc_id, "factId": fact_id}


func test_record_from_chat_proposal_creates_accepted_promise() -> void:
	var state := _community_state(990011)
	var pair: Dictionary = _npc_with_fact(state)
	var result: Dictionary = CommunityPromiseService.record_from_chat_proposal(
		state,
		str(pair.get("npcId", "")),
		{
			"type": "return_with_information",
			"fact_id": str(pair.get("factId", "")),
			"deadline_turn": state.turn + 2,
			"duration_turns": 2,
		},
		{"sessionId": "sess_test"},
	)
	assert_true(bool(result.get("ok", false)))
	var promise: Dictionary = result.get("promise", {})
	assert_eq(str(promise.get("status", "")), "accepted")
	assert_eq(state.community.get("promises", []).size(), 1)


func test_return_with_information_fulfills_when_fact_confirmed() -> void:
	var state := _community_state(990022)
	var pair: Dictionary = _npc_with_fact(state)
	var npc_id := str(pair.get("npcId", ""))
	var fact_id := str(pair.get("factId", ""))

	CommunityPromiseService.record_from_chat_proposal(state, npc_id, {
		"type": "return_with_information",
		"fact_id": fact_id,
		"deadline_turn": state.turn + 1,
		"duration_turns": 1,
	})

	CommunityKnowledgeService.record_player_discovery(
		state,
		fact_id,
		npc_id,
		"direct_statement",
		0.9,
		"confirmed",
	)

	var trust_before := int(CommunityState.get_social_state(state, npc_id).get("trust", 0))
	var outcomes: Array = CommunityPromiseService.process_turn(state)
	assert_eq(outcomes.size(), 1)
	assert_eq(str((outcomes[0] as Dictionary).get("status", "")), "fulfilled")
	var trust_after := int(CommunityState.get_social_state(state, npc_id).get("trust", 0))
	assert_gt(trust_after, trust_before)


func test_return_with_information_breaks_when_deadline_passes() -> void:
	var state := _community_state(990033)
	var pair: Dictionary = _npc_with_fact(state)
	var npc_id := str(pair.get("npcId", ""))
	var fact_id := str(pair.get("factId", ""))

	CommunityPromiseService.record_from_chat_proposal(state, npc_id, {
		"type": "return_with_information",
		"fact_id": fact_id,
		"deadline_turn": state.turn,
		"duration_turns": 1,
	})

	state.turn += 1
	var outcomes: Array = CommunityPromiseService.process_turn(state)
	assert_eq(outcomes.size(), 1)
	assert_eq(str((outcomes[0] as Dictionary).get("status", "")), "broken")


func test_promise_fulfillment_disabled_skips_recording() -> void:
	var state := _community_state(990044)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_PROMISE_FULFILLMENT, false)
	var pair: Dictionary = _npc_with_fact(state)
	var result: Dictionary = CommunityPromiseService.record_from_chat_proposal(
		state,
		str(pair.get("npcId", "")),
		{"type": "price_hold", "duration_turns": 2},
	)
	assert_false(bool(result.get("ok", false)))
	assert_eq(state.community.get("promises", []).size(), 0)


func test_record_payment_fulfills_invoice_promise() -> void:
	var state := _community_state(990055)
	var pair: Dictionary = _npc_with_fact(state)
	var npc_id := str(pair.get("npcId", ""))

	CommunityPromiseService.record_from_chat_proposal(state, npc_id, {
		"type": "pay_invoice_on_time",
		"subject_id": npc_id,
		"deadline_turn": state.turn + 3,
		"amount_due": 500,
	})

	var fulfilled: Array = CommunityPromiseService.record_payment_toward_npc(state, npc_id, 500)
	assert_eq(fulfilled.size(), 1)
	assert_eq(str((fulfilled[0] as Dictionary).get("status", "")), "fulfilled")
