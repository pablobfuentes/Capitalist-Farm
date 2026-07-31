# Unified negotiation notebook — investigate + community chat intel (8.3 §3).
class_name CommunityNotebookService
extends RefCounted

const _Diligence := preload("res://core/systems/diligence_system.gd")
const _Archetypes := preload("res://core/content/negotiation_archetypes.gd")
const _V2Preview := preload("res://core/systems/negotiation_v2_preview.gd")


static func record_investigate_entries(state: RunState, opp: Dictionary) -> Array:
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, state):
		return []

	var cp: Dictionary = opp.get("counterparty", {})
	var asking: int = int(opp.get("price", 0))
	var rng := SeededRng.new(state.run_seed + state.turn * 8803 + asking)
	var entries: Array = []
	var opp_id := str(opp.get("id", ""))
	var related_npc_id := str(cp.get("communityNpcId", ""))

	var diligence: Dictionary = _Diligence.ensure_seller_diligence(cp, asking, rng)
	if not diligence.is_empty():
		entries.append(_add_entry(state, {
			"source": "investigate",
			"category": "moved_most_by",
			"displaySummary": str(diligence.get("motivatorLabel", "")),
			"relatedOpportunityId": opp_id,
			"relatedNpcId": related_npc_id,
			"discoveryTurn": state.turn,
		}))
		entries.append(_add_entry(state, {
			"source": "investigate",
			"category": "tactic",
			"displaySummary": "Why selling now: %s" % str(diligence.get("sellReason", "")),
			"relatedOpportunityId": opp_id,
			"relatedNpcId": related_npc_id,
			"discoveryTurn": state.turn,
		}))
		entries.append(_add_entry(state, {
			"source": "investigate",
			"category": "floor_hint",
			"displaySummary": str(diligence.get("reach", "")),
			"relatedOpportunityId": opp_id,
			"relatedNpcId": related_npc_id,
			"discoveryTurn": state.turn,
		}))
		var hidden := str(diligence.get("hiddenNote", "")).strip_edges()
		if not hidden.is_empty():
			entries.append(_add_entry(state, {
				"source": "investigate",
				"category": "tactic",
				"displaySummary": "Hidden leverage: %s" % hidden,
				"relatedOpportunityId": opp_id,
				"relatedNpcId": related_npc_id,
				"discoveryTurn": state.turn,
			}))

	var preview_raw: Variant = opp.get("v2Preview")
	if preview_raw is Dictionary and not (preview_raw as Dictionary).is_empty():
		var keywords: Array = (preview_raw as Dictionary).get("keywords", [])
		for kw in keywords:
			entries.append(_add_entry(state, {
				"source": "investigate",
				"category": "phrase_unlock",
				"displaySummary": "Phrase unlock: \"%s\"" % str(kw),
				"relatedOpportunityId": opp_id,
				"relatedNpcId": related_npc_id,
				"discoveryTurn": state.turn,
			}))

	var arch: Dictionary = _Archetypes.get_archetype(str(cp.get("archetypeId", "")))
	for tip_variant in arch.get("tips", []):
		entries.append(_add_entry(state, {
			"source": "investigate",
			"category": "tactic",
			"displaySummary": str(tip_variant),
			"relatedOpportunityId": opp_id,
			"relatedNpcId": related_npc_id,
			"discoveryTurn": state.turn,
		}))

	return entries


static func record_chat_discovery(
	state: RunState,
	npc_id: String,
	fact_id: String,
	display_summary: String,
	confirmation_state: String,
) -> Dictionary:
	if display_summary.is_empty():
		var fact: Dictionary = CommunityKnowledgeService.get_fact(state, fact_id)
		var payload: Dictionary = fact.get("canonicalPayload", {})
		display_summary = str(payload.get("summary", fact_id))

	var fact: Dictionary = CommunityKnowledgeService.get_fact(state, fact_id)
	var category := _category_for_fact(fact)
	return _add_entry(state, {
		"source": "chat",
		"category": category,
		"factId": fact_id,
		"displaySummary": display_summary,
		"relatedNpcId": npc_id,
		"confirmationState": confirmation_state,
		"discoveryTurn": state.turn,
		"negotiationTags": fact.get("leverageTags", []),
	})


static func record_renegotiation_event(state: RunState, event: Dictionary) -> Dictionary:
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, state):
		return {}
	return _add_entry(state, {
		"source": "chat",
		"category": "supplier_client",
		"displaySummary": str(event.get("summary", "Client renegotiation")),
		"relatedNpcId": str(event.get("counterpartNpcId", "")),
		"relatedPlayerBusinessId": str(event.get("playerBusinessId", "")),
		"discoveryTurn": state.turn,
		"negotiationTags": ["supplier_client", "renegotiation"],
		"metadata": {
			"templateId": str(event.get("templateId", "")),
			"capacityIncreasePct": float(event.get("capacityIncreasePct", 0.0)),
			"durationTurns": int(event.get("durationTurns", 0)),
			"terminationRisk": bool(event.get("terminationRisk", false)),
		},
	})


