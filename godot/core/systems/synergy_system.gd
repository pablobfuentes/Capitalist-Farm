class_name SynergySystem
extends RefCounted

const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")
const _SupplyPolicy := preload("res://core/systems/supply_policy_system.gd")

const ALLOCATABLE_LAYERS: Array[String] = ["primary_production", "processing", "infrastructure"]
const EXPORT_VOLUME_CAP_FRAC := 0.28
const EXPORT_FLOOR_YIELD := 0.42
const INFRA_EXTERNAL_YIELD := 0.58
const AUTOPILOT_NEGLECT_TURNS := 4
const CHAIN_HINT_INTERVAL := 3


static func compute_synergies(state: RunState) -> Array[Dictionary]:
	var businesses: Array = _portfolio_nodes(state)
	var by_template: Dictionary = {}

	for node_variant in businesses:
		var tid := _node_template_id(node_variant)
		if tid == "":
			continue
		if not by_template.has(tid):
			by_template[tid] = []
		(by_template[tid] as Array).append(node_variant)

	var supplier_links: Dictionary = {}
	for conn: SupplyConnection in Content.connections:
		var suppliers: Array = by_template.get(conn.supplier, [])
		var customers: Array = by_template.get(conn.customer, [])
		if suppliers.is_empty() or customers.is_empty():
			continue
		var supplier: Variant = suppliers[0]
		for customer_variant in customers:
			var customer: Variant = customer_variant
			if _node_id(supplier) == _node_id(customer):
				continue
			if not supplier_links.has(conn.supplier):
				supplier_links[conn.supplier] = []
			(supplier_links[conn.supplier] as Array).append({
				"connectionId": conn.id,
				"conn": conn,
				"supplier": supplier,
				"customer": customer,
				"supplierId": _node_id(supplier),
				"customerId": _node_id(customer),
			})

	var fulfill_map: Dictionary = {}
	var supplier_util: Dictionary = {}
	for supplier_template_id: String in supplier_links.keys():
		var link_rows: Array = supplier_links[supplier_template_id]
		var alloc: Dictionary = _allocate_supplier_capacity(state, supplier_template_id, link_rows)
		supplier_util[supplier_template_id] = alloc.get("utilization", {})
		var alloc_links: Array = alloc.get("links", [])
		for link_variant in alloc_links:
			if typeof(link_variant) != TYPE_DICTIONARY:
				continue
			var link: Dictionary = link_variant
			var key := "%s:%s" % [str(link.get("connectionId", "")), str(link.get("customerId", ""))]
			fulfill_map[key] = link.get("fulfill", 1.0)

	var active: Array[Dictionary] = []
	for conn: SupplyConnection in Content.connections:
		var suppliers: Array = by_template.get(conn.supplier, [])
		var customers: Array = by_template.get(conn.customer, [])
		if suppliers.is_empty() or customers.is_empty():
			continue

		var supplier: Variant = suppliers[0]
		var default_util: Dictionary = _utilization_ratio(0.0, float(_effective_capacity(state, conn.supplier) or 1))
		var util: Dictionary = supplier_util.get(conn.supplier, default_util)

		for customer_variant in customers:
			var customer: Variant = customer_variant
			if _node_id(supplier) == _node_id(customer):
				continue
			var fulfill_key := "%s:%s" % [conn.id, _node_id(customer)]
			var f: float = float(fulfill_map.get(fulfill_key, 1.0))
			var fx: Dictionary = conn.effects
			var strain: float = _capacity_strain_factor(
				conn.supplier,
				customers.size(),
				f,
				int(util.get("utilizationPct", 0))
			)
			var effect_scale: float = f * strain

			active.append({
				"connectionId": conn.id,
				"chainId": conn.id,
				"supplierId": _node_id(supplier),
				"partnerId": _node_id(supplier),
				"anchorId": _node_id(customer),
				"customerId": _node_id(customer),
				"supplierTemplateId": conn.supplier,
				"customerTemplateId": conn.customer,
				"label": "%s → %s" % [_node_name(supplier), _node_name(customer)],
				"flow": conn.flow,
				"internalLink": true,
				"fulfillRatio": f,
				"costReduction": float(fx.get("customerCostReduction", 0.0)) * effect_scale,
				"revenueBonusCustomer": float(fx.get("customerRevenueBonus", 0.0)) * effect_scale,
				"revenueBonusSupplier": 0.0,
				"demandStability": 0.0,
				"reliabilityBonus": float(fx.get("customerReliabilityBonus", 0.0)) * effect_scale,
				"addedRiskLabel": conn.vulnerability_label,
				"riskLinks": conn.risk_links,
				"capacityStrained": f < 0.85 or bool(util.get("overCapacity", false)) or strain < 0.95,
				"supplierUtilizationPct": util.get("utilizationPct", 0),
				"addedCostPerTurn": int(round((180.0 + float(fx.get("customerCostReduction", 0.0)) * 800.0) * maxf(0.5, f))),
			})

	var customer_ids: Dictionary = {}
	var supplier_ids: Dictionary = {}
	for a: Dictionary in active:
		customer_ids[str(a.get("customerId", ""))] = true
		supplier_ids[str(a.get("supplierId", ""))] = true

	for a: Dictionary in active:
		var customer_id: String = str(a.get("customerId", ""))
		var supplier_id: String = str(a.get("supplierId", ""))
		if supplier_ids.has(customer_id) and customer_ids.has(supplier_id):
			a["chainBonus"] = 0.04
		elif supplier_ids.has(customer_id) or customer_ids.has(supplier_id):
			a["chainBonus"] = 0.03
		else:
			a["chainBonus"] = 0.0

	return active


