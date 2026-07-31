# Post-acquisition supply transfer + client renegotiation (8.3 §7).
class_name CommunityAcquisitionService
extends RefCounted


static func on_player_business_acquired(
	state: RunState,
	player_business: BusinessInstance,
	opportunity: Dictionary = {},
) -> Dictionary:
	if state == null or player_business == null:
		return {"ok": false, "error": "missing_state"}
	CommunityState.ensure_initialized(state)
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state):
		return {"ok": true, "skipped": true}

	var community_business: Dictionary = _resolve_community_business(state, player_business, opportunity)
	if community_business.is_empty():
		return {"ok": true, "skipped": true, "reason": "no_community_match"}

	var community_business_id := str(community_business.get("id", ""))
	var district_id := str(community_business.get("districtId", CommunityConfig.mvp_district_id()))
	var transferred: Array = _transfer_supply_contracts(
		state,
		player_business,
		community_business_id,
		district_id,
	)
	_link_player_business(state, player_business, community_business_id, district_id, transferred)
	_mark_community_business_acquired(state, district_id, community_business_id, player_business.id)
	_clear_parcel_community_binding(state, community_business)

	var scheduled: Array = []
	for contract_variant in transferred:
		if typeof(contract_variant) != TYPE_DICTIONARY:
			continue
		var contract: Dictionary = contract_variant
		if str(contract.get("acquiredRole", "")) != "supplier":
			continue
		if float(contract.get("dependence", 0.0)) < CommunityRenegotiationTemplates.major_client_dependence_min():
			continue
		var event: Dictionary = CommunityRenegotiationTemplates.schedule_renegotiation(state, player_business, contract)
		if not event.is_empty():
			scheduled.append(event)

	return {
		"ok": true,
		"communityBusinessId": community_business_id,
		"transferredContracts": transferred.size(),
		"scheduledRenegotiations": scheduled.size(),
	}


static func contracts_for_player_business(state: RunState, player_business_id: String) -> Array:
	CommunityState.ensure_initialized(state)
	var contracts: Array = state.community.get("playerSupplyContracts", [])
	var matched: Array = []
	for contract_variant in contracts:
		if typeof(contract_variant) != TYPE_DICTIONARY:
			continue
		var contract: Dictionary = contract_variant
		if str(contract.get("playerBusinessId", "")) == player_business_id:
			matched.append(contract.duplicate(true))
	return matched


static func player_business_link(state: RunState, player_business_id: String) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var links: Dictionary = state.community.get("playerBusinessLinks", {})
	if links.has(player_business_id):
		return (links[player_business_id] as Dictionary).duplicate(true)
	return {}


static func _resolve_community_business(
	state: RunState,
	player_business: BusinessInstance,
	opportunity: Dictionary,
) -> Dictionary:
	var parcel_id := str(opportunity.get("parcelId", ""))
	if parcel_id.is_empty():
		parcel_id = CommunityNegotiationBridge.parcel_id_for_opportunity(state, str(opportunity.get("id", "")))
	var district_id := str(opportunity.get("districtId", CommunityConfig.mvp_district_id()))

	if not parcel_id.is_empty():
		var assignment: Dictionary = state.parcel_assignments.get(parcel_id, {})
		var community_business_id := str(assignment.get("community_business_id", ""))
		if not community_business_id.is_empty():
			var business: Dictionary = CommunityGenerator.get_business(state, community_business_id)
			if not business.is_empty():
				return business
		var by_parcel: Dictionary = CommunityGenerator.get_business_for_parcel(state, parcel_id, district_id)
		if not by_parcel.is_empty():
			return by_parcel

	var template_id := str(player_business.template_id)
	if template_id.is_empty():
		template_id = str(opportunity.get("templateId", ""))
	if not template_id.is_empty():
		var npc_id := CommunityNegotiationBridge.npc_id_for_template(state, district_id, template_id)
		if not npc_id.is_empty():
			var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
			var business_id := str(npc.get("primaryBusinessId", ""))
			if not business_id.is_empty():
				return CommunityGenerator.get_business(state, business_id)
	return {}


