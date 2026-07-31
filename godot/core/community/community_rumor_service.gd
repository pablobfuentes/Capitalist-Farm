# District rumor propagation along supply edges (8.3 Phase 6 / Community spec §8).
class_name CommunityRumorService
extends RefCounted


static func seed_from_disclosure(state: RunState, source_npc_id: String, fact_id: String) -> void:
	if not _enabled(state) or source_npc_id.is_empty() or fact_id.is_empty():
		return
	_queue_seed(state, source_npc_id, fact_id, 1.0, 0)


static func seed_from_player_discovery(state: RunState, source_npc_id: String, fact_id: String) -> void:
	if not _enabled(state) or source_npc_id.is_empty() or fact_id.is_empty():
		return
	_queue_seed(state, source_npc_id, fact_id, 0.85, 0)


static func process_turn(state: RunState) -> Array:
	if not _enabled(state):
		return []

	var spreads: Array = []
	var cfg: Dictionary = CommunitySocialEffects.rumor_propagation_config()
	var max_spreads := int(cfg.get("maxSpreadsPerTurn", 14))
	var seeds: Array = state.community.get("pendingRumorSeeds", [])
	if typeof(seeds) != TYPE_ARRAY:
		seeds = []

	for seed_variant in seeds:
		if spreads.size() >= max_spreads:
			break
		if typeof(seed_variant) != TYPE_DICTIONARY:
			continue
		var seed: Dictionary = seed_variant
		spreads.append_array(_spread_from_source(
			state,
			str(seed.get("sourceNpcId", "")),
			str(seed.get("factId", "")),
			float(seed.get("sourceConfidence", 0.8)),
			int(seed.get("hopCount", 0)),
			max_spreads - spreads.size(),
		))

	state.community["pendingRumorSeeds"] = []
	spreads.append_array(_ambient_spread_turn(state, max_spreads - spreads.size()))

	if not spreads.is_empty():
		var log: Array = state.community.get("rumorSpreadLog", [])
		for spread_variant in spreads:
			log.append(spread_variant)
		state.community["rumorSpreadLog"] = log.slice(maxi(0, log.size() - 100))

	return spreads


static func supply_neighbor_npcs(state: RunState, npc_id: String, district_id: String = "") -> Array:
	var target_district := district_id
	if target_district.is_empty():
		target_district = CommunityConfig.mvp_district_id()
	var business_id := _business_id_for_npc(state, npc_id)
	if business_id.is_empty():
		return []

	var district_payload: Dictionary = state.community.get("districts", {}).get(target_district, {})
	var edges: Array = district_payload.get("supplyRelationships", [])
	var neighbors: Array = []
	var seen: Dictionary = {}

	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var supplier_id := str(edge.get("supplierBusinessId", ""))
		var client_id := str(edge.get("clientBusinessId", ""))
		var counterpart_business_id := ""
		if supplier_id == business_id:
			counterpart_business_id = client_id
		elif client_id == business_id:
			counterpart_business_id = supplier_id
		else:
			continue
		var counterpart: Dictionary = CommunityGenerator.get_business(state, counterpart_business_id)
		var neighbor_npc := str(counterpart.get("ownerNpcId", ""))
		if neighbor_npc.is_empty() or neighbor_npc == npc_id or seen.has(neighbor_npc):
			continue
		seen[neighbor_npc] = true
		neighbors.append(neighbor_npc)
	return neighbors


static func _enabled(state: RunState) -> bool:
	return CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state) \
		and CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_RUMOR_PROPAGATION, state)


static func _queue_seed(
	state: RunState,
	source_npc_id: String,
	fact_id: String,
	source_confidence: float,
	hop_count: int,
) -> void:
	var seeds: Array = state.community.get("pendingRumorSeeds", [])
	if typeof(seeds) != TYPE_ARRAY:
		seeds = []
	seeds.append({
		"sourceNpcId": source_npc_id,
		"factId": fact_id,
		"sourceConfidence": source_confidence,
		"hopCount": hop_count,
		"queuedTurn": state.turn,
	})
	state.community["pendingRumorSeeds"] = seeds


