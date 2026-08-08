class_name SupplyChainGraphService
extends RefCounted

const _Ownership := preload("res://core/systems/parcel_ownership_system.gd")
const _SCOwn := preload("res://core/systems/supply_chain_ownership.gd")


## Build a district-scoped supply graph for map visualization.
## Returns { districtId, nodes: Dictionary id→node, edges: Array, nodesByTemplate: Dictionary }.
static func build_for_district(state: RunState, district_id: String, district: Dictionary) -> Dictionary:
	var empty := {
		"districtId": district_id,
		"nodes": {},
		"edges": [],
		"nodesByTemplate": {},
	}
	if state == null or district_id.is_empty() or district.is_empty():
		return empty
	if not state.is_capital_farm():
		return empty

	var nodes: Dictionary = {}
	var by_template: Dictionary = {}

	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		var role := str(parcel.get("role", "core"))
		if role in ["civic", "bank", "plaza"]:
			continue
		if role == "development" and not _parcel_has_supply_node(state, parcel, district):
			continue
		var node: Dictionary = _node_from_parcel(state, district_id, district, parcel)
		if node.is_empty():
			continue
		var node_id := str(node.get("id", ""))
		if node_id.is_empty() or nodes.has(node_id):
			continue
		nodes[node_id] = node
		var tid := str(node.get("templateId", ""))
		if tid.is_empty():
			continue
		if not by_template.has(tid):
			by_template[tid] = []
		(by_template[tid] as Array).append(node_id)

	var edges: Array = []
	var edge_keys: Dictionary = {}
	for conn in Content.connections:
		if conn == null:
			continue
		var suppliers: Array = by_template.get(conn.supplier, [])
		var customers: Array = by_template.get(conn.customer, [])
		if suppliers.is_empty() or customers.is_empty():
			continue
		var is_infra := (
			Content.is_infrastructure_template(str(conn.supplier))
			or Content.is_infrastructure_template(str(conn.customer))
		)
		var pairs: Array = []
		if is_infra:
			# Support hubs fan out to every matching customer when that hub is selected.
			for source_id_variant in suppliers:
				for target_id_variant in customers:
					pairs.append([str(source_id_variant), str(target_id_variant)])
		else:
			# Product routes: nearest pairing only — avoids restaurant↔restaurant-style clutter.
			pairs = _nearest_template_pairs(nodes, suppliers, customers)
		for pair_variant in pairs:
			var pair: Array = pair_variant
			if pair.size() < 2:
				continue
			var source_id := str(pair[0])
			var target_id := str(pair[1])
			if source_id.is_empty() or target_id.is_empty() or source_id == target_id:
				continue
			var source: Dictionary = nodes.get(source_id, {})
			var target: Dictionary = nodes.get(target_id, {})
			if source.is_empty() or target.is_empty():
				continue
			if str(source.get("templateId", "")) == str(target.get("templateId", "")):
				continue
			var edge_key := "%s|%s|%s" % [conn.id, source_id, target_id]
			if edge_keys.has(edge_key):
				continue
			edge_keys[edge_key] = true
			var player_controlled := _SCOwn.is_player_controlled_edge(
				bool(source.get("playerOwned", false)),
				bool(target.get("playerOwned", false)),
			)
			var edge := {
				"id": edge_key,
				"catalogId": conn.id,
				"sourceId": source_id,
				"targetId": target_id,
				"resourceType": conn.flow,
				"flow": conn.flow,
				"playerControlled": player_controlled,
				"isInfrastructure": is_infra,
			}
			edge["visualState"] = _SCOwn.get_connection_visual_state(edge)
			edges.append(edge)

	return {
		"districtId": district_id,
		"nodes": nodes,
		"edges": edges,
		"nodesByTemplate": by_template,
	}


