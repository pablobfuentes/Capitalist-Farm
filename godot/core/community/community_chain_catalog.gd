# Authored chain skeletons + supply adjacency from farm content.
class_name CommunityChainCatalog
extends RefCounted

const CHAIN_SKELETONS_PATH := "res://data/community_chain_skeletons.json"
const GENERATION_DATA_PATH := "res://data/community_generation_data.json"

static var _chains_root: Dictionary = {}
static var _generation_root: Dictionary = {}
static var _loaded := false


static func load_catalog() -> void:
	if _loaded:
		return
	_chains_root = _read_json(CHAIN_SKELETONS_PATH)
	_generation_root = _read_json(GENERATION_DATA_PATH)
	_loaded = true


static func reload_catalog() -> void:
	_loaded = false
	_chains_root = {}
	_generation_root = {}
	load_catalog()


static func chains() -> Array:
	load_catalog()
	return (_chains_root.get("chains", []) as Array).duplicate(true)


static func required_templates() -> Array:
	load_catalog()
	return (_chains_root.get("requiredTemplates", []) as Array).duplicate(true)


static func fill_templates() -> Array:
	load_catalog()
	var from_chains: Array = _chains_root.get("fillTemplates", [])
	if not from_chains.is_empty():
		return from_chains.duplicate(true)
	return required_templates()


static func district_slot_ids(district_id: String) -> Array:
	load_catalog()
	var slots: Dictionary = _chains_root.get("districtSlots", {})
	return (slots.get(district_id, []) as Array).duplicate(true)


static func generation_data() -> Dictionary:
	load_catalog()
	return _generation_root.duplicate(true)


static func operational_issue_types() -> Array:
	return generation_data().get("operationalIssueTypes", [])


static func social_fact_types() -> Array:
	var types: Array = generation_data().get("socialFactTypes", [])
	if types.is_empty() and _loaded:
		# Hot-reload safeguard when generation JSON gained new fields mid-session.
		reload_catalog()
		types = generation_data().get("socialFactTypes", [])
	return types


static func connection_map() -> Dictionary:
	var out: Dictionary = {}
	for conn in Content.connections:
		if conn == null:
			continue
		var supplier := str(conn.supplier)
		var customer := str(conn.customer)
		if not out.has(supplier):
			out[supplier] = []
		(out[supplier] as Array).append({
			"id": str(conn.id),
			"supplier": supplier,
			"customer": customer,
			"flow": str(conn.flow),
			"productTypeId": _product_slug(conn.flow),
			"vulnerabilityLabel": str(conn.vulnerability_label),
		})
	return out


static func customers_of(template_id: String, connection_map_cache: Dictionary = {}) -> Array:
	var map: Dictionary = connection_map_cache if not connection_map_cache.is_empty() else connection_map()
	var out: Array = []
	for supplier_key in map.keys():
		if str(supplier_key) != template_id:
			continue
		for edge_variant in map[supplier_key]:
			if typeof(edge_variant) != TYPE_DICTIONARY:
				continue
			var edge: Dictionary = edge_variant
			out.append(str(edge.get("customer", "")))
	return out


static func suppliers_of(template_id: String, connection_map_cache: Dictionary = {}) -> Array:
	var map: Dictionary = connection_map_cache if not connection_map_cache.is_empty() else connection_map()
	var out: Array = []
	for supplier_key in map.keys():
		for edge_variant in map[supplier_key]:
			if typeof(edge_variant) != TYPE_DICTIONARY:
				continue
			var edge: Dictionary = edge_variant
			if str(edge.get("customer", "")) == template_id:
				out.append(str(supplier_key))
	return out


static func pick_chain_skeletons(rng: SeededRng, cfg: Dictionary) -> Array:
	var all_chains: Array = chains()
	if all_chains.is_empty():
		return []
	var min_chains := int(cfg.get("chainSkeletonCountMin", 2))
	var max_chains := int(cfg.get("chainSkeletonCountMax", 4))
	var count := rng.randi_range(mini(min_chains, all_chains.size()), mini(max_chains, all_chains.size()))
	var pool: Array = all_chains.duplicate(true)
	var picked: Array = []
	for _i in count:
		if pool.is_empty():
			break
		var idx := rng.randi_range(0, pool.size() - 1)
		picked.append(pool[idx])
		pool.remove_at(idx)
	return picked


static func _product_slug(flow: String) -> String:
	var slug := flow.to_lower()
	slug = slug.replace(",", "")
	slug = slug.replace("/", "_")
	slug = slug.replace(" ", "_")
	slug = slug.replace("-", "_")
	while slug.find("__") >= 0:
		slug = slug.replace("__", "_")
	return slug.strip_edges()


static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CommunityChainCatalog: missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