static func apply_to_business(
	biz: BusinessInstance,
	synergies: Array,
	state: RunState,
	opts: Dictionary = {}
) -> Dictionary:
	var as_customer: Array[Dictionary] = []
	var as_supplier: Array[Dictionary] = []
	for syn_variant in synergies:
		if typeof(syn_variant) != TYPE_DICTIONARY:
			continue
		var syn: Dictionary = syn_variant
		if str(syn.get("customerId", "")) == biz.id:
			as_customer.append(syn)
		if str(syn.get("supplierId", "")) == biz.id:
			as_supplier.append(syn)

	var rev := float(biz.revenue_per_turn)
	var cost := float(biz.operating_costs)
	var crisis_mult := biz.crisis_mult
	var notes: Array[String] = []

	var cost_red := 0.0
	for y: Dictionary in as_customer:
		cost_red += float(y.get("costReduction", 0.0))
		cost_red += float(y.get("chainBonus", 0.0))
		if float(y.get("revenueBonusCustomer", 0.0)) != 0.0:
			rev *= 1.0 + float(y.get("revenueBonusCustomer", 0.0))
		if float(y.get("reliabilityBonus", 0.0)) != 0.0:
			crisis_mult *= 1.0 - minf(0.2, float(y.get("reliabilityBonus", 0.0)) * 0.5)
		cost += float(y.get("addedCostPerTurn", 0))

	for y: Dictionary in as_supplier:
		if float(y.get("revenueBonusSupplier", 0.0)) != 0.0 and not bool(y.get("internalLink", false)):
			rev *= 1.0 + float(y.get("revenueBonusSupplier", 0.0))
		if float(y.get("demandStability", 0.0)) != 0.0 and not bool(y.get("internalLink", false)):
			rev *= 1.0 + float(y.get("demandStability", 0.0)) * 0.5
			crisis_mult *= 1.0 - minf(0.12, float(y.get("demandStability", 0.0)) * 0.4)

	var same_count := 0
	for node_variant in _portfolio_nodes(state):
		if node_variant is BusinessInstance:
			var node: BusinessInstance = node_variant
			if node.template_id == biz.template_id:
				same_count += 1
	if same_count > 1:
		cost *= 0.95
		notes.append("horizontal overhead sharing")

	cost_red = MathUtil.clamp(cost_red, 0.0, 0.35)
	if bool(opts.get("supply_chain_builder_bonus", false)) and not as_customer.is_empty():
		var first: Dictionary = as_customer[0]
		var fulfill: float = float(first.get("fulfillRatio", 1.0))
		cost_red = minf(0.38, cost_red + 0.05 * fulfill)
		notes.append("supply-chain builder bonus")

	cost *= 1.0 - cost_red

	if _UpgradeSystem.is_active(state):
		_UpgradeSystem.ensure_business_upgrades(biz)
		cost = int(round(float(cost) * _UpgradeSystem.business_opex_mult(biz)))
		crisis_mult *= _UpgradeSystem.business_care_crisis_mult(biz)
		var demand_factor: float = _UpgradeSystem.consumer_demand_rev_factor(biz, state, synergies)
		if demand_factor != 1.0:
			rev *= demand_factor
			notes.append("marketing demand lift")

	var added_cost := 0.0
	for y: Dictionary in as_customer:
		added_cost += float(y.get("addedCostPerTurn", 0))
	var savings := maxf(0.0, float(biz.operating_costs) - (cost - added_cost))

	return {
		"rev": int(round(rev)),
		"cost": int(round(maxf(0.0, cost))),
		"crisisMult": MathUtil.clamp(crisis_mult, 0.35, 1.2),
		"costReductionTotal": cost_red,
		"savings": int(round(savings)),
		"notes": notes,
	}


