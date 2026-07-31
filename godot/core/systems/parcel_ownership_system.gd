class_name ParcelOwnershipSystem
extends RefCounted

const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")
const _World := preload("res://scenes/farm_map/world_layout_data.gd")

const OWNER_PLAYER := "player"
const OWNER_NPC := "npc"
const OWNER_VACANT := "vacant"
const OWNER_OPPORTUNITY := "opportunity"
const OWNER_CONTESTED := "contested"
const OWNER_CIVIC := "civic"
const OWNER_BANK := "bank"

const DEFAULT_DISTRICT_ID := "meadowgate_commons"

const DISTRICT_PATHS: Dictionary = {
	DEFAULT_DISTRICT_ID: _Layout.MEADOWGATE_PATH,
}

const ROLE_PRIORITY: Dictionary = {
	"premium": 0,
	"core": 1,
	"specialization": 2,
	"development": 3,
	"competitive": 99,
}


static func applies_to(state: RunState) -> bool:
	return state != null and GameMode.is_2d_run(state.mode)


static func load_district_for_state(state: RunState) -> Dictionary:
	var district_id := DEFAULT_DISTRICT_ID
	if state != null and str(state.active_district_id) != "":
		district_id = str(state.active_district_id)
	var region: Dictionary = _World.load_region()
	var entry: Dictionary = _World.find_entry_by_id(region, district_id)
	if not entry.is_empty():
		return _World.load_district_from_entry(entry)
	return _Layout.load_district(str(DISTRICT_PATHS.get(district_id, _Layout.MEADOWGATE_PATH)))


static func plaza_id_for(district: Dictionary, plaza: Dictionary) -> String:
	return "%s:plaza_%d_%d" % [
		str(district.get("id", "district")),
		int(plaza.get("parcel_x", 0)),
		int(plaza.get("parcel_y", 0)),
	]


static func seed_district(state: RunState, district: Dictionary) -> void:
	if not applies_to(state) or district.is_empty():
		return
	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		var parcel_id := str(parcel.get("id", ""))
		if parcel_id.is_empty() or state.parcel_assignments.has(parcel_id):
			continue
		state.parcel_assignments[parcel_id] = _default_assignment_for_parcel(parcel)
	for plaza_variant in district.get("plazas", []):
		if typeof(plaza_variant) != TYPE_DICTIONARY:
			continue
		var plaza: Dictionary = plaza_variant
		var plaza_id := plaza_id_for(district, plaza)
		if state.parcel_assignments.has(plaza_id):
			continue
		state.parcel_assignments[plaza_id] = {
			"owner": OWNER_CIVIC,
			"business_id": "",
			"opportunity_id": "",
			"npc_label": str(plaza.get("label", "Plaza")),
		}


static func ensure_seeded(state: RunState, district: Dictionary = {}) -> void:
	if not applies_to(state):
		return
	DistrictUnlockSystem.ensure_initialized(state)
	if str(state.active_district_id).is_empty():
		state.active_district_id = DEFAULT_DISTRICT_ID
	var region: Dictionary = _World.load_region()
	for entry_variant in _World.district_entries(region):
		var entry: Dictionary = entry_variant
		if not DistrictUnlockSystem.is_unlocked(state, _World.district_id(entry)):
			continue
		seed_district(state, _World.load_district_from_entry(entry))
	if typeof(district) == TYPE_DICTIONARY and not district.is_empty():
		seed_district(state, district)


static func sync_from_state(state: RunState, district: Dictionary = {}) -> void:
	if not applies_to(state):
		return
	ensure_seeded(state, district)
	var region: Dictionary = _World.load_region()
	var district_bundles: Array = []
	for entry_variant in _World.district_entries(region):
		var entry: Dictionary = entry_variant
		if not DistrictUnlockSystem.is_unlocked(state, _World.district_id(entry)):
			continue
		var district_data: Dictionary = _World.load_district_from_entry(entry)
		_sync_district(state, district_data)
		district_bundles.append({
			"district_id": _World.district_id(entry),
			"district": district_data,
		})
	if typeof(district) == TYPE_DICTIONARY and not district.is_empty():
		var extra_id := str(district.get("id", ""))
		var found := false
		for bundle_variant in district_bundles:
			if str((bundle_variant as Dictionary).get("district_id", "")) == extra_id:
				found = true
				break
		if not found:
			_sync_district(state, district)
			district_bundles.append({
				"district_id": extra_id,
				"district": district,
			})
	_sync_opportunity_bindings(state, district_bundles)


