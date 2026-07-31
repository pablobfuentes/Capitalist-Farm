# Validates generated district business graphs (Community spec §7.3).
class_name CommunityGraphValidator
extends RefCounted


static func validate(district_payload: Dictionary, cfg: Dictionary) -> Dictionary:
	var businesses: Dictionary = district_payload.get("businesses", {})
	var edges: Array = district_payload.get("supplyRelationships", [])
	var min_connected: int = int(cfg.get("connectedBusinessMinimum", 15))
	var min_businesses: int = int(cfg.get("businessesPerDistrictMin", 18))
	var max_businesses: int = int(cfg.get("businessesPerDistrictMax", 22))

	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	var business_ids: Dictionary = {}
	var template_counts: Dictionary = {}

	for business_id_key in businesses.keys():
		var business_id := str(business_id_key)
		business_ids[business_id] = true
		var business: Dictionary = businesses[business_id]
		var template_id := str(business.get("templateId", ""))
		if template_id.is_empty():
			errors.append("business_missing_template:%s" % business_id)
		elif Content.get_template(template_id) == null:
			errors.append("unknown_template:%s:%s" % [business_id, template_id])
		template_counts[template_id] = int(template_counts.get(template_id, 0)) + 1

	var business_count := businesses.size()
	if business_count < min_businesses or business_count > max_businesses:
		warnings.append("business_count_outside_range:%d" % business_count)

	var degree: Dictionary = {}
	for business_id_key in businesses.keys():
		degree[str(business_id_key)] = 0

	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			errors.append("invalid_edge_entry")
			continue
		var edge: Dictionary = edge_variant
		var supplier_id := str(edge.get("supplierBusinessId", ""))
		var client_id := str(edge.get("clientBusinessId", ""))
		if not business_ids.has(supplier_id):
			errors.append("edge_missing_supplier:%s" % supplier_id)
		if not business_ids.has(client_id):
			errors.append("edge_missing_client:%s" % client_id)
		if supplier_id == client_id:
			errors.append("self_edge:%s" % supplier_id)
		if business_ids.has(supplier_id):
			degree[supplier_id] = int(degree.get(supplier_id, 0)) + 1
		if business_ids.has(client_id):
			degree[client_id] = int(degree.get(client_id, 0)) + 1

		var supplier_template := str(businesses.get(supplier_id, {}).get("templateId", ""))
		var client_template := str(businesses.get(client_id, {}).get("templateId", ""))
		if not supplier_template.is_empty() and not client_template.is_empty():
			if not _connection_exists(supplier_template, client_template, str(edge.get("connectionId", ""))):
				errors.append("incompatible_edge:%s->%s" % [supplier_template, client_template])

	var connected_count := 0
	for business_id_key in degree.keys():
		if int(degree[business_id_key]) >= 1:
			connected_count += 1
	if connected_count < min_connected:
		errors.append("connected_business_minimum:%d<%d" % [connected_count, min_connected])

	for required_template in CommunityChainCatalog.required_templates():
		var req := str(required_template)
		if int(template_counts.get(req, 0)) <= 0:
			warnings.append("missing_required_template:%s" % req)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"businessCount": business_count,
		"edgeCount": edges.size(),
		"connectedBusinessCount": connected_count,
		"degreeByBusinessId": degree,
	}


static func _connection_exists(supplier_template: String, client_template: String, connection_id: String) -> bool:
	for conn in Content.connections:
		if conn == null:
			continue
		if str(conn.supplier) == supplier_template and str(conn.customer) == client_template:
			return true
		if not connection_id.is_empty() and str(conn.id) == connection_id:
			return true
	return false
