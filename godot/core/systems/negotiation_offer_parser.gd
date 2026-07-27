# Port of rival-farmer.js offer parsing (parseOfferAmountsFromText, buildPlayerOfferFromMessage, etc.)
class_name NegotiationOfferParser
extends RefCounted

static var _re_cache: Dictionary = {}


static func _money_int(val: Variant) -> int:
	if val == null:
		return 0
	match typeof(val):
		TYPE_INT:
			return int(val)
		TYPE_FLOAT:
			return int(round(float(val)))
		TYPE_STRING:
			var s := str(val).replace("$", "").replace(",", "").strip_edges()
			if s.is_empty():
				return 0
			return int(round(float(s)))
		_:
			return 0


static func _re(pattern: String) -> RegEx:
	if not _re_cache.has(pattern):
		var compiled := RegEx.new()
		compiled.compile(pattern)
		_re_cache[pattern] = compiled
	return _re_cache[pattern]


static func expand_money_shorthand(text: String) -> String:
	var result := text
	for m in _re("\\b(\\d+(?:\\.\\d+)?)\\s*([kKmM])\\b").search_all(text):
		var num: float = float(m.get_string(1))
		var unit: String = m.get_string(2).to_lower()
		var mult: int = 1000000 if unit == "m" else 1000
		result = result.replace(m.get_string(), str(int(round(num * mult))))
	return result


static func extract_numbers_from_text(text: String) -> Array:
	var expanded := expand_money_shorthand(text)
	var nums: Array = []
	for m in _re("\\$?\\d[\\d,]{2,}").search_all(expanded):
		var raw: String = m.get_string().replace("$", "").replace(",", "")
		nums.append(int(raw))
	return nums


static func message_has_offer_figures(text: String) -> bool:
	var expanded := expand_money_shorthand(text)
	if _re("\\$?\\d[\\d,]{2,}").search(expanded) != null:
		return true
	if _re("\\b(\\d+(?:\\.\\d+)?)\\s*([kKmM])\\b").search(text) != null:
		return true
	return text.to_lower().contains("percent") or text.contains("%")


static func is_purchase_intent_text(text: String) -> bool:
	return _re("\\b(?:offer|pay|bid|buy|take|give|i'?ll do|i will do|can do|could do|willing to pay|happy to pay)\\b").search(text.to_lower()) != null


static func is_asking_price_offer_text(text: String) -> bool:
	var lower := text.to_lower()
	return (
		_re("\\b(?:pay|match|meet|take|accept|do)\\s+(?:the\\s+)?(?:full\\s+)?(?:asking|listed|list)\\s+price\\b").search(lower) != null
		or _re("\\b(?:asking|listed|list)\\s+price\\b").search(lower) != null
		or _re("\\byour\\s+(?:asking\\s+)?price\\b").search(lower) != null
		or _re("\\bfull\\s+(?:asking\\s+)?price\\b").search(lower) != null
		or _re("\\bmatch(?:ing)?\\s+(?:your\\s+)?(?:ask|price|number)\\b").search(lower) != null
		or _re("\\bat\\s+(?:your\\s+)?ask\\b").search(lower) != null
	)


static func should_treat_as_all_cash_offer(text: String, total_price: int, ask_price: int = 0) -> bool:
	if is_all_cash_offer_text(text):
		return true
	if is_structured_financing_text(text):
		return false
	if is_purchase_intent_text(text) or is_asking_price_offer_text(text):
		return true
	if ask_price > 0 and total_price >= int(round(float(ask_price) * 0.995)):
		return true
	return false


static func _strip_financing_terms(terms: Array) -> Array:
	var filtered: Array = []
	for t in terms:
		if t == null:
			continue
		if not RegEx.create_from_string("seller note|payment schedule|earnout|deposit").search(str(t).to_lower()):
			filtered.append(t)
	return filtered


