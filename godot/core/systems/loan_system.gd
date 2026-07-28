# Bank lines of credit — port of MVP computeLoanTerms / takeLoan / payoffLoan.
class_name LoanSystem
extends RefCounted


static func compute_loan_terms(amount: int, rate: float, term: int = 10) -> Dictionary:
	var principal_per_turn: float = float(amount) / maxf(1.0, float(term))
	var payment_per_turn: float = principal_per_turn + float(amount) * rate
	return {
		"principalPerTurn": principal_per_turn,
		"paymentPerTurn": payment_per_turn,
		"totalReturn": int(round(payment_per_turn * float(term))),
		"term": term,
	}


static func remaining_interest(loan: Dictionary) -> int:
	var payment: int = int(loan.get("paymentPerTurn", 0))
	var principal: int = int(loan.get("principal", 0))
	var remaining: int = int(loan.get("turnsRemaining", 0))
	return maxi(0, payment * remaining - principal)


static func debt_service_total(state: RunState) -> int:
	return FinanceSystem.compute_quarterly_run_rates(state, false).get("debtService", 0)


static func loans_taken_this_turn(state: RunState) -> Array:
	var taken: Array = []
	for loan_variant in state.loans:
		if typeof(loan_variant) != TYPE_DICTIONARY:
			continue
		var loan: Dictionary = loan_variant
		if int(loan.get("takenTurn", loan.get("taken_turn", -1))) == state.turn:
			taken.append(loan)
	return taken


static func format_opportunity_line(opp: Dictionary) -> String:
	var amount: int = int(opp.get("maxAmount", 0))
	var rate: float = float(opp.get("rate", 0.0))
	var term: int = int(opp.get("termTurns", 10))
	var terms: Dictionary = compute_loan_terms(amount, rate, term)
	var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
	return "%s\nReceive %s · Rate %s/qtr · Payment %s/qtr for %d qtrs · Total %s%s\n%s" % [
		str(opp.get("name", "Bank Line of Credit Offer")),
		MathUtil.fmt_money(amount),
		MathUtil.fmt_pct(rate),
		MathUtil.fmt_money(int(round(float(terms.get("paymentPerTurn", 0.0))))),
		term,
		MathUtil.fmt_money(int(terms.get("totalReturn", 0))),
		expiry_tag,
		str(opp.get("blurb", "")).substr(0, 140),
	]


static func format_portfolio_line(loan: Dictionary) -> String:
	var payment: int = int(loan.get("paymentPerTurn", 0))
	var principal: int = int(loan.get("principal", 0))
	var remaining: int = int(loan.get("turnsRemaining", 0))
	var saved: int = remaining_interest(loan)
	return "%s\nPrincipal %s · Pmt %s/qtr · Rate %s/qtr · %d qtrs left\nPay off now: %s (saves %s interest)" % [
		str(loan.get("label", "Loan")),
		MathUtil.fmt_money(principal),
		MathUtil.fmt_money(payment),
		MathUtil.fmt_pct(float(loan.get("rate", 0.0))),
		remaining,
		MathUtil.fmt_money(principal),
		MathUtil.fmt_money(saved),
	]


static func total_debt(state: RunState) -> int:
	var total := 0
	for loan_variant in state.loans:
		if typeof(loan_variant) != TYPE_DICTIONARY:
			continue
		total += int((loan_variant as Dictionary).get("principal", 0))
	return total


static func find_loan(state: RunState, loan_id: String) -> Dictionary:
	for loan_variant in state.loans:
		if typeof(loan_variant) != TYPE_DICTIONARY:
			continue
		var loan: Dictionary = loan_variant
		if str(loan.get("id", "")) == loan_id:
			return loan
	return {}


static func take_loan(state: RunState, opportunity_id: String) -> Dictionary:
	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap

	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
	if opp.is_empty() or str(opp.get("assetType", "")) != "loan":
		return {"ok": false, "error": "Loan offer not found"}

	return _draw_loan(state, opp, true)


static func take_loan_from_offer(state: RunState, offer: Dictionary) -> Dictionary:
	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap
	if offer.is_empty() or int(offer.get("maxAmount", 0)) <= 0:
		return {"ok": false, "error": "No credit available"}
	return _draw_loan(state, offer, false)


