class_name MarketSystem
extends RefCounted

const _OpportunitySystem := preload("res://core/systems/opportunity_system.gd")
const _Security := preload("res://core/systems/security_system.gd")
const _RunStats := preload("res://core/systems/run_stats_system.gd")

const INTEREST_STATES: Array[String] = ["falling", "stable", "rising", "restrictive"]
const CREDIT_STATES: Array[String] = ["loose", "normal", "selective", "frozen"]
const DEMAND_STATES: Array[String] = ["weak", "stable", "strong"]
const CONFIDENCE_STATES: Array[String] = ["contraction", "neutral", "expansion"]
const INFLATION_STATES: Array[String] = ["low", "moderate", "high"]
const MOMENTUM_STATES: Array[String] = ["negative", "neutral", "positive"]

const SEASON_HARVEST_TEMPLATES: Array[String] = ["grain_farm", "vegetable_farm"]
const SEASON_PERISHABLE_TEMPLATES: Array[String] = [
	"vegetable_farm", "dairy_barn", "poultry_coop", "bakery", "farmhouse_restaurant", "general_store",
]

const WILDCARD_EVENTS: Array = [
	{
		"id": "estate_auction", "label": "Estate Auction", "tagline": "executor wants a clean break — one flash listing",
		"assetType": "business", "priceMult": 0.76, "expiresIn": 1,
	},
	{
		"id": "inheritance", "label": "Unexpected Inheritance", "tagline": "a relative left land and a little cash",
		"assetType": "realestate", "priceMult": 0.82, "cashBonus": 6000, "expiresIn": 2,
	},
	{
		"id": "fire_sale", "label": "Distressed Fire Sale", "tagline": "owner exiting — equipment condition uncertain",
		"assetType": "business", "priceMult": 0.64, "expiresIn": 1, "marginAdj": -0.04,
	},
]

const FARM_SHOCKS: Array = [
	{
		"id": "drought", "label": "Drought", "initial": ["grain_farm", "vegetable_farm"],
		"primary": {"costMult": 1.18, "revenueMult": 0.88},
		"note": "Drought stresses crops — feed, livestock, and food-channel costs rise along the chain.",
	},
	{
		"id": "animal_disease", "label": "Animal disease outbreak", "initial": ["dairy_barn", "poultry_coop"],
		"primary": {"costMult": 1.12, "revenueMult": 0.78},
		"note": "Animal disease cuts livestock output — bakery, restaurant, store, and logistics feel the shortage.",
	},
	{
		"id": "consumer_slowdown", "label": "Consumer slowdown", "initial": ["farmhouse_restaurant", "general_store"],
		"primary": {"revenueMult": 0.85},
		"note": "Consumers pull back — upstream producers lose volume and waste rises.",
	},
]

const MARKET_EVENTS: Array = [
	{
		"id": "equipment_failure", "label": "Equipment failure", "exposes": "old equipment / deferred maintenance",
		"cash_hit_min": 3000, "cash_hit_max": 9000,
		"note_tpl": "%s: equipment failure exposes deferred maintenance.",
	},
	{
		"id": "client_leaves", "label": "Major client leaves", "exposes": "customer concentration",
		"revenue_mult": 0.7, "note_tpl": "%s: a major client has churned.",
	},
	{
		"id": "input_price_shock", "label": "Input price shock", "exposes": "supplier concentration",
		"cost_mult": 1.15, "note_tpl": "%s: a key input has spiked in price.",
	},
	{
		"id": "demand_slowdown", "label": "Demand slowdown", "exposes": "cyclical sector / high fixed costs",
		"revenue_mult": 0.88, "note_tpl": "%s: demand has softened this quarter.",
	},
	{
		"id": "competitor_failure", "label": "Competitor failure", "exposes": "available liquidity/capacity",
		"revenue_mult": 1.12, "note_tpl": "%s: a local competitor closed, demand shifted your way.",
	},
	{
		"id": "referral_opportunity", "label": "Referral opportunity", "exposes": "strong reputation",
		"reputation_bonus": 2, "note": "A prior counterparty referred you to a promising new lead.",
	},
]


static func farm_season(state: RunState) -> Dictionary:
	if state == null or not state.is_capital_farm():
		return {}
	var q: int = (state.turn - 1) % 4
	var seasons: Array = [
		{"id": "spring", "label": "Spring Planting", "harvestRevMult": 1.0, "perishableCostMult": 1.0, "note": "Planting season — steady operations."},
		{"id": "summer", "label": "Summer Growth", "harvestRevMult": 1.04, "perishableCostMult": 1.0, "note": "Long days — produce moves well."},
		{"id": "harvest", "label": "Harvest Quarter", "harvestRevMult": 1.12, "perishableCostMult": 1.0, "note": "Grain and vegetables peak — revenue bonus on farms."},
		{"id": "winter", "label": "Winter Quarter", "harvestRevMult": 1.0, "perishableCostMult": 1.08, "note": "Cold storage and heating costs bite perishables."},
	]
	return seasons[q] if q < seasons.size() else {}