static func _apply_all_cash_amounts(total_price: int, text: String, ask_price: int = 0) -> Dictionary:
	if total_price <= 0:
		return {}
	if should_treat_as_all_cash_offer(text, total_price, ask_price):
		return {"totalPrice": total_price, "cashAtClosing": total_price, "_allCash": true}
	return {}


static func is_structured_financing_text(text: String) -> bool:
	return _re("seller note|earn[-\\s]?out|contingent|deferred|note payable|rest on|remainder|balance on|balance due|carry back|next quarter|over \\d+ quarter|installment|financing structure").search(text.to_lower()) != null


static func _upfront_amount_match(lower: String) -> RegExMatch:
	return _re("(\\d[\\d,]+)(?:\\s+\\w+){0,3}\\s*(?:upfront|up\\s+front|at closing|cash at closing|down payment|now\\b)").search(lower)


static func _deferred_amount_match(lower: String) -> RegExMatch:
	return _re("(\\d[\\d,]+)\\s*(?:on|as|via|over)\\s+(?:an\\s+)?(?:a\\s+)?(?:seller'?s?\\s*)?(?:note|earn[-\\s]?out|contingent(?:\\s+payment)?|deferred(?:\\s+payment)?)").search(lower)


static func _pick_all_cash_amount(text: String, nums: Array, ask_price: int) -> int:
	var lower := text.to_lower()
	var total_match := _re("(\\d[\\d,]+)\\s*(?:dollars?\\s*)?(?:total|altogether|in total|all in|all-in|overall)\\b").search(lower)
	if total_match:
		return int(total_match.get_string(1).replace(",", ""))
	if ask_price > 0:
		for n in nums:
			if int(n) != ask_price:
				return int(n)
	return int(nums.max())


static func _try_upfront_deferred_split(lower: String) -> Dictionary:
	var upfront_match := _upfront_amount_match(lower)
	var deferred_match := _deferred_amount_match(lower)
	if upfront_match and deferred_match:
		var up := int(upfront_match.get_string(1).replace(",", ""))
		var deferred := int(deferred_match.get_string(1).replace(",", ""))
		if up >= 500 and deferred >= 500:
			return {"totalPrice": up + deferred, "cashAtClosing": up}
	return {}


static func is_closing_intent_text(text: String) -> bool:
	return _re("\\b(?:let'?s|lets)\\s+close\\b|\\bclose\\s+(?:at|for|on)\\b|\\bready to close\\b|\\bfinalize\\b|\\bwrap (?:this )?up\\b|\\bclose the deal\\b|\\bif you agree\\b|\\bagreed\\b|\\bsounds good\\b|\\bdeal\\b|\\baccept\\b").search(text.to_lower()) != null


static func is_all_cash_offer_text(text: String) -> bool:
	var lower := text.to_lower()
	if _re("no seller note|without a seller note|without seller note|no note\\b|no deferred").search(lower):
		return true
	if is_structured_financing_text(text):
		return false
	if _re("all\\s+cash|full\\s+cash|cash\\s+only|cash\\s+deal|pay\\s+(?:in\\s+)?cash|entire(?:ly)?\\s+in\\s+cash|100%\\s*cash|(?:in|as|via|with)\\s+(?:direct\\s+)?cash\\b|direct\\s+cash").search(lower):
		return true
	if _re("all\\s+upfront|pay\\s+upfront|entire(?:ly)?\\s+upfront|full\\s+upfront|100%\\s*upfront|upfront\\s+all|all\\s+at\\s+closing").search(lower):
		return true
	if _re("(?:let'?s|lets)\\s+close\\s+(?:at|for|on)\\s+\\d").search(lower):
		return true
	if _re("\\d[\\d,]+\\s*at closing").search(lower) and not is_structured_financing_text(text):
		return true
	if _re("(?:only|just|will do|i'?ll do)\\s+\\d[\\d,]+\\s*at closing").search(lower) and not is_structured_financing_text(text):
		return true
	return false


