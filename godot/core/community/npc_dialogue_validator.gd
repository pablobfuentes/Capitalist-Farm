# Validates structured NPC chat responses before state changes (Community spec §10.4, §14).
class_name NpcDialogueValidator
extends RefCounted

const _Schema := preload("res://core/community/npc_dialogue_schema.gd")


static func validate(raw: Variant, context: Dictionary = {}) -> Dictionary:
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	if typeof(raw) != TYPE_DICTIONARY:
		return _result(false, _Schema.empty_response(), errors, warnings, ["root_not_object"])

	var response: Dictionary = raw
	var normalized := _Schema.empty_response()

	var dialogue := str(response.get("dialogue", "")).strip_edges()
	if dialogue.is_empty():
		errors.append("missing_dialogue")
	elif dialogue.length() > _Schema.MAX_DIALOGUE_CHARS:
		errors.append("dialogue_too_long")
	normalized["dialogue"] = dialogue

	var tone := str(response.get("tone", "neutral"))
	if tone not in _Schema.TONES:
		errors.append("invalid_tone")
		tone = "neutral"
	normalized["tone"] = tone

	var social_action := str(response.get("social_action", "none"))
	if social_action not in _Schema.SOCIAL_ACTIONS:
		errors.append("invalid_social_action")
		social_action = "none"
	normalized["social_action"] = social_action

	var allowed_fact_ids: Array = _string_array(context.get("allowedFactIds", []))
	var disclosures := _validate_disclosures(response.get("fact_disclosures", []), allowed_fact_ids, errors, warnings)
	normalized["fact_disclosures"] = disclosures

	normalized["gift"] = _validate_gift(response.get("gift", null), errors)
	normalized["promise_proposal"] = _validate_promise_proposal(response.get("promise_proposal", null), errors, context)

	var classification: Dictionary = _validate_classification(response.get("interaction_classification", {}), errors)
	normalized["interaction_classification"] = classification

	var proposals := _validate_new_fact_proposals(response.get("new_fact_proposals", []), errors, warnings)
	normalized["new_fact_proposals"] = proposals

	var ok := errors.is_empty()
	return _result(ok, normalized, errors, warnings, [])


static func _validate_disclosures(
	raw: Variant,
	allowed_fact_ids: Array,
	errors: PackedStringArray,
	warnings: PackedStringArray,
) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		if raw != null:
			errors.append("fact_disclosures_not_array")
		return out
	for item_variant in raw:
		if typeof(item_variant) != TYPE_DICTIONARY:
			errors.append("invalid_fact_disclosure_entry")
			continue
		var item: Dictionary = item_variant
		var fact_id := str(item.get("fact_id", ""))
		if fact_id.is_empty():
			errors.append("fact_disclosure_missing_id")
			continue
		if not allowed_fact_ids.is_empty() and fact_id not in allowed_fact_ids:
			warnings.append("fact_disclosure_not_allowed:%s" % fact_id)
			continue
		var mode := str(item.get("mode", "direct"))
		if mode not in _Schema.DISCLOSURE_MODES:
			errors.append("invalid_disclosure_mode")
			mode = "direct"
		var confidence_language := str(item.get("confidence_language", "likely"))
		if confidence_language not in _Schema.CONFIDENCE_LANGUAGE:
			errors.append("invalid_confidence_language")
			confidence_language = "likely"
		out.append({
			"fact_id": fact_id,
			"mode": mode,
			"confidence_language": confidence_language,
		})
	return out


static func _validate_gift(raw: Variant, errors: PackedStringArray) -> Variant:
	if raw == null:
		return null
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("gift_not_object")
		return null
	var gift: Dictionary = raw
	var concept := str(gift.get("concept", "")).strip_edges()
	if concept.length() > _Schema.MAX_GIFT_CONCEPT_CHARS:
		errors.append("gift_concept_too_long")
	return {
		"concept": concept,
		"accepted": bool(gift.get("accepted", false)),
		"preference_match": bool(gift.get("preference_match", false)),
	}