static func _ambient_spread_turn(state: RunState, remaining: int) -> Array:
	if remaining <= 0:
		return []
	var spreads: Array = []
	var cfg: Dictionary = CommunitySocialEffects.rumor_propagation_config()
	var min_confidence := float(cfg.get("minSourceConfidence", 0.40))
	var by_npc: Dictionary = state.community.get("npcFactKnowledge", {})
	for npc_id_variant in by_npc.keys():
		if spreads.size() >= remaining:
			break
		var npc_id := str(npc_id_variant)
		var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
		if float(npc.get("gossipTendency", 0.0)) < 0.45:
			continue
		var facts_for_npc: Dictionary = by_npc[npc_id]
		for fact_id_variant in facts_for_npc.keys():
			if spreads.size() >= remaining:
				break
			var fact_id := str(fact_id_variant)
			var knowledge: Dictionary = facts_for_npc[fact_id]
			if float(knowledge.get("confidence", 0.0)) < min_confidence:
				continue
			var hop_count := int(knowledge.get("hopCount", 0))
			if hop_count >= int(cfg.get("maxHops", 2)):
				continue
			spreads.append_array(_spread_from_source(
				state,
				npc_id,
				fact_id,
				float(knowledge.get("confidence", 0.8)),
				hop_count,
				remaining - spreads.size(),
			))
	return spreads


static func _spread_from_source(
	state: RunState,
	source_npc_id: String,
	fact_id: String,
	source_confidence: float,
	source_hop_count: int,
	limit: int,
) -> Array:
	if limit <= 0 or source_npc_id.is_empty() or fact_id.is_empty():
		return []
	var cfg: Dictionary = CommunitySocialEffects.rumor_propagation_config()
	var max_hops := int(cfg.get("maxHops", 2))
	if source_hop_count >= max_hops:
		return []

	var source_npc: Dictionary = CommunityGenerator.get_npc(state, source_npc_id)
	var spread_rate := float(cfg.get("baseSpreadRate", 0.38))
	spread_rate *= lerpf(0.75, 1.35, float(source_npc.get("gossipTendency", 0.35)))
	spread_rate *= float(cfg.get("supplyEdgeMultiplier", 1.25))

	var decay := float(cfg.get("confidenceDecayPerHop", 0.18))
	var next_confidence := maxf(0.2, source_confidence - decay)
	var next_hop := source_hop_count + 1
	var spreads: Array = []

	for neighbor_id_variant in supply_neighbor_npcs(state, source_npc_id):
		if spreads.size() >= limit:
			break
		var neighbor_id := str(neighbor_id_variant)
		if not _should_spread_to(state, neighbor_id, fact_id, next_confidence, spread_rate):
			continue
		var granted: Dictionary = CommunityKnowledgeService.grant_rumor_knowledge(
			state,
			neighbor_id,
			fact_id,
			source_npc_id,
			next_confidence,
			next_hop,
		)
		if not bool(granted.get("ok", false)):
			continue
		var spread_record := {
			"turn": state.turn,
			"factId": fact_id,
			"fromNpcId": source_npc_id,
			"toNpcId": neighbor_id,
			"confidence": next_confidence,
			"hopCount": next_hop,
		}
		spreads.append(spread_record)
		CommunityInteractionLedger.append_event(state, {
			"eventType": "rumor_spread",
			"npcId": neighbor_id,
			"payload": spread_record,
			"summary": "Rumor spread about %s" % fact_id,
		})
	return spreads


static func _should_spread_to(
	state: RunState,
	target_npc_id: String,
	fact_id: String,
	next_confidence: float,
	spread_rate: float,
) -> bool:
	var existing: Dictionary = CommunityKnowledgeService.npc_knowledge(state, target_npc_id, fact_id)
	if not existing.is_empty():
		if float(existing.get("confidence", 0.0)) >= next_confidence:
			return false
	var rng := SeededRng.new(state.run_seed + state.turn * 131 + hash(target_npc_id) + hash(fact_id))
	return rng.randf() <= spread_rate


static func _business_id_for_npc(state: RunState, npc_id: String) -> String:
	var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
	return str(npc.get("primaryBusinessId", ""))