static func _portfolio_nodes(state: RunState) -> Array:
	return state.portfolio.portfolio_nodes()


static func _node_id(node: Variant) -> String:
	if node is BusinessInstance:
		return (node as BusinessInstance).id
	if typeof(node) == TYPE_DICTIONARY:
		return str((node as Dictionary).get("id", ""))
	return ""


static func _node_name(node: Variant) -> String:
	if node is BusinessInstance:
		return (node as BusinessInstance).name
	if typeof(node) == TYPE_DICTIONARY:
		return str((node as Dictionary).get("name", ""))
	return ""


static func _node_template_id(node: Variant) -> String:
	if node is BusinessInstance:
		return (node as BusinessInstance).template_id
	if typeof(node) == TYPE_DICTIONARY:
		var dict: Dictionary = node
		return str(dict.get("templateId", dict.get("template_id", "")))
	return ""


static func _capacity_for(template_id: String) -> Variant:
	var tmpl := Content.get_template(template_id)
	if tmpl == null or tmpl.capacity_units == null:
		return null
	return tmpl.capacity_units


static func _is_allocatable_template(template_id: String) -> bool:
	var tmpl := Content.get_template(template_id)
	return tmpl != null and tmpl.capacity_units != null and tmpl.layer in ALLOCATABLE_LAYERS


static func _unique_owned_customers_for_supplier(state: RunState, supplier_template_id: String) -> int:
	var owned: Dictionary = state.portfolio.owned_template_ids()
	var customers: Dictionary = {}
	for conn: SupplyConnection in Content.connections:
		if conn.supplier == supplier_template_id and owned.has(conn.customer):
			customers[conn.customer] = true
	return customers.size()


static func _agri_conglomerate_capacity_mult(state: RunState, template_id: String) -> float:
	if not state.has_strategic_edge("agri_conglomerate") or not _is_allocatable_template(template_id):
		return 1.0
	var n: int = _unique_owned_customers_for_supplier(state, template_id)
	return 1.0 + minf(0.2, float(n) * 0.05)


static func _effective_capacity(state: RunState, template_id: String) -> Variant:
	var base = _capacity_for(template_id)
	if base == null:
		return null
	var mult: float = _agri_conglomerate_capacity_mult(state, template_id)
	if _UpgradeSystem.is_active(state):
		mult *= _UpgradeSystem.business_capacity_mult(state, template_id)
	return int(round(float(base) * mult))


static func _connection_demand_weight(connection_id: String, state: RunState) -> int:
	var base: int = 20
	if Content.connection_demand.has(connection_id):
		base = int(Content.connection_demand[connection_id])
	if not _UpgradeSystem.is_active(state):
		return base
	for conn: SupplyConnection in Content.connections:
		if conn.id != connection_id:
			continue
		return int(round(float(base) * _UpgradeSystem.business_demand_mult(state, conn.customer)))
	return base


static func _utilization_ratio(demand: float, capacity: float) -> Dictionary:
	if capacity <= 0.0:
		return {"ratio": 1.0, "overCapacity": false, "utilizationPct": 0, "demand": demand, "capacity": 0.0}
	var raw: float = demand / capacity
	return {
		"ratio": minf(1.0, raw),
		"overCapacity": raw > 1.0,
		"utilizationPct": int(round(minf(150.0, raw * 100.0))),
		"demand": demand,
		"capacity": capacity,
	}


static func _get_supply_policy(state: RunState, template_id: String) -> String:
	return _SupplyPolicy.get_policy(state, template_id)


static func _bid_score_for_connection(conn: SupplyConnection) -> float:
	var fx: Dictionary = conn.effects
	return float(fx.get("customerCostReduction", 0.0)) * 2.0 + float(fx.get("customerRevenueBonus", 0.0)) * 1.5