static func extract_terms_from_text(text: String) -> Array:
	var lower := text.to_lower()
	var terms: Array = []
	var add := func(t: String) -> void:
		for existing in terms:
			if str(existing).to_lower() == t.to_lower():
				return
		terms.append(t)

	if RegEx.create_from_string("keep (?:all )?(?:the |your )?(?:staff|employees|team|workers|people)|employee retention|staff retention|job retention|retain (?:all )?(?:the |your )?(?:staff|employees|team|workers)|keep employees|keeping staff|keep everyone|keep the team").search(lower):
		add.call("employee retention")
	if RegEx.create_from_string("growth plan|expansion plan for staff|staff growth").search(lower):
		add.call("growth plan")
	if RegEx.create_from_string("premium|member card|loyalty card|loyalty program").search(lower):
		add.call("premium member card")
	if RegEx.create_from_string("milestone|payment schedule|installment|staged payment").search(lower):
		add.call("payment schedule")
	if RegEx.create_from_string("deposit|down payment").search(lower):
		add.call("deposit")
	elif RegEx.create_from_string("upfront").search(lower) and is_structured_financing_text(lower):
		add.call("deposit")
	if RegEx.create_from_string("fast close|quick close|30 day|thirty day").search(lower):
		add.call("fast close")
	if is_structured_financing_text(lower):
		add.call("seller note")
	if _re("earn[-\\s]?out|contingent payment").search(lower):
		add.call("earnout")
	if RegEx.create_from_string("\\d+\\s*quarter|quarterly|over \\d+ quarter|to \\d+ quarter").search(lower):
		add.call("payment schedule")
	if RegEx.create_from_string("continuity|legacy|keep the team|respect (?:for |your )?(?:the )?(?:business|legacy|team|staff)").search(lower):
		add.call("continuity")
	if RegEx.create_from_string("\\brespect\\b|fair dealing|long.?term commitment").search(lower):
		add.call("respect")
	if RegEx.create_from_string("warrant|inspection window|due diligence period").search(lower):
		add.call("warranties")
	if RegEx.create_from_string("all\\s+cash|full\\s+cash|cash\\s+deal|100%\\s*cash|pay\\s+(?:in\\s+)?cash").search(lower):
		add.call("all cash")
	return terms


static func _merge_terms(existing: Array, from_text: Array) -> Array:
	var out: Array = existing.duplicate() if existing != null else []
	for t in from_text:
		var found := false
		for x in out:
			if str(x).to_lower() == str(t).to_lower():
				found = true
				break
		if not found:
			out.append(t)
	return out