static func count_district_opportunities(state: RunState, district: Dictionary) -> int:
	var count := 0
	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel_id := str((parcel_variant as Dictionary).get("id", ""))
		if parcel_id.is_empty():
			continue
		var assignment: Dictionary = state.parcel_assignments.get(parcel_id, {})
		if str(assignment.get("opportunity_id", "")) != "":
			count += 1
	return count


static func _sync_district(state: RunState, district: Dictionary) -> void:
	for parcel_id_variant in state.parcel_assignments.keys():
		var parcel_id := str(parcel_id_variant)
		if _find_parcel_by_id(district, parcel_id).is_empty():
			continue
		var assignment: Dictionary = state.parcel_assignments[parcel_id]
		var business_id := str(assignment.get("business_id", ""))
		if business_id != "" and _find_business(state, business_id) == null:
			_reset_parcel_to_default(state, district, parcel_id)

	for biz: BusinessInstance in state.portfolio.businesses:
		if not _business_has_parcel(state, biz.id):
			_assign_business_to_best_parcel(state, district, biz)

	for parcel_id_variant in state.parcel_assignments.keys():
		var parcel_id := str(parcel_id_variant)
		if _find_parcel_by_id(district, parcel_id).is_empty():
			continue
		var assignment: Dictionary = state.parcel_assignments[parcel_id]
		var opportunity_id := str(assignment.get("opportunity_id", ""))
		if opportunity_id == "":
			continue
		if OpportunitySystem.find_opportunity(state, opportunity_id).is_empty():
			_clear_opportunity_binding(state, district, parcel_id)


static func _sync_opportunity_bindings(state: RunState, district_bundles: Array) -> void:
	var unbound: Array = []
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		var opp: Dictionary = opp_variant
		if str(opp.get("assetType", "")) != "business":
			continue
		var opportunity_id := str(opp.get("id", ""))
		if opportunity_id.is_empty() or _opportunity_has_parcel(state, opportunity_id):
			continue
		unbound.append(opp)

	for opp: Dictionary in unbound:
		var bundle := _pick_district_bundle_for_opportunity(state, district_bundles, opp)
		if bundle.is_empty():
			continue
		var district: Dictionary = bundle.get("district", {})
		var parcel_id := _pick_parcel_for_opportunity(state, district, opp)
		if parcel_id.is_empty():
			continue
		_bind_opportunity(state, district, parcel_id, opp, str(bundle.get("district_id", "")))


static func _pick_district_bundle_for_opportunity(
	state: RunState,
	district_bundles: Array,
	opp: Dictionary
) -> Dictionary:
	var preferred := str(opp.get("districtId", ""))
	if not preferred.is_empty():
		for bundle_variant in district_bundles:
			var bundle: Dictionary = bundle_variant
			if str(bundle.get("district_id", "")) != preferred:
				continue
			var district: Dictionary = bundle.get("district", {})
			if not _pick_parcel_for_opportunity(state, district, opp).is_empty():
				return bundle

	var candidates: Array = []
	for bundle_variant in district_bundles:
		var bundle: Dictionary = bundle_variant
		var district: Dictionary = bundle.get("district", {})
		if _pick_parcel_for_opportunity(state, district, opp).is_empty():
			continue
		candidates.append(bundle)

	if candidates.is_empty():
		return {}

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var district_a: Dictionary = a.get("district", {})
		var district_b: Dictionary = b.get("district", {})
		return count_district_opportunities(state, district_a) < count_district_opportunities(state, district_b)
	)
	return candidates[0] as Dictionary


