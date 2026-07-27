class_name Portfolio
extends RefCounted

var businesses: Array[BusinessInstance] = []
var real_estate: Array[Dictionary] = []
var securities: Array[Dictionary] = []


static func from_dict(d: Dictionary) -> Portfolio:
	var p := Portfolio.new()
	var businesses_raw: Array = d.get("businesses", [])
	for raw_variant in businesses_raw:
		if typeof(raw_variant) == TYPE_DICTIONARY:
			p.businesses.append(BusinessInstance.from_dict(raw_variant))
	for re_variant in d.get("realEstate", d.get("real_estate", [])):
		if typeof(re_variant) == TYPE_DICTIONARY:
			p.real_estate.append(re_variant)
	for sec_variant in d.get("securities", []):
		if typeof(sec_variant) == TYPE_DICTIONARY:
			p.securities.append(sec_variant)
	return p


func to_dict() -> Dictionary:
	var biz_arr: Array = []
	for b: BusinessInstance in businesses:
		biz_arr.append(b.to_dict())
	return {
		"businesses": biz_arr,
		"realEstate": real_estate,
		"securities": securities,
	}


func portfolio_nodes() -> Array:
	var nodes: Array = []
	nodes.append_array(businesses)
	for raw: Dictionary in real_estate:
		var tid: String = str(raw.get("templateId", raw.get("template_id", "")))
		if ContentAccess.is_real_estate_asset(tid):
			nodes.append(raw)
	return nodes


func owned_template_ids() -> Dictionary:
	var out: Dictionary = {}
	for node_variant in portfolio_nodes():
		var tid := ""
		if node_variant is BusinessInstance:
			tid = (node_variant as BusinessInstance).template_id
		elif typeof(node_variant) == TYPE_DICTIONARY:
			var node: Dictionary = node_variant
			tid = str(node.get("templateId", node.get("template_id", "")))
		if tid != "":
			out[tid] = true
	return out
