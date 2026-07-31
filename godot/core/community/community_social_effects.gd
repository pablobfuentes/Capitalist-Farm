# Loads social effect tables for community chat (Phase 2).
class_name CommunitySocialEffects
extends RefCounted

static var _root: Dictionary = {}
static var _loaded := false


static func load_effects() -> void:
	if _loaded:
		return
	CommunityConfig.load_config()
	var path := CommunityConfig.social_effects_path()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CommunitySocialEffects: missing %s" % path)
		_root = {}
		_loaded = true
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_root = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_loaded = true


static func root() -> Dictionary:
	load_effects()
	return _root


static func social_action(action: String) -> Dictionary:
	var actions: Dictionary = root().get("socialActions", {})
	return (actions.get(action, {}) as Dictionary).duplicate(true)


static func disclosure_weights() -> Dictionary:
	return root().get("disclosureWeights", {})


static func disclosure_default_threshold() -> float:
	return float(root().get("disclosureDefaultThreshold", 0.35))


static func max_delta_per_interaction() -> int:
	return int(root().get("maxDeltaPerInteraction", 8))


static func repetition_multiplier(band: String) -> float:
	var multipliers: Dictionary = root().get("repetitionMultipliers", {})
	return float(multipliers.get(band, 1.0))


static func sincerity_multiplier(level: String) -> float:
	var multipliers: Dictionary = root().get("sincerityMultipliers", {})
	return float(multipliers.get(level, 1.0))


static func respectfulness_multiplier(level: String) -> float:
	var multipliers: Dictionary = root().get("respectfulnessMultipliers", {})
	return float(multipliers.get(level, 1.0))


static func personal_relationship_weights() -> Dictionary:
	return root().get("personalRelationshipWeights", {})


static func dimension_range() -> Dictionary:
	return root().get("dimensionRange", {"min": -100, "max": 100})


static func rumor_propagation_config() -> Dictionary:
	return root().get("rumorPropagation", {})


static func promise_fulfillment_config() -> Dictionary:
	return root().get("promiseFulfillment", {})