static func record_promise_event(state: RunState, promise: Dictionary, phase: String) -> Dictionary:
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, state):
		return {}
	var promise_type := str(promise.get("type", ""))
	var def: Dictionary = CommunityConfig.promise_type_def(promise_type)
	var label := str(def.get("label", promise_type))
	var status := str(promise.get("status", phase))
	var summary := "Promise with %s: %s" % [label, status]
	if not str(promise.get("outcomeNote", "")).is_empty():
		summary += " — %s" % str(promise.get("outcomeNote", ""))
	return _add_entry(state, {
		"source": "chat",
		"category": "preference",
		"displaySummary": summary,
		"relatedNpcId": str(promise.get("npcId", "")),
		"factId": str(promise.get("factId", promise.get("subjectId", ""))),
		"discoveryTurn": state.turn,
		"negotiationTags": ["promise", status],
		"metadata": {
			"promiseId": str(promise.get("id", "")),
			"promiseType": promise_type,
			"status": status,
			"deadlineTurn": int(promise.get("deadlineTurn", 0)),
		},
	})


static func entries_for_negotiation(state: RunState, negotiation: Dictionary) -> Array:
	if state == null:
		return []
	CommunityState.ensure_initialized(state)
	var ctx: Dictionary = negotiation.get("context", {})
	var opp: Dictionary = ctx.get("opp", {}) if typeof(ctx.get("opp")) == TYPE_DICTIONARY else {}
	var opp_id := str(opp.get("id", ctx.get("opportunityId", "")))
	var cp: Dictionary = negotiation.get("counterparty", {})
	var related_npc := str(cp.get("communityNpcId", ""))
	var template_id := str(opp.get("templateId", ""))

	var matched: Array = []
	for entry_variant in state.community.get("notebookEntries", []):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if _entry_matches_negotiation(entry, opp_id, related_npc, template_id):
			matched.append(entry.duplicate(true))
	return matched


static func format_community_intel_block(state: RunState, negotiation: Dictionary) -> String:
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, state):
		return ""

	var entries := entries_for_negotiation(state, negotiation)
	if entries.is_empty():
		return ""

	var investigate_lines: PackedStringArray = []
	var chat_lines: PackedStringArray = []
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		var line := "• %s" % str(entry.get("displaySummary", ""))
		var source := str(entry.get("source", ""))
		if source == "investigate":
			investigate_lines.append(line)
		elif source == "chat":
			var conf := str(entry.get("confirmationState", ""))
			if not conf.is_empty() and conf != "confirmed":
				line += " (%s)" % conf
			chat_lines.append(line)

	var sections: PackedStringArray = []
	if not investigate_lines.is_empty():
		sections.append("NOTEBOOK — INVESTIGATE")
		sections.append_array(investigate_lines)
	if not chat_lines.is_empty():
		if not sections.is_empty():
			sections.append("")
		sections.append("NOTEBOOK — COMMUNITY INTEL")
		sections.append_array(chat_lines)
	return "\n".join(sections)


static func format_diligence_with_notebook(state: RunState, base_text: String, negotiation: Dictionary) -> String:
	var block := format_community_intel_block(state, negotiation)
	if block.is_empty():
		return base_text
	if base_text.is_empty():
		return block
	return "%s\n\n%s" % [base_text, block]


static func _add_entry(state: RunState, entry: Dictionary) -> Dictionary:
	return CommunityState.add_notebook_entry(state, entry)


static func _category_for_fact(fact: Dictionary) -> String:
	var tags: Array = fact.get("leverageTags", [])
	if "preference" in tags:
		return "preference"
	if "supplier_client" in tags:
		return "supplier_client"
	if "leverage" in tags:
		return "leverage"
	if "fear" in tags:
		return "fear"
	if str(fact.get("factType", "")) == "operational":
		return "operational"
	return "operational"


static func _entry_matches_negotiation(
	entry: Dictionary,
	opp_id: String,
	related_npc: String,
	template_id: String,
) -> bool:
	if not opp_id.is_empty() and str(entry.get("relatedOpportunityId", "")) == opp_id:
		return true
	if not related_npc.is_empty() and str(entry.get("relatedNpcId", "")) == related_npc:
		return true
	if not template_id.is_empty() and str(entry.get("relatedTemplateId", "")) == template_id:
		return true
	return false