static func season_rev_mult(biz: BusinessInstance, state: RunState) -> float:
	var season: Dictionary = farm_season(state)
	if season.is_empty() or biz == null:
		return 1.0
	if biz.template_id in SEASON_HARVEST_TEMPLATES:
		return float(season.get("harvestRevMult", 1.0))
	return 1.0


static func season_cost_mult(biz: BusinessInstance, state: RunState) -> float:
	var season: Dictionary = farm_season(state)
	if season.is_empty() or biz == null:
		return 1.0
	if biz.template_id in SEASON_PERISHABLE_TEMPLATES:
		return float(season.get("perishableCostMult", 1.0))
	return 1.0


static func resolve_market_update(state: RunState) -> void:
	if state.market_state.is_empty():
		state.market_state = RunBootstrap.default_market_state()

	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 7919 + 17)

	state.market_state["interestRates"] = _drift(str(state.market_state.get("interestRates", "stable")), INTEREST_STATES, rng)
	state.market_state["creditAvailability"] = _drift(str(state.market_state.get("creditAvailability", "normal")), CREDIT_STATES, rng)
	state.market_state["consumerDemand"] = _drift(str(state.market_state.get("consumerDemand", "stable")), DEMAND_STATES, rng)
	state.market_state["businessConfidence"] = _drift(str(state.market_state.get("businessConfidence", "neutral")), CONFIDENCE_STATES, rng)
	state.market_state["inflation"] = _drift(str(state.market_state.get("inflation", "moderate")), INFLATION_STATES, rng)

	var momentum: Dictionary = state.market_state.get("sectorMomentum", {})
	if typeof(momentum) != TYPE_DICTIONARY:
		momentum = {}
	for sector_key: String in momentum.keys():
		momentum[sector_key] = _drift(str(momentum[sector_key]), MOMENTUM_STATES, rng)
	state.market_state["sectorMomentum"] = momentum
	_Security.update_prices(state, rng)


static func maybe_trigger_market_event(state: RunState) -> Dictionary:
	if not state.is_capital_farm():
		return {}
	var node_count: int = state.portfolio.businesses.size() + state.portfolio.real_estate.size()
	if node_count <= 0:
		return {}

	var cfg: Dictionary = GameMode.config(state.mode)
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 5521)

	if node_count < 2:
		if rng.randf() > 0.12 * float(cfg.get("event_freq_mult", 1.0)):
			return {}
		var early_safe: Array = MARKET_EVENTS.filter(func(ev: Variant) -> bool:
			return typeof(ev) == TYPE_DICTIONARY and str((ev as Dictionary).get("id", "")) in ["referral_opportunity", "competitor_failure"]
		)
		if early_safe.is_empty():
			return {}
		return _apply_market_event(state, early_safe[rng.randi_range(0, early_safe.size() - 1)] as Dictionary, rng, true)

	if rng.randf() > 0.35 * float(cfg.get("event_freq_mult", 1.0)):
		return {}

	if rng.randf() < 0.72 and not state.portfolio.businesses.is_empty():
		var shock: Dictionary = _pick_farm_shock(state, rng)
		if not shock.is_empty():
			return _apply_farm_shock(state, shock)

	if MARKET_EVENTS.is_empty():
		return {}
	return _apply_market_event(state, MARKET_EVENTS[rng.randi_range(0, MARKET_EVENTS.size() - 1)] as Dictionary, rng, false)


static func maybe_trigger_wildcard(state: RunState) -> Dictionary:
	if state.wildcard_triggered or state.wildcard_event.is_empty():
		return {}
	if state.turn < 7 or state.turn > 22:
		return {}
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 9191)
	if rng.randf() > 0.42:
		return {}

	state.wildcard_triggered = true
	var ev: Dictionary = state.wildcard_event
	if ev.has("cashBonus"):
		state.cash += int(ev.get("cashBonus", 0))
	var opp: Dictionary = _make_wildcard_opportunity(state, ev, rng)
	if not opp.is_empty():
		state.run_log.append("⚡ Wildcard — %s: %s. %s" % [
			str(ev.get("label", "Event")),
			str(opp.get("name", "")),
			str(ev.get("tagline", "")),
		])
		var stats: Dictionary = _RunStats.ensure(state)
		stats["wildcard"] = {"label": str(ev.get("label", "")), "turn": state.turn, "name": str(opp.get("name", ""))}
	return opp


