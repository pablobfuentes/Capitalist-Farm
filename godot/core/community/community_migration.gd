# Save migration for community schema (8.3 Phase 0).
class_name CommunityMigration
extends RefCounted

const CURRENT_SCHEMA_VERSION := 1


static func migrate_run_dict(data: Dictionary) -> Dictionary:
	var version := int(data.get("communitySchemaVersion", 0))
	if version == 0:
		var seed := int(data.get("seed", 0))
		data["communitySchemaVersion"] = CURRENT_SCHEMA_VERSION
		data["community"] = CommunityState.empty_dict(seed)
		version = CURRENT_SCHEMA_VERSION
	while version < CURRENT_SCHEMA_VERSION:
		version += 1
		data["communitySchemaVersion"] = version
	return data


static func migrate_community_block(community: Dictionary, from_version: int, run_seed: int) -> Dictionary:
	var working: Dictionary = community.duplicate(true)
	var version := from_version
	if version <= 0:
		return CommunityState.empty_dict(run_seed)
	while version < CURRENT_SCHEMA_VERSION:
		if version == 0:
			if not working.has("playerFactKnowledge"):
				working["playerFactKnowledge"] = {}
			if not working.has("conversationSummaries"):
				working["conversationSummaries"] = {}
			if not working.has("playerSupplyContracts"):
				working["playerSupplyContracts"] = []
			if not working.has("playerBusinessLinks"):
				working["playerBusinessLinks"] = {}
			if not working.has("pendingClientRenegotiations"):
				working["pendingClientRenegotiations"] = []
			if not working.has("activeClientRenegotiations"):
				working["activeClientRenegotiations"] = []
			if not working.has("pendingRumorSeeds"):
				working["pendingRumorSeeds"] = []
			if not working.has("rumorSpreadLog"):
				working["rumorSpreadLog"] = []
		version += 1
	return working
