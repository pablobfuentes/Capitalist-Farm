extends Node

## Phase 0/1 smoke test — press F5 in Godot editor.
## Validates content load, synergy detection, and turn advance.


func _ready() -> void:
	print("=== EconGame smoke test ===")
	_run()


func _run() -> void:
	var template_count: int = Content.templates_by_id.size()
	var conn_count: int = Content.connections.size()
	print("Content: %d templates, %d connections" % [template_count, conn_count])
	assert(template_count == 10, "Expected 10 farm templates")
	assert(conn_count == 29, "Expected 29 supply connections")

	var fixture_path := "res://tests/fixtures/grain_bakery_link.json"
	var state: RunState = _load_fixture(fixture_path)
	print("Fixture loaded: %d businesses" % state.portfolio.businesses.size())

	var synergies: Array = SynergySystem.compute_synergies(state)
	print("Active synergies: %d" % synergies.size())
	assert(synergies.size() == 1, "Expected grain_farm → bakery synergy")

	var syn: Dictionary = synergies[0]
	print("  %s  costReduction=%.3f  fulfill=%.2f" % [
		str(syn.get("label", "")),
		float(syn.get("costReduction", 0.0)),
		float(syn.get("fulfillRatio", 0.0)),
	])
	assert(str(syn.get("supplierTemplateId", "")) == "grain_farm")
	assert(str(syn.get("customerTemplateId", "")) == "bakery")
	assert(float(syn.get("costReduction", 0.0)) > 0.0)

	var bakery: BusinessInstance = state.portfolio.businesses[1]
	var applied: Dictionary = SynergySystem.apply_to_business(bakery, synergies, state, {})
	print("Bakery after synergy: rev=%d cost=%d savings=%d" % [
		int(applied.get("rev", 0)),
		int(applied.get("cost", 0)),
		int(applied.get("savings", 0)),
	])
	assert(int(applied.get("cost", bakery.operating_costs)) < bakery.operating_costs, "Synergy should reduce bakery opex")

	var nw_before: int = FinanceSystem.net_worth(state)
	Game.state = state
	var turn_result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	assert(bool(turn_result.get("ok", false)), "advance_turn command failed: %s" % str(turn_result.get("error", "")))
	var nw_after: int = FinanceSystem.net_worth(Game.state)
	print("Turn advanced: turn=%d cash=%d profit applied NW=%d (was %d)" % [
		Game.state.turn,
		Game.state.cash,
		nw_after,
		nw_before,
	])
	assert(Game.state.turn == 2)

	print("=== Smoke test PASSED ===")
	get_tree().quit()


func _load_fixture(path: String) -> RunState:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "Missing fixture: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(typeof(parsed) == TYPE_DICTIONARY)
	return RunState.from_dict(parsed)