static func _allocate_supplier_capacity(state: RunState, supplier_template_id: String, link_rows: Array) -> Dictionary:
	var cap = _effective_capacity(state, supplier_template_id)
	var policy: String = _get_supply_policy(state, supplier_template_id)
	var links: Array[Dictionary] = []
	for row_variant in link_rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var copy: Dictionary = (row_variant as Dictionary).duplicate(true)
		copy["weight"] = _connection_demand_weight(str(copy.get("connectionId", "")), state)
		links.append(copy)

	var total_demand := 0.0
	for l: Dictionary in links:
		total_demand += float(l.get("weight", 0.0))

	if cap == null or total_demand <= float(cap):
		for l: Dictionary in links:
			l["fulfill"] = 1.0
		var cap_float: float = float(cap) if cap != null else maxf(1.0, total_demand)
		return {
			"links": links,
			"utilization": _utilization_ratio(total_demand, cap_float),
			"overCapacity": false,
		}

	for l: Dictionary in links:
		l["fulfill"] = 0.0

	if policy == "balanced" or policy == "contract_first":
		var frac: float = float(cap) / total_demand
		var mult: float = minf(1.0, frac * 1.02) if policy == "contract_first" else frac
		for l: Dictionary in links:
			l["fulfill"] = mult
	else:
		var sorted: Array[Dictionary] = links.duplicate()
		if policy == "highest_bidder":
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var conn_a: SupplyConnection = a.get("conn")
				var conn_b: SupplyConnection = b.get("conn")
				return _bid_score_for_connection(conn_b) < _bid_score_for_connection(conn_a)
			)
		else:
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var conn_a: SupplyConnection = a.get("conn")
				var conn_b: SupplyConnection = b.get("conn")
				var pa: int = int(Content.customer_alloc_priority.get(conn_a.customer, 0))
				var pb: int = int(Content.customer_alloc_priority.get(conn_b.customer, 0))
				return pb < pa
			)
		var remaining: float = float(cap)
		for l: Dictionary in sorted:
			if remaining <= 0.0:
				continue
			var weight: float = float(l.get("weight", 0.0))
			var take: float = minf(weight, remaining)
			l["fulfill"] = take / weight if weight > 0.0 else 0.0
			remaining -= take

	return {
		"links": links,
		"utilization": _utilization_ratio(total_demand, float(cap)),
		"overCapacity": true,
	}


static func _capacity_strain_factor(
	supplier_template_id: String,
	customer_count: int,
	fulfill_avg: float,
	util_pct: int
) -> float:
	var strain := 1.0
	if supplier_template_id in ["equipment_repair", "delivery_cold_storage"]:
		if customer_count >= 5:
			strain = 0.7
		elif customer_count >= 3:
			strain = 0.85
	if util_pct > 85:
		strain *= 0.82
	if util_pct > 100:
		strain *= 0.68
	if fulfill_avg < 0.85:
		strain *= 0.9 + fulfill_avg * 0.1
	return strain


static func compute_owned_downstream_demand(state: RunState, supplier_template_id: String) -> float:
	var owned: Dictionary = state.portfolio.owned_template_ids()
	var demand: float = 0.0
	for conn: SupplyConnection in Content.connections:
		if conn.supplier != supplier_template_id or not owned.has(conn.customer):
			continue
		demand += float(_connection_demand_weight(conn.id, state))
	return demand


static func effective_capacity(state: RunState, template_id: String) -> Variant:
	return _effective_capacity(state, template_id)


static func compute_supplier_utilization(state: RunState) -> Dictionary:
	var out: Dictionary = {}
	var owned: Dictionary = state.portfolio.owned_template_ids()
	for tmpl: BusinessTemplate in Content.get_all_templates():
		if not _is_allocatable_template(tmpl.id) or not owned.has(tmpl.id):
			continue
		var cap: Variant = _effective_capacity(state, tmpl.id)
		if cap == null:
			continue
		var demand: float = compute_owned_downstream_demand(state, tmpl.id)
		var util: Dictionary = _utilization_ratio(demand, float(cap))
		var econ: Dictionary = compute_capacity_economics(state, tmpl.id, demand, float(cap))
		out[tmpl.id] = {
			"templateId": tmpl.id,
			"name": tmpl.name,
			"policy": _SupplyPolicy.get_policy(state, tmpl.id),
			"demand": int(round(demand)),
			"capacity": int(cap),
			"baseCapacity": _capacity_for(tmpl.id),
			"ratio": util.get("ratio", 1.0),
			"overCapacity": util.get("overCapacity", false),
			"utilizationPct": util.get("utilizationPct", 0),
			"externalContractRevenue": int(econ.get("externalContractRevenue", 0)),
			"exportRevenue": int(econ.get("exportRevenue", 0)),
			"exportLabel": str(econ.get("exportLabel", "")),
			"externalDropped": bool(econ.get("externalDropped", false)),
		}
	return out


static func detect_supply_shortages(state: RunState) -> Array:
	var shortages: Array = []
	for util_variant in compute_supplier_utilization(state).values():
		if typeof(util_variant) != TYPE_DICTIONARY:
			continue
		var util: Dictionary = util_variant
		if bool(util.get("overCapacity", false)):
			shortages.append(util)
	return shortages


