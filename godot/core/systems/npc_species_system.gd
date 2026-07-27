# Capped species utility bonuses + farm NPC dialogue (port of farm-animal-npc.js).
class_name NpcSpeciesSystem
extends RefCounted

const _SPECIES: Dictionary = {
	"pig": {
		"label": "Pig",
		"traits": "calculating, opportunistic",
		"voice": "Calculating and opportunistic. Prefer deal structure, earn-outs, exclusivity, and upside participation over pure price fights.",
		"exampleVoice": "The price can move. The question is what I receive if this business grows exactly as you claim it will.",
	},
	"donkey": {
		"label": "Donkey",
		"traits": "stubborn, skeptical",
		"voice": "Stubborn and skeptical. Assume optimistic claims are incomplete until shown evidence, warranties, or risk-sharing.",
		"exampleVoice": "You keep telling me the harvest will improve. Show me the contracts, the water rights, and the last four quarters.",
	},
	"hen": {
		"label": "Hen",
		"traits": "precise, schedule-driven",
		"voice": "Precise and schedule-driven. Cash timing and certainty matter more than clever financing.",
		"exampleVoice": "Tell me what hits my account at closing and when the rest arrives — then we can talk.",
	},
	"horse": {
		"label": "Horse",
		"traits": "proud, continuity-focused",
		"voice": "Proud and continuity-focused. Staff and legacy matter alongside price.",
		"exampleVoice": "The number matters, but so does what happens to the people who built this place.",
	},
	"goat": {
		"label": "Goat",
		"traits": "fast, package-oriented",
		"voice": "Fast and package-oriented. Responds to complete offers, not vague intent.",
		"exampleVoice": "Put the full package on the table — price, cash, note, timeline — and we move.",
	},
	"sheep": {
		"label": "Sheep",
		"traits": "reputation-sensitive, herd-aware",
		"voice": "Reputation-sensitive. Fair dealing and community standing influence how flexible they get.",
		"exampleVoice": "The valley hears how you close deals — make this one clean.",
	},
}


static func species_prompt_block(counterparty: Dictionary) -> String:
	var species_id := str(counterparty.get("speciesId", ""))
	if species_id.is_empty() or not _SPECIES.has(species_id):
		return "Personality: negotiator."
	var sp: Dictionary = _SPECIES[species_id]
	return """Species: %s (%s).
Species voice: %s
Example tone: "%s"
Stay in this animal-character business voice: dry farm-capitalism wit (Stardew meets Bloomberg). Lead with numbers and stakes; one sharp line of personality is enough — never cartoonish, never break the fourth wall.""" % [
		str(sp.get("label", species_id)),
		str(sp.get("traits", "")),
		str(sp.get("voice", "")),
		str(sp.get("exampleVoice", "")),
	]


static func relationship_memory_block(counterparty: Dictionary) -> String:
	var mem: Dictionary = counterparty.get("relationshipMemory", {})
	if typeof(mem) != TYPE_DICTIONARY:
		mem = {}
	var trust_pct := int(round(float(mem.get("trust", counterparty.get("trust", 0.5))) * 100.0))
	var last_q: Variant = mem.get("lastDealQuality", null)
	var grievances: Array = mem.get("grievances", [])
	var g_text := "none"
	if grievances is Array and not grievances.is_empty():
		var parts: PackedStringArray = []
		for g in grievances:
			parts.append(str(g))
		g_text = ", ".join(parts)
	return "Relationship memory — trust %d%%, promises kept %s, promises broken %s, last deal quality %s, grievances: %s." % [
		trust_pct,
		str(mem.get("promisesKept", 0)),
		str(mem.get("promisesBroken", 0)),
		str(last_q) if last_q != null else "n/a",
		g_text,
	]


static func sanitize_seller_dialogue(dialogue: String, decision: String) -> String:
	var d := dialogue.strip_edges()
	if decision != "accept" and RegEx.create_from_string("glad to close|whenever you're ready|close on that|ready to sign|we have a deal").search(d.to_lower()) != null:
		return ""
	return d


