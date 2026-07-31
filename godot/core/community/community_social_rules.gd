# Deterministic social dimension changes from validated classifications (Community spec §9).
class_name CommunitySocialRules
extends RefCounted


static func apply_validated_turn(
	state: RunState,
	npc_id: String,
	validated: Dictionary,
	context: Dictionary = {},
) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var classification: Dictionary = validated.get("interaction_classification", {})
	var social_action := str(validated.get("social_action", "none"))
	var action_deltas: Dictionary = CommunitySocialEffects.social_action(social_action)

	var deltas: Dictionary = {}
	for key in action_deltas.keys():
		deltas[str(key)] = int(action_deltas[key])

	if social_action == "gift_offer":
		var gift: Variant = validated.get("gift", null)
		if gift is Dictionary:
			if bool(gift.get("preference_match", false)):
				_merge_deltas(deltas, CommunitySocialEffects.root().get("giftBonuses", {}).get("preference_match", {}))
			if bool(context.get("firstTimeGift", true)):
				_merge_deltas(deltas, CommunitySocialEffects.root().get("giftBonuses", {}).get("firstTime", {}))

	var repetition := str(classification.get("repetition", "new"))
	var sincerity := str(classification.get("sincerity", "medium"))
	var respectfulness := str(classification.get("respectfulness", "medium"))
	var multiplier := (
		CommunitySocialEffects.repetition_multiplier(repetition)
		* CommunitySocialEffects.sincerity_multiplier(sincerity)
		* CommunitySocialEffects.respectfulness_multiplier(respectfulness)
	)

	var max_delta := CommunitySocialEffects.max_delta_per_interaction()
	for key in deltas.keys():
		var scaled := int(round(float(deltas[key]) * multiplier))
		deltas[key] = clampi(scaled, -max_delta, max_delta)

	var social := CommunityState.get_social_state(state, npc_id)
	var dim_range: Dictionary = CommunitySocialEffects.dimension_range()
	var dim_min := int(dim_range.get("min", -100))
	var dim_max := int(dim_range.get("max", 100))

	for key in deltas.keys():
		if not social.has(key):
			continue
		social[key] = clampi(int(social.get(key, 0)) + int(deltas[key]), dim_min, dim_max)
	social["updatedTurn"] = state.turn
	social["personalRelationshipScore"] = summarize_personal_relationship(social)
	CommunityState.set_social_state(state, npc_id, social)

	return {
		"npcId": npc_id,
		"socialAction": social_action,
		"deltas": deltas,
		"multiplier": multiplier,
		"personalRelationshipScore": int(social.get("personalRelationshipScore", 0)),
	}


static func summarize_personal_relationship(social: Dictionary) -> int:
	var weights: Dictionary = CommunitySocialEffects.personal_relationship_weights()
	var score := 0.0
	for key in weights.keys():
		var weight := float(weights[key])
		var value := float(social.get(str(key), 0))
		score += value * weight
	var normalized := int(round(score / 20.0))
	var range_cfg: Dictionary = CommunityConfig.personal_relationship_range()
	return clampi(
		normalized,
		int(range_cfg.get("min", -5)),
		int(range_cfg.get("max", 5)),
	)


static func apply_turn_decay(state: RunState) -> void:
	CommunityState.ensure_initialized(state)
	var decay := int(CommunitySocialEffects.root().get("gratitudeDecayPerTurn", 1))
	if decay <= 0:
		return
	var social_states: Dictionary = state.community.get("socialStates", {})
	for npc_id_key in social_states.keys():
		var npc_id := str(npc_id_key)
		var social: Dictionary = social_states[npc_id]
		if int(social.get("gratitude", 0)) > 0:
			social["gratitude"] = maxi(0, int(social.get("gratitude", 0)) - decay)
			social["personalRelationshipScore"] = summarize_personal_relationship(social)
			social_states[npc_id] = social
	state.community["socialStates"] = social_states


static func _merge_deltas(target: Dictionary, extra: Variant) -> void:
	if typeof(extra) != TYPE_DICTIONARY:
		return
	for key in (extra as Dictionary).keys():
		var dim := str(key)
		target[dim] = int(target.get(dim, 0)) + int(extra[dim])
