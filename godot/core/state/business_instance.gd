class_name BusinessInstance
extends RefCounted

var id: String = ""
var template_id: String = ""
var name: String = ""
var revenue_per_turn: int = 0
var operating_costs: int = 0
var industry: String = ""
var layer: String = ""
var crisis_mult: float = 1.0
var purchase_price: int = 0
var marked_value: int = 0
var level: int = 1
var client_health: int = 72
var supplier_health: int = 72
var client_state: String = "stable"
var supplier_state: String = "stable"
var client_cooldown: int = 0
var supplier_cooldown: int = 0
var cust_conc: float = 0.12
var last_care_turn: int = 0
var acquired_turn: int = 0
var over_cap_penalty_turn: int = -1
var upgrades: Dictionary = {}
var upgrade_stats: Dictionary = {}
var manager_drift: Dictionary = {}


static func from_dict(d: Dictionary) -> BusinessInstance:
	var b := BusinessInstance.new()
	b.id = str(d.get("id", ""))
	b.template_id = str(d.get("templateId", d.get("template_id", "")))
	b.name = str(d.get("name", ""))
	b.revenue_per_turn = int(d.get("revenuePerTurn", d.get("revenue_per_turn", 0)))
	b.operating_costs = int(d.get("operatingCosts", d.get("operating_costs", 0)))
	b.industry = str(d.get("industry", ""))
	b.layer = str(d.get("layer", ""))
	b.crisis_mult = float(d.get("crisisMult", d.get("crisis_mult", 1.0)))
	b.purchase_price = int(d.get("purchasePrice", d.get("purchase_price", 0)))
	b.marked_value = int(d.get("markedValue", d.get("marked_value", d.get("valuation", 0))))
	b.level = int(d.get("level", 1))
	b.client_health = int(d.get("clientHealth", d.get("client_health", 72)))
	b.supplier_health = int(d.get("supplierHealth", d.get("supplier_health", 72)))
	b.client_state = str(d.get("clientState", d.get("client_state", "stable")))
	b.supplier_state = str(d.get("supplierState", d.get("supplier_state", "stable")))
	b.client_cooldown = int(d.get("clientCooldown", d.get("client_cooldown", 0)))
	b.supplier_cooldown = int(d.get("supplierCooldown", d.get("supplier_cooldown", 0)))
	b.cust_conc = float(d.get("custConc", d.get("cust_conc", 0.12)))
	b.last_care_turn = int(d.get("lastCareTurn", d.get("last_care_turn", 0)))
	b.acquired_turn = int(d.get("acquiredTurn", d.get("acquired_turn", 0)))
	b.over_cap_penalty_turn = int(d.get("overCapPenaltyTurn", d.get("over_cap_penalty_turn", -1)))
	b.upgrades = (d.get("upgrades", d.get("upgradeTiers", {})) as Dictionary).duplicate(true)
	b.upgrade_stats = (d.get("upgradeStats", d.get("upgrade_stats", {})) as Dictionary).duplicate(true)
	b.manager_drift = (d.get("managerDrift", d.get("manager_drift", {})) as Dictionary).duplicate(true)
	return b


func to_dict() -> Dictionary:
	return {
		"id": id,
		"templateId": template_id,
		"name": name,
		"revenuePerTurn": revenue_per_turn,
		"operatingCosts": operating_costs,
		"industry": industry,
		"layer": layer,
		"crisisMult": crisis_mult,
		"purchasePrice": purchase_price,
		"markedValue": marked_value,
		"valuation": marked_value,
		"level": level,
		"clientHealth": client_health,
		"supplierHealth": supplier_health,
		"clientState": client_state,
		"supplierState": supplier_state,
		"clientCooldown": client_cooldown,
		"supplierCooldown": supplier_cooldown,
		"custConc": cust_conc,
		"lastCareTurn": last_care_turn,
		"acquiredTurn": acquired_turn,
		"overCapPenaltyTurn": over_cap_penalty_turn,
		"upgrades": upgrades,
		"upgradeStats": upgrade_stats,
		"managerDrift": manager_drift,
	}


static func create_from_template(tmpl_id: String, display_name: String, revenue: int, costs: int) -> BusinessInstance:
	var tmpl: BusinessTemplate = ContentAccess.get_template(tmpl_id)
	var b := BusinessInstance.new()
	b.id = MathUtil.uid()
	b.template_id = tmpl_id
	b.name = display_name
	b.revenue_per_turn = revenue
	b.operating_costs = costs
	if tmpl:
		b.industry = tmpl.industry
		b.layer = tmpl.layer
	b.upgrades = {"hire": 0, "marketing": 0, "automation": 0, "care": 0, "manager": false}
	return b