static func _make_wildcard_opportunity(state: RunState, ev: Dictionary, rng: SeededRng) -> Dictionary:
	var opp: Dictionary = {}
	if str(ev.get("assetType", "")) == "realestate":
		opp = _OpportunitySystem._make_real_estate_opportunity(state, rng, {"expires_in": int(ev.get("expiresIn", 1))})
		if not opp.is_empty() and ev.has("priceMult"):
			opp["price"] = int(round(float(opp.get("price", 0)) * float(ev.get("priceMult", 1.0))))
	else:
		opp = _OpportunitySystem._make_business_opportunity(state, rng, {
			"expires_in": int(ev.get("expiresIn", 1)),
			"price_mult": float(ev.get("priceMult", 1.0)),
		})
		if not opp.is_empty() and ev.has("marginAdj"):
			var rev: int = int(opp.get("revenue", 0))
			var margin_adj: float = float(ev.get("marginAdj", 0.0))
			var new_margin: float = MathUtil.clamp(float(opp.get("margin", 0.2)) + margin_adj, 0.05, 0.55)
			opp["margin"] = new_margin
			opp["cost"] = int(round(float(rev) * (1.0 - new_margin)))
	if opp.is_empty():
		return {}
	opp["wildcardDeal"] = true
	opp["name"] = "%s: %s" % [str(ev.get("label", "Wildcard")), str(opp.get("name", "Listing"))]
	opp["blurb"] = ("%s. %s" % [str(ev.get("tagline", "")), str(opp.get("blurb", ""))]).strip_edges()
	opp["expiresIn"] = int(ev.get("expiresIn", opp.get("expiresIn", 1)))
	return opp


static func _pick_farm_shock(state: RunState, rng: SeededRng) -> Dictionary:
	var owned: Array[String] = []
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.template_id != "":
			owned.append(biz.template_id)
	for raw_variant in state.portfolio.real_estate:
		if typeof(raw_variant) == TYPE_DICTIONARY:
			var tid: String = str((raw_variant as Dictionary).get("templateId", ""))
			if tid != "":
				owned.append(tid)
	var eligible: Array = []
	for shock_variant in FARM_SHOCKS:
		if typeof(shock_variant) != TYPE_DICTIONARY:
			continue
		var shock: Dictionary = shock_variant
		var initial: Array = shock.get("initial", [])
		for init_id in initial:
			if str(init_id) in owned:
				eligible.append(shock)
				break
	if eligible.is_empty():
		return {}
	return eligible[rng.randi_range(0, eligible.size() - 1)] as Dictionary


static func _apply_farm_shock(state: RunState, shock: Dictionary) -> Dictionary:
	var initial: Array = shock.get("initial", [])
	var primary: Array = []
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.template_id in initial:
			primary.append(biz)
	if primary.is_empty():
		return {}
	var mults: Dictionary = shock.get("primary", {})
	var log_bits: PackedStringArray = []
	for biz: BusinessInstance in primary:
		if mults.has("revenueMult"):
			biz.revenue_per_turn = int(round(float(biz.revenue_per_turn) * float(mults.get("revenueMult", 1.0))))
		if mults.has("costMult"):
			biz.operating_costs = int(round(float(biz.operating_costs) * float(mults.get("costMult", 1.0))))
		log_bits.append(biz.name)
	return {
		"label": str(shock.get("label", "Farm shock")),
		"note": "%s Hit: %s." % [str(shock.get("note", "")), ", ".join(log_bits)],
		"exposes": "connected farm supply chain",
		"affectedCount": primary.size(),
	}


static func _apply_market_event(state: RunState, ev: Dictionary, rng: SeededRng, early_run: bool) -> Dictionary:
	var biz: BusinessInstance = null
	if not state.portfolio.businesses.is_empty():
		biz = state.portfolio.businesses[rng.randi_range(0, state.portfolio.businesses.size() - 1)]
	var note: String = str(ev.get("note", ""))
	if ev.has("note_tpl") and biz != null:
		note = str(ev.get("note_tpl", "")) % biz.name
	elif ev.has("note_tpl"):
		note = str(ev.get("note_tpl", "")) % "your operation"

	if ev.has("cash_hit_min") and biz != null:
		var hit: int = rng.randi_range(int(ev.get("cash_hit_min", 0)), int(ev.get("cash_hit_max", 0)))
		if early_run:
			hit = int(round(float(hit) * 0.35))
		state.cash -= hit
		if early_run:
			note += " (early-run impact reduced)"
	elif ev.has("revenue_mult") and biz != null:
		biz.revenue_per_turn = int(round(float(biz.revenue_per_turn) * float(ev.get("revenue_mult", 1.0))))
	elif ev.has("cost_mult") and biz != null:
		biz.operating_costs = int(round(float(biz.operating_costs) * float(ev.get("cost_mult", 1.0))))
	if ev.has("reputation_bonus"):
		state.reputation += int(ev.get("reputation_bonus", 0))

	return {
		"label": str(ev.get("label", "Market event")),
		"note": note,
		"exposes": str(ev.get("exposes", "")),
	}


static func _drift(current: String, states: Array, rng: SeededRng) -> String:
	var idx: int = states.find(current)
	if idx < 0:
		idx = states.size() / 2
	var roll: float = rng.randf()
	if roll < 0.2 and idx > 0:
		return states[idx - 1]
	if roll > 0.8 and idx < states.size() - 1:
		return states[idx + 1]
	return current
