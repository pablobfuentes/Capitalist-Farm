# Negotiation v2 bridge — personal relationship gauge + chat intel leverage (8.3 §1, §8).
class_name CommunityNegotiationBridge
extends RefCounted

const _V2Data := preload("res://core/systems/negotiation_v2_data.gd")


static func enrich_counterparty(state: RunState, counterparty: Dictionary, opp: Dictionary = {}) -> void:
	if state == null or typeof(counterparty) != TYPE_DICTIONARY:
		return
	CommunityState.ensure_initialized(state)
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state):
		return

	var npc_id := str(counterparty.get("communityNpcId", ""))
	if npc_id.is_empty():
		npc_id = resolve_community_npc_id(state, opp)
	if not npc_id.is_empty():
		counterparty["communityNpcId"] = npc_id
		var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
		if not npc.is_empty():
			var npc_name := str(npc.get("displayName", ""))
			if not npc_name.is_empty():
				counterparty["npcName"] = npc_name
			var species_id := str(npc.get("speciesId", ""))
			if not species_id.is_empty():
				counterparty["speciesId"] = species_id

	if CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, state):
		counterparty["leverageScore"] = leverage_score_from_intel(state, opp, counterparty)


static func resolve_community_npc_id(state: RunState, opp: Dictionary) -> String:
	if state == null or opp.is_empty():
		return ""
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state):
		return ""

	var parcel_id := str(opp.get("parcelId", ""))
	if parcel_id.is_empty():
		parcel_id = parcel_id_for_opportunity(state, str(opp.get("id", "")))

	var district_id := str(opp.get("districtId", ""))
	if district_id.is_empty():
		district_id = CommunityConfig.mvp_district_id()

	if not parcel_id.is_empty():
		var business: Dictionary = CommunityGenerator.get_business_for_parcel(state, parcel_id, district_id)
		if not business.is_empty():
			return str(business.get("ownerNpcId", ""))

	var template_id := str(opp.get("templateId", ""))
	if not template_id.is_empty():
		return npc_id_for_template(state, district_id, template_id)
	return ""


static func parcel_id_for_opportunity(state: RunState, opportunity_id: String) -> String:
	if state == null or opportunity_id.is_empty():
		return ""
	for parcel_id_variant in state.parcel_assignments.keys():
		var parcel_id := str(parcel_id_variant)
		var assignment: Dictionary = state.parcel_assignments.get(parcel_id, {})
		if str(assignment.get("opportunity_id", "")) == opportunity_id:
			return parcel_id
	return ""


static func npc_id_for_template(state: RunState, district_id: String, template_id: String) -> String:
	var district_payload: Dictionary = state.community.get("districts", {}).get(district_id, {})
	var businesses: Dictionary = district_payload.get("businesses", {})
	for business_variant in businesses.values():
		if typeof(business_variant) != TYPE_DICTIONARY:
			continue
		var business: Dictionary = business_variant
		if str(business.get("templateId", "")) == template_id:
			return str(business.get("ownerNpcId", ""))
	return ""


static func personal_relationship_gauge_adj(state: RunState, npc_id: String, species_id: String) -> int:
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_NEGOTIATION_PERSONAL_RELATIONSHIP, state):
		return 0
	if npc_id.is_empty():
		return 0
	var social: Dictionary = CommunityState.get_social_state(state, npc_id)
	var score := int(social.get("personalRelationshipScore", 0))
	var weight := CommunityConfig.species_personal_gauge_weight(species_id)
	return int(round(float(score) * float(weight)))


static func relationship_qualitative_label(score: int) -> String:
	if score >= 3:
		return "Trusted"
	if score >= 1:
		return "Friendly"
	if score <= -3:
		return "Wary"
	if score <= -1:
		return "Cool"
	return "Stranger"


static func leverage_score_from_intel(state: RunState, opp: Dictionary, counterparty: Dictionary) -> float:
	var base := float(counterparty.get("leverageScore", 0.5))
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, state):
		return clampf(base, 0.0, 1.0)

	var npc_id := str(counterparty.get("communityNpcId", ""))
	var opp_id := str(opp.get("id", ""))
	var template_id := str(opp.get("templateId", ""))
	var boost := 0.0

	for entry_variant in state.community.get("notebookEntries", []):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("source", "")) != "chat":
			continue
		if not _notebook_entry_matches(entry, opp_id, npc_id, template_id):
			continue
		boost += _leverage_boost_for_entry(entry)

	return clampf(base + boost, 0.0, 1.0)


