extends GutTest


func before_all() -> void:
	Content.load_farm_content()


func test_header_stats_shape() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	var stats: Dictionary = RunView.header_stats(state)
	assert_true(stats.has("turn"))
	assert_true(stats.has("netWorth"))
	assert_true(stats.has("debt"))
	assert_true(stats.has("actionPoints"))


func test_supply_chain_view_empty_portfolio() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	var view: Dictionary = RunView.supply_chain_view(state)
	assert_false(str(view.get("emptyMessage", "")).is_empty())


func test_parcel_panel_player_business_shares_display() -> void:
	const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")
	var state: RunState = RunState.create_new(RunState.FARM_2D_MODE)
	var district: Dictionary = _Layout.load_district()
	var biz := BusinessInstance.create_from_template("grain_farm", "Player Grain Farm", 12000, 7000)
	biz.id = "biz-grain-1"
	state.portfolio.businesses.append(biz)
	ParcelOwnershipSystem.on_business_acquired(state, biz, {"templateId": "grain_farm"})

	var parcel: Dictionary = {}
	for parcel_variant in district.get("parcels", []):
		if str((parcel_variant as Dictionary).get("id", "")) == "mg_01":
			parcel = parcel_variant
			break

	var panel: Dictionary = RunView.parcel_panel(state, parcel, district)
	assert_eq(str(panel.get("ownerState", "")), ParcelOwnershipSystem.OWNER_PLAYER)
	var details: String = str(panel.get("details", ""))
	assert_string_contains(details, "Val")
	assert_string_contains(details, "Profit")
	assert_false(details.contains("Template:"))
	assert_false(details.contains("Player Grain Farm"))
	var actions: Dictionary = panel.get("actions", {})
	assert_eq(str(actions.get("kind", "")), "business")
	assert_eq(str(actions.get("businessId", "")), "biz-grain-1")
	assert_string_contains(str(actions.get("sellLabel", "")), "Sell · ~")


func test_business_supply_balance_view_for_grain_farm() -> void:
	const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")
	var state: RunState = RunState.create_new(RunState.FARM_2D_MODE)
	state.farm_upgrade_v2 = true
	var district: Dictionary = _Layout.load_district()
	var biz := BusinessInstance.create_from_template("grain_farm", "Player Grain Farm", 12000, 7000)
	biz.id = "biz-grain-1"
	state.portfolio.businesses.append(biz)
	ParcelOwnershipSystem.on_business_acquired(state, biz, {"templateId": "grain_farm"})

	var parcel: Dictionary = {}
	for parcel_variant in district.get("parcels", []):
		if str((parcel_variant as Dictionary).get("id", "")) == "mg_01":
			parcel = parcel_variant
			break

	var view: Dictionary = RunView.business_supply_balance_view(state, biz, district, parcel)
	assert_true(bool(view.get("visible", false)))
	var capacity: Dictionary = view.get("capacity", {})
	assert_gt(int(capacity.get("capacity", 0)), 0)
	assert_false((view.get("clients", []) as Array).is_empty())


func test_parcel_panel_includes_supply_balance() -> void:
	const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")
	var state: RunState = RunState.create_new(RunState.FARM_2D_MODE)
	state.farm_upgrade_v2 = true
	var district: Dictionary = _Layout.load_district()
	var biz := BusinessInstance.create_from_template("grain_farm", "Player Grain Farm", 12000, 7000)
	biz.id = "biz-grain-1"
	state.portfolio.businesses.append(biz)
	ParcelOwnershipSystem.on_business_acquired(state, biz, {"templateId": "grain_farm"})

	var parcel: Dictionary = {}
	for parcel_variant in district.get("parcels", []):
		if str((parcel_variant as Dictionary).get("id", "")) == "mg_01":
			parcel = parcel_variant
			break

	var panel: Dictionary = RunView.parcel_panel(state, parcel, district)
	var supply: Dictionary = panel.get("supplyBalance", {})
	assert_true(bool(supply.get("visible", false)))


func test_parcel_panel_player_on_development_lot_uses_business_name() -> void:
	const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")
	var state: RunState = RunState.create_new(RunState.FARM_2D_MODE)
	var district: Dictionary = _Layout.load_district()
	var biz := BusinessInstance.create_from_template("grain_farm", "GrainFarm Hearthstead", 12000, 7000)
	biz.id = "biz-hearthstead"
	state.portfolio.businesses.append(biz)
	ParcelOwnershipSystem.on_business_acquired(state, biz, {
		"templateId": "grain_farm",
		"parcelId": "mg_18",
	})

	var parcel: Dictionary = {}
	for parcel_variant in district.get("parcels", []):
		if str((parcel_variant as Dictionary).get("id", "")) == "mg_18":
			parcel = parcel_variant
			break

	var panel: Dictionary = RunView.parcel_panel(state, parcel, district)
	assert_eq(str(panel.get("title", "")), "GrainFarm Hearthstead")
	assert_string_contains(str(panel.get("roleLine", "")), "Level")
	assert_false(str(panel.get("roleLine", "")).contains("Vacant"))
	assert_eq(str(panel.get("ownerState", "")), ParcelOwnershipSystem.OWNER_PLAYER)
	assert_true(str(panel.get("ownershipLine", "")).is_empty())


func test_business_display_includes_value_and_growth() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	var biz := BusinessInstance.create_from_template("grain_farm", "Test Farm", 10000, 6000)
	biz.purchase_price = 10000
	biz.marked_value = 12000
	var display: Dictionary = RunView.business_display(state, biz)
	assert_string_contains(str(display.get("summary", "")), "Val")
	assert_string_contains(str(display.get("growthLine", "")), "vs purchase")
	assert_string_contains(str(display.get("sellLabel", "")), "Sell · ~")


func test_business_display_matches_business_row_summary() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	var biz := BusinessInstance.create_from_template("grain_farm", "Test Farm", 10000, 6000)
	var row: Dictionary = RunView.business_row(state, biz)
	var display: Dictionary = RunView.business_display(state, biz)
	assert_eq(str(row.get("summary", "")), str(display.get("summary", "")))


func test_portfolio_card_data_fields() -> void:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	var biz := BusinessInstance.create_from_template("grain_farm", "Test Farm", 10000, 6000)
	biz.purchase_price = 10000
	biz.level = 2
	biz.revenue_per_turn = 14000
	biz.operating_costs = 9000
	state.portfolio.businesses.append(biz)
	var card: Dictionary = RunView.portfolio_card_data(state, biz)
	assert_eq(str(card.get("name", "")), "Test Farm")
	assert_eq(int(card.get("level", 0)), 2)
	assert_eq(int(card.get("profitPerTurn", -1)), 5000)
	assert_eq(int(card.get("revenuePerTurn", 0)), 14000)
	assert_eq(int(card.get("costPerTurn", 0)), 9000)
	assert_gt(int(card.get("currentValue", 0)), 0)
