class_name SecuritySystem
extends RefCounted

const SECURITIES: Array = [
	{"ticker": "TCH", "name": "Technology Fund", "sector": "technology", "basePrice": 100, "volatility": 0.09},
	{"ticker": "CNS", "name": "Consumer Fund", "sector": "consumer", "basePrice": 100, "volatility": 0.05},
	{"ticker": "NRG", "name": "Energy Fund", "sector": "energy", "basePrice": 100, "volatility": 0.08},
	{"ticker": "BNK", "name": "Banking Fund", "sector": "finance", "basePrice": 100, "volatility": 0.06},
	{"ticker": "HLT", "name": "Healthcare Fund", "sector": "healthcare", "basePrice": 100, "volatility": 0.04},
	{"ticker": "SCP", "name": "Small-Cap Fund", "sector": "small_cap", "basePrice": 100, "volatility": 0.12},
	{"ticker": "GOV", "name": "Government Bond Fund", "sector": "bonds", "basePrice": 100, "volatility": 0.015},
	{"ticker": "BRD", "name": "Broad-Market Fund", "sector": "broad", "basePrice": 100, "volatility": 0.045},
]

const MIN_SHARE_LOT := 10


static func init_run(state: RunState) -> void:
	if state.sec_prices.is_empty():
		for sec_variant in SECURITIES:
			if typeof(sec_variant) != TYPE_DICTIONARY:
				continue
			var sec: Dictionary = sec_variant
			state.sec_prices[str(sec.get("ticker", ""))] = int(sec.get("basePrice", 100))


static func security_by_ticker(ticker: String) -> Dictionary:
	for sec_variant in SECURITIES:
		if typeof(sec_variant) == TYPE_DICTIONARY and str((sec_variant as Dictionary).get("ticker", "")) == ticker:
			return sec_variant as Dictionary
	return {}


static func current_price(state: RunState, ticker: String) -> int:
	for holding_variant in state.portfolio.securities:
		if typeof(holding_variant) == TYPE_DICTIONARY and str((holding_variant as Dictionary).get("ticker", "")) == ticker:
			return int((holding_variant as Dictionary).get("price", 0))
	var tmpl: Dictionary = security_by_ticker(ticker)
	if tmpl.is_empty():
		return 0
	if state.sec_prices.has(ticker):
		return int(state.sec_prices[ticker])
	return int(tmpl.get("basePrice", 100))


static func update_prices(state: RunState, rng: SeededRng) -> void:
	init_run(state)
	var momentum: Dictionary = state.market_state.get("sectorMomentum", {})
	if typeof(momentum) != TYPE_DICTIONARY:
		momentum = {}

	for holding_variant in state.portfolio.securities:
		if typeof(holding_variant) != TYPE_DICTIONARY:
			continue
		var holding: Dictionary = holding_variant
		var ticker: String = str(holding.get("ticker", ""))
		var tmpl: Dictionary = security_by_ticker(ticker)
		if tmpl.is_empty():
			continue
		var sector: String = str(tmpl.get("sector", "broad"))
		var mom: String = str(momentum.get(sector, "neutral"))
		var drift: float = 0.02 if mom == "positive" else (-0.02 if mom == "negative" else 0.0)
		var vol: float = float(tmpl.get("volatility", 0.05))
		var new_price: int = maxi(5, int(round(float(holding.get("price", 100)) * (1.0 + drift + rng.randf_range(-vol, vol)))))
		holding["price"] = new_price
		state.sec_prices[ticker] = new_price

	for ticker: String in state.sec_prices.keys():
		if _has_holding(state, ticker):
			continue
		var tmpl: Dictionary = security_by_ticker(ticker)
		if tmpl.is_empty():
			continue
		var sector: String = str(tmpl.get("sector", "broad"))
		var mom: String = str(momentum.get(sector, "neutral"))
		var drift: float = 0.02 if mom == "positive" else (-0.02 if mom == "negative" else 0.0)
		var vol: float = float(tmpl.get("volatility", 0.05))
		var base: int = int(state.sec_prices.get(ticker, tmpl.get("basePrice", 100)))
		state.sec_prices[ticker] = maxi(5, int(round(float(base) * (1.0 + drift + rng.randf_range(-vol, vol)))))


static func securities_market_value(state: RunState) -> int:
	var total := 0
	for holding_variant in state.portfolio.securities:
		if typeof(holding_variant) != TYPE_DICTIONARY:
			continue
		var holding: Dictionary = holding_variant
		total += int(holding.get("shares", 0)) * int(holding.get("price", 0))
	return total


static func price_change_pct(current: int, basis: int) -> float:
	if basis <= 0:
		return 0.0
	return float(current - basis) / float(basis)


static func change_indicator_text(current: int, basis: int) -> String:
	if basis <= 0 or current == basis:
		return ""
	var pct: float = price_change_pct(current, basis) * 100.0
	var up: bool = pct >= 0.0
	return "%s %s%.1f%%" % ["▲" if up else "▼", "+" if up else "", absf(pct)]


static func holding_market_value(holding: Dictionary) -> int:
	return int(holding.get("shares", 0)) * int(holding.get("price", 0))


static func holding_cost_basis_total(holding: Dictionary) -> int:
	return int(holding.get("shares", 0)) * int(holding.get("costBasis", holding.get("cost_basis", 0)))