static func _validate_promise_proposal(raw: Variant, errors: PackedStringArray, context: Dictionary) -> Variant:
	if raw == null:
		return null
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("promise_proposal_not_object")
		return null
	var proposal: Dictionary = raw
	var promise_type := str(proposal.get("type", ""))
	if promise_type.is_empty():
		errors.append("promise_proposal_missing_type")
		return null
	var allowed_types: Array = _string_array(context.get("allowedPromiseTypes", CommunityConfig.promise_type_ids()))
	if not allowed_types.is_empty() and promise_type not in allowed_types:
		errors.append("promise_type_not_allowed:%s" % promise_type)
		return null
	var subject_id: Variant = proposal.get("subject_id", null)
	if subject_id != null:
		subject_id = str(subject_id)
	var allowed_entity_ids: Array = _string_array(context.get("allowedEntityIds", []))
	if subject_id != null and not str(subject_id).is_empty() and not allowed_entity_ids.is_empty():
		if str(subject_id) not in allowed_entity_ids:
			errors.append("promise_subject_not_allowed:%s" % str(subject_id))
			return null
	var deadline_turn: Variant = proposal.get("deadline_turn", null)
	if deadline_turn != null:
		deadline_turn = int(deadline_turn)
	var duration_turns: Variant = proposal.get("duration_turns", null)
	if duration_turns != null:
		duration_turns = int(duration_turns)
	var normalized := {
		"type": promise_type,
		"subject_id": subject_id,
		"deadline_turn": deadline_turn,
	}
	for optional_key in ["duration_turns", "policy_id", "template_id", "fact_id", "capacity_percent", "amount_due"]:
		if proposal.has(optional_key):
			var value: Variant = proposal[optional_key]
			if optional_key == "duration_turns" and duration_turns != null:
				normalized[optional_key] = duration_turns
			elif optional_key == "capacity_percent":
				normalized[optional_key] = float(value)
			elif optional_key == "amount_due":
				normalized[optional_key] = int(value)
			elif value != null and str(value) != "":
				normalized[optional_key] = str(value)
	return normalized


static func _validate_classification(raw: Variant, errors: PackedStringArray) -> Dictionary:
	var defaults: Dictionary = _Schema.empty_response()["interaction_classification"]
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("interaction_classification_not_object")
		return defaults.duplicate(true)
	var classification: Dictionary = raw
	var sincerity := str(classification.get("sincerity", "medium"))
	if sincerity not in _Schema.SINCERITY_LEVELS:
		errors.append("invalid_sincerity")
		sincerity = "medium"
	var respectfulness := str(classification.get("respectfulness", "medium"))
	if respectfulness not in _Schema.RESPECTFULNESS_LEVELS:
		errors.append("invalid_respectfulness")
		respectfulness = "medium"
	var manipulation_signal := str(classification.get("manipulation_signal", "none"))
	if manipulation_signal not in _Schema.MANIPULATION_SIGNALS:
		errors.append("invalid_manipulation_signal")
		manipulation_signal = "none"
	var repetition := str(classification.get("repetition", "new"))
	if repetition not in _Schema.REPETITION_BANDS:
		errors.append("invalid_repetition")
		repetition = "new"
	return {
		"sincerity": sincerity,
		"respectfulness": respectfulness,
		"manipulation_signal": manipulation_signal,
		"repetition": repetition,
	}


static func _validate_new_fact_proposals(raw: Variant, errors: PackedStringArray, warnings: PackedStringArray) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		if raw != null:
			errors.append("new_fact_proposals_not_array")
		return out
	for item_variant in raw:
		if typeof(item_variant) != TYPE_DICTIONARY:
			errors.append("invalid_new_fact_proposal_entry")
			continue
		var item: Dictionary = item_variant
		var category := str(item.get("category", ""))
		if category != "atmospheric":
			errors.append("new_fact_proposal_invalid_category")
			continue
		var text := str(item.get("text", "")).strip_edges()
		if text.is_empty():
			errors.append("new_fact_proposal_missing_text")
			continue
		if text.length() > _Schema.MAX_NEW_FACT_PROPOSAL_CHARS:
			warnings.append("new_fact_proposal_truncated")
			text = text.substr(0, _Schema.MAX_NEW_FACT_PROPOSAL_CHARS)
		out.append({"category": category, "text": text})
	return out


static func _string_array(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		out.append(str(item))
	return out


static func _result(
	ok: bool,
	normalized: Dictionary,
	errors: PackedStringArray,
	warnings: PackedStringArray,
	rejected_fields: Array,
) -> Dictionary:
	return {
		"ok": ok,
		"normalized": normalized,
		"errors": errors,
		"warnings": warnings,
		"rejectedFields": rejected_fields,
	}
