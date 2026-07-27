# Loads authored farm content from JSON (exported from js/farm-supply-chain.js).
extends Node

const BusinessTemplateClass := preload("res://data/templates/business_template.gd")
const SupplyConnectionClass := preload("res://data/connections/supply_connection.gd")

const FARM_CONTENT_PATH := "res://data/farm_content.json"

var templates_by_id: Dictionary = {}
var connections: Array[SupplyConnection] = []
var connection_demand: Dictionary = {}
var customer_alloc_priority: Dictionary = {}


func load_farm_content() -> void:
	templates_by_id.clear()
	connections.clear()
	connection_demand.clear()
	customer_alloc_priority.clear()

	var file := FileAccess.open(FARM_CONTENT_PATH, FileAccess.READ)
	if file == null:
		push_error("Content: missing %s — run: node scripts/export-farm-content.js" % FARM_CONTENT_PATH)
		return

	var root: Variant = JSON.parse_string(file.get_as_text())
	if typeof(root) != TYPE_DICTIONARY:
		push_error("Content: invalid JSON in %s" % FARM_CONTENT_PATH)
		return

	var root_dict: Dictionary = root
	var templates_raw: Array = root_dict.get("templates", [])
	for raw_variant in templates_raw:
		if typeof(raw_variant) != TYPE_DICTIONARY:
			continue
		var raw: Dictionary = raw_variant
		var tmpl: BusinessTemplate = BusinessTemplateClass.from_dict(raw)
		templates_by_id[tmpl.id] = tmpl

	var connections_raw: Array = root_dict.get("connections", [])
	for raw_variant in connections_raw:
		if typeof(raw_variant) != TYPE_DICTIONARY:
			continue
		var raw: Dictionary = raw_variant
		connections.append(SupplyConnectionClass.from_dict(raw))

	connection_demand = root_dict.get("connection_demand", {})
	customer_alloc_priority = root_dict.get("customer_alloc_priority", {})


func get_template(template_id: String) -> BusinessTemplate:
	return templates_by_id.get(template_id) as BusinessTemplate


func get_all_templates() -> Array[BusinessTemplate]:
	var out: Array[BusinessTemplate] = []
	for tmpl_variant in templates_by_id.values():
		if tmpl_variant is BusinessTemplate:
			out.append(tmpl_variant)
	return out


func is_real_estate_asset(template_id: String) -> bool:
	var tmpl := get_template(template_id)
	return tmpl != null and tmpl.asset_class == "real_estate"


func is_infrastructure_template(template_id: String) -> bool:
	return template_id in ["equipment_repair", "delivery_cold_storage"]
