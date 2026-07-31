# Fact, NPC knowledge, player knowledge, and disclosure eligibility (Community spec §8).
class_name CommunityKnowledgeService
extends RefCounted


static func get_fact(state: RunState, fact_id: String) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var facts: Dictionary = state.community.get("facts", {})
	if facts.has(fact_id):
		return (facts[fact_id] as Dictionary).duplicate(true)
	return {}


static func npc_knowledge(state: RunState, npc_id: String, fact_id: String) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var by_npc: Dictionary = state.community.get("npcFactKnowledge", {})
	if typeof(by_npc) != TYPE_DICTIONARY or not by_npc.has(npc_id):
		return {}
	var facts_for_npc: Dictionary = by_npc[npc_id]
	if typeof(facts_for_npc) != TYPE_DICTIONARY or not facts_for_npc.has(fact_id):
		return {}
	return (facts_for_npc[fact_id] as Dictionary).duplicate(true)


static func player_knowledge(state: RunState, fact_id: String) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var player_facts: Dictionary = state.community.get("playerFactKnowledge", {})
	if player_facts.has(fact_id):
		return (player_facts[fact_id] as Dictionary).duplicate(true)
	return {}


static func player_knows(state: RunState, fact_id: String) -> bool:
	return not player_knowledge(state, fact_id).is_empty()


static func compute_disclosure_score(
	state: RunState,
	npc_id: String,
	fact_id: String,
	context: Dictionary = {},
) -> float:
	var fact: Dictionary = get_fact(state, fact_id)
	if fact.is_empty():
		return -999.0
	var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
	var social: Dictionary = CommunityState.get_social_state(state, npc_id)
	var knowledge: Dictionary = npc_knowledge(state, npc_id, fact_id)
	if knowledge.is_empty():
		return -999.0

	var weights: Dictionary = CommunitySocialEffects.disclosure_weights()
	var familiarity_norm := float(social.get("familiarity", 0)) / 100.0
	var trust_norm := float(social.get("trust", 0)) / 100.0
	var gossip := float(npc.get("gossipTendency", 0.35))
	var sensitivity := float(fact.get("sensitivity", 2)) / 5.0
	var loyalty := float(context.get("loyaltyToSubject", knowledge.get("loyaltyToSubject", 0.0)))
	var confidentiality := float(context.get("confidentialityObligation", knowledge.get("confidentialityObligation", 0.0)))
	var knowledge_state := str(knowledge.get("knowledgeState", "knows"))
	var willingness := float(knowledge.get("willingnessToDisclose", 0.5))

	var score := (
		gossip * float(weights.get("gossipTendency", 0.20))
		+ familiarity_norm * float(weights.get("familiarity", 0.15))
		+ trust_norm * float(weights.get("trust", 0.25))
		+ float(context.get("topicRelevance", 0.5)) * float(weights.get("topicRelevance", 0.15))
		+ float(context.get("emotionalPressure", 0.0)) * float(weights.get("emotionalPressure", 0.10))
		+ float(context.get("questionQuality", 0.5)) * float(weights.get("questionQuality", 0.10))
		- sensitivity * float(weights.get("sensitivity", -0.35))
		- loyalty * float(weights.get("loyaltyToSubject", -0.25))
		- confidentiality * float(weights.get("confidentialityObligation", -0.40))
	)
	if knowledge_state == "rumor":
		score += willingness * 0.22
	return score


static func disclosure_threshold(fact: Dictionary) -> float:
	if fact.has("disclosureThreshold"):
		return float(fact.get("disclosureThreshold"))
	return CommunitySocialEffects.disclosure_default_threshold()


static func is_disclosure_eligible(
	state: RunState,
	npc_id: String,
	fact_id: String,
	context: Dictionary = {},
) -> bool:
	var fact: Dictionary = get_fact(state, fact_id)
	if fact.is_empty() or npc_knowledge(state, npc_id, fact_id).is_empty():
		return false
	return compute_disclosure_score(state, npc_id, fact_id, context) >= disclosure_threshold(fact)


static func get_eligible_facts(state: RunState, npc_id: String, context: Dictionary = {}) -> Array:
	CommunityState.ensure_initialized(state)
	var by_npc: Dictionary = state.community.get("npcFactKnowledge", {})
	if typeof(by_npc) != TYPE_DICTIONARY or not by_npc.has(npc_id):
		return []
	var out: Array = []
	for fact_id_key in (by_npc[npc_id] as Dictionary).keys():
		var fact_id := str(fact_id_key)
		if not is_disclosure_eligible(state, npc_id, fact_id, context):
			continue
		var fact: Dictionary = get_fact(state, fact_id)
		if fact.is_empty():
			continue
		var payload: Dictionary = fact.get("canonicalPayload", {})
		out.append({
			"factId": fact_id,
			"factType": str(fact.get("factType", "")),
			"summary": str(payload.get("summary", "")),
			"sensitivity": int(fact.get("sensitivity", 2)),
			"leverageTags": fact.get("leverageTags", []),
		})
	return out