static func parse_offer_amounts_from_text(text: String, ask_price: int = 0) -> Dictionary:
	var raw := expand_money_shorthand(text)
	var lower := raw.to_lower()

	var close_at := RegEx.create_from_string("(?:let'?s|lets)\\s+close\\s+(?:at|for|on)\\s+\\$?(\\d[\\d,]{2,})").search(lower)
	if close_at and not is_structured_financing_text(text):
		var val := int(close_at.get_string(1).replace(",", ""))
		if val >= 500:
			return {"totalPrice": val, "cashAtClosing": val}

	var close_bare := RegEx.create_from_string("\\bclose\\s+(?:at|for|on)\\s+\\$?(\\d[\\d,]{2,})").search(lower)
	if close_bare and not is_structured_financing_text(text):
		var val := int(close_bare.get_string(1).replace(",", ""))
		if val >= 500:
			return {"totalPrice": val, "cashAtClosing": val}

	var direct_cash := RegEx.create_from_string("(\\d[\\d,]{2,})\\s*(?:dollars?\\s*)?(?:in|as|via|with)\\s+(?:direct\\s+)?cash\\b").search(lower)
	if direct_cash:
		var val := int(direct_cash.get_string(1).replace(",", ""))
		if val >= 500:
			return {"totalPrice": val, "cashAtClosing": val}

	if is_all_cash_offer_text(text):
		var nums: Array = []
		for n in extract_numbers_from_text(text):
			if int(n) >= 500:
				nums.append(int(n))
		if nums.size() == 1:
			return {"totalPrice": nums[0], "cashAtClosing": nums[0]}
		if nums.size() >= 2:
			var offer_amt: int = _pick_all_cash_amount(text, nums, ask_price)
			return {"totalPrice": offer_amt, "cashAtClosing": offer_amt}

	var matches: Array = []
	for m in _re("\\$?\\d[\\d,]{2,}").search_all(raw):
		matches.append({
			"value": int(m.get_string().replace("$", "").replace(",", "")),
			"index": m.get_start(),
			"end": m.get_end(),
		})
	if matches.is_empty():
		return {}

	var values: Array = []
	for match in matches:
		values.append(match["value"])

	if is_structured_financing_text(text) and matches.size() >= 2:
		var split := _try_split_financing_amounts(lower, values, ask_price)
		if not split.is_empty():
			return split
		var upfront_deferred := _try_upfront_deferred_split(lower)
		if not upfront_deferred.is_empty():
			return upfront_deferred

	var total_price = null
	var cash_at_closing = null

	for match in matches:
		var after := lower.substr(match["end"], mini(48, lower.length() - match["end"]))
		var before := lower.substr(maxi(0, match["index"] - 32), mini(32, match["index"]))
		var is_closing := (
			RegEx.create_from_string("^\\s*(at closing|cash at closing|upfront|up\\s+front|down payment|at close|cash at close|due at closing)").search(after) != null
			or RegEx.create_from_string("^\\s*(?:in|as|via|with)\\s+(?:direct\\s+)?cash\\b").search(after) != null
			or (
				RegEx.create_from_string("(?:only|just|with only)\\s+(?:\\$)?\\d[\\d,]*\\s*$").search(before) != null
				and RegEx.create_from_string("(?:at closing|upfront|down|cash at close)").search(after) != null
			)
			or RegEx.create_from_string("(at closing|cash at closing|upfront|down payment|at close)\\s*(and|,)?\\.{0,8}$").search(before) != null
		)
		var is_total := (
			RegEx.create_from_string("^\\s*(total|altogether|in total|all in|all-in|overall)").search(after) != null
			or RegEx.create_from_string("(total|altogether|in total|all in)\\s*(and|,)?\\.{0,8}$").search(before) != null
			or RegEx.create_from_string("\\boffer(?:ing)?\\s+\\$?\\d").search(before + raw.substr(match["index"], match["end"] - match["index"] + 12)) != null
		)
		if is_closing and cash_at_closing == null:
			cash_at_closing = match["value"]
		if is_total and total_price == null:
			total_price = match["value"]

	var only_closing := RegEx.create_from_string("(?:only|just|with only)\\s+\\$?(\\d[\\d,]{2,})\\s*(?:at closing|upfront|down|cash at close)").search(lower)
	if only_closing:
		cash_at_closing = int(only_closing.get_string(1).replace(",", ""))

	var total_re := RegEx.create_from_string("(\\d[\\d,]{2,})\\s*(?:dollars?\\s*)?(?:total|altogether|in total|all in|all-in|overall)\\b").search(lower)
	var closing_re := RegEx.create_from_string("(\\d[\\d,]{2,})\\s*(?:dollars?\\s*)?(?:at closing|cash at closing|upfront|down payment|at close|due at closing)\\b").search(lower)
	if total_re:
		total_price = int(total_re.get_string(1).replace(",", ""))
	if closing_re:
		cash_at_closing = int(closing_re.get_string(1).replace(",", ""))

	if total_price == null and values.size() == 1:
		total_price = values[0]
		if should_treat_as_all_cash_offer(text, int(total_price), ask_price):
			cash_at_closing = values[0]

	if ask_price > 0 and is_asking_price_offer_text(text) and total_price == null and cash_at_closing == null:
		total_price = ask_price
		cash_at_closing = ask_price

	if ask_price > 0 and total_price == ask_price and values.size() >= 2:
		for v in values:
			if int(v) != ask_price:
				total_price = int(v)
				break
	if ask_price > 0 and cash_at_closing == ask_price and values.size() >= 2:
		for v in values:
			if int(v) != ask_price:
				cash_at_closing = int(v)
				break

	if total_price == null and cash_at_closing == null and values.size() >= 2:
		if is_structured_financing_text(text):
			var parts := _offer_values_excluding_ask(values, ask_price)
			if parts.size() >= 2:
				total_price = int(parts[0]) + int(parts[1])
				for i in range(2, parts.size()):
					total_price += int(parts[i])
				cash_at_closing = maxi(int(parts[0]), int(parts[1]))
			else:
				total_price = maxi(int(values[0]), int(values[1]))
				cash_at_closing = mini(int(values[0]), int(values[1]))
		else:
			total_price = maxi(int(values[0]), int(values[1]))
			cash_at_closing = mini(int(values[0]), int(values[1]))
	else:
		if total_price == null and cash_at_closing != null:
			if is_structured_financing_text(text):
				var parts := _offer_values_excluding_ask(values, ask_price)
				if parts.size() >= 2:
					total_price = 0
					for p in parts:
						total_price += int(p)
				else:
					var other = null
					for v in values:
						if int(v) != int(cash_at_closing) and (ask_price <= 0 or int(v) != ask_price):
							other = int(v)
							break
					total_price = int(cash_at_closing) + int(other) if other != null else int(cash_at_closing)
			else:
				var other = null
				for v in values:
					if int(v) != int(cash_at_closing):
						other = int(v)
						break
				total_price = other if other != null else cash_at_closing
		if cash_at_closing == null and total_price != null:
			var other2 = null
			for v in values:
				if int(v) != int(total_price):
					other2 = int(v)
					break
			if is_all_cash_offer_text(text):
				cash_at_closing = total_price
			elif should_treat_as_all_cash_offer(text, int(total_price), ask_price):
				cash_at_closing = total_price
			elif other2 != null:
				cash_at_closing = other2
			else:
				cash_at_closing = int(round(float(total_price) * 0.45))

	if is_all_cash_offer_text(text) and total_price != null:
		cash_at_closing = total_price

	if total_price != null:
		var all_cash := _apply_all_cash_amounts(int(total_price), text, ask_price)
		if not all_cash.is_empty():
			total_price = all_cash["totalPrice"]
			cash_at_closing = all_cash["cashAtClosing"]

	if total_price != null and cash_at_closing != null and int(cash_at_closing) > int(total_price):
		var hi := maxi(int(total_price), int(cash_at_closing))
		var lo := mini(int(total_price), int(cash_at_closing))
		total_price = hi
		cash_at_closing = lo

	if total_price == null:
		return {}
	return {
		"totalPrice": int(total_price),
		"cashAtClosing": int(cash_at_closing) if cash_at_closing != null else int(round(float(total_price) * 0.45)),
	}