static func compute_export_slot_units(state: RunState, template_id: String, owned_demand: float, cap: float) -> int:
	if not _export_channel_enabled(state, template_id) or cap <= 0.0 or owned_demand >= cap:
		return 0
	var spare: float = cap - owned_demand
	var cap_export: int = int(round(cap * EXPORT_VOLUME_CAP_FRAC))
	if state.has_strategic_edge("bulk_commodity_exporter"):
		cap_export = int(round(float(cap_export) * 1.15))
	return mini(int(spare), cap_export)


static func compute_capacity_economics(state: RunState, template_id: String, owned_demand: float, cap: float) -> Dictionary:
	var util_pct: int = int(round((owned_demand / cap) * 100.0)) if cap > 0.0 else 0
	var spare_capacity: float = maxf(0.0, cap - owned_demand) if cap > 0.0 else 0.0
	var export_units: int = compute_export_slot_units(state, template_id, owned_demand, cap)
	var result := {
		"externalContractRevenue": 0,
		"exportRevenue": 0,
		"exportUnits": export_units,
		"exportLabel": "",
		"strainOpexMult": 1.0,
		"externalDropped": false,
		"spareCapacity": spare_capacity,
		"ownedDemand": owned_demand,
		"effectiveCapacity": cap,
	}

	if util_pct > 100:
		result["externalDropped"] = true
		result["strainOpexMult"] = 1.12
		return result
	if util_pct > 85:
		result["strainOpexMult"] = 1.08

	if Content.is_infrastructure_template(template_id):
		var asset: Variant = _node_for_template(state, template_id)
		var base_rent: float = 0.0
		if typeof(asset) == TYPE_DICTIONARY:
			var re: Dictionary = asset
			var rent: int = int(re.get("rentPerTurn", re.get("rent_per_turn", 0)))
			var vacancy: float = float(re.get("vacancyRisk", re.get("vacancy_risk", 0.1)))
			base_rent = float(rent) * (1.0 - vacancy * 0.4)
		else:
			var tmpl := Content.get_template(template_id)
			if tmpl != null and tmpl.rev_range.size() > 0:
				base_rent = float(tmpl.rev_range[0])
		var spare_ratio: float = spare_capacity / cap if cap > 0.0 else 0.0
		var yield_mult: float = INFRA_EXTERNAL_YIELD * spare_ratio
		if util_pct > 85:
			yield_mult *= 0.42
		result["externalContractRevenue"] = int(round(base_rent * yield_mult * _monopoly_tollkeeper_external_mult(state, template_id)))
		if spare_ratio > 0.08:
			result["exportLabel"] = "External contracts · %d%% spare capacity" % int(round(spare_ratio * 100.0))

	if export_units > 0:
		var asset_node: Variant = _node_for_template(state, template_id)
		var base_rev: float = 0.0
		if asset_node is BusinessInstance:
			base_rev = float((asset_node as BusinessInstance).revenue_per_turn)
		elif typeof(asset_node) == TYPE_DICTIONARY:
			var re: Dictionary = asset_node
			base_rev = float(re.get("rentPerTurn", re.get("rent_per_turn", re.get("revenuePerTurn", 0))))
		var floor_per_unit: float = (base_rev / cap) * EXPORT_FLOOR_YIELD if cap > 0.0 else 0.0
		result["exportRevenue"] = int(round(floor_per_unit * float(export_units)))
		result["exportLabel"] = "Export (floor) · %d cap units" % export_units

	return result


static func apply_export_to_business(biz: BusinessInstance, state: RunState) -> Dictionary:
	if biz == null or not _is_upstream_export_eligible(biz.template_id):
		return {"exportRevenue": 0, "exportLabel": ""}
	var cap_variant: Variant = _effective_capacity(state, biz.template_id)
	if cap_variant == null:
		return {"exportRevenue": 0, "exportLabel": ""}
	var cap: float = float(cap_variant)
	var owned_demand: float = compute_owned_downstream_demand(state, biz.template_id)
	var econ: Dictionary = compute_capacity_economics(state, biz.template_id, owned_demand, cap)
	var export_revenue: int = int(econ.get("exportRevenue", 0))
	if _UpgradeSystem.is_active(state) and export_revenue > 0:
		var tmpl := Content.get_template(biz.template_id)
		var export_weight: float = tmpl.demand_export_weight if tmpl else 0.25
		var demand_mult: float = _UpgradeSystem.business_demand_mult(state, biz.template_id)
		export_revenue = int(round(float(export_revenue) * (1.0 + (demand_mult - 1.0) * export_weight)))
	return {
		"exportRevenue": export_revenue,
		"exportLabel": str(econ.get("exportLabel", "")),
		"externalDropped": bool(econ.get("externalDropped", false)),
	}


