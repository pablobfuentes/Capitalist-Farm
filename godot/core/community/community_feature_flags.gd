# Runtime feature flags for community mechanic (8.3 Phase 0).
class_name CommunityFeatureFlags
extends RefCounted

const FLAG_COMMUNITY_CHAT := "community_chat"
const FLAG_COMMUNITY_GENERATION := "community_generation"
const FLAG_NEGOTIATION_PERSONAL_RELATIONSHIP := "negotiation_personal_relationship"
const FLAG_NOTEBOOK_INTEL := "notebook_intel"
const FLAG_RUMOR_PROPAGATION := "rumor_propagation"
const FLAG_PROMISE_FULFILLMENT := "promise_fulfillment"

static var _overrides: Dictionary = {}


static func reset_overrides() -> void:
	_overrides.clear()


static func set_override(flag: String, enabled: bool) -> void:
	_overrides[flag] = enabled


static func is_enabled(flag: String, state: RunState = null) -> bool:
	if _overrides.has(flag):
		return bool(_overrides[flag])
	if state != null and typeof(state.community.get("featureFlags", {})) == TYPE_DICTIONARY:
		var run_flags: Dictionary = state.community["featureFlags"]
		if run_flags.has(flag):
			return bool(run_flags[flag])
	CommunityConfig.load_config()
	var defaults: Dictionary = CommunityConfig.feature_flags()
	return bool(defaults.get(flag, false))


static func apply_run_defaults(state: RunState) -> void:
	if state == null:
		return
	if typeof(state.community.get("featureFlags", null)) != TYPE_DICTIONARY:
		state.community["featureFlags"] = CommunityConfig.feature_flags().duplicate(true)