static func _transfer_supply_contracts(
	state: RunState,
	player_business: BusinessInstance,
	community_business_id: String,
	district_id: String,
) -> Array:
	var district_payload: Dictionary = state.community.get("districts", {}).get(district_id, {})
	var edges: Array = district_payload.get("supplyRelationships", [])
	var contracts: Array = state.community.get("playerSupplyContracts", [])
	if typeof(contracts) != TYPE_ARRAY:
		contracts = []

	var transferred: Array = []
	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var supplier_id := str(edge.get("supplierBusinessId", ""))
		var client_id := str(edge.get("clientBusinessId", ""))
		var acquired_role := ""
		if supplier_id == community_business_id:
			acquired_role = "supplier"
		elif client_id == community_business_id:
			acquired_role = "client"
		else:
			continue

		var counterpart_business_id := client_id if acquired_role == "supplier" else supplier_id
		var counterpart: Dictionary = CommunityGenerator.get_business(state, counterpart_business_id)
		var contract := {
			"id": str(edge.get("id", "")),
			"playerBusinessId": player_business.id,
			"communityBusinessId": community_business_id,
			"districtId": district_id,
			"supplierBusinessId": supplier_id,
			"clientBusinessId": client_id,
			"acquiredRole": acquired_role,
			"counterpartBusinessId": counterpart_business_id,
			"counterpartNpcId": str(counterpart.get("ownerNpcId", "")),
			"productTypeId": str(edge.get("productTypeId", "supply")),
			"flow": str(edge.get("flow", "")),
			"reliability": float(edge.get("reliability", 0.7)),
			"dependence": float(edge.get("dependence", 0.5)),
			"status": "active",
			"acquiredTurn": state.turn,
			"inheritedOnSale": true,
		}
		contracts.append(contract)
		transferred.append(contract.duplicate(true))

	state.community["playerSupplyContracts"] = contracts
	return transferred


static func _link_player_business(
	state: RunState,
	player_business: BusinessInstance,
	community_business_id: String,
	district_id: String,
	transferred: Array,
) -> void:
	var links: Dictionary = state.community.get("playerBusinessLinks", {})
	if typeof(links) != TYPE_DICTIONARY:
		links = {}
	var edge_ids: Array = []
	for contract_variant in transferred:
		if typeof(contract_variant) == TYPE_DICTIONARY:
			edge_ids.append(str((contract_variant as Dictionary).get("id", "")))
	links[player_business.id] = {
		"playerBusinessId": player_business.id,
		"communityBusinessId": community_business_id,
		"districtId": district_id,
		"acquiredTurn": state.turn,
		"supplyEdgeIds": edge_ids,
	}
	state.community["playerBusinessLinks"] = links


static func _mark_community_business_acquired(
	state: RunState,
	district_id: String,
	community_business_id: String,
	player_business_id: String,
) -> void:
	var districts: Dictionary = state.community.get("districts", {})
	var district_payload: Dictionary = districts.get(district_id, {})
	var businesses: Dictionary = district_payload.get("businesses", {})
	if not businesses.has(community_business_id):
		return
	var business: Dictionary = businesses[community_business_id]
	business["saleState"] = "acquired_by_player"
	business["acquiredByPlayerBusinessId"] = player_business_id
	business["acquiredTurn"] = state.turn
	businesses[community_business_id] = business
	district_payload["businesses"] = businesses
	districts[district_id] = district_payload
	state.community["districts"] = districts


static func _clear_parcel_community_binding(state: RunState, community_business: Dictionary) -> void:
	var parcel_id := str(community_business.get("parcelId", ""))
	if parcel_id.is_empty() or not state.parcel_assignments.has(parcel_id):
		return
	var assignment: Dictionary = state.parcel_assignments[parcel_id]
	if str(assignment.get("community_business_id", "")) == str(community_business.get("id", "")):
		assignment.erase("community_business_id")
		state.parcel_assignments[parcel_id] = assignment
