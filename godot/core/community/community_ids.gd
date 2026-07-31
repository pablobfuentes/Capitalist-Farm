# Stable deterministic IDs for community entities (8.3 § Phase 0).
class_name CommunityIds
extends RefCounted

const DISTRICT_SLUGS := {
	"meadowgate_commons": "mg",
	"northfield_heights": "nf",
	"riverbend_flats": "rb",
	"sunmarket_row": "sm",
	"ironwood_yard": "iw",
	"highland_terrace": "ht",
}


static func world_id(run_seed: int) -> String:
	return "world_%08x" % int(run_seed)


static func district_slug(district_id: String) -> String:
	if DISTRICT_SLUGS.has(district_id):
		return str(DISTRICT_SLUGS[district_id])
	var compact := district_id.replace("_", "")
	if compact.length() <= 8:
		return compact
	return compact.substr(0, 8)


static func business_id(district_id: String, index: int) -> String:
	return "business_%s_%03d" % [district_slug(district_id), index]


static func npc_id(district_id: String, index: int) -> String:
	return "npc_%s_%03d" % [district_slug(district_id), index]


static func fact_id(district_id: String, index: int) -> String:
	return "fact_%s_%04d" % [district_slug(district_id), index]


static func supply_relationship_id(supplier_business_id: String, client_business_id: String, product_type_id: String) -> String:
	var product_slug := product_type_id.replace("_", "")
	return "supply_%s_%s_%s" % [supplier_business_id, client_business_id, product_slug]


static func interaction_event_id(sequence: int) -> String:
	return "event_%08d" % sequence


static func conversation_session_id(district_id: String, npc_id_value: String, turn: int, session_index: int) -> String:
	return "chat_%s_%s_t%d_s%d" % [district_slug(district_id), npc_id_value, turn, session_index]


static func notebook_entry_id(source: String, fact_id_value: String, discovery_turn: int) -> String:
	return "notebook_%s_%s_t%d" % [source, fact_id_value, discovery_turn]


static func promise_id(sequence: int) -> String:
	return "promise_%08d" % sequence


static func personal_gauge_adj(species_id: String, personal_score: int) -> int:
	var range_cfg: Dictionary = CommunityConfig.personal_relationship_range()
	var clamped := clampi(
		personal_score,
		int(range_cfg.get("min", -5)),
		int(range_cfg.get("max", 5)),
	)
	return int(round(float(clamped) * float(CommunityConfig.species_personal_gauge_weight(species_id))))
