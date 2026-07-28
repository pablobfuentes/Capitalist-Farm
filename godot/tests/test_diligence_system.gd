extends GutTest

const _Diligence := preload("res://core/systems/diligence_system.gd")


func before_all() -> void:
	Content.load_farm_content()
	NegotiationArchetypes.ensure_loaded()


func test_investigate_spends_ap_and_unlocks_intel() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	OpportunitySystem.refresh_opportunities(state)
	assert_gt(state.opportunities.size(), 0)
	var opp_id: String = str(state.opportunities[0].get("id", ""))
	state.action_points = 2

	var result: Dictionary = _Diligence.investigate_opportunity(state, opp_id)
	assert_true(bool(result.get("ok", false)))
	assert_eq(state.action_points, 1)

	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opp_id)
	assert_true(bool(opp.get("diligenceDone", false)))


func test_intel_panel_locked_without_diligence() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	var neg: Dictionary = {
		"intelUnlocked": false,
		"counterparty": {"archetypeId": "desperate_seller"},
		"context": {"price": 20000},
	}
	var text: String = _Diligence.format_intel_panel(neg, state)
	assert_true(text.contains("LOCKED"))


func test_intel_panel_shows_seller_diligence_when_unlocked() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	OpportunitySystem.refresh_opportunities(state)
	var opp: Dictionary = state.opportunities[0]
	_Diligence.investigate_opportunity(state, str(opp.get("id", "")))

	var neg: Dictionary = {
		"intelUnlocked": true,
		"counterparty": opp.get("counterparty", {}),
		"context": {"price": int(opp.get("price", 0)), "diligenceDone": true},
	}
	var text: String = _Diligence.format_intel_panel(neg, state)
	assert_true(text.contains("SELLER DILIGENCE"))
	assert_true(text.contains("NEGOTIATION TACTICS"))


func test_intel_panel_shows_v2_economics_when_unlocked() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	OpportunitySystem.refresh_opportunities(state)
	var opp: Dictionary = state.opportunities[0]
	_Diligence.investigate_opportunity(state, str(opp.get("id", "")))
	opp = OpportunitySystem.find_opportunity(state, str(opp.get("id", "")))

	var neg: Dictionary = {
		"intelUnlocked": true,
		"counterparty": opp.get("counterparty", {}),
		"context": {"price": int(opp.get("price", 0)), "diligenceDone": true, "opp": opp},
	}
	var text: String = _Diligence.format_intel_panel(neg, state)
	assert_true(text.contains("NEGOTIATION ECONOMICS"))
	assert_true(text.contains("Hard floor"))
	assert_true(text.contains("Phrases that unlock progress"))


func test_v2_preview_matches_negotiation_opening() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	OpportunitySystem.refresh_opportunities(state)
	state.action_points = 5
	var opp_id: String = str(state.opportunities[0].get("id", ""))
	_Diligence.investigate_opportunity(state, opp_id)
	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opp_id)
	var preview: Dictionary = opp.get("v2Preview", {})

	var start: Dictionary = NegotiationSystem.start_negotiation(state, opp_id)
	assert_true(bool(start.get("ok", false)))
	var v2: Dictionary = state.negotiation.get("v2", {})
	assert_eq(int(v2.get("hardFloor", -1)), int(preview.get("hardFloor", -2)))
	assert_eq(int(v2.get("acceptableValue", -1)), int(preview.get("openingAcceptable", -2)))


func test_negotiation_start_carries_diligence_flag() -> void:
	var state: RunState = RunState.create_new(RunState.CAPITAL_FARM_MODE)
	OpportunitySystem.refresh_opportunities(state)
	var opp_id: String = str(state.opportunities[0].get("id", ""))
	_Diligence.investigate_opportunity(state, opp_id)

	var result: Dictionary = NegotiationSystem.start_negotiation(state, opp_id)
	assert_true(bool(result.get("ok", false)))
	assert_true(bool(state.negotiation.get("intelUnlocked", false)))
	assert_true(bool(state.negotiation.get("context", {}).get("diligenceDone", false)))