static func infer_offer_structure(text: String, amounts: Dictionary) -> Dictionary:
	var lower := text.to_lower()
	var terms := extract_terms_from_text(text)
	if amounts.is_empty():
		return {"amounts": {}, "terms": terms}

	var total_price: int = _money_int(amounts.get("totalPrice", 0))
	var cash_at_closing: int = _money_int(amounts.get("cashAtClosing", 0))

	if is_all_cash_offer_text(text):
		cash_at_closing = total_price
		var filtered: Array = []
		for t in terms:
			if not RegEx.create_from_string("seller note|payment schedule|earnout|deposit").search(str(t).to_lower()):
				filtered.append(t)
		terms = filtered
		return {"amounts": {"totalPrice": total_price, "cashAtClosing": cash_at_closing}, "terms": terms}

	if RegEx.create_from_string("no seller note|without a seller note|without seller note|no note\\b|no deferred").search(lower):
		cash_at_closing = total_price
		var filtered2: Array = []
		for t in terms:
			if not RegEx.create_from_string("seller note|payment schedule|earnout|deposit").search(str(t).to_lower()):
				filtered2.append(t)
		terms = filtered2
		return {"amounts": {"totalPrice": total_price, "cashAtClosing": cash_at_closing}, "terms": terms}

	if RegEx.create_from_string("rest (on|via|as|over)|remainder|balance (on|as|over)|seller note|deferred|note payable|carry back").search(lower):
		terms = _merge_terms(terms, ["seller note"])

	if RegEx.create_from_string("upfront.*(?:rest|remainder|balance).*(?:at closing|at close)").search(lower):
		cash_at_closing = total_price
		terms = _merge_terms(terms, ["deposit", "payment schedule"])
	elif RegEx.create_from_string("(?:upfront|down payment|deposit)").search(lower) and not RegEx.create_from_string("rest|remainder|balance|note|deferred|seller note|earn").search(lower):
		cash_at_closing = total_price
		terms = _merge_terms(terms, ["deposit", "payment schedule"])
	elif RegEx.create_from_string("(?:only|just|with only)\\s+\\d[\\d,]*\\s*(?:at closing|upfront|down)").search(lower) and not is_all_cash_offer_text(text):
		terms = _merge_terms(terms, ["seller note", "payment schedule"])

	if (
		cash_at_closing < int(float(total_price) * 0.72)
		and not is_all_cash_offer_text(text)
		and not RegEx.create_from_string("all cash|full cash|100% cash|cash deal").search(lower)
	):
		var has_deposit_term := false
		for t in terms:
			if RegEx.create_from_string("deposit|payment schedule").search(str(t).to_lower()):
				has_deposit_term = true
				break
		if not has_deposit_term:
			terms = _merge_terms(terms, ["seller note", "payment schedule"])

	return {"amounts": {"totalPrice": total_price, "cashAtClosing": cash_at_closing}, "terms": terms}