static func apply_profile_fields(state: RunState, counterparty: Dictionary, profile: Dictionary) -> Dictionary:
	var npc_id := str(counterparty.get("communityNpcId", ""))
	var species_id := str(profile.get("speciesId", counterparty.get("speciesId", "hen")))
	var personal_adj := personal_relationship_gauge_adj(state, npc_id, species_id)
	var social: Dictionary = CommunityState.get_social_state(state, npc_id) if not npc_id.is_empty() else {}
	var score := int(social.get("personalRelationshipScore", 0))
	var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id) if not npc_id.is_empty() else {}

	profile["personalRelationshipGaugeAdj"] = personal_adj
	profile["personalRelationshipLabel"] = relationship_qualitative_label(score)
	profile["personalRelationshipNpcId"] = npc_id
	profile["personalRelationshipNpcName"] = str(npc.get("displayName", ""))
	profile["communityIntelLeverageScore"] = float(counterparty.get("leverageScore", 0.5))
	return profile


static func format_modifier_snapshot(state: RunState, v2: Dictionary, counterparty: Dictionary) -> String:
	if v2.is_empty():
		return ""
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state):
		return ""

	var lines: PackedStringArray = ["DEAL MOMENTUM — STARTING MODIFIERS"]
	lines.append("Reputation: %s (%+d)" % [
		str(v2.get("reputationTier", "—")),
		int(v2.get("reputationGaugeAdj", 0)),
	])
	lines.append("Deal memory: %+d" % int(v2.get("memoryGaugeAdj", 0)))
	lines.append("Leverage (%s): %+d" % [
		str(v2.get("leverageLabel", "Balanced")),
		int(v2.get("leverageGaugeAdj", 0)),
	])

	if CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_NEGOTIATION_PERSONAL_RELATIONSHIP, state):
		var npc_name := str(v2.get("personalRelationshipNpcName", "")).strip_edges()
		var rel_label := str(v2.get("personalRelationshipLabel", "Stranger"))
		var personal_adj := int(v2.get("personalRelationshipGaugeAdj", 0))
		if npc_name.is_empty():
			npc_name = "Seller"
		lines.append("Personal relationship (%s): %s (%+d)" % [npc_name, rel_label, personal_adj])
	elif int(v2.get("personalRelationshipGaugeAdj", 0)) != 0:
		lines.append("Personal relationship: %+d" % int(v2.get("personalRelationshipGaugeAdj", 0)))

	if CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, state):
		var intel_score := float(v2.get("communityIntelLeverageScore", counterparty.get("leverageScore", 0.5)))
		if absf(intel_score - 0.5) > 0.01:
			lines.append("Community intel leverage score: %.2f" % intel_score)

	lines.append("Starting gauge: %d" % int(v2.get("gaugeStart", _V2Data.GAUGE_BASE)))
	return "\n".join(lines)


static func _notebook_entry_matches(
	entry: Dictionary,
	opp_id: String,
	npc_id: String,
	template_id: String,
) -> bool:
	if not opp_id.is_empty() and str(entry.get("relatedOpportunityId", "")) == opp_id:
		return true
	if not npc_id.is_empty() and str(entry.get("relatedNpcId", "")) == npc_id:
		return true
	if not template_id.is_empty() and str(entry.get("relatedTemplateId", "")) == template_id:
		return true
	return false


static func _leverage_boost_for_entry(entry: Dictionary) -> float:
	var category := str(entry.get("category", ""))
	var boost := 0.0
	match category:
		"leverage", "supplier_client":
			boost = 0.08
		"operational":
			boost = 0.05
		"preference", "fear":
			boost = 0.03
		_:
			boost = 0.02

	var conf := str(entry.get("confirmationState", "confirmed"))
	if conf == "rumored":
		boost *= 0.5
	elif conf == "supported":
		boost *= 0.75
	return boost
