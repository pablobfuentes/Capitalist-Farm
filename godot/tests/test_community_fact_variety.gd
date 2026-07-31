extends GutTest


func before_all() -> void:
	Content.load_farm_content()
	CommunityConfig.load_config()
	CommunityChainCatalog.reload_catalog()
	CommunitySocialEffects.load_effects()
	CommunityFeatureFlags.reset_overrides()
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, true)
	CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_CHAT, true)


func after_all() -> void:
	CommunityFeatureFlags.reset_overrides()


func _community_state(seed_value: int) -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = seed_value
	RunBootstrap.prepare_new_run(state)
	return state


func test_social_fact_types_loaded() -> void:
	var types: Array = CommunityChainCatalog.social_fact_types()
	assert_gte(types.size(), 5)
	var ids: PackedStringArray = []
	for type_variant in types:
		ids.append(str((type_variant as Dictionary).get("id", "")))
	assert_true("neighbor_preference" in ids)
	assert_true("district_gossip" in ids)


func test_generation_seeds_non_supply_facts() -> void:
	var state := _community_state(550101)
	var facts: Dictionary = state.community.get("facts", {})
	assert_gt(facts.size(), 0)
	var social_count := 0
	var ops_count := 0
	for fact_id_key in facts.keys():
		var fact: Dictionary = facts[fact_id_key]
		var fact_type := str(fact.get("factType", ""))
		if fact_type == "operational":
			ops_count += 1
		else:
			social_count += 1
			var payload: Dictionary = fact.get("canonicalPayload", {})
			assert_false(str(payload.get("summary", "")).is_empty())
			assert_gt((payload.get("topicTags", []) as Array).size(), 0)
	assert_gt(ops_count, 0, "expected operational supply facts")
	assert_gt(social_count, 0, "expected non-supply social/atmospheric facts")


func test_topic_router_detects_supply_vs_gossip() -> void:
	var supply_topics := CommunityFactTopicRouter.detect_topics("How are your supplier deliveries going?")
	assert_true("supply" in supply_topics or "delivery" in supply_topics)
	var gossip_topics := CommunityFactTopicRouter.detect_topics("Any gossip around the valley?")
	assert_true("gossip" in gossip_topics)
	var general_topics := CommunityFactTopicRouter.detect_topics("Hey, how's your day?")
	assert_eq(general_topics.size(), 1)
	assert_eq(general_topics[0], "general")


func test_topic_router_limits_ops_on_general_chat() -> void:
	var eligible: Array = [
		{"factId": "a", "factType": "operational", "summary": "deliveries late", "topicTags": ["supply"], "sensitivity": 2},
		{"factId": "b", "factType": "operational", "summary": "capacity spare", "topicTags": ["supply", "capacity"], "sensitivity": 1},
		{"factId": "c", "factType": "operational", "summary": "contract strain", "topicTags": ["supply"], "sensitivity": 3},
		{"factId": "d", "factType": "preference", "summary": "likes practical help", "topicTags": ["preference"], "sensitivity": 1},
		{"factId": "e", "factType": "atmospheric", "summary": "hears porch talk", "topicTags": ["gossip"], "sensitivity": 1},
		{"factId": "f", "factType": "staff", "summary": "short-handed", "topicTags": ["staff"], "sensitivity": 2},
	]
	var selected: Array = CommunityFactTopicRouter.select_for_prompt(eligible, "Hey there", 5)
	assert_gte(selected.size(), 3)
	var ops := 0
	var non_ops := 0
	for fact_variant in selected:
		var fact: Dictionary = fact_variant
		if str(fact.get("factType", "")) == "operational":
			ops += 1
		else:
			non_ops += 1
	assert_lte(ops, 2)
	assert_gte(non_ops, 2)


func test_context_builder_routes_eligible_facts_by_topic() -> void:
	var state := _community_state(550202)
	var npc_id := str(state.community.get("npcs", {}).keys()[0])
	var npc: Dictionary = state.community["npcs"][npc_id]
	var social: Dictionary = CommunityState.get_social_state(state, npc_id)
	social["trust"] = 90
	social["familiarity"] = 80
	CommunityState.set_social_state(state, npc_id, social)

	var session := {
		"sessionId": "test_session",
		"npcId": npc_id,
		"businessId": str(npc.get("primaryBusinessId", "")),
		"districtId": CommunityConfig.mvp_district_id(),
		"parcelId": "",
		"messages": [],
		"playerMessagesSent": 0,
		"maxPlayerMessages": 5,
		"conversationSummary": "",
	}
	var gossip_ctx: Dictionary = CommunityContextBuilder.build(state, session, "Any gossip from the neighbors?")
	assert_true(gossip_ctx.has("detectedTopics"))
	assert_true("gossip" in gossip_ctx.get("detectedTopics", []))
	var eligible: Array = gossip_ctx.get("eligibleFacts", [])
	assert_gt(eligible.size(), 0)
