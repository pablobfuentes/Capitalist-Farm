extends GutTest

const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")


func before_all() -> void:
	Content.load_farm_content()


func _make_2d_state() -> RunState:
	var state: RunState = RunState.create_new(RunState.FARM_2D_MODE)
	RunBootstrap.prepare_new_run(state)
	OpportunitySystem.refresh_opportunities(state)
	ParcelOwnershipSystem.sync_from_state(state)
	return state


func test_bank_parcel_in_meadowgate() -> void:
	var district := _Layout.load_district()
	var bank: Dictionary = {}
	for parcel_variant in district.get("parcels", []):
		if str((parcel_variant as Dictionary).get("id", "")) == "mg_20":
			bank = parcel_variant
			break
	assert_eq(str(bank.get("role", "")), BankSystem.ROLE)
	assert_true(BankSystem.is_bank_parcel(bank))


func test_bank_loan_draw_without_opportunity() -> void:
	var state := _make_2d_state()
	state.action_points = 3
	var before_cash := state.cash
	var result: Dictionary = CommandProcessor.apply(state, GameCommand.take_bank_loan())
	assert_true(bool(result.get("ok", false)))
	assert_eq(state.loans.size(), 1)
	assert_gt(state.cash, before_cash)


func test_bank_loan_cannot_be_drawn_twice_same_turn() -> void:
	var state := _make_2d_state()
	state.action_points = 3
	var first: Dictionary = CommandProcessor.apply(state, GameCommand.take_bank_loan())
	assert_true(bool(first.get("ok", false)))
	var second: Dictionary = CommandProcessor.apply(state, GameCommand.take_bank_loan())
	assert_false(bool(second.get("ok", false)))
	assert_eq(state.loans.size(), 1)


func test_buy_security_by_ticker() -> void:
	var state := _make_2d_state()
	state.action_points = 3
	state.cash = 50000
	SecuritySystem.init_run(state)
	var result: Dictionary = CommandProcessor.apply(state, GameCommand.buy_security_ticker("TCH"))
	assert_true(bool(result.get("ok", false)))
	assert_eq(state.portfolio.securities.size(), 1)


func test_buy_security_quantity_must_be_affordable() -> void:
	var state := _make_2d_state()
	state.action_points = 3
	state.cash = 500
	SecuritySystem.init_run(state)
	var result: Dictionary = CommandProcessor.apply(state, GameCommand.buy_security_ticker("TCH", 100))
	assert_false(bool(result.get("ok", false)))
