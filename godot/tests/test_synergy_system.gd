extends GutTest

const FIXTURE := "res://tests/fixtures/grain_bakery_link.json"


func before_all() -> void:
	Content.load_farm_content()


func test_content_registry_loads_farm_data() -> void:
	assert_eq(Content.templates_by_id.size(), 10, "template count")
	assert_eq(Content.connections.size(), 29, "connection count")
	var grain: BusinessTemplate = Content.get_template("grain_farm")
	assert_not_null(grain)
	assert_eq(grain.layer, "primary_production")


func test_grain_to_bakery_synergy_active() -> void:
	var state: RunState = _load_fixture(FIXTURE)
	var synergies: Array = SynergySystem.compute_synergies(state)
	assert_eq(synergies.size(), 1)
	var syn: Dictionary = synergies[0]
	assert_eq(str(syn.get("connectionId", "")), "grain_to_bakery")
	assert_eq(str(syn.get("supplierTemplateId", "")), "grain_farm")
	assert_eq(str(syn.get("customerTemplateId", "")), "bakery")
	assert_gt(float(syn.get("costReduction", 0.0)), 0.0)
	assert_eq(float(syn.get("fulfillRatio", 0.0)), 1.0)


func test_synergy_reduces_bakery_operating_costs() -> void:
	var state: RunState = _load_fixture(FIXTURE)
	var synergies: Array = SynergySystem.compute_synergies(state)
	var bakery: BusinessInstance = state.portfolio.businesses[1]
	var base_cost: int = bakery.operating_costs
	var applied: Dictionary = SynergySystem.apply_to_business(bakery, synergies, state, {})
	assert_lt(int(applied.get("cost", base_cost)), base_cost)
	assert_gt(int(applied.get("savings", 0)), 0)


func test_advance_turn_increments_and_updates_cash() -> void:
	var state: RunState = _load_fixture(FIXTURE)
	var resolver := TurnResolver.new()
	var cash_before: int = state.cash
	var rates: Dictionary = FinanceSystem.compute_quarterly_run_rates(state)
	var next: RunState = resolver.advance_turn(state)
	assert_eq(next.turn, 2)
	assert_eq(next.cash, cash_before + int(rates.get("profit", 0)))


func _load_fixture(path: String) -> RunState:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "fixture file")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return RunState.from_dict(parsed)
