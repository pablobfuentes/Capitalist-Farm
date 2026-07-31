# Builds filtered NPC context packets for community chat (Community spec §10.2).
class_name CommunityContextBuilder
extends RefCounted

const _NpcSpecies := preload("res://core/systems/npc_species_system.gd")


static func build(state: RunState, session: Dictionary, player_message: String = "") -> Dictionary:
	CommunityState.ensure_initialized(state)
	var npc_id := str(session.get("npcId", ""))
	var business_id := str(session.get("businessId", ""))
	var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
	var business: Dictionary = CommunityGenerator.get_business(state, business_id)
	if npc.is_empty():
		return {}

	var topics := CommunityFactTopicRouter.detect_topics(player_message)
	var topic_relevance := 0.55
	if not (topics.size() == 1 and topics[0] == "general"):
		topic_relevance = 0.8
	var all_eligible: Array = CommunityKnowledgeService.get_eligible_facts(
		state,
		npc_id,
		{
			"topicRelevance": topic_relevance,
			"questionQuality": 0.7,
		},
	)
	var eligible_facts: Array = CommunityFactTopicRouter.select_for_prompt(
		all_eligible,
		player_message,
	)
	var allowed_fact_ids: Array = []
	for fact_variant in eligible_facts:
		if typeof(fact_variant) == TYPE_DICTIONARY:
			allowed_fact_ids.append(str((fact_variant as Dictionary).get("factId", "")))

	var player_known: Array = []
	var player_facts: Dictionary = state.community.get("playerFactKnowledge", {})
	for fact_id_key in player_facts.keys():
		player_known.append(str(fact_id_key))

	var recent_events: Array = CommunityInteractionLedger.recent_events_for_npc(state, npc_id, 6)
	var social: Dictionary = CommunityState.get_social_state(state, npc_id)
	var species_id := str(npc.get("speciesId", "hen"))

	return {
		"schemaVersion": CommunityConfig.dialogue_schema_version(),
		"requestId": str(session.get("sessionId", "")),
		"conversationMode": "casual",
		"scene": {
			"turn": state.turn,
			"locationName": str(business.get("displayName", "Business")),
			"businessSaleState": str(business.get("saleState", "not_for_sale")),
			"districtId": str(session.get("districtId", "")),
			"parcelId": str(session.get("parcelId", "")),
		},
		"npc": {
			"id": npc_id,
			"displayName": str(npc.get("displayName", "Neighbor")),
			"speciesId": species_id,
			"role": "owner",
			"personalityTraits": npc.get("personalityTraits", []),
			"voiceRules": [_NpcSpecies.species_prompt_block({"speciesId": species_id})],
		},
		"playerRelationship": {
			"labels": _relationship_labels(social),
			"personalRelationshipScore": int(social.get("personalRelationshipScore", 0)),
			"recentEvents": recent_events,
		},
		"detectedTopics": Array(topics),
		"eligibleFacts": eligible_facts,
		"playerKnownFactIds": player_known,
		"allowedFactIds": allowed_fact_ids,
		"allowedEntityIds": _allowed_entity_ids(state, npc_id, business_id),
		"allowedPromiseTypes": CommunityConfig.promise_type_ids(),
		"recentDialogue": session.get("messages", []),
		"conversationSummary": str(session.get("conversationSummary", "")),
		"messagesRemaining": maxi(
			0,
			int(session.get("maxPlayerMessages", CommunityConfig.chat_max_player_messages()))
			- int(session.get("playerMessagesSent", 0)),
		),
	}


static func _relationship_labels(social: Dictionary) -> Array:
	var score := int(social.get("personalRelationshipScore", 0))
	if score >= 3:
		return ["Trusted"]
	if score >= 1:
		return ["Friendly"]
	if score <= -3:
		return ["Wary"]
	if score <= -1:
		return ["Cool"]
	return ["Stranger"]


static func _allowed_entity_ids(state: RunState, npc_id: String, business_id: String) -> Array:
	var ids: Array = [npc_id]
	if not business_id.is_empty():
		ids.append(business_id)
	for npc_key in state.community.get("npcs", {}).keys():
		ids.append(str(npc_key))
	for fact_key in state.community.get("facts", {}).keys():
		ids.append(str(fact_key))
	return ids
