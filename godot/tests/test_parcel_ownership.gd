extends GutTest

const _Ownership := preload("res://core/systems/parcel_ownership_system.gd")
const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")


func before_all() -> void:
	Content.load_farm_content()
	NegotiationArchetypes.ensure_loaded()


func _make_2d_state() -> RunState:
	var state: RunState = RunState.create_new(RunState.FARM_2D_MODE)
	RunBootstrap.prepare_new_run(state)
	OpportunitySystem.refresh_opportunities(state)
	_Ownership.sync_from_state(state)
	return state


func _parcel_by_id(district: Dictionary, parcel_id: String) -> Dictionary:
	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		if str(parcel.get("id", "")) == parcel_id:
			return parcel
	return {}


func test_seed_assignments_for_meadowgate_roles() -> void:
	var state := _make_2d_state()
	var district := _Layout.load_district()
	DistrictUnlockSystem.ensure_initialized(state)
	ParcelOwnershipSystem.seed_district(state, district)

	assert_eq(
		str(state.parcel_assignments["mg_16"].get("owner", "")),
		_Ownership.OWNER_NPC
	)
	assert_eq(
		str(state.parcel_assignments["mg_18"].get("owner", "")),
		_Ownership.OWNER_VACANT
	)
	assert_eq(
		str(state.parcel_assignments["mg_20"].get("owner", "")),
		_Ownership.OWNER_CIVIC
	)

	var competitive := _Ownership.resolve(state, _parcel_by_id(district, "mg_16"), district)
	assert_eq(str(competitive.get("state", "")), _Ownership.OWNER_NPC)
	assert_string_contains(str(competitive.get("detail", "")), "Rowe Family Grain")


func test_opportunity_binds_to_matching_template_parcel() -> void:
	var state := _make_2d_state()
	var district := _Layout.load_district()
	state.opportunities.append({
		"id": "test-opp-dairy",
		"assetType": "business",
		"templateId": "dairy_barn",
		"name": "Premium Dairy Listing",
		"price": 42000,
		"expiresIn": 2,
	})
	_Ownership.sync_from_state(state, district)

	var premium := _Ownership.resolve(state, _parcel_by_id(district, "mg_17"), district)
	assert_eq(str(premium.get("state", "")), _Ownership.OWNER_OPPORTUNITY)
	assert_eq(str(premium.get("opportunity_id", "")), "test-opp-dairy")


func test_business_acquisition_marks_player_owned_parcel() -> void:
	var state := _make_2d_state()
	var district := _Layout.load_district()
	var biz := BusinessInstance.new()
	biz.id = "biz-grain-1"
	biz.template_id = "grain_farm"
	biz.name = "Player Grain Farm"
	biz.revenue = 12000
	biz.cost = 7000
	state.portfolio.businesses.append(biz)

	_Ownership.on_business_acquired(state, biz, {"templateId": "grain_farm"})
	var core := _Ownership.resolve(state, _parcel_by_id(district, "mg_01"), district)
	assert_eq(str(core.get("state", "")), _Ownership.OWNER_PLAYER)
	assert_eq(str(core.get("business_id", "")), "biz-grain-1")


func test_farm_2d_counts_as_capital_farm() -> void:
	var state: RunState = RunState.create_new(RunState.FARM_2D_MODE)
	assert_true(state.is_capital_farm())
