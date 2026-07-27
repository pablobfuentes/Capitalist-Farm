class_name BusinessTemplate
extends RefCounted

var id: String = ""
var name: String = ""
var layer: String = ""
var layer_label: String = ""
var industry: String = ""
var asset_class: String = ""
var autopilot: int = 3
var capacity_units: Variant = null
var consumer_capacity_units: Variant = null
var baseline_capacity_frac: float = 0.0
var demand_export_weight: float = 0.25
var marketing_eligible: bool = true
var input_tags: Array = []
var output_tags: Array = []
var risk_tags: Array = []
var blurb: String = ""
var price_range: Array = []
var rev_range: Array = []
var margin_range: Array = []
var owner_dep: float = 0.5
var cust_conc: Array = []


static func from_dict(d: Dictionary) -> BusinessTemplate:
	var t := BusinessTemplate.new()
	t.id = str(d.get("id", ""))
	t.name = str(d.get("name", ""))
	t.layer = str(d.get("layer", ""))
	t.layer_label = str(d.get("layer_label", ""))
	t.industry = str(d.get("industry", ""))
	t.asset_class = str(d.get("asset_class", ""))
	t.autopilot = int(d.get("autopilot", 3))
	t.capacity_units = d.get("capacity_units")
	t.consumer_capacity_units = d.get("consumer_capacity_units")
	t.baseline_capacity_frac = float(d.get("baseline_capacity_frac", 0.0))
	t.demand_export_weight = float(d.get("demand_export_weight", 0.25))
	t.marketing_eligible = bool(d.get("marketing_eligible", true))
	var input_tags_raw: Array = d.get("input_tags", [])
	var output_tags_raw: Array = d.get("output_tags", [])
	var risk_tags_raw: Array = d.get("risk_tags", [])
	t.input_tags.assign(input_tags_raw)
	t.output_tags.assign(output_tags_raw)
	t.risk_tags.assign(risk_tags_raw)
	t.blurb = str(d.get("blurb", ""))
	t.price_range = d.get("price_range", [])
	t.rev_range = d.get("rev_range", [])
	t.margin_range = d.get("margin_range", [])
	t.owner_dep = float(d.get("owner_dep", 0.5))
	t.cust_conc = d.get("cust_conc", [])
	if typeof(t.price_range) != TYPE_ARRAY:
		t.price_range = []
	if typeof(t.rev_range) != TYPE_ARRAY:
		t.rev_range = []
	if typeof(t.margin_range) != TYPE_ARRAY:
		t.margin_range = []
	if typeof(t.cust_conc) != TYPE_ARRAY:
		t.cust_conc = []
	return t