static func fallback_dialogue_farm(decision: String, counterparty: Dictionary, rng: SeededRng = null) -> String:
	var r := rng if rng != null else SeededRng.new(Time.get_ticks_usec())
	var species_id := str(counterparty.get("speciesId", ""))
	if decision == "accept":
		return _pick(r, [
			"Numbers work — paperwork time.",
			"Fine. My accountant will pretend to be surprised.",
			"Accepted. Do not make me regret the barnyard handshake.",
		])
	if decision == "reject":
		return _pick(r, ["I appreciate the offer, but", "Not at those terms —", "That does not clear my bar —"])
	if decision == "counter":
		return _pick(r, [
			"I hear you, but I need something closer to my side of the ledger.",
			"Closer on price or structure — I am not moving on faith alone.",
			"You are in the ballpark; sharpen the terms.",
		])
	match species_id:
		"donkey":
			return "Show me evidence, then we will talk price."
		"hen":
			return "Give me the numbers — schedule, cash, downside."
	return "Go on — but keep it concrete."


static func seller_opening_line(counterparty: Dictionary, context: Dictionary, archetype: Dictionary, rng: SeededRng, stakes_tier: String = "standard") -> String:
	var price: int = int(context.get("price", 0))
	var tier := stakes_tier
	var ask := MathUtil.fmt_money(price) if price > 0 else "my number"
	var species_id := str(counterparty.get("speciesId", ""))

	var cores: Array = []
	match tier:
		"small":
			cores = [
				"Asking %s — small deal, clean close if the math works." % ask,
				"%s on the sign. I'm not here for a three-act drama." % ask,
			]
		"major", "institutional":
			cores = [
				"%s is the headline — we'll need structure, proof, and patience before anyone signs." % ask,
				"This is a %s transaction. Expect diligence, not handshake poetry." % ask,
			]
		_:
			cores = [
				"I'm asking %s. Solid asset — I'll listen if your terms are serious." % ask,
				"%s on the table. I'd rather close cleanly than negotiate forever." % ask,
			]

	var line: String = _pick(rng, cores)
	var species_lead: Dictionary = {
		"hen": "Show me the payment calendar, not the vision deck.",
		"donkey": "I want the paperwork before the poetry.",
		"horse": "Tell me what happens to the crew after close.",
		"pig": "Simple terms, fast close — that is how we both eat.",
		"sheep": "Others in the valley are watching how this one prices.",
		"goat": "I move fast — do not waste the turn.",
	}
	if species_id in species_lead and rng.randf() < 0.75:
		line = "%s %s" % [species_lead[species_id], line]
	if not str(archetype.get("flavor", "")).is_empty() and rng.randf() < 0.35:
		line = "%s (%s: %s)" % [line, str(archetype.get("name", "")), str(archetype.get("flavor", ""))]
	return line


static func _pick(rng: SeededRng, options: Array) -> String:
	if options.is_empty():
		return ""
	return str(options[rng.randi_range(0, options.size() - 1)])


static func urgent_problem_text(prob_type: String, opts: Dictionary) -> String:
	var biz: String = str(opts.get("businessName", "the operation"))
	var npc: String = str(opts.get("npcName", "Your counterparty"))
	var stake: int = int(opts.get("stakeAmount", 0))
	var escalation: String = str(opts.get("escalation", "strained"))
	var stake_str: String = MathUtil.fmt_money(stake)
	var rng := SeededRng.new(str(biz + npc + prob_type).hash())

	if prob_type == "client":
		if escalation == "at_risk":
			return _pick(rng, [
				"%s says %s's biggest account is packing feed bags elsewhere — %s/qtr walks if you don't renegotiate now." % [npc, biz, stake_str],
				"Your top client at %s is one signature from leaving. That's %s/qtr off the ledger, permanently, if this blows over." % [biz, stake_str],
			])
		return _pick(rng, [
			"%s at %s wants new terms — margins are thin and they're shopping around (%s/qtr on the line)." % [npc, biz, stake_str],
			"%s's anchor client is grumbling about price. Fix it before %s forwards the invoice to a competitor." % [biz, npc],
		])
	if prob_type == "supplier":
		if escalation == "at_risk":
			return _pick(rng, [
				"%s is done eating the cost — %s's input bill jumps %s/qtr unless you talk them down today." % [npc, biz, stake_str],
				"Critical supplier for %s is imposing a lasting hike. %s/qtr extra opex if you ignore %s." % [biz, stake_str, npc],
			])
		return _pick(rng, [
			"%s says hay doesn't grow on goodwill — %s faces a %s/qtr cost bump unless terms change." % [npc, biz, stake_str],
			"Your %s supplier wants more per load. %s has spreadsheets and they're not sentimental." % [biz, npc],
		])
	if prob_type == "lender":
		return _pick(rng, [
			"%s flagged coverage on your loan — covenant chat now or %s/qtr higher payments later." % [npc, stake_str],
			"The bank (%s) wants reassurance on collateral. Ignore it and the payment ratchets up ~%s/qtr." % [npc, stake_str],
		])
	return "%s: relationship issue needs negotiation." % biz


