extends GutTest

const _Rival := preload("res://core/systems/rival_system.gd")


func before_all() -> void:
	Content.load_farm_content()
	NegotiationArchetypes.ensure_loaded()


func test_contest_turn_every_three_in_capital_farm() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	state.turn = 3
	assert_true(_Rival.is_contest_turn(state))
	state.turn = 4
	assert_false(_Rival.is_contest_turn(state))


func test_apply_contest_marks_highest_scored_listing() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	state.turn = 3
	OpportunitySystem.refresh_opportunities(state)
	assert_gt(state.opportunities.size(), 0)

	var result: Dictionary = _Rival.apply_contest_to_turn(state)
	assert_false(result.is_empty())
	var opp_id: String = str(result.get("opp", {}).get("id", ""))
	var found := OpportunitySystem.find_opportunity(state, opp_id)
	assert_true(bool(found.get("rivalContest", false)))


func test_build_contest_rules_caps_rival_bid_above_ask() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	OpportunitySystem.refresh_opportunities(state)
	var opp: Dictionary = state.opportunities[0]
	var rules: Dictionary = _Rival.build_contest_rules(state, opp, opp.get("counterparty", {}))
	var ask: int = int(opp.get("price", 0))
	assert_gt(int(rules.get("rivalMaxBid", 0)), ask)
	assert_lt(int(rules.get("rivalMinBid", 0)), ask)


func test_resolve_uncontested_removes_contested_listing() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	OpportunitySystem.refresh_opportunities(state)
	state.opportunities[0]["rivalContest"] = true
	var before: int = state.opportunities.size()
	_Rival.resolve_uncontested_contests(state)
	assert_eq(state.opportunities.size(), before - 1)


func test_package_comparison_handles_null_player_offer() -> void:
	var neg: Dictionary = {
		"contestRules": {"askPrice": 20000},
		"rival": {"name": "Cassius \"Cash\" Rowe"},
		"rivalLastOffer": {"totalPrice": 19000, "cashAtClosing": 11000},
		"playerLastOffer": null,
		"leadingBidder": "rival",
		"rivalConceded": false,
	}
	var text: String = _Rival.package_comparison_text(neg)
	assert_gt(text.length(), 0)
	assert_true(text.contains("19000") or text.contains("19,000"))