## Pair each supplier to its nearest customer and each customer to its nearest supplier.
static func _nearest_template_pairs(nodes: Dictionary, suppliers: Array, customers: Array) -> Array:
	var pairs: Array = []
	var seen: Dictionary = {}
	for source_id_variant in suppliers:
		var source_id := str(source_id_variant)
		var best := _nearest_node_id(nodes, source_id, customers)
		if best.is_empty():
			continue
		var key := "%s>%s" % [source_id, best]
		if seen.has(key):
			continue
		seen[key] = true
		pairs.append([source_id, best])
	for target_id_variant in customers:
		var target_id := str(target_id_variant)
		var best := _nearest_node_id(nodes, target_id, suppliers)
		if best.is_empty():
			continue
		var key := "%s>%s" % [best, target_id]
		if seen.has(key):
			continue
		seen[key] = true
		pairs.append([best, target_id])
	return pairs


static func _nearest_node_id(nodes: Dictionary, from_id: String, candidates: Array) -> String:
	var from: Dictionary = nodes.get(from_id, {})
	if from.is_empty():
		return ""
	var best_id := ""
	var best_score := INF
	for cand_variant in candidates:
		var cand_id := str(cand_variant)
		if cand_id.is_empty() or cand_id == from_id:
			continue
		var cand: Dictionary = nodes.get(cand_id, {})
		if cand.is_empty():
			continue
		if str(cand.get("templateId", "")) == str(from.get("templateId", "")):
			continue
		var dx := float(cand.get("parcelX", 0)) - float(from.get("parcelX", 0))
		var dy := float(cand.get("parcelY", 0)) - float(from.get("parcelY", 0))
		var dist := dx * dx + dy * dy
		# Prefer player-owned counterparts when distance ties.
		var owned_bias := 0.0 if bool(cand.get("playerOwned", false)) else 0.01
		var score := dist + owned_bias
		if score < best_score:
			best_score = score
			best_id = cand_id
	return best_id


static func find_node_id_for_parcel(graph: Dictionary, parcel_id: String) -> String:
	if parcel_id.is_empty():
		return ""
	var nodes: Dictionary = graph.get("nodes", {})
	for node_variant in nodes.values():
		if typeof(node_variant) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = node_variant
		if str(node.get("parcelId", "")) == parcel_id:
			return str(node.get("id", ""))
	return ""


static func pick_initial_node_id(graph: Dictionary, preferred_parcel_id: String = "") -> String:
	var nodes: Dictionary = graph.get("nodes", {})
	var edges: Array = graph.get("edges", [])
	if nodes.is_empty() or edges.is_empty():
		return ""

	var degree: Dictionary = {}
	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var s := str(edge.get("sourceId", ""))
		var t := str(edge.get("targetId", ""))
		degree[s] = int(degree.get(s, 0)) + 1
		degree[t] = int(degree.get(t, 0)) + 1

	# 1) Currently selected parcel, if connected.
	if not preferred_parcel_id.is_empty():
		var preferred := find_node_id_for_parcel(graph, preferred_parcel_id)
		if not preferred.is_empty() and int(degree.get(preferred, 0)) > 0:
			return preferred

	# 2) Player-owned with connections.
	var owned_connected: Array[String] = []
	var multi_connected: Array[String] = []
	var any_connected: Array[String] = []
	for node_id_variant in nodes.keys():
		var node_id := str(node_id_variant)
		var deg := int(degree.get(node_id, 0))
		if deg <= 0:
			continue
		any_connected.append(node_id)
		var node: Dictionary = nodes[node_id]
		if bool(node.get("playerOwned", false)):
			owned_connected.append(node_id)
		if deg >= 2:
			multi_connected.append(node_id)

	var pick := _prefer_non_infrastructure(owned_connected, nodes)
	if not pick.is_empty():
		return pick
	pick = _prefer_non_infrastructure(multi_connected, nodes)
	if not pick.is_empty():
		return pick
	pick = _prefer_non_infrastructure(any_connected, nodes)
	if not pick.is_empty():
		return pick
	return ""