static func record_player_discovery(
	state: RunState,
	fact_id: String,
	source_npc_id: String,
	source_type: String,
	confidence: float,
	confirmation_state: String,
) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var player_facts: Dictionary = state.community.get("playerFactKnowledge", {})
	if typeof(player_facts) != TYPE_DICTIONARY:
		player_facts = {}
		state.community["playerFactKnowledge"] = player_facts

	var record := {
		"factId": fact_id,
		"sourceNpcId": source_npc_id,
		"sourceType": source_type,
		"confidence": clampf(confidence, 0.0, 1.0),
		"confirmationState": confirmation_state,
		"discoveryTurn": state.turn,
	}
	player_facts[fact_id] = record
	state.community["playerFactKnowledge"] = player_facts
	if CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_RUMOR_PROPAGATION, state):
		CommunityRumorService.seed_from_player_discovery(state, source_npc_id, fact_id)
	return record.duplicate(true)


static func grant_rumor_knowledge(
	state: RunState,
	npc_id: String,
	fact_id: String,
	source_npc_id: String,
	confidence: float,
	hop_count: int,
) -> Dictionary:
	CommunityState.ensure_initialized(state)
	if get_fact(state, fact_id).is_empty() or npc_id.is_empty():
		return {"ok": false, "error": "missing_fact_or_npc"}

	var by_npc: Dictionary = state.community.get("npcFactKnowledge", {})
	if typeof(by_npc) != TYPE_DICTIONARY:
		by_npc = {}
	if not by_npc.has(npc_id):
		by_npc[npc_id] = {}

	var facts_for_npc: Dictionary = by_npc[npc_id]
	var existing: Dictionary = facts_for_npc.get(fact_id, {})
	if typeof(existing) == TYPE_DICTIONARY and float(existing.get("confidence", 0.0)) >= confidence:
		return {"ok": false, "error": "already_knows_better"}

	var cfg: Dictionary = CommunitySocialEffects.rumor_propagation_config()
	var willingness_base := float(cfg.get("willingnessBase", 0.28))
	var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
	var willingness := clampf(
		willingness_base + float(npc.get("gossipTendency", 0.35)) * 0.25,
		0.12,
		0.75,
	)

	var record := {
		"knowledgeState": "rumor",
		"confidence": clampf(confidence, 0.15, 0.95),
		"willingnessToDisclose": willingness,
		"sourceNpcId": source_npc_id,
		"learnedTurn": state.turn,
		"hopCount": hop_count,
	}
	facts_for_npc[fact_id] = record
	by_npc[npc_id] = facts_for_npc
	state.community["npcFactKnowledge"] = by_npc
	return {"ok": true, "record": record.duplicate(true)}


static func disclose_fact_to_player(
	state: RunState,
	npc_id: String,
	fact_id: String,
	mode: String,
	confidence_language: String,
) -> Dictionary:
	if not is_disclosure_eligible(state, npc_id, fact_id):
		return {"ok": false, "error": "not_eligible"}

	var confidence := 0.55
	var confirmation := "rumored"
	match confidence_language:
		"certain":
			confidence = 0.95
			confirmation = "confirmed"
		"likely":
			confidence = 0.75
			confirmation = "supported"
		"uncertain":
			confidence = 0.45
			confirmation = "rumored"

	var source_type := "direct_statement"
	if mode == "rumor":
		source_type = "rumor"
	elif mode == "hint":
		source_type = "observation"

	var discovery := record_player_discovery(
		state,
		fact_id,
		npc_id,
		source_type,
		confidence,
		confirmation,
	)
	var fact: Dictionary = get_fact(state, fact_id)
	var payload: Dictionary = fact.get("canonicalPayload", {})
	var notebook_entry := CommunityNotebookService.record_chat_discovery(
		state,
		npc_id,
		fact_id,
		str(payload.get("summary", "")),
		confirmation,
	)
	if CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_RUMOR_PROPAGATION, state):
		CommunityRumorService.seed_from_disclosure(state, npc_id, fact_id)
	return {"ok": true, "discovery": discovery, "notebookEntry": notebook_entry}