static func normalize_offer(raw: Dictionary, negotiation: Dictionary = {}) -> Dictionary:
	var o: Dictionary = raw.duplicate(true)
	var total: int = _money_int(o.get("totalPrice", 0))
	var cash: int = _money_int(o.get("cashAtClosing", 0))
	var all_cash: bool = bool(o.get("_allCash", false))
	var ask: int = int(negotiation.get("context", {}).get("price", 0))
	o["totalPrice"] = total
	if total > 0 and (not o.has("cashAtClosing") or cash == 0):
		cash = total if all_cash else int(round(float(total) * 0.45))
		o["cashAtClosing"] = cash
	elif total > 0:
		o["cashAtClosing"] = cash
	if all_cash or (total > 0 and cash == total):
		o["cashAtClosing"] = total
		o["termsOffered"] = _strip_financing_terms(o.get("termsOffered", []))
	elif ask > 0 and total >= int(round(float(ask) * 0.995)) and cash >= total:
		o["cashAtClosing"] = total
		o["termsOffered"] = _strip_financing_terms(o.get("termsOffered", []))
	return o


static func reconcile_offer_amounts(offer: Dictionary, text: String, ask_price: int = 0) -> Dictionary:
	if offer.is_empty():
		return offer
	var parsed := parse_offer_amounts_from_text(text, ask_price)
	if parsed.is_empty():
		return offer
	var labeled := RegEx.create_from_string("at closing|cash at closing|upfront|down payment|\\btotal\\b|altogether|in total|all in|seller note|pay|offer|bid").search(text.to_lower()) != null
	var inverted := _money_int(offer.get("cashAtClosing", 0)) > _money_int(offer.get("totalPrice", 0))
	var text_mismatch := (
		_money_int(offer.get("totalPrice", 0)) != _money_int(parsed.get("totalPrice", 0))
		or _money_int(offer.get("cashAtClosing", 0)) != _money_int(parsed.get("cashAtClosing", 0))
	)
	if labeled or inverted or (text_mismatch and extract_numbers_from_text(text).size() >= 1):
		offer["totalPrice"] = parsed["totalPrice"]
		offer["cashAtClosing"] = parsed["cashAtClosing"]
		if int(parsed.get("cashAtClosing", 0)) == int(parsed.get("totalPrice", 0)):
			offer["_allCash"] = true
	return offer


