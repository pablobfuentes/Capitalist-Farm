extends GutTest


func before_all() -> void:
	Content.load_farm_content()


func _farm_state() -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.supply_shortage_ack_turn = state.turn
	return state


func test_advance_turn_returns_events_array() -> void:
	var state: RunState = _farm_state()
	var result: Dictionary = TurnPipeline.advance_turn(state)
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	assert_true(result.has("events"))
	assert_true(result.get("events") is Array)


func test_advance_turn_emits_debrief_event() -> void:
	var state: RunState = _farm_state()
	var result: Dictionary = TurnPipeline.advance_turn(state)
	var events: Array = result.get("events", [])
	var found := false
	for ev_variant in events:
		if typeof(ev_variant) == TYPE_DICTIONARY and str((ev_variant as Dictionary).get("type", "")) == TurnPipeline.EVENT_TURN_DEBRIEF_READY:
			found = true
			break
	assert_true(found, "Expected turn debrief event after advance")


func test_blocks_advance_during_negotiation() -> void:
	var state: RunState = _farm_state()
	state.negotiation = {"active": true}
	var result: Dictionary = TurnPipeline.advance_turn(state)
	assert_false(bool(result.get("ok", false)))


func test_2d_mode_unlocks_district_on_high_net_worth() -> void:
	var state: RunState = RunState.create_new(RunState.FARM_2D_MODE)
	DistrictUnlockSystem.ensure_initialized(state)
	state.supply_shortage_ack_turn = state.turn
	state.cash = 200000
	var result: Dictionary = TurnPipeline.advance_turn(state)
	assert_true(bool(result.get("ok", false)), str(result.get("error", "")))
	var next: RunState = result.get("state")
	assert_true(DistrictUnlockSystem.is_unlocked(next, "northfield_heights"))
	var events: Array = result.get("events", [])
	var found_unlock := false
	for ev_variant in events:
		if typeof(ev_variant) != TYPE_DICTIONARY:
			continue
		var ev: Dictionary = ev_variant
		if str(ev.get("type", "")) == TurnPipeline.EVENT_DISTRICTS_UNLOCKED:
			found_unlock = true
			assert_true("northfield_heights" in ev.get("districtIds", []))
			break
	assert_true(found_unlock, "Expected districts_unlocked event")