static func intel_tips(counterparty: Dictionary) -> Array[String]:
	var tips: Array[String] = []
	var species_id := str(counterparty.get("speciesId", ""))
	match species_id:
		"hen":
			tips.append("This Hen weighs certainty — more cash at closing moves them more than creative financing.")
		"horse":
			tips.append("This Horse cares about people — employee retention and continuity terms carry real weight.")
		"pig":
			tips.append("This Pig cares about structure — earn-outs, exclusivity, or upside participation can move them more than shaving price.")
		"donkey":
			tips.append("This Donkey needs evidence — warranties, inspection rights, or verified numbers beat pressure.")
		"goat":
			tips.append("This Goat reads packages, not vibes — combine price with at least two concrete terms.")
		"sheep":
			tips.append("This Sheep responds to reputation and social proof — references and partner roles beat small price tweaks.")
	return tips


static func negotiation_coach_tip(counterparty: Dictionary, v2: Dictionary = {}) -> String:
	var species_id := str(counterparty.get("speciesId", ""))
	var situation_id := str(v2.get("situationId", counterparty.get("businessSituation", "")))
	var species_line := ""
	match species_id:
		"hen":
			species_line = "Say: all cash at closing, fast close, inspection window, written guarantee."
		"donkey":
			species_line = "Say: reviewed records, conservative numbers, inspection rights, warranties in writing."
		"sheep":
			species_line = "Say: reputation, references, community trust, respected partner / brand role."
		"horse":
			species_line = "Say: employee retention, continuity, legacy respect, smooth transition."
		"pig":
			species_line = "Say: earn-out, exclusivity, volume, option package — structure over haggling."
		"goat":
			species_line = "Say: firm package with at least two concrete terms, not price alone."
		_:
			species_line = "Lead with species-aligned terms, then your price."

	match situation_id:
		"retirement_transition":
			return "%s Also: keep the team, honor what they built, retention in writing." % species_line
		"cash_pressure":
			return "%s Also: all cash, fast close, no deferred payments." % species_line
		"entrepreneur_growth":
			return "%s Also: growth plan, territory, volume, upside partnership." % species_line
		"stable_position":
			return "%s Stable seller — expect modest headline discount; terms matter." % species_line
	return species_line


static func apply_utility_bonus(utility: float, offer: Dictionary, counterparty: Dictionary, context: Dictionary, state: RunState) -> float:
	if counterparty.is_empty() or not counterparty.has("speciesId"):
		return utility

	var species_id: String = str(counterparty.get("speciesId", ""))
	var terms: Array = offer.get("termsOffered", [])
	var total_price: int = int(offer.get("totalPrice", 0))
	var cash_at_closing: int = int(offer.get("cashAtClosing", total_price))
	var certainty: float = float(cash_at_closing) / maxf(1.0, float(total_price))
	var bonus: float = 0.0

	match species_id:
		"hen":
			bonus += certainty * 4.0
		"horse":
			if _term_hit(terms, "employee|staff|continu|long.?term|legacy|worker|retention"):
				bonus += 9.0
		"pig":
			if _term_hit(terms, "earn.?out|contingent|exclusiv|option|information|upside|royalt"):
				bonus += 8.0
			if _term_hit(terms, "control|governance|renewal"):
				bonus += 4.0
		"donkey":
			if _term_hit(terms, "warrant|inspect|guarantee|trial|retention|verified|diligence"):
				bonus += 8.0
			if bool(context.get("diligenceDone", false)):
				bonus += 4.0
		"goat":
			if terms.size() >= 2:
				bonus += 5.0
			if _term_hit(terms, "territor|priority|reopen|option package"):
				bonus += 5.0
			var ask: int = int(context.get("price", 0))
			if terms.is_empty() and total_price > 0 and ask > 0:
				var cut: float = float(ask - total_price) / float(ask)
				if cut > 0.12:
					bonus -= 4.0
		"sheep":
			var rep: float = float(state.reputation if state else 50)
			bonus += MathUtil.clamp((rep - 50.0) / 50.0, -1.0, 1.0) * 8.0
			if _term_hit(terms, "reference|reputation|partner|renew|community"):
				bonus += 5.0

	return utility + MathUtil.clamp(bonus, -15.0, 15.0)


static func _term_hit(terms: Array, pattern: String) -> bool:
	var re := RegEx.create_from_string(pattern)
	for t in terms:
		if re.search(str(t).to_lower()) != null:
			return true
	return false