static func _prefer_non_infrastructure(candidates: Array, nodes: Dictionary) -> String:
	if candidates.is_empty():
		return ""
	var core: Array[String] = []
	for id_variant in candidates:
		var id := str(id_variant)
		var node: Dictionary = nodes.get(id, {})
		if not bool(node.get("isInfrastructure", false)):
			core.append(id)
	if not core.is_empty():
		return core[randi() % core.size()]
	return str(candidates[randi() % candidates.size()])


static func _node_from_parcel(
	state: RunState,
	district_id: String,
	district: Dictionary,
	parcel: Dictionary,
) -> Dictionary:
	var parcel_id := str(parcel.get("id", ""))
	if parcel_id.is_empty():
		return {}
	var resolved: Dictionary = _Ownership.resolve(state, parcel, district)
	var owner_state := str(resolved.get("state", ""))
	if owner_state in [_Ownership.OWNER_VACANT, _Ownership.OWNER_CIVIC, _Ownership.OWNER_BANK]:
		return {}

	var template_id := str(parcel.get("template_id", parcel.get("templateId", "")))
	var player_owned := owner_state == _Ownership.OWNER_PLAYER
	var business_id := str(resolved.get("business_id", ""))
	var community_id := str(resolved.get("community_business_id", ""))
	var opportunity_id := str(resolved.get("opportunity_id", ""))
	var display_name := str(resolved.get("operator_name", parcel.get("label", "")))

	if player_owned and not business_id.is_empty():
		var biz := _find_business(state, business_id)
		if biz != null:
			template_id = biz.template_id
			display_name = biz.name
	elif not community_id.is_empty():
		var community: Dictionary = CommunityGenerator.get_business(state, community_id)
		if not community.is_empty():
			template_id = str(community.get("templateId", template_id))
			display_name = str(community.get("displayName", display_name))
	elif not opportunity_id.is_empty():
		var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
		if not opp.is_empty():
			template_id = str(opp.get("templateId", template_id))
			display_name = str(opp.get("name", display_name))

	if template_id.is_empty():
		return {}

	var node_id := ""
	var kind := "npc"
	if player_owned and not business_id.is_empty():
		node_id = "biz:%s" % business_id
		kind = "player"
	elif not community_id.is_empty():
		node_id = "npc:%s" % community_id
		kind = "npc"
	elif not opportunity_id.is_empty():
		node_id = "opp:%s" % opportunity_id
		kind = "opportunity"
	else:
		node_id = "parcel:%s" % parcel_id
		kind = "npc"

	return {
		"id": node_id,
		"templateId": template_id,
		"parcelId": parcel_id,
		"parcelX": int(parcel.get("parcel_x", parcel.get("parcelX", 0))),
		"parcelY": int(parcel.get("parcel_y", parcel.get("parcelY", 0))),
		"districtId": district_id,
		"kind": kind,
		"playerOwned": player_owned,
		"businessId": business_id,
		"communityBusinessId": community_id,
		"opportunityId": opportunity_id,
		"displayName": display_name,
		"isInfrastructure": Content.is_infrastructure_template(template_id),
	}


static func find_node_id_for_business(graph: Dictionary, business_id: String) -> String:
	if business_id.is_empty():
		return ""
	var nodes: Dictionary = graph.get("nodes", {})
	for node_variant in nodes.values():
		if typeof(node_variant) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = node_variant
		if str(node.get("businessId", "")) == business_id:
			return str(node.get("id", ""))
	return ""


static func _parcel_has_supply_node(state: RunState, parcel: Dictionary, district: Dictionary) -> bool:
	var resolved: Dictionary = _Ownership.resolve(state, parcel, district)
	if str(resolved.get("state", "")) != _Ownership.OWNER_PLAYER:
		return false
	var business_id := str(resolved.get("business_id", ""))
	if business_id.is_empty():
		return false
	var biz := _find_business(state, business_id)
	return biz != null and not str(biz.template_id).is_empty()


static func _find_business(state: RunState, business_id: String) -> BusinessInstance:
	for biz in state.portfolio.businesses:
		if biz is BusinessInstance and (biz as BusinessInstance).id == business_id:
			return biz
	return null
