# Loads community mechanic configuration (8.3 Phase 0).
class_name CommunityConfig
extends RefCounted

const CONFIG_PATH := "res://data/community_config.json"

static var _root: Dictionary = {}
static var _promises: Dictionary = {}
static var _loaded := false


static func load_config() -> void:
	if _loaded:
		return
	_root = _read_json(CONFIG_PATH)
	var promise_path := str(_root.get("promiseCatalogPath", "res://data/community_promises.json"))
	_promises = _read_json(promise_path)
	_loaded = true


static func is_loaded() -> bool:
	return _loaded


static func root() -> Dictionary:
	load_config()
	return _root


static func generator_version() -> String:
	return str(root().get("generatorVersion", "1.0.0"))


static func schema_version() -> int:
	return int(root().get("schemaVersion", 1))


static func personal_relationship_range() -> Dictionary:
	return root().get("personalRelationship", {"min": -5, "max": 5, "neutral": 0})


static func species_personal_gauge_weight(species_id: String) -> int:
	var weights: Dictionary = root().get("speciesPersonalGaugeWeight", {})
	return int(weights.get(species_id, weights.get("hen", 1)))


static func chat_max_player_messages() -> int:
	var session: Dictionary = root().get("chatSession", {})
	return int(session.get("maxPlayerMessages", 5))


static func generation_config() -> Dictionary:
	return root().get("generation", {})


static func mvp_district_id() -> String:
	return str(generation_config().get("mvpDistrictId", "meadowgate_commons"))


static func feature_flags() -> Dictionary:
	return root().get("featureFlags", {}).duplicate(true)


static func ai_requirement() -> Dictionary:
	return root().get("aiRequirement", {})


static func community_chat_requires_ai() -> bool:
	return bool(ai_requirement().get("communityChatRequiresAi", true))


static func offline_block_message() -> String:
	return str(
		ai_requirement().get(
			"offlineBlockMessage",
			"Community chat requires the local AI server. Start Ollama and the proxy, then try again.",
		)
	)


static func promise_types() -> Array:
	load_config()
	var types: Array = _promises.get("promiseTypes", [])
	return types.duplicate(true)


static func promise_type_ids() -> Array:
	var ids: Array = []
	for entry_variant in promise_types():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var promise_id := str(entry.get("id", ""))
		if not promise_id.is_empty():
			ids.append(promise_id)
	return ids


static func is_valid_promise_type(promise_type: String) -> bool:
	return promise_type in promise_type_ids()


static func promise_type_def(promise_type: String) -> Dictionary:
	for entry_variant in promise_types():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) == promise_type:
			return entry.duplicate(true)
	return {}


static func promise_fulfillment_key(promise_type: String) -> String:
	var def: Dictionary = promise_type_def(promise_type)
	return str(def.get("fulfillmentKey", ""))


static func dialogue_schema_version() -> int:
	return int(root().get("dialogueSchemaVersion", 1))


static func social_effects_path() -> String:
	return str(root().get("socialEffectsPath", "res://data/community_social_effects.json"))


static func notebook_categories() -> Dictionary:
	return root().get("notebookCategories", {})


static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CommunityConfig: missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CommunityConfig: invalid JSON in %s" % path)
		return {}
	return parsed