static func resolve(state: RunState, parcel: Dictionary, district: Dictionary = {}) -> Dictionary:
	if typeof(district) != TYPE_DICTIONARY or district.is_empty():
		district = load_district_for_state(state)
	var parcel_id := str(parcel.get("id", ""))
	if parcel_id.is_empty() and str(parcel.get("role", "")) == "plaza":
		parcel_id = str(parcel.get("_plaza_key", ""))

	if state == null or not applies_to(state):
		return _fallback_resolve(parcel)

	ensure_seeded(state, district)
	if BankSystem.is_bank_parcel(parcel):
		return _resolve_bank(parcel, district)

	var assignment: Dictionary = state.parcel_assignments.get(parcel_id, _default_assignment_for_parcel(parcel))

	var business_id := str(assignment.get("business_id", ""))
	if business_id != "":
		var biz := _find_business(state, business_id)
		if biz != null:
			return {
				"state": OWNER_PLAYER,
				"headline": "You operate this lot",
				"detail": "%s · Rev %s / Cost %s" % [
					biz.name,
					MathUtil.fmt_money(biz.revenue_per_turn),
					MathUtil.fmt_money(biz.operating_costs),
				],
				"business_id": biz.id,
				"opportunity_id": "",
				"operator_name": biz.name,
			}

	var opportunity_id := str(assignment.get("opportunity_id", ""))
	if opportunity_id != "":
		var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
		if not opp.is_empty():
			var contested := bool(opp.get("rivalContest", false))
			return {
				"state": OWNER_CONTESTED if contested else OWNER_OPPORTUNITY,
				"headline": "Contested listing" if contested else "Acquisition opportunity",
				"detail": "%s · Ask %s · %d turns left" % [
					str(opp.get("name", "Listing")),
					MathUtil.fmt_money(int(opp.get("price", 0))),
					int(opp.get("expiresIn", 0)),
				],
				"business_id": "",
				"opportunity_id": opportunity_id,
				"operator_name": str(opp.get("name", "")),
			}

	var community_business_id := str(assignment.get("community_business_id", ""))
	if community_business_id.is_empty():
		var district_id := str(district.get("id", ""))
		var community_business: Dictionary = CommunityGenerator.get_business_for_parcel(
			state,
			parcel_id,
			district_id,
		)
		if not community_business.is_empty():
			community_business_id = str(community_business.get("id", ""))
	if community_business_id != "":
		var community_business: Dictionary = CommunityGenerator.get_business(state, community_business_id)
		if not community_business.is_empty():
			var operator_name := str(community_business.get("displayName", assignment.get("npc_label", "")))
			return {
				"state": OWNER_NPC,
				"headline": "NPC-operated",
				"detail": "Run by %s" % operator_name,
				"business_id": "",
				"community_business_id": community_business_id,
				"opportunity_id": "",
				"operator_name": operator_name,
			}

	var owner := str(assignment.get("owner", OWNER_NPC))
	match owner:
		OWNER_VACANT:
			return {
				"state": OWNER_VACANT,
				"headline": "Vacant development lot",
				"detail": "No operator · open for future deals",
				"business_id": "",
				"opportunity_id": "",
				"operator_name": "",
			}
		OWNER_CIVIC:
			return {
				"state": OWNER_CIVIC,
				"headline": "Civic space",
				"detail": "Not available for acquisition",
				"business_id": "",
				"opportunity_id": "",
				"operator_name": str(assignment.get("npc_label", parcel.get("label", ""))),
			}
		_:
			var operator_name := str(assignment.get("npc_label", parcel.get("label", "Local operator")))
			return {
				"state": OWNER_NPC,
				"headline": "NPC-operated",
				"detail": "Run by %s" % operator_name,
				"business_id": "",
				"opportunity_id": "",
				"operator_name": operator_name,
			}


static func owner_state(state: RunState, parcel: Dictionary, district: Dictionary = {}) -> String:
	return str(resolve(state, parcel, district).get("state", OWNER_NPC))


static func ownership_label(state: String) -> String:
	match state:
		OWNER_PLAYER:
			return "Player-owned"
		OWNER_NPC:
			return "NPC-operated"
		OWNER_VACANT:
			return "Vacant"
		OWNER_OPPORTUNITY:
			return "Opportunity"
		OWNER_CONTESTED:
			return "Contested opportunity"
		OWNER_CIVIC:
			return "Civic"
		OWNER_BANK:
			return "Bank branch"
		_:
			return state.capitalize()


static func on_business_acquired(state: RunState, business: BusinessInstance, opportunity: Dictionary = {}) -> void:
	if not applies_to(state) or business == null:
		return
	var district := load_district_for_state(state)
	ensure_seeded(state, district)

	var parcel_id := str(opportunity.get("parcelId", ""))
	if parcel_id.is_empty():
		parcel_id = _pick_parcel_for_business(state, district, business)
	if parcel_id.is_empty():
		return

	state.parcel_assignments[parcel_id] = {
		"owner": OWNER_PLAYER,
		"business_id": business.id,
		"opportunity_id": "",
		"npc_label": _npc_label_for_parcel_id(district, parcel_id),
	}


