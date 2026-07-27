class_name AcquisitionFinance
extends RefCounted

const SELLER_NOTE_TERM := 8


static func seller_note_rate(state: RunState) -> float:
	var cfg: Dictionary = GameMode.config(state.mode)
	var rate: float = 0.12 + float(cfg.get("rate_adj", 0.0)) + LoanSystem.reputation_rate_adj(state.reputation)
	if state.has_strategic_edge("seller_financing_specialist"):
		rate -= 0.015
	return MathUtil.clamp(rate, 0.03, 0.16)


static func settle_acquisition_finance(
	state: RunState,
	ask_price: int,
	offer: Dictionary,
	kind: String,
) -> Dictionary:
	var total_price: int = int(offer.get("totalPrice", ask_price))
	var cash_requested: int = int(offer.get("cashAtClosing", total_price))
	var cash_at_closing: int = mini(state.cash, cash_requested)
	state.cash -= cash_at_closing
	var financed: int = maxi(0, total_price - cash_at_closing)
	var rate: Variant = null
	var label: Variant = null
	if financed > 0:
		rate = seller_note_rate(state)
		var terms: Dictionary = LoanSystem.compute_loan_terms(financed, float(rate), SELLER_NOTE_TERM)
		label = "Expansion Financing" if kind == "levelup" else "Seller Note (%s)" % kind
		state.loans.append({
			"id": MathUtil.uid(),
			"label": label,
			"type": kind,
			"principal": financed,
			"rate": rate,
			"principalPerTurn": terms.get("principalPerTurn", 0.0),
			"paymentPerTurn": int(round(float(terms.get("paymentPerTurn", 0.0)))),
			"turnsRemaining": SELLER_NOTE_TERM,
		})
	state.reputation += 3 if state.has_strategic_edge("relationship_capital") else 2
	return {
		"askingPrice": ask_price,
		"totalPrice": total_price,
		"cashAtClosing": cash_at_closing,
		"financed": financed,
		"sellerNoteRate": rate,
		"loanLabel": label,
	}
