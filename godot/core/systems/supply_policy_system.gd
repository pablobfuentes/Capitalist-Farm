# Allocation policies when upstream capacity is strained (port of FarmSupplyChain.SUPPLY_POLICIES).
class_name SupplyPolicySystem
extends RefCounted

const POLICIES: Dictionary = {
	"portfolio_first": {
		"id": "portfolio_first",
		"label": "Portfolio First",
		"summary": "Owned downstream gets priority — best for vertical integration.",
	},
	"highest_bidder": {
		"id": "highest_bidder",
		"label": "Highest Bidder",
		"summary": "Capacity goes to the highest-margin links — may starve owned downstream.",
	},
	"contract_first": {
		"id": "contract_first",
		"label": "Contract First",
		"summary": "Stable proportional fill — steady cash flow, less spike upside.",
	},
	"balanced": {
		"id": "balanced",
		"label": "Balanced",
		"summary": "Split capacity proportionally — moderate everything.",
	},
}


static func all_policies() -> Array:
	var out: Array = []
	for key in POLICIES.keys():
		out.append(POLICIES[key])
	return out


static func policy_label(policy_id: String) -> String:
	var pol: Dictionary = POLICIES.get(policy_id, {})
	return str(pol.get("label", policy_id))


static func get_policy(state: RunState, template_id: String) -> String:
	if state.supply_policies.has(template_id):
		return str(state.supply_policies[template_id])
	if state.has_strategic_edge("monopoly_tollkeeper") and Content.is_infrastructure_template(template_id):
		return "portfolio_first"
	return "portfolio_first"


static func set_policy(state: RunState, template_id: String, policy_id: String) -> void:
	if not POLICIES.has(policy_id):
		return
	var prev: String = get_policy(state, template_id)
	state.supply_policies[template_id] = policy_id
	if prev == policy_id:
		return
	var tmpl := Content.get_template(template_id)
	var asset := tmpl.name if tmpl else template_id
	state.run_log.append("Allocation policy: %s → %s." % [asset, policy_label(policy_id)])


static func confirm_shortage_ack(state: RunState) -> void:
	state.supply_shortage_ack_turn = state.turn
	state.run_log.append("Allocation policies confirmed for this turn.")
