# Serializable community state on RunState (8.3 Phase 0).
class_name CommunityState
extends RefCounted

const EVENT_COUNTER_KEY := "nextEventSequence"
const PROMISE_COUNTER_KEY := "nextPromiseSequence"
const SESSION_COUNTER_KEY := "nextSessionSequence"


static func empty_dict(run_seed: int) -> Dictionary:
	return {
		"worldId": CommunityIds.world_id(run_seed),
		"generatorVersion": CommunityConfig.generator_version(),
		"districts": {},
		"npcs": {},
		"facts": {},
		"socialStates": {},
		"interactionEvents": [],
		"notebookEntries": [],
		"promises": [],
		"activeChatSessions": {},
		"npcFactKnowledge": {},
		"playerFactKnowledge": {},
		"conversationSummaries": {},
		"playerSupplyContracts": [],
		"playerBusinessLinks": {},
		"pendingClientRenegotiations": [],
		"activeClientRenegotiations": [],
		"pendingRumorSeeds": [],
		"rumorSpreadLog": [],
		"featureFlags": CommunityConfig.feature_flags().duplicate(true),
		EVENT_COUNTER_KEY: 1,
		PROMISE_COUNTER_KEY: 1,
		SESSION_COUNTER_KEY: 1,
	}


static func ensure_initialized(state: RunState) -> void:
	if state == null:
		return
	CommunityConfig.load_config()
	if state.community_schema_version <= 0:
		state.community_schema_version = CommunityMigration.CURRENT_SCHEMA_VERSION
	if state.community.is_empty():
		state.community = empty_dict(state.run_seed)
	CommunityFeatureFlags.apply_run_defaults(state)
	if state.community_schema_version < CommunityMigration.CURRENT_SCHEMA_VERSION:
		state.community = CommunityMigration.migrate_community_block(
			state.community,
			state.community_schema_version,
			state.run_seed,
		)
		state.community_schema_version = CommunityMigration.CURRENT_SCHEMA_VERSION


static func next_event_id(state: RunState) -> String:
	ensure_initialized(state)
	var seq := int(state.community.get(EVENT_COUNTER_KEY, 1))
	state.community[EVENT_COUNTER_KEY] = seq + 1
	return CommunityIds.interaction_event_id(seq)


static func next_promise_id(state: RunState) -> String:
	ensure_initialized(state)
	var seq := int(state.community.get(PROMISE_COUNTER_KEY, 1))
	state.community[PROMISE_COUNTER_KEY] = seq + 1
	return CommunityIds.promise_id(seq)


static func get_social_state(state: RunState, npc_id: String) -> Dictionary:
	ensure_initialized(state)
	var social_states: Dictionary = state.community.get("socialStates", {})
	if typeof(social_states) != TYPE_DICTIONARY:
		social_states = {}
		state.community["socialStates"] = social_states
	if not social_states.has(npc_id):
		social_states[npc_id] = default_social_state(npc_id)
	return (social_states[npc_id] as Dictionary).duplicate(true)


static func default_social_state(npc_id: String) -> Dictionary:
	var neutral := int(CommunityConfig.personal_relationship_range().get("neutral", 0))
	return {
		"npcId": npc_id,
		"familiarity": 0,
		"warmth": 0,
		"trust": 0,
		"businessRespect": 0,
		"gratitude": 0,
		"resentment": 0,
		"suspicion": 0,
		"personalRelationshipScore": neutral,
		"updatedTurn": 0,
	}


static func personal_relationship_score(state: RunState, npc_id: String) -> int:
	var social := get_social_state(state, npc_id)
	var range_cfg: Dictionary = CommunityConfig.personal_relationship_range()
	return clampi(
		int(social.get("personalRelationshipScore", range_cfg.get("neutral", 0))),
		int(range_cfg.get("min", -5)),
		int(range_cfg.get("max", 5)),
	)


static func add_notebook_entry(state: RunState, entry: Dictionary) -> Dictionary:
	ensure_initialized(state)
	var entries: Array = state.community.get("notebookEntries", [])
	if typeof(entries) != TYPE_ARRAY:
		entries = []
	var normalized := entry.duplicate(true)
	if not normalized.has("id"):
		normalized["id"] = CommunityIds.notebook_entry_id(
			str(normalized.get("source", "unknown")),
			str(normalized.get("factId", "misc")),
			int(state.turn),
		)
	entries.append(normalized)
	state.community["notebookEntries"] = entries
	return normalized


static func notebook_entries_for(state: RunState, source: String = "") -> Array:
	ensure_initialized(state)
	var entries: Array = state.community.get("notebookEntries", [])
	if source.is_empty():
		return entries.duplicate(true)
	var filtered: Array = []
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("source", "")) == source:
			filtered.append(entry.duplicate(true))
	return filtered


static func set_social_state(state: RunState, npc_id: String, social: Dictionary) -> void:
	ensure_initialized(state)
	var social_states: Dictionary = state.community.get("socialStates", {})
	if typeof(social_states) != TYPE_DICTIONARY:
		social_states = {}
	social_states[npc_id] = social.duplicate(true)
	state.community["socialStates"] = social_states