static func apply_infrastructure_to_real_estate(asset: Dictionary, state: RunState, synergies: Array) -> Dictionary:
	if asset.is_empty() or not Content.is_infrastructure_template(str(asset.get("templateId", asset.get("template_id", "")))):
		return {}
	var template_id: String = str(asset.get("templateId", asset.get("template_id", "")))
	var cap_variant: Variant = _effective_capacity(state, template_id)
	if cap_variant == null:
		return {}
	var cap: float = float(cap_variant)
	var owned_demand: float = compute_owned_downstream_demand(state, template_id)
	var econ: Dictionary = compute_capacity_economics(state, template_id, owned_demand, cap)
	var rent: int = int(asset.get("rentPerTurn", asset.get("rent_per_turn", 0)))
	var vacancy: float = float(asset.get("vacancyRisk", asset.get("vacancy_risk", 0.1)))
	var base_rent: float = float(rent) * (1.0 - vacancy * 0.4)
	var total_rent: int = int(round(base_rent + float(econ.get("externalContractRevenue", 0))))
	var opex: int = int(round(float(asset.get("operatingExpenses", asset.get("operating_expenses", 0))) * float(econ.get("strainOpexMult", 1.0))))
	if _UpgradeSystem.is_active(state):
		var biz_like := BusinessInstance.from_dict(asset)
		_UpgradeSystem.ensure_business_upgrades(biz_like)
		opex = int(round(float(opex) * _UpgradeSystem.business_opex_mult(biz_like)))
	return {
		"rent": total_rent,
		"opex": opex,
		"baseRent": int(round(base_rent)),
		"externalContractRevenue": int(econ.get("externalContractRevenue", 0)),
		"strainOpexMult": float(econ.get("strainOpexMult", 1.0)),
		"externalDropped": bool(econ.get("externalDropped", false)),
		"exportLabel": str(econ.get("exportLabel", "")),
		"utilizationPct": int(round((owned_demand / cap) * 100.0)) if cap > 0.0 else 0,
	}


static func portfolio_risk_summary(state: RunState, synergies: Array = []) -> Dictionary:
	var active_syns: Array = synergies if not synergies.is_empty() else compute_synergies(state)
	var strained: int = 0
	for syn_variant in active_syns:
		if typeof(syn_variant) == TYPE_DICTIONARY and bool((syn_variant as Dictionary).get("capacityStrained", false)):
			strained += 1
	var utilization: Dictionary = compute_supplier_utilization(state)
	var utilization_rows: Array = []
	var external_total := 0
	for util_variant in utilization.values():
		if typeof(util_variant) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = util_variant
		utilization_rows.append(u)
		external_total += int(u.get("externalContractRevenue", 0)) + int(u.get("exportRevenue", 0))
	var shortages: Array = utilization_rows.filter(func(u: Variant) -> bool:
		return typeof(u) == TYPE_DICTIONARY and bool((u as Dictionary).get("overCapacity", false))
	)
	return {
		"activeLinks": active_syns.size(),
		"capacityStrain": strained,
		"utilization": utilization_rows,
		"shortages": shortages,
		"externalRevenueTotal": external_total,
	}


static func apply_over_capacity_penalties(state: RunState) -> Array[String]:
	if not state.is_capital_farm():
		return []
	var notes: Array[String] = []
	var owned: Dictionary = state.portfolio.owned_template_ids()
	for tmpl: BusinessTemplate in Content.get_all_templates():
		if not _is_allocatable_template(tmpl.id) or not owned.has(tmpl.id):
			continue
		var cap_variant: Variant = _effective_capacity(state, tmpl.id)
		if cap_variant == null:
			continue
		var owned_demand: float = compute_owned_downstream_demand(state, tmpl.id)
		var util: Dictionary = _utilization_ratio(owned_demand, float(cap_variant))
		if not bool(util.get("overCapacity", false)):
			continue
		for conn: SupplyConnection in Content.connections:
			if conn.supplier != tmpl.id:
				continue
			for biz: BusinessInstance in state.portfolio.businesses:
				if biz.template_id != conn.customer:
					continue
				if biz.over_cap_penalty_turn == state.turn:
					continue
				biz.over_cap_penalty_turn = state.turn
				biz.supplier_health = maxi(0, biz.supplier_health - 8)
				biz.client_health = maxi(0, biz.client_health - 3)
		notes.append("%s over capacity — downstream relationships strained, external contracts suspended" % tmpl.name)
	return notes