static func finalize_player_offer(offer: Dictionary, text: String, negotiation: Dictionary = {}) -> Dictionary:
	if offer.is_empty():
		return {}
	var inferred := infer_offer_structure(text, {
		"totalPrice": offer.get("totalPrice", 0),
		"cashAtClosing": offer.get("cashAtClosing", 0),
	})
	offer["totalPrice"] = inferred["amounts"].get("totalPrice", 0)
	offer["cashAtClosing"] = inferred["amounts"].get("cashAtClosing", 0)
	offer["termsOffered"] = _merge_terms(offer.get("termsOffered", []), inferred.get("terms", []))
	var ask: int = int(negotiation.get("context", {}).get("price", 0))
	var total_after: int = _money_int(offer.get("totalPrice", 0))
	var all_cash_override := _apply_all_cash_amounts(total_after, text, ask)
	if not all_cash_override.is_empty():
		offer["totalPrice"] = all_cash_override["totalPrice"]
		offer["cashAtClosing"] = all_cash_override["cashAtClosing"]
		offer["_allCash"] = true
		offer["termsOffered"] = _strip_financing_terms(offer.get("termsOffered", []))
	for t in offer.get("termsOffered", []):
		if RegEx.create_from_string("seller note|payment schedule|earnout").search(str(t).to_lower()):
			offer["riskToCounterparty"] = 14
			break
	if not offer.has("riskToCounterparty"):
		offer["riskToCounterparty"] = 8
	return normalize_offer(offer, negotiation)


static func enrich_offer_from_message(offer: Dictionary, text: String, ai_parsed: Dictionary = {}) -> Dictionary:
	if offer.is_empty():
		return offer
	var merged: Array = offer.get("termsOffered", [])
	merged = _merge_terms(merged, extract_terms_from_text(text))
	if ai_parsed.has("offer") and typeof(ai_parsed.get("offer")) == TYPE_DICTIONARY:
		var ai_offer: Dictionary = ai_parsed["offer"]
		if typeof(ai_offer.get("termsOffered")) == TYPE_ARRAY:
			merged = _merge_terms(merged, ai_offer.get("termsOffered", []))
	offer["termsOffered"] = merged
	return offer


static func _offer_values_excluding_ask(values: Array, ask_price: int) -> Array:
	var parts: Array = []
	for v in values:
		var n := int(v)
		if ask_price > 0 and n == ask_price:
			continue
		if n >= 500:
			parts.append(n)
	return parts


static func _try_split_financing_amounts(lower: String, values: Array, ask_price: int) -> Dictionary:
	var upfront_deferred := _try_upfront_deferred_split(lower)
	if not upfront_deferred.is_empty():
		return upfront_deferred

	var parts := _offer_values_excluding_ask(values, ask_price)
	if parts.size() >= 2:
		var total := 0
		for p in parts:
			total += int(p)
		var cash := int(parts[0])
		var upfront_match := _upfront_amount_match(lower)
		var deferred_match := _deferred_amount_match(lower)
		if upfront_match:
			cash = int(upfront_match.get_string(1).replace(",", ""))
		elif deferred_match:
			cash = total - int(deferred_match.get_string(1).replace(",", ""))
		else:
			cash = maxi(int(parts[0]), int(parts[1]))
		return {"totalPrice": total, "cashAtClosing": cash}
	return {}


