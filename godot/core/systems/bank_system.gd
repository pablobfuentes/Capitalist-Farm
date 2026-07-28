class_name BankSystem
extends RefCounted

const ROLE := "bank"
const BANK_LABEL := "Capital Farm Bank"

const _LoanSystem := preload("res://core/systems/loan_system.gd")
const _SecuritySystem := preload("res://core/systems/security_system.gd")


static func is_bank_parcel(entry: Dictionary) -> bool:
	return str(entry.get("role", "")) == ROLE


static func applies_to(state: RunState) -> bool:
	return state != null and GameMode.is_2d_run(state.mode)


static func bank_loan_available(state: RunState) -> bool:
	return state != null and state.bank_loan_drawn_turn != state.turn


static func current_loan_offer(state: RunState) -> Dictionary:
	if state == null or not bank_loan_available(state):
		return {}
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 8803 + 41)
	var cfg: Dictionary = GameMode.config(state.mode)
	var scale: float = _tier_scale(state, cfg)
	var interest_env: String = str(state.market_state.get("interestRates", "stable"))
	var base_rate: float
	if interest_env in ["rising", "restrictive"]:
		base_rate = rng.randf_range(0.08, 0.12)
	else:
		base_rate = rng.randf_range(0.05, 0.08)
	var rate: float = MathUtil.clamp(
		base_rate + float(cfg.get("rate_adj", 0.0)) + _LoanSystem.reputation_rate_adj(state.reputation),
		0.015,
		0.14,
	)
	var credit_mult: float = _LoanSystem.credit_mult(state.reputation)
	var max_amount: int = int(round(rng.randf_range(20000.0, 80000.0) * scale * credit_mult))
	var term: int = 10
	var terms: Dictionary = _LoanSystem.compute_loan_terms(max_amount, rate, term)
	var rep_note := ""
	if state.reputation >= 35:
		rep_note = " Strong reputation improves terms."
	return {
		"maxAmount": max_amount,
		"rate": rate,
		"termTurns": term,
		"paymentPerTurn": int(round(float(terms.get("paymentPerTurn", 0.0)))),
		"totalReturn": int(terms.get("totalReturn", 0)),
		"blurb": "Standing line of credit — draw cash now, repay over %d quarters.%s" % [term, rep_note],
	}


static func loan_offer_row(state: RunState) -> Dictionary:
	if not bank_loan_available(state):
		return {
			"summary": "Line of credit already drawn this turn.\nVisit again next quarter for a new offer.",
			"canTake": false,
			"alreadyDrawn": true,
		}
	var offer: Dictionary = current_loan_offer(state)
	if offer.is_empty():
		return {}
	var amount: int = int(offer.get("maxAmount", 0))
	return {
		"summary": "%s\nReceive %s · Rate %s/qtr · Payment %s/qtr for %d qtrs · Total %s\n%s" % [
			"Bank Line of Credit",
			MathUtil.fmt_money(amount),
			MathUtil.fmt_pct(float(offer.get("rate", 0.0))),
			MathUtil.fmt_money(int(offer.get("paymentPerTurn", 0))),
			int(offer.get("termTurns", 10)),
			MathUtil.fmt_money(int(offer.get("totalReturn", 0))),
			str(offer.get("blurb", "")),
		],
		"canTake": state.action_points >= 1 and amount > 0,
		"alreadyDrawn": false,
	}


static func security_catalog(state: RunState) -> Array:
	_SecuritySystem.init_run(state)
	var rows: Array = []
	for sec_variant in _SecuritySystem.SECURITIES:
		if typeof(sec_variant) != TYPE_DICTIONARY:
			continue
		var tmpl: Dictionary = sec_variant
		var ticker: String = str(tmpl.get("ticker", ""))
		if ticker.is_empty():
			continue
		var price: int = _SecuritySystem.current_price(state, ticker)
		var sector: String = str(tmpl.get("sector", ""))
		var momentum: String = str(state.market_state.get("sectorMomentum", {}).get(sector, "neutral"))
		var momentum_tag := ""
		match momentum:
			"positive":
				momentum_tag = " · Sector momentum ▲"
			"negative":
				momentum_tag = " · Sector momentum ▼"
		rows.append({
			"ticker": ticker,
			"name": str(tmpl.get("name", ticker)),
			"pricePerShare": price,
			"summary": "%s (%s)\nPrice %s/share · %s sector%s · lots of %d shares" % [
				str(tmpl.get("name", ticker)),
				ticker,
				MathUtil.fmt_money(price),
				sector,
				momentum_tag,
				_SecuritySystem.MIN_SHARE_LOT,
			],
		})
	return rows


static func bank_panel(state: RunState, entry: Dictionary, district: Dictionary) -> Dictionary:
	var loan_row: Dictionary = loan_offer_row(state)
	var details_lines: PackedStringArray = []
	details_lines.append("Lines of credit and fund shares.")
	if not loan_row.is_empty():
		details_lines.append(str(loan_row.get("summary", "")))
	return {
		"title": str(entry.get("label", BANK_LABEL)),
		"roleLine": "Regional bank · %s" % str(district.get("name", "Unknown")),
		"details": "\n".join(details_lines),
		"ownershipLine": "Public services",
		"ownershipColor": Color(0.78, 0.88, 0.98, 1.0),
		"ownerState": ParcelOwnershipSystem.OWNER_BANK,
		"actions": {
			"kind": "bank",
			"canOpen": true,
			"canTakeLoan": bool(loan_row.get("canTake", false)),
		},
	}


static func _tier_scale(state: RunState, cfg: Dictionary) -> float:
	if not bool(cfg.get("tier_scale_on", false)):
		return 1.0
	var capital: float = float(maxi(FinanceSystem.net_worth(state), maxi(state.cash, 1000)))
	return MathUtil.clamp(capital / 90000.0, 0.35, 16.0)


static func take_loan(state: RunState) -> Dictionary:
	if not applies_to(state):
		return {"ok": false, "error": "Bank not available in this mode"}
	if not bank_loan_available(state):
		return {"ok": false, "error": "Line of credit already drawn this turn"}
	var offer: Dictionary = current_loan_offer(state)
	if offer.is_empty():
		return {"ok": false, "error": "No credit available"}
	var result: Dictionary = _LoanSystem.take_loan_from_offer(state, {
		"name": "Bank Line of Credit",
		"maxAmount": int(offer.get("maxAmount", 0)),
		"rate": float(offer.get("rate", 0.0)),
		"termTurns": int(offer.get("termTurns", 10)),
		"source": "bank",
	})
	if bool(result.get("ok", false)):
		state.bank_loan_drawn_turn = state.turn
	return result


static func can_afford_shares(state: RunState, price_per_share: int, quantity: int) -> bool:
	if state == null or state.action_points < 1:
		return false
	var lot: int = _SecuritySystem.MIN_SHARE_LOT
	var qty: int = maxi(lot, int(round(float(quantity) / float(lot))) * lot)
	return state.cash >= qty * price_per_share


static func buy_shares(state: RunState, ticker: String, quantity: int = 10) -> Dictionary:
	if not applies_to(state):
		return {"ok": false, "error": "Bank not available in this mode"}
	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap
	if _SecuritySystem.security_by_ticker(ticker).is_empty():
		return {"ok": false, "error": "Unknown fund %s" % ticker}
	_SecuritySystem.init_run(state)
	var price: int = _SecuritySystem.current_price(state, ticker)
	if not can_afford_shares(state, price, quantity):
		return {"ok": false, "error": "Insufficient cash for %d shares" % quantity}
	return _SecuritySystem.purchase_shares(state, ticker, price, quantity)