static func apply_neglect_pressure(state: RunState) -> Array[Dictionary]:
	if not state.is_capital_farm():
		return []
	var notes: Array[Dictionary] = []
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.template_id == "" or not is_neglected(biz, state.turn):
			continue
		var sev: float = _neglect_severity(biz.template_id)
		var ap: int = _autopilot_for(biz.template_id)
		var threshold: int = _UpgradeSystem.neglect_threshold(biz)
		var excess: int = mini(turns_since_care(biz, state.turn) - threshold + 1, 3)
		var touch_mult: float = 1.2 if ap <= 2 else 0.62
		var client_drop: int = int(round(2.5 * sev * float(excess) * touch_mult))
		var sup_drop: int = int(round(2.0 * sev * float(excess) * touch_mult))
		biz.client_health = maxi(0, biz.client_health - client_drop)
		biz.supplier_health = maxi(0, biz.supplier_health - sup_drop)
		if ap <= 2:
			biz.crisis_mult = MathUtil.clamp(biz.crisis_mult * (1.0 - 0.035 * sev * float(excess)), 0.45, 1.0)
		if excess >= 1:
			notes.append({
				"name": biz.name,
				"templateId": biz.template_id,
				"turns": turns_since_care(biz, state.turn),
				"label": autopilot_burden_label(biz.template_id),
			})
	return notes


static func turns_since_care(biz: BusinessInstance, turn: int) -> int:
	if biz == null:
		return 0
	var last: int = biz.last_care_turn if biz.last_care_turn > 0 else (biz.acquired_turn if biz.acquired_turn > 0 else turn)
	return maxi(0, turn - last)


static func is_neglected(biz: BusinessInstance, turn: int) -> bool:
	return turns_since_care(biz, turn) >= _UpgradeSystem.neglect_threshold(biz)


static func mark_business_care(biz: BusinessInstance, turn: int) -> void:
	if biz == null:
		return
	biz.last_care_turn = turn


static func has_critical_chain_gap(state: RunState) -> bool:
	return pick_critical_missing_template(state) != null


static func pick_critical_missing_template(state: RunState) -> BusinessTemplate:
	var owned: Dictionary = state.portfolio.owned_template_ids()
	var nodes: Array = _portfolio_nodes(state)
	if nodes.is_empty():
		return null
	var scores: Dictionary = {}

	var add_score := func(id: String, n: float) -> void:
		if owned.has(id):
			return
		scores[id] = float(scores.get(id, 0.0)) + n

	for conn: SupplyConnection in Content.connections:
		if owned.has(conn.supplier) and not owned.has(conn.customer):
			add_score.call(conn.customer, 6.0)
		if owned.has(conn.customer) and not owned.has(conn.supplier):
			add_score.call(conn.supplier, 6.0)

	if nodes.size() >= 2:
		add_score.call("delivery_cold_storage", 3.5)
		add_score.call("equipment_repair", 3.0)

	var best_id: String = ""
	var best_score: float = -1.0
	for id_key: String in scores.keys():
		var score: float = float(scores[id_key])
		if score > best_score and Content.get_template(id_key) != null:
			best_score = score
			best_id = id_key
	if best_id == "":
		return null
	return Content.get_template(best_id)


static func strategic_hint(state: RunState, template_id: String) -> String:
	var tmpl := Content.get_template(template_id)
	if tmpl == null:
		return ""
	var owned: Array = _portfolio_nodes(state)
	if owned.is_empty():
		if Content.is_real_estate_asset(template_id):
			return "Farm infrastructure — grows like property and unlocks supply-chain links."
		return "Foundational Capital Farm operation."

	var hits: Array[String] = []
	for conn: SupplyConnection in Content.connections:
		if conn.supplier == template_id:
			for node_variant in owned:
				if _node_template_id(node_variant) != conn.customer:
					continue
				var base_cost: float = _node_operating_cost(node_variant)
				var base_rev: float = _node_revenue(node_variant)
				var red: float = float(conn.effects.get("customerCostReduction", 0.0))
				var rev_bonus: float = float(conn.effects.get("customerRevenueBonus", 0.0))
				if red > 0.0:
					hits.append("Would cut %s costs ~%s/qtr (%s)" % [_node_name(node_variant), MathUtil.fmt_money(int(round(base_cost * red))), conn.flow])
				elif rev_bonus > 0.0:
					hits.append("Would lift %s revenue ~%s/qtr" % [_node_name(node_variant), MathUtil.fmt_money(int(round(base_rev * rev_bonus)))])
	return " · ".join(hits.slice(0, 2))