static func build_player_offer_from_message(
	text: String,
	parsed: Dictionary,
	negotiation: Dictionary,
) -> Dictionary:
	var n: Dictionary = negotiation if not negotiation.is_empty() else {}
	var lower := text.to_lower()
	var nums := extract_numbers_from_text(text)
	var mentions_figure := message_has_offer_figures(text)
	var intent: String = str(parsed.get("intent", "question"))

	if mentions_figure and RegEx.create_from_string("\\boffer|\\boffering|\\bi'?ll do|\\bi will do|\\bdo \\d|\\bwith \\d|\\bclose at|\\bclose for|\\bclose on|\\ball upfront|\\ball cash|\\bupfront\\b|\\bat closing\\b").search(lower):
		intent = "offer"
	if is_closing_intent_text(text) and mentions_figure:
		intent = "accept"

	if intent == "offer" and parsed.has("offer") and typeof(parsed.get("offer")) == TYPE_DICTIONARY:
		var ask_for_parse: int = int(n.get("context", {}).get("price", 0))
		var text_amounts: Dictionary = parse_offer_amounts_from_text(text, ask_for_parse)
		var from_ai: Dictionary = normalize_offer((parsed["offer"] as Dictionary).duplicate(true), n)
		from_ai = reconcile_offer_amounts(from_ai, text, ask_for_parse)
		if not text_amounts.is_empty() and _money_int(text_amounts.get("totalPrice", 0)) > 0:
			from_ai["totalPrice"] = text_amounts["totalPrice"]
			from_ai["cashAtClosing"] = text_amounts["cashAtClosing"]
		if _money_int(from_ai.get("totalPrice", 0)) > 0:
			from_ai = finalize_player_offer(from_ai, text, n)
			from_ai = enrich_offer_from_message(from_ai, text, parsed)
			return {"offer": from_ai, "intent": "offer"}

	if not mentions_figure or nums.is_empty():
		if is_closing_intent_text(text):
			var ask: int = int(n.get("context", {}).get("price", 0))
			var amounts := parse_offer_amounts_from_text(text, ask)
			if amounts.get("totalPrice", 0) > 0:
				var raw_offer := {
					"totalPrice": amounts["totalPrice"],
					"cashAtClosing": amounts["cashAtClosing"],
					"closingSpeed": "standard",
					"termsOffered": extract_terms_from_text(text),
					"_allCash": amounts["cashAtClosing"] == amounts["totalPrice"],
				}
				var offer := finalize_player_offer(raw_offer, text, n)
				offer = enrich_offer_from_message(offer, text, parsed)
				if offer.get("totalPrice", 0) > 0:
					return {"offer": offer, "intent": "accept"}
			var last: Dictionary = n.get("playerLastOffer", {})
			if last.get("totalPrice", 0) > 0:
				return {"offer": last, "intent": "accept"}
			return {"offer": null, "intent": "accept"}
		if RegEx.create_from_string("walk|withdraw|never mind|give up").search(lower):
			return {"offer": null, "intent": "walk"}
		return {"offer": null, "intent": intent}

	var ask2: int = int(n.get("context", {}).get("price", 0))
	var amounts2 := parse_offer_amounts_from_text(text, ask2)
	var raw: Dictionary
	if not amounts2.is_empty():
		raw = amounts2.duplicate()
		if int(raw.get("cashAtClosing", 0)) == int(raw.get("totalPrice", 0)):
			raw["_allCash"] = true
	else:
		var lone_total: int = maxi(int(nums[0]), int(nums[1])) if nums.size() >= 2 else int(nums[0])
		var all_cash_lone := should_treat_as_all_cash_offer(text, lone_total, ask2)
		raw = {
			"totalPrice": lone_total,
			"cashAtClosing": lone_total if all_cash_lone else (mini(int(nums[0]), int(nums[1])) if nums.size() >= 2 else int(round(float(lone_total) * 0.45))),
			"_allCash": all_cash_lone,
		}
	raw["closingSpeed"] = "fast" if RegEx.create_from_string("fast|quick|30 day|thirty day").search(lower) else "standard"
	raw["termsOffered"] = extract_terms_from_text(text)
	if is_all_cash_offer_text(text) or bool(raw.get("_allCash", false)):
		raw["_allCash"] = true

	var final_offer := finalize_player_offer(raw, text, n)
	if final_offer.get("totalPrice", 0) > 0:
		final_offer = enrich_offer_from_message(final_offer, text, parsed)
		var out_intent := "accept" if is_closing_intent_text(text) else "offer"
		return {"offer": final_offer, "intent": out_intent}
	return {"offer": null, "intent": intent}