static func _draw_loan(state: RunState, opp: Dictionary, remove_opportunity: bool) -> Dictionary:
	var amount: int = int(opp.get("maxAmount", 0))
	var rate: float = float(opp.get("rate", 0.0))
	var term: int = int(opp.get("termTurns", 10))
	if amount <= 0:
		return {"ok": false, "error": "Invalid loan amount"}

	ActionPointsSystem.spend(state, 1)
	state.cash += amount

	var terms: Dictionary = compute_loan_terms(amount, rate, term)
	var loan: Dictionary = {
		"id": MathUtil.uid(),
		"label": str(opp.get("name", "Bank Line of Credit")),
		"type": "personal",
		"principal": amount,
		"rate": rate,
		"principalPerTurn": terms.get("principalPerTurn", 0.0),
		"paymentPerTurn": int(round(float(terms.get("paymentPerTurn", 0.0)))),
		"turnsRemaining": term,
		"takenTurn": state.turn,
	}
	state.loans.append(loan)
	if remove_opportunity:
		var opp_id := str(opp.get("id", ""))
		if not opp_id.is_empty():
			_remove_opportunity(state, opp_id)

	state.run_log.append(
		"Drew %s line of credit at %s/qtr — %s/qtr for %d quarters, %s total." % [
			MathUtil.fmt_money(amount),
			MathUtil.fmt_pct(rate),
			MathUtil.fmt_money(int(loan.get("paymentPerTurn", 0))),
			term,
			MathUtil.fmt_money(int(terms.get("totalReturn", 0))),
		]
	)

	return {"ok": true, "state": state, "loan": loan}


static func payoff_loan(state: RunState, loan_id: String) -> Dictionary:
	var loan: Dictionary = find_loan(state, loan_id)
	if loan.is_empty():
		return {"ok": false, "error": "Loan not found"}

	var principal: int = int(loan.get("principal", 0))
	if state.cash < principal:
		return {"ok": false, "error": "Need %s cash to pay off early" % MathUtil.fmt_money(principal)}

	var payment: int = int(loan.get("paymentPerTurn", 0))
	var remaining: int = int(loan.get("turnsRemaining", 0))
	var remaining_interest: int = maxi(0, payment * remaining - principal)

	state.cash -= principal
	state.loans = _loans_without_id(state.loans, loan_id)
	state.run_log.append(
		"Paid off %s early for %s — saved %s in future interest." % [
			str(loan.get("label", "loan")),
			MathUtil.fmt_money(principal),
			MathUtil.fmt_money(remaining_interest),
		]
	)

	return {"ok": true, "state": state}


static func amortize_loans(state: RunState) -> void:
	var kept: Array = []
	for loan_variant in state.loans:
		if typeof(loan_variant) != TYPE_DICTIONARY:
			continue
		var loan: Dictionary = (loan_variant as Dictionary).duplicate(true)
		var turns: int = int(loan.get("turnsRemaining", 0)) - 1
		var principal: float = float(loan.get("principal", 0)) - float(loan.get("principalPerTurn", 0.0))
		loan["turnsRemaining"] = turns
		loan["principal"] = int(round(maxf(0.0, principal)))
		if turns > 0 and int(loan.get("principal", 0)) > 0:
			kept.append(loan)
	state.loans = kept


static func credit_mult(reputation: int) -> float:
	if reputation >= 80:
		return 1.4
	if reputation >= 55:
		return 1.28
	if reputation >= 35:
		return 1.18
	if reputation >= 18:
		return 1.1
	return 1.0


static func reputation_rate_adj(reputation: int) -> float:
	if reputation >= 80:
		return -0.025
	if reputation >= 55:
		return -0.018
	if reputation >= 35:
		return -0.012
	if reputation >= 18:
		return -0.008
	return 0.0


static func _remove_opportunity(state: RunState, opportunity_id: String) -> void:
	var kept: Array = []
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		if str((opp_variant as Dictionary).get("id", "")) != opportunity_id:
			kept.append(opp_variant)
	state.opportunities = kept


static func _loans_without_id(loans: Array, loan_id: String) -> Array:
	var kept: Array = []
	for loan_variant in loans:
		if typeof(loan_variant) != TYPE_DICTIONARY:
			continue
		if str((loan_variant as Dictionary).get("id", "")) != loan_id:
			kept.append(loan_variant)
	return kept