static func capture_synergy_state(state: RunState) -> Array:
	var syns: Array = compute_synergies(state)
	var out: Array = []
	for syn_variant in syns:
		if typeof(syn_variant) != TYPE_DICTIONARY:
			continue
		var syn: Dictionary = syn_variant
		out.append({
			"key": synergy_key(syn),
			"label": str(syn.get("label", "")),
			"flow": str(syn.get("flow", "")),
			"strained": bool(syn.get("capacityStrained", false)),
		})
	return out


static func strain_alerts(prev_snap: Array, curr_snap: Array) -> Array:
	var prev_strained: Dictionary = {}
	for row_variant in prev_snap:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if bool(row.get("strained", false)):
			prev_strained[str(row.get("key", ""))] = true
	var alerts: Array = []
	for row_variant in curr_snap:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var key: String = str(row.get("key", ""))
		if bool(row.get("strained", false)) and not prev_strained.has(key):
			alerts.append(row)
	return alerts


static func synergy_key(syn: Dictionary) -> String:
	return "%s|%s|%s" % [str(syn.get("connectionId", syn.get("chainId", ""))), str(syn.get("supplierId", "")), str(syn.get("customerId", ""))]


static func autopilot_burden_label(template_id: String) -> String:
	var ap: int = _autopilot_for(template_id)
	if ap <= 1:
		return "High-touch asset — needs constant attention"
	if ap == 2:
		return "Management-intensive — neglect shows quickly"
	if ap >= 4:
		return "Mostly self-running — lower urgent pressure"
	return ""


static func neglect_urgent_mult(biz: BusinessInstance, turn: int) -> float:
	if biz == null:
		return 1.0
	var threshold: int = _UpgradeSystem.neglect_threshold(biz)
	var since: int = turns_since_care(biz, turn)
	if since < threshold:
		return 1.0
	var sev: float = _neglect_severity(biz.template_id)
	var excess: int = since - threshold + 1
	var mult: float = 1.0 + sev * 0.18 * float(mini(excess, 4))
	_UpgradeSystem.ensure_business_upgrades(biz)
	var ap: int = int(biz.upgrade_stats.get("effectiveAutopilot", _autopilot_for(biz.template_id)))
	mult *= MathUtil.clamp(1.2 - float(ap) * 0.15, 0.45, 1.1)
	return mult


static func urgent_stake_mult(template_id: String) -> float:
	var ap: int = _autopilot_for(template_id)
	return MathUtil.clamp(1.5 - float(ap) * 0.18, 0.55, 1.5)


static func _export_channel_enabled(_state: RunState, template_id: String) -> bool:
	return _is_upstream_export_eligible(template_id)


static func _is_upstream_export_eligible(template_id: String) -> bool:
	var tmpl := Content.get_template(template_id)
	return tmpl != null and tmpl.layer in ["primary_production", "processing"]


static func _monopoly_tollkeeper_external_mult(state: RunState, template_id: String) -> float:
	if state.has_strategic_edge("monopoly_tollkeeper") and Content.is_infrastructure_template(template_id):
		return 1.12
	return 1.0


static func _neglect_severity(template_id: String) -> float:
	var ap: int = _autopilot_for(template_id)
	return MathUtil.clamp(1.4 - float(ap) * 0.22, 0.22, 1.2)


static func _autopilot_for(template_id: String) -> int:
	var tmpl := Content.get_template(template_id)
	return tmpl.autopilot if tmpl else 3


static func _node_for_template(state: RunState, template_id: String) -> Variant:
	for node_variant in _portfolio_nodes(state):
		if _node_template_id(node_variant) == template_id:
			return node_variant
	return null


static func _node_revenue(node: Variant) -> float:
	if node is BusinessInstance:
		return float((node as BusinessInstance).revenue_per_turn)
	if typeof(node) == TYPE_DICTIONARY:
		var d: Dictionary = node
		return float(d.get("revenuePerTurn", d.get("rentPerTurn", d.get("rent_per_turn", 0))))
	return 0.0


static func _node_operating_cost(node: Variant) -> float:
	if node is BusinessInstance:
		return float((node as BusinessInstance).operating_costs)
	if typeof(node) == TYPE_DICTIONARY:
		var d: Dictionary = node
		return float(d.get("operatingCosts", d.get("operatingExpenses", d.get("operating_expenses", 0))))
	return 0.0
