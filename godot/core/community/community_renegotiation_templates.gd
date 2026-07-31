# Authored client renegotiation templates (8.3 §7).
class_name CommunityRenegotiationTemplates
extends RefCounted

const TEMPLATES_PATH := "res://data/community_renegotiation_templates.json"

static var _root: Dictionary = {}
static var _loaded := false


static func load_templates() -> void:
	if _loaded:
		return
	_root = _read_json(TEMPLATES_PATH)
	_loaded = true


static func major_client_dependence_min() -> float:
	load_templates()
	return float(_root.get("majorClientDependenceMin", 0.55))


static func trigger_delay_turns() -> int:
	load_templates()
	return int(_root.get("triggerDelayTurns", 1))


static func default_duration_turns() -> int:
	load_templates()
	return int(_root.get("defaultDurationTurns", 3))


static func contract_health_band(reliability: float) -> String:
	if reliability >= 0.75:
		return "strong"
	if reliability >= 0.55:
		return "neutral"
	return "strained"


static func relationship_band(score: int) -> String:
	if score >= 3:
		return "good"
	if score <= -3:
		return "bad"
	return "neutral"


static func pick_template(reliability: float, personal_score: int) -> Dictionary:
	load_templates()
	var health := contract_health_band(reliability)
	var relationship := relationship_band(personal_score)
	var templates: Array = _root.get("templates", [])
	for template_variant in templates:
		if typeof(template_variant) != TYPE_DICTIONARY:
			continue
		var template: Dictionary = template_variant
		if str(template.get("contractHealth", "")) == health and str(template.get("relationshipBand", "")) == relationship:
			return template.duplicate(true)
	for template_variant in templates:
		if typeof(template_variant) != TYPE_DICTIONARY:
			continue
		var template: Dictionary = template_variant
		if str(template.get("contractHealth", "")) == health:
			return template.duplicate(true)
	if templates.size() > 0 and typeof(templates[0]) == TYPE_DICTIONARY:
		return (templates[0] as Dictionary).duplicate(true)
	return {}


static func schedule_renegotiation(
	state: RunState,
	player_business: BusinessInstance,
	contract: Dictionary,
) -> Dictionary:
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state):
		return {}

	var npc_id := str(contract.get("counterpartNpcId", ""))
	var personal_score := CommunityState.personal_relationship_score(state, npc_id)
	var template: Dictionary = pick_template(float(contract.get("reliability", 0.7)), personal_score)
	if template.is_empty():
		return {}

	var counterpart: Dictionary = CommunityGenerator.get_business(
		state,
		str(contract.get("counterpartBusinessId", "")),
	)
	var counterpart_name := str(counterpart.get("displayName", "A major client"))
	var duration := int(template.get("durationTurns", default_duration_turns()))
	var summary_template := str(template.get("summaryTemplate", "%s requests a contract review."))
	var summary := summary_template % [counterpart_name, duration] if "%" in summary_template else summary_template

	var pending: Array = state.community.get("pendingClientRenegotiations", [])
	if typeof(pending) != TYPE_ARRAY:
		pending = []

	var event := {
		"id": CommunityState.next_event_id(state),
		"status": "pending",
		"dueTurn": state.turn + trigger_delay_turns(),
		"playerBusinessId": player_business.id,
		"playerBusinessName": player_business.name,
		"contractId": str(contract.get("id", "")),
		"counterpartBusinessId": str(contract.get("counterpartBusinessId", "")),
		"counterpartNpcId": npc_id,
		"templateId": str(template.get("id", "")),
		"contractHealth": contract_health_band(float(contract.get("reliability", 0.7))),
		"relationshipBand": relationship_band(personal_score),
		"personalRelationshipScore": personal_score,
		"capacityIncreasePct": float(template.get("capacityIncreasePct", 0.0)),
		"durationTurns": duration,
		"strictCovenants": bool(template.get("strictCovenants", false)),
		"terminationRisk": bool(template.get("terminationRisk", false)),
		"summary": summary,
		"createdTurn": state.turn,
	}
	pending.append(event)
	state.community["pendingClientRenegotiations"] = pending
	return event.duplicate(true)


static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CommunityRenegotiationTemplates: missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