static func format_holding_summary(holding: Dictionary) -> String:
	var ticker: String = str(holding.get("ticker", ""))
	var tmpl: Dictionary = security_by_ticker(ticker)
	var shares: int = int(holding.get("shares", 0))
	var price: int = int(holding.get("price", 0))
	var basis: int = int(holding.get("costBasis", holding.get("cost_basis", price)))
	var change: String = change_indicator_text(price, basis)
	var change_suffix := " · %s" % change if not change.is_empty() else ""
	return "%s (%s)\n%d shares · Price %s · Basis %s%s\nValue %s" % [
		ticker,
		str(tmpl.get("name", "Fund")),
		shares,
		MathUtil.fmt_money(price),
		MathUtil.fmt_money(basis),
		change_suffix,
		MathUtil.fmt_money(holding_market_value(holding)),
	]


static func make_security_opportunity(state: RunState, rng: SeededRng) -> Dictionary:
	init_run(state)
	if SECURITIES.is_empty():
		return {}
	var tmpl: Dictionary = SECURITIES[rng.randi_range(0, SECURITIES.size() - 1)].duplicate(true)
	var ticker: String = str(tmpl.get("ticker", ""))
	var price: int = current_price(state, ticker)
	var momentum: String = str(state.market_state.get("sectorMomentum", {}).get(str(tmpl.get("sector", "")), "neutral"))
	return {
		"id": MathUtil.uid(),
		"kind": "investment",
		"assetType": "security",
		"ticker": ticker,
		"name": str(tmpl.get("name", ticker)),
		"price": price,
		"sector": str(tmpl.get("sector", "")),
		"momentum": momentum,
		"expiresIn": 1,
		"blurb": "%s — %s sector." % [
			"Trading below recent levels" if momentum == "negative" else "Posted price, no negotiation",
			str(tmpl.get("sector", "")),
		],
	}


static func buy_security(state: RunState, opportunity_id: String, quantity: int = 10) -> Dictionary:
	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap
	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
	if opp.is_empty() or str(opp.get("assetType", "")) != "security":
		return {"ok": false, "error": "Not a security listing"}
	var ticker: String = str(opp.get("ticker", ""))
	var price: int = int(opp.get("price", current_price(state, ticker)))
	var result: Dictionary = _purchase_shares(state, ticker, price, quantity)
	if bool(result.get("ok", false)):
		_remove_opportunity(state, opportunity_id)
	return result


static func purchase_shares(state: RunState, ticker: String, price: int, quantity: int) -> Dictionary:
	return _purchase_shares(state, ticker, price, quantity)


static func _purchase_shares(state: RunState, ticker: String, price: int, quantity: int) -> Dictionary:
	var qty: int = maxi(MIN_SHARE_LOT, int(round(float(quantity) / float(MIN_SHARE_LOT))) * MIN_SHARE_LOT)
	var cost: int = qty * price
	if state.cash < cost:
		return {"ok": false, "error": "Insufficient cash for %d shares" % qty}
	state.cash -= cost
	ActionPointsSystem.spend(state, 1)
	var holding := _find_holding(state, ticker)
	if holding.is_empty():
		state.portfolio.securities.append({
			"ticker": ticker,
			"shares": qty,
			"price": price,
			"costBasis": price,
		})
	else:
		var old_shares: int = int(holding.get("shares", 0))
		var old_basis: int = int(holding.get("costBasis", price))
		holding["shares"] = old_shares + qty
		holding["costBasis"] = int(round(float(old_basis * old_shares + cost) / float(old_shares + qty)))
		holding["price"] = price
	state.run_log.append("Bought %d shares of %s for %s." % [qty, ticker, MathUtil.fmt_money(cost)])
	return {"ok": true, "state": state, "ticker": ticker, "shares": qty, "cost": cost}


static func sell_security(state: RunState, ticker: String) -> Dictionary:
	var holding: Dictionary = _find_holding(state, ticker)
	if holding.is_empty():
		return {"ok": false, "error": "No holding for %s" % ticker}
	var proceeds: int = int(holding.get("shares", 0)) * int(holding.get("price", 0))
	state.cash += proceeds
	state.portfolio.securities = state.portfolio.securities.filter(func(h: Variant) -> bool:
		return typeof(h) != TYPE_DICTIONARY or str((h as Dictionary).get("ticker", "")) != ticker
	)
	state.run_log.append("Sold %d shares of %s for %s." % [int(holding.get("shares", 0)), ticker, MathUtil.fmt_money(proceeds)])
	return {"ok": true, "state": state, "proceeds": proceeds}


static func _find_holding(state: RunState, ticker: String) -> Dictionary:
	for holding_variant in state.portfolio.securities:
		if typeof(holding_variant) == TYPE_DICTIONARY and str((holding_variant as Dictionary).get("ticker", "")) == ticker:
			return holding_variant as Dictionary
	return {}


static func _has_holding(state: RunState, ticker: String) -> bool:
	return not _find_holding(state, ticker).is_empty()


static func _remove_opportunity(state: RunState, opportunity_id: String) -> void:
	var kept: Array = []
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		if str((opp_variant as Dictionary).get("id", "")) != opportunity_id:
			kept.append(opp_variant)
	state.opportunities = kept