static func _default_assignment_for_parcel(parcel: Dictionary) -> Dictionary:
	var role := str(parcel.get("role", "core"))
	match role:
		"development":
			return {
				"owner": OWNER_VACANT,
				"business_id": "",
				"opportunity_id": "",
				"npc_label": "",
			}
		"civic":
			return {
				"owner": OWNER_CIVIC,
				"business_id": "",
				"opportunity_id": "",
				"npc_label": str(parcel.get("label", "")),
			}
		"bank":
			return {
				"owner": OWNER_BANK,
				"business_id": "",
				"opportunity_id": "",
				"npc_label": str(parcel.get("label", BankSystem.BANK_LABEL)),
			}
		"competitive":
			return {
				"owner": OWNER_NPC,
				"business_id": "",
				"opportunity_id": "",
				"npc_label": str(parcel.get("label", "Rival operator")),
			}
		_:
			return {
				"owner": OWNER_NPC,
				"business_id": "",
				"opportunity_id": "",
				"npc_label": str(parcel.get("label", "Local operator")),
			}


static func _resolve_bank(parcel: Dictionary, district: Dictionary) -> Dictionary:
	return {
		"state": OWNER_BANK,
		"headline": "Capital Farm Bank",
		"detail": "Draw a line of credit or buy fund shares · %s" % str(district.get("name", "District")),
		"business_id": "",
		"opportunity_id": "",
		"operator_name": str(parcel.get("label", BankSystem.BANK_LABEL)),
	}


static func _fallback_resolve(parcel: Dictionary) -> Dictionary:
	var role := str(parcel.get("role", "core"))
	match role:
		"development":
			return {"state": OWNER_VACANT, "headline": "Vacant development lot", "detail": "", "business_id": "", "opportunity_id": "", "operator_name": ""}
		"civic", "plaza":
			return {"state": OWNER_CIVIC, "headline": "Civic space", "detail": "", "business_id": "", "opportunity_id": "", "operator_name": str(parcel.get("label", ""))}
		"bank":
			return {"state": OWNER_BANK, "headline": "Bank branch", "detail": "Loans and fund shares always available", "business_id": "", "opportunity_id": "", "operator_name": str(parcel.get("label", BankSystem.BANK_LABEL))}
		"competitive":
			return {"state": OWNER_NPC, "headline": "NPC-operated", "detail": "", "business_id": "", "opportunity_id": "", "operator_name": str(parcel.get("label", ""))}
		_:
			return {"state": OWNER_NPC, "headline": "NPC-operated", "detail": "", "business_id": "", "opportunity_id": "", "operator_name": str(parcel.get("label", ""))}


static func _reset_parcel_to_default(state: RunState, district: Dictionary, parcel_id: String) -> void:
	var parcel := _find_parcel_by_id(district, parcel_id)
	if parcel.is_empty():
		state.parcel_assignments.erase(parcel_id)
		return
	state.parcel_assignments[parcel_id] = _default_assignment_for_parcel(parcel)


static func _clear_opportunity_binding(state: RunState, district: Dictionary, parcel_id: String) -> void:
	var assignment: Dictionary = state.parcel_assignments.get(parcel_id, {})
	if str(assignment.get("business_id", "")) != "":
		assignment["opportunity_id"] = ""
		state.parcel_assignments[parcel_id] = assignment
		return
	_reset_parcel_to_default(state, district, parcel_id)


static func _bind_opportunity(
	state: RunState,
	district: Dictionary,
	parcel_id: String,
	opp: Dictionary,
	district_id: String = ""
) -> void:
	var parcel := _find_parcel_by_id(district, parcel_id)
	var contested := bool(opp.get("rivalContest", false))
	state.parcel_assignments[parcel_id] = {
		"owner": OWNER_CONTESTED if contested else OWNER_OPPORTUNITY,
		"business_id": "",
		"opportunity_id": str(opp.get("id", "")),
		"npc_label": str(parcel.get("label", "")),
	}
	opp["parcelId"] = parcel_id
	if district_id.is_empty():
		district_id = str(district.get("id", ""))
	if not district_id.is_empty():
		opp["districtId"] = district_id


static func _assign_business_to_best_parcel(state: RunState, district: Dictionary, business: BusinessInstance) -> void:
	var parcel_id := _pick_parcel_for_business(state, district, business)
	if parcel_id.is_empty():
		return
	state.parcel_assignments[parcel_id] = {
		"owner": OWNER_PLAYER,
		"business_id": business.id,
		"opportunity_id": "",
		"npc_label": _npc_label_for_parcel_id(district, parcel_id),
	}


