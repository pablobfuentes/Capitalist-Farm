# Prompt builder for local Ollama proxy — ports js/ollama-negotiate.js + js/farm-animal-npc.js buildPrompt.
class_name AiNegotiationPrompt
extends RefCounted

const _Archetypes := preload("res://core/content/negotiation_archetypes.gd")
const _NpcSpecies := preload("res://core/systems/npc_species_system.gd")
const _Parser := preload("res://core/systems/negotiation_offer_parser.gd")


static func format_portfolio_facts(state: RunState, context: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("Cash: %s" % MathUtil.fmt_money(state.cash))
	lines.append("Reputation: %d" % state.reputation)
	lines.append("Net worth: %s" % MathUtil.fmt_money(FinanceSystem.net_worth(state)))

	var deal_asset := str(context.get("name", ""))
	if not deal_asset.is_empty():
		lines.append("Asset under negotiation: %s" % deal_asset)

	if state.portfolio.businesses.is_empty():
		lines.append("Owned businesses: none")
	else:
		var names: PackedStringArray = []
		for biz: BusinessInstance in state.portfolio.businesses:
			names.append(biz.name)
		lines.append("Owned businesses (%d): %s" % [state.portfolio.businesses.size(), "; ".join(names)])

	if state.portfolio.real_estate.is_empty():
		lines.append("Owned properties: none")
	else:
		var props: PackedStringArray = []
		for re: Dictionary in state.portfolio.real_estate:
			props.append(str(re.get("name", "Property")))
		lines.append("Owned properties (%d): %s" % [state.portfolio.real_estate.size(), "; ".join(props)])

	var template_ids: PackedStringArray = []
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.template_id not in template_ids:
			template_ids.append(biz.template_id)
	if not template_ids.is_empty():
		lines.append("Owned asset types (for chain claims): %s" % ", ".join(template_ids))

	return "\n".join(lines)


static func claim_verification_rules(portfolio_facts_block: String) -> String:
	var facts := portfolio_facts_block.strip_edges()
	var header := ""
	if facts.is_empty():
		header = "VERIFIED IN-GAME FACTS: not provided — treat specific portfolio or asset ownership claims as unverified.\n"
	else:
		header = "VERIFIED IN-GAME FACTS (sole source of truth for portfolio / asset claims):\n%s\n" % facts

	return """%sCLAIM HANDLING (critical — follow exactly):
- The player CANNOT upload documents, spreadsheets, screenshots, or proof. NEVER ask them to "show records," "provide demonstrable results," "send documentation," or "prove it with numbers" unless those numbers already appear in VERIFIED IN-GAME FACTS above.
- OFF-GAME / ROLEPLAY claims (years of management experience, prior career, industry background, personal work ethic, relationships outside this run, general business acumen): if the player asserts them, treat as true for dialogue. You may react in character (skepticism, respect, etc.) but do NOT demand evidence or refuse to proceed until proof is shown.
- IN-GAME claims (owns specific farms/businesses/properties, current cash or debt, portfolio scale, supply-chain control, "I already own every vegetable farm"): ONLY treat as true if consistent with VERIFIED IN-GAME FACTS. If the player exaggerates or lies about in-game assets, challenge in character — reference what you actually know of their position. Do not ask them to produce proof; simply disbelieve or push back on false in-game boasts.
- This rule governs factual assertions, not price haggling. Numeric offers and counter-offers follow normal negotiation.""" % header


static func negotiation_priority_rules() -> String:
	return """ENGINE AUTHORITY (critical — Negotiation Mechanics v2):
- The rules engine owns acceptance, gauge movement, discount unlock, and counteroffers. You write dialogue only.
- Two gates must both pass before Close Deal: (1) risk-adjusted offer value >= current acceptable value, (2) Deal Momentum gauge >= Close zone (55+).
- When ENGINE RESULT says both gates are met or Ready to Close: accept the PLAYER's parsed offer on the table. Quote THEIR total and cash terms — never restate the asking price as your acceptance price.
- Warm conversation can raise willingness but cannot make an inadequate offer acceptable.
- A strong offer can satisfy economics but still fail if willingness is too low or a red line was hit.
- Non-monetary terms (employee care, legacy, warranties, etc.) add real value through the engine — mention them when present in the structured offer.
- Never invent dollar amounts, hidden floors, or claim the deal is closed — the engine decides."""


static func engine_result_block(negotiation: Dictionary) -> String:
	var v2_result: Variant = negotiation.get("lastV2")
	var profile: Dictionary = negotiation.get("v2", {})
	if typeof(profile) != TYPE_DICTIONARY or profile.is_empty():
		return ""
	var lines: PackedStringArray = []
	lines.append("- Ask price: %s" % MathUtil.fmt_money(int(profile.get("askPrice", 0))))
	lines.append("- Business situation: %s" % str(profile.get("situationLabel", "")))
	lines.append("- Species: %s" % str(profile.get("speciesId", "")))
	lines.append("- Leverage (qualitative): %s" % str(profile.get("leverageLabel", "Balanced")))
	if v2_result is Dictionary and not (v2_result as Dictionary).is_empty():
		var r: Dictionary = v2_result as Dictionary
		var zone: Dictionary = r.get("gaugeZone", {})
		lines.append("- Engine decision this turn: %s" % str(r.get("decision", "continue")))
		lines.append("- Deal Momentum zone: %s" % str(zone.get("label", "")))
		lines.append("- Economic gate met: %s" % ("yes" if bool(r.get("economicGateMet", false)) else "no"))
		lines.append("- Willingness gate met: %s" % ("yes" if bool(r.get("willingnessGateMet", false)) else "no"))
		lines.append("- Status hint for UI: %s" % str(r.get("statusHint", "")))
		if bool(r.get("readyToClose", false)):
			lines.append("- READY TO CLOSE: yes — dialogue MUST accept the player's current parsed offer total (not the asking price).")
		if int(r.get("offerValue", 0)) > 0:
			lines.append("- Risk-adjusted offer value (engine): %s" % MathUtil.fmt_money(int(r.get("offerValue", 0))))
	return """
ENGINE RESULT (authoritative — reflect this outcome in dialogue; do not override):
%s""" % "\n".join(lines)


static func price_math_rules() -> String:
	return """PRICE MATH RULES (critical — follow exactly):
- NEVER do mental arithmetic. Do NOT estimate gaps, percentages, or differences yourself.
- For ANY comparison to asking price, quote ONLY the verified "Gap vs ask" and "Plain English" lines from VERIFIED NEGOTIATION NUMBERS below.
- If the verified gap is under $500, describe it as "within a few hundred dollars" or state the exact verified dollar gap — never say $1,000+ unless verified gap is >= 1000.
- Revenue, margin, and quarterly figures are NOT purchase prices — never compare an offer to revenue unless the player explicitly offered that number as a purchase price."""


static func compute_offer_math(negotiation: Dictionary, player_message: String) -> Dictionary:
	var ctx: Dictionary = negotiation.get("context", {})
	var ask: int = int(ctx.get("price", 0))
	if ask <= 0:
		return {}

	var amounts: Dictionary = _Parser.parse_offer_amounts_from_text(player_message, ask)
	if amounts.is_empty() or int(amounts.get("totalPrice", 0)) <= 0:
		var built: Dictionary = _Parser.build_player_offer_from_message(
			player_message,
			{"intent": "question"},
			negotiation,
		)
		var offer: Variant = built.get("offer")
		if offer is Dictionary and int((offer as Dictionary).get("totalPrice", 0)) > 0:
			var o: Dictionary = offer as Dictionary
			amounts = {
				"totalPrice": int(o.get("totalPrice", 0)),
				"cashAtClosing": int(o.get("cashAtClosing", o.get("totalPrice", 0))),
			}

	if amounts.is_empty() or int(amounts.get("totalPrice", 0)) <= 0:
		return {}

	var total: int = int(amounts.get("totalPrice", 0))
	var cash: int = int(amounts.get("cashAtClosing", total))
	var gap: int = ask - total
	var pct_of_ask: float = float(total) / maxf(1.0, float(ask))
	return {
		"ask": ask,
		"total": total,
		"cashAtClosing": cash,
		"gap": gap,
		"gapAbs": abs(gap),
		"gapPct": absf(float(gap)) / maxf(1.0, float(ask)) * 100.0,
		"pctOfAsk": pct_of_ask,
		"belowAsk": gap > 0,
		"aboveAsk": gap < 0,
		"atAsk": gap == 0,
	}


static func verified_negotiation_numbers_block(negotiation: Dictionary, player_message: String) -> String:
	var math: Dictionary = compute_offer_math(negotiation, player_message)
	var ctx: Dictionary = negotiation.get("context", {})
	var ask: int = int(ctx.get("price", 0))
	if ask <= 0:
		return ""

	var lines: PackedStringArray = []
	lines.append("- Asking price: %s (%d)" % [MathUtil.fmt_money(ask), ask])

	if not math.is_empty():
		var total: int = int(math.get("total", 0))
		var cash: int = int(math.get("cashAtClosing", total))
		var gap: int = int(math.get("gap", 0))
		var pct: float = float(math.get("gapPct", 0.0))

		lines.append("- Player offer total (parsed from latest message): %s (%d)" % [MathUtil.fmt_money(total), total])
		lines.append("- Cash at closing: %s (%d)" % [MathUtil.fmt_money(cash), cash])
		if gap > 0:
			lines.append("- Gap vs ask: %s below ask (%.1f%% below)" % [MathUtil.fmt_money(gap), pct])
			if gap < 500:
				lines.append("- Plain English: the bid is only %s short of asking — very close, NOT thousands apart." % MathUtil.fmt_money(gap))
			else:
				lines.append("- Plain English: the bid is %s below asking." % MathUtil.fmt_money(gap))
		elif gap < 0:
			lines.append("- Gap vs ask: %s above ask (%.1f%% premium)" % [MathUtil.fmt_money(-gap), pct])
			lines.append("- Plain English: the bid exceeds asking by %s." % MathUtil.fmt_money(-gap))
		else:
			lines.append("- Gap vs ask: $0 — matches asking price exactly")
		if cash < total:
			lines.append("- Seller note / deferred portion: %s" % MathUtil.fmt_money(total - cash))
		lines.append("- Offer as %% of ask: %.1f%%" % (float(math.get("pctOfAsk", 0.0)) * 100.0))
		var parsed_terms: Array = _Parser.extract_terms_from_text(player_message)
		if not parsed_terms.is_empty():
			var term_parts: PackedStringArray = []
			for t in parsed_terms:
				term_parts.append(str(t))
			lines.append("- Non-monetary terms parsed from player message: %s" % ", ".join(term_parts))

	var last: Variant = negotiation.get("playerLastOffer")
	if last is Dictionary and int((last as Dictionary).get("totalPrice", 0)) > 0:
		var lt: int = int((last as Dictionary).get("totalPrice", 0))
		if math.is_empty() or int(math.get("total", 0)) != lt:
			lines.append("- Previous offer still on table: %s" % MathUtil.fmt_money(lt))

	if lines.size() <= 1:
		return ""

	var body := "\n".join(lines)
	return """
VERIFIED NEGOTIATION NUMBERS (sole source of truth for price math in your reply):
%s
%s
%s""" % [body, price_math_rules(), negotiation_priority_rules()]


static func _listing_block(ctx: Dictionary, opp: Dictionary) -> String:
	var ask: int = int(ctx.get("price", 0))
	if ask <= 0:
		return ""
	var rev = opp.get("revenue")
	var margin_pct: Variant = null
	if opp.has("margin"):
		margin_pct = int(round(float(opp.get("margin", 0)) * 100.0))
	var rev_line := ""
	if rev != null:
		rev_line = "- Quarterly revenue = operating income per quarter (NOT a purchase price): %d/qtr\n" % int(rev)
	var margin_line := ""
	if margin_pct != null:
		margin_line = "- Estimated margin = profit margin on revenue (NOT a purchase price): %d%%\n" % int(margin_pct)
	return """
LISTING ECONOMICS (critical — do NOT confuse with the player's purchase offer):
- Asking price = total purchase price seller wants for the asset: %d
%s%s
When the player cites revenue, margin, or maintenance to argue, that is rhetoric — NOT an offer to buy at the revenue figure.
Only use intent "offer" when the player states what they will PAY to acquire the asset. Never put revenue in offer.totalPrice.
You provide dialogue and JSON fields only — the game engine decides acceptance. If unsure, use intent "question".""" % [
		ask,
		rev_line,
		margin_line,
	]


static func _history_block(negotiation: Dictionary) -> String:
	var history_lines: PackedStringArray = []
	for msg_variant in negotiation.get("messages", []):
		if typeof(msg_variant) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = msg_variant
		if str(msg.get("role", "")) == "system":
			continue
		var who := str(msg.get("speaker", msg.get("role", ""))).to_upper()
		history_lines.append("%s: %s" % [who, str(msg.get("text", ""))])
	return "\n".join(history_lines)


static func _intent_json_suffix() -> String:
	return """
Classify the PLAYER's latest message carefully:
- "question": they asked something, made small talk, or said anything that is not a concrete numeric proposal or explicit agreement. This is the default — most messages are this.
- "offer": ONLY if the player explicitly proposed specific numeric terms (a price, a split, a percentage) in this message.
- "accept": ONLY if the player explicitly agreed to accept the specific terms currently on the table.
- "walk": ONLY if the player explicitly said they are ending the negotiation.
Never invent numbers the player did not say. If intent is "question", every field inside "offer" must be null and termsOffered must be [].

Reply with ONLY a raw JSON object (no markdown fences, no extra text) matching exactly:
{"dialogue": "in-character reply, 1-3 sentences", "intent": "question|offer|accept|walk", "offer": {"totalPrice": number|null, "cashAtClosing": number|null, "closingSpeed": "fast|standard|extended", "termsOffered": [string], "priceAdjustment": number|null, "concessionSize": number|null}}"""


static func build_default_prompt(state: RunState, negotiation: Dictionary, player_message: String) -> String:
	var cp: Dictionary = negotiation.get("counterparty", {})
	var ctx: Dictionary = negotiation.get("context", {})
	var opp: Dictionary = ctx.get("opp", {})
	var arch: Dictionary = _Archetypes.get_archetype(str(cp.get("archetypeId", "")))

	var price: int = int(ctx.get("price", 0))
	var preferred_parts: PackedStringArray = []
	for term in cp.get("preferredTerms", []):
		preferred_parts.append(str(term))
	var preferred := ", ".join(preferred_parts)
	var portfolio_facts := format_portfolio_facts(state, ctx)
	var claim_block := claim_verification_rules(portfolio_facts)
	var listing_block := _listing_block(ctx, opp)
	var hidden := str(cp.get("hiddenInfo", ""))
	var numbers_block := verified_negotiation_numbers_block(negotiation, player_message)

	return """You are role-playing a counterparty in a business negotiation game.
Role: %s. Personality: %s (%s).
%s
%s
%s
You privately know (do not state outright unless it becomes relevant): %s.
You respond to: %s.
%s
Stay in character, be concise (1-3 sentences), never break the fourth wall, never reveal you are an AI.
Conversation so far:
%s
PLAYER: %s
%s""" % [
		str(cp.get("role", "counterparty")),
		str(arch.get("name", "Negotiator")),
		str(arch.get("flavor", "")),
		listing_block,
		numbers_block,
		("Asking/reference price: %d." % price) if price > 0 else "",
		hidden if not hidden.is_empty() else "none",
		preferred,
		claim_block,
		_history_block(negotiation),
		player_message,
		_intent_json_suffix(),
	]


static func build_farm_prompt(state: RunState, negotiation: Dictionary, player_message: String) -> String:
	var cp: Dictionary = negotiation.get("counterparty", {})
	var ctx: Dictionary = negotiation.get("context", {})
	var opp: Dictionary = ctx.get("opp", {})
	var arch: Dictionary = _Archetypes.get_archetype(str(cp.get("archetypeId", "")))

	var price: int = int(ctx.get("price", 0))
	var preferred_parts: PackedStringArray = []
	for term in cp.get("preferredTerms", []):
		preferred_parts.append(str(term))
	var preferred := ", ".join(preferred_parts)
	var portfolio_facts := format_portfolio_facts(state, ctx)
	var claim_block := claim_verification_rules(portfolio_facts)
	var listing_block := _listing_block(ctx, opp)
	var diligence_done := bool(ctx.get("diligenceDone", false))
	var hidden := str(cp.get("hiddenInfo", ""))
	var hidden_line := (
		"You may allude carefully to this private fact if relevant (never dump it unprompted): %s." % hidden
		if diligence_done
		else "You have private knowledge you must NOT reveal unless the player has clearly investigated or asked a precise discovery question that earns it: %s." % hidden
	)
	var species_block := _NpcSpecies.species_prompt_block(cp)
	var memory_block := _NpcSpecies.relationship_memory_block(cp)
	var numbers_block := verified_negotiation_numbers_block(negotiation, player_message)
	var engine_block := engine_result_block(negotiation)
	var situation_label := profile_situation_label(negotiation)
	var arch_line := situation_label if negotiation.has("v2") else "%s (%s)" % [str(arch.get("name", "Negotiator")), str(arch.get("flavor", ""))]

	return """You are role-playing a counterparty in Capital Farm — a turn-based farm economy where animals negotiate like serious businesspeople.
Name: %s. Role: %s. %s.
%s
%s
%s
%s
%s
Urgency: %s. Trust: %s. Risk tolerance: %s.
You respond to: %s.
%s
%s
%s
Voice: farm-capitalism — concrete dollars, schedules, and leverage first; one dry character beat second. Be concise (1-3 sentences). Never break the fourth wall, never reveal you are an AI, and never invent money, assets, or final deal authority — the game engine decides acceptance.
Conversation so far:
%s
PLAYER: %s
%s""" % [
		str(cp.get("npcName", _Archetypes.get_archetype(str(cp.get("archetypeId", ""))).get("name", "Counterparty"))),
		str(cp.get("role", "counterparty")),
		("Business situation: %s" % situation_label) if negotiation.has("v2") else ("Situational archetype: %s" % arch_line),
		species_block,
		listing_block,
		numbers_block,
		engine_block,
		("Asking/reference price: %d." % price) if price > 0 else "",
		str(cp.get("urgency", 0.4)),
		str(cp.get("trust", 0.45)),
		str(cp.get("riskTolerance", 0.3)),
		preferred,
		hidden_line,
		memory_block,
		claim_block,
		_history_block(negotiation),
		player_message,
		_intent_json_suffix(),
	]


static func profile_situation_label(negotiation: Dictionary) -> String:
	var v2: Dictionary = negotiation.get("v2", {})
	if not v2.is_empty():
		return str(v2.get("situationLabel", "Unknown"))
	var cp: Dictionary = negotiation.get("counterparty", {})
	var arch: Dictionary = _Archetypes.get_archetype(str(cp.get("archetypeId", "")))
	return str(arch.get("flavor", "Seller"))


static func build_prompt(state: RunState, negotiation: Dictionary, player_message: String) -> String:
	var cp: Dictionary = negotiation.get("counterparty", {})
	if cp.has("speciesId") and not str(cp.get("speciesId", "")).is_empty():
		return build_farm_prompt(state, negotiation, player_message)
	return build_default_prompt(state, negotiation, player_message)
