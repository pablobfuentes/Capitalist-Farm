extends GutTest

const Prompt := preload("res://core/systems/ai_negotiation_prompt.gd")
const NegSystem := preload("res://core/systems/negotiation_system.gd")


func _neg(ask: int, archetype_id: String = "desperate_seller", red_line: int = 0) -> Dictionary:
	var cp: Dictionary = {"archetypeId": archetype_id, "role": "seller"}
	if red_line > 0:
		cp["redLine"] = red_line
	return {
		"context": {"price": ask, "name": "Test Farm", "opp": {"price": ask, "revenue": 3000}},
		"counterparty": cp,
	}


func test_verified_block_includes_pct_of_ask() -> void:
	var block: String = Prompt.verified_negotiation_numbers_block(_neg(10000), "9200 all cash")
	assert_true(block.contains("Offer as % of ask"))
	assert_false(block.contains("PRICE ADEQUATE"))


func test_compute_offer_math_near_ask() -> void:
	var math: Dictionary = Prompt.compute_offer_math(_neg(9423, "proud_founder", 7200), "I offer 9337 all cash")
	assert_eq(int(math.get("ask", 0)), 9423)
	assert_eq(int(math.get("total", 0)), 9337)
	assert_eq(int(math.get("gap", 0)), 86)
	assert_eq(int(math.get("gapAbs", 0)), 86)


func test_verified_block_states_small_gap() -> void:
	var block: String = Prompt.verified_negotiation_numbers_block(_neg(9423, "proud_founder", 7200), "9337")
	assert_true(block.contains("$86"))
	assert_true(block.contains("NOT thousands apart"))


func test_dialogue_gap_conflict_detects_wrong_thousand_claim() -> void:
	var bad := "You're over $1,000 away from my asking price."
	assert_true(NegSystem._dialogue_gap_conflicts_with_math(bad, _neg(9423, "proud_founder", 7200), "9337"))


func test_dialogue_gap_conflict_allows_correct_gap() -> void:
	var ok := "You're $86 short — that's close."
	assert_false(NegSystem._dialogue_gap_conflicts_with_math(ok, _neg(9423, "proud_founder", 7200), "9337"))
