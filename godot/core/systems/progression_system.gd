class_name ProgressionSystem
extends RefCounted

const MILESTONE_STAGES: Array = [
	{"id": "survival", "name": "Survival", "min": 0, "max": 50000, "pressure": "Build positive cash flow and avoid early liquidity failure."},
	{"id": "local_investor", "name": "Local Investor", "min": 50000, "max": 250000, "pressure": "Manage your first meaningful client or supplier crisis."},
	{"id": "professional_investor", "name": "Professional Investor", "min": 250000, "max": 1000000, "pressure": "Withstand a recession, refinancing, or concentration test."},
	{"id": "capital_allocator", "name": "Capital Allocator", "min": 1000000, "max": 3000000, "pressure": "Navigate complex financing and a portfolio-wide shock."},
	{"id": "mogul", "name": "Mogul", "min": 3000000, "max": 10000000, "pressure": "Final test of liquidity, leverage, and execution."},
]

const STRATEGIC_EDGES: Array = [
	{"id": "operator", "name": "Operator", "build": "Turnaround / long-term ownership", "effect": "Businesses held 3+ turns after an Improve action gain +8% operating margin."},
	{"id": "seller_financing_specialist", "name": "Seller-Financing Specialist", "build": "Low-cash acquisition", "effect": "Sellers are more willing to defer payment; seller-note rates run 1.5pts lower."},
	{"id": "contrarian", "name": "Contrarian", "build": "Market timing / distressed", "effect": "Assets bought while a sector is in a negative regime gain a +10% recovery valuation bonus."},
	{"id": "relationship_capital", "name": "Relationship Capital", "build": "Network / reputation", "effect": "Each accepted deal with quality 70+ raises reputation gain by 50%."},
	{"id": "roll_up_strategy", "name": "Roll-Up Strategy", "build": "Horizontal consolidation", "effect": "Same-industry businesses share 5% of overhead and purchasing costs."},
	{"id": "capital_allocator", "name": "Capital Allocator", "build": "Active portfolio rotation", "effect": "Profitable exits reduce the price of your next acquisition by 5%."},
	{"id": "supply_chain_builder", "name": "Supply-Chain Builder", "build": "Vertical integration", "effect": "First active chain link on each business: +5% cost reduction, scaled by fulfillment."},
	{"id": "agri_conglomerate", "name": "Agri-Conglomerate", "build": "Upstream scale", "effect": "+5% effective capacity per unique owned downstream customer (cap +20%)."},
	{"id": "monopoly_tollkeeper", "name": "Monopoly Tollkeeper", "build": "Infrastructure tollbooth", "effect": "+10% external contract revenue per 3 downstream customers served."},
	{"id": "cash_discipline", "name": "Cash Discipline", "build": "Defensive / resilient", "effect": "While liquidity ratio > 1.5, financing rates improve and crisis penalties are halved."},
	{"id": "recurring_revenue_focus", "name": "Recurring Revenue Focus", "build": "Quality compounder", "effect": "Businesses with low customer concentration (<15%) get +8% valuation."},
	{"id": "negotiation_analyst", "name": "Negotiation Analyst", "build": "Negotiation-centric", "effect": "Negotiation Intel available immediately without investigating first."},
	{"id": "debt_optimizer", "name": "Debt Optimizer", "build": "Leveraged portfolio", "effect": "Refinancing costs 1pt less when debt-service coverage is above 1.5x."},
	{"id": "customer_diversifier", "name": "Customer Diversifier", "build": "Risk reduction", "effect": "Marketing improvements are 50% more effective when customer concentration is high."},
	{"id": "bulk_commodity_exporter", "name": "Bulk Commodity Exporter", "build": "Upstream / commodity export", "effect": "Export slot +15% volume; commodity & weather shocks hurt 40% less."},
]

const FARM_SUPPLY_CHAIN_EDGE_IDS: Array[String] = [
	"supply_chain_builder", "agri_conglomerate", "monopoly_tollkeeper", "bulk_commodity_exporter",
]


static func edge_by_id(edge_id: String) -> Dictionary:
	for edge_variant in STRATEGIC_EDGES:
		if typeof(edge_variant) == TYPE_DICTIONARY and str((edge_variant as Dictionary).get("id", "")) == edge_id:
			return edge_variant as Dictionary
	return {}


static func pick_setup_edge_pool(rng: SeededRng) -> Array:
	var farm_pool: Array = []
	var rest_pool: Array = []
	for edge_variant in STRATEGIC_EDGES:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		if str(edge.get("id", "")) in FARM_SUPPLY_CHAIN_EDGE_IDS:
			farm_pool.append(edge.duplicate(true))
		else:
			rest_pool.append(edge.duplicate(true))
	farm_pool.shuffle()
	rest_pool.shuffle()
	var out: Array = farm_pool.slice(0, mini(2, farm_pool.size()))
	if not rest_pool.is_empty():
		out.append(rest_pool[0])
	out.shuffle()
	return out.slice(0, mini(3, out.size()))


static func pick_milestone_edge_choices(state: RunState, rng: SeededRng) -> Array:
	var available: Array = []
	for edge_variant in STRATEGIC_EDGES:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var edge_id: String = str(edge.get("id", ""))
		if edge_id not in state.strategic_edges:
			available.append(edge.duplicate(true))
	available.shuffle()
	rng.set_rng_seed(state.run_seed + state.turn * 4441 + FinanceSystem.net_worth(state))
	return available.slice(0, mini(3, available.size()))


static func check_milestone(state: RunState) -> Dictionary:
	var nw: int = FinanceSystem.net_worth(state)
	var stage: Dictionary = MILESTONE_STAGES[MILESTONE_STAGES.size() - 1]
	for stage_variant in MILESTONE_STAGES:
		if typeof(stage_variant) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = stage_variant
		if nw >= int(s.get("min", 0)) and nw < int(s.get("max", 999999999)):
			stage = s
			break
	if str(stage.get("id", "")) != state.milestone_stage and str(stage.get("id", "")) not in state.milestones_hit:
		state.milestone_stage = str(stage.get("id", ""))
		state.milestones_hit.append(state.milestone_stage)
		if state.milestone_stage != "survival":
			return stage
	state.milestone_stage = str(stage.get("id", ""))
	return {}


static func choose_edge(state: RunState, edge_id: String) -> Dictionary:
	if edge_id.is_empty():
		state.edge_choices_pending = []
		return {"ok": true, "state": state}
	var edge: Dictionary = edge_by_id(edge_id)
	if edge.is_empty():
		return {"ok": false, "error": "Unknown edge: %s" % edge_id}
	if edge_id in state.strategic_edges:
		return {"ok": false, "error": "Edge already owned"}
	var pending_ids: Array = []
	for choice_variant in state.edge_choices_pending:
		if typeof(choice_variant) == TYPE_DICTIONARY:
			pending_ids.append(str((choice_variant as Dictionary).get("id", "")))
	if not pending_ids.is_empty() and edge_id not in pending_ids:
		return {"ok": false, "error": "Edge not in current choices"}
	state.strategic_edges.append(edge_id)
	state.edge_choices_pending = []
	state.run_log.append("New Strategic Edge acquired: %s." % str(edge.get("name", edge_id)))
	return {"ok": true, "state": state, "edge": edge}


static func skip_edge_choice(state: RunState) -> Dictionary:
	state.edge_choices_pending = []
	return {"ok": true, "state": state}