static func _pick_parcel_for_business(state: RunState, district: Dictionary, business: BusinessInstance) -> String:
	var candidates: Array = []
	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		if str(parcel.get("template_id", "")) != business.template_id:
			continue
		var parcel_id := str(parcel.get("id", ""))
		if parcel_id.is_empty() or not _parcel_available_for_player(state, parcel_id):
			continue
		candidates.append(parcel)

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(ROLE_PRIORITY.get(str(a.get("role", "")), 50)) < int(ROLE_PRIORITY.get(str(b.get("role", "")), 50))
	)
	if candidates.is_empty():
		return ""
	return str((candidates[0] as Dictionary).get("id", ""))


static func _pick_parcel_for_opportunity(state: RunState, district: Dictionary, opp: Dictionary) -> String:
	var template_id := str(opp.get("templateId", ""))
	if template_id.is_empty():
		return ""

	var bound_parcel_id := str(opp.get("parcelId", ""))
	if not bound_parcel_id.is_empty() and _parcel_available_for_opportunity(state, bound_parcel_id):
		return bound_parcel_id

	var candidates: Array = []
	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		var role := str(parcel.get("role", ""))
		if role in ["civic", "competitive"]:
			continue
		if str(parcel.get("template_id", "")) != template_id and role != "development":
			continue
		var parcel_id := str(parcel.get("id", ""))
		if parcel_id.is_empty() or not _parcel_available_for_opportunity(state, parcel_id):
			continue
		candidates.append(parcel)

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(ROLE_PRIORITY.get(str(a.get("role", "")), 50)) < int(ROLE_PRIORITY.get(str(b.get("role", "")), 50))
	)
	if candidates.is_empty():
		return ""
	return str((candidates[0] as Dictionary).get("id", ""))


static func _parcel_available_for_player(state: RunState, parcel_id: String) -> bool:
	var assignment: Dictionary = state.parcel_assignments.get(parcel_id, {})
	if str(assignment.get("business_id", "")) != "":
		return false
	var owner := str(assignment.get("owner", OWNER_NPC))
	return owner in [OWNER_NPC, OWNER_VACANT, OWNER_OPPORTUNITY, OWNER_CONTESTED]


static func _parcel_available_for_opportunity(state: RunState, parcel_id: String) -> bool:
	var assignment: Dictionary = state.parcel_assignments.get(parcel_id, {})
	if str(assignment.get("business_id", "")) != "":
		return false
	if str(assignment.get("opportunity_id", "")) != "":
		return false
	var owner := str(assignment.get("owner", OWNER_NPC))
	return owner in [OWNER_NPC, OWNER_VACANT]


static func _business_has_parcel(state: RunState, business_id: String) -> bool:
	for assignment_variant in state.parcel_assignments.values():
		if typeof(assignment_variant) != TYPE_DICTIONARY:
			continue
		if str((assignment_variant as Dictionary).get("business_id", "")) == business_id:
			return true
	return false


static func _opportunity_has_parcel(state: RunState, opportunity_id: String) -> bool:
	for assignment_variant in state.parcel_assignments.values():
		if typeof(assignment_variant) != TYPE_DICTIONARY:
			continue
		if str((assignment_variant as Dictionary).get("opportunity_id", "")) == opportunity_id:
			return true
	return false


static func _find_business(state: RunState, business_id: String) -> BusinessInstance:
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.id == business_id:
			return biz
	return null


static func _find_parcel_by_id(district: Dictionary, parcel_id: String) -> Dictionary:
	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		if str(parcel.get("id", "")) == parcel_id:
			return parcel
	if parcel_id.begins_with("plaza_") or ":plaza_" in parcel_id:
		for plaza_variant in district.get("plazas", []):
			if typeof(plaza_variant) != TYPE_DICTIONARY:
				continue
			var plaza: Dictionary = plaza_variant
			var plaza_key := plaza_id_for(district, plaza)
			if plaza_key == parcel_id or parcel_id.ends_with(":plaza_%d_%d" % [int(plaza.get("parcel_x", 0)), int(plaza.get("parcel_y", 0))]):
				return {
					"id": plaza_key,
					"_plaza_key": plaza_key,
					"parcel_x": int(plaza.get("parcel_x", 0)),
					"parcel_y": int(plaza.get("parcel_y", 0)),
					"label": str(plaza.get("label", "Plaza")),
					"template_id": "",
					"role": "plaza",
				}
	return {}


static func _npc_label_for_parcel_id(district: Dictionary, parcel_id: String) -> String:
	var parcel := _find_parcel_by_id(district, parcel_id)
	return str(parcel.get("label", ""))
