# Ranks/filter eligible chat facts by player-message topic so ops/supply
# intel does not dominate every casual visit.
class_name CommunityFactTopicRouter
extends RefCounted

const DEFAULT_LIMIT := 8

const _TOPIC_KEYWORDS: Dictionary = {
	"supply": ["supplier", "supply", "delivery", "deliveries", "shipment", "logistics", "feed", "order", "orders", "capacity", "contract"],
	"delivery": ["delivery", "deliveries", "late", "shipment", "shipments", "truck", "miss"],
	"money": ["pay", "paid", "payment", "invoice", "cash", "money", "price", "cost"],
	"staff": ["staff", "worker", "workers", "hiring", "help", "hands", "employee", "short-handed", "busy"],
	"people": ["people", "family", "community", "neighbor", "neighbours", "street", "block", "who"],
	"preference": ["like", "likes", "prefer", "preference", "favor", "favour", "gift", "thanks", "appreciate"],
	"fear": ["worry", "worried", "fear", "afraid", "risk", "scared", "anxious", "bank", "future"],
	"gossip": ["gossip", "rumor", "rumour", "hear", "heard", "news", "talk", "valley", "town"],
	"season": ["season", "seasonal", "weather", "harvest", "calendar", "rush"],
	"rival": ["rival", "competition", "competitor", "other business", "across town", "elsewhere"],
	"help": ["help", "assist", "spare", "can i", "anything i", "need"],
	"general": [],
}


static func detect_topics(player_message: String) -> PackedStringArray:
	var lowered := player_message.strip_edges().to_lower()
	var hits: PackedStringArray = []
	if lowered.is_empty():
		hits.append("general")
		return hits
	for topic_key in _TOPIC_KEYWORDS.keys():
		if str(topic_key) == "general":
			continue
		var keywords: Array = _TOPIC_KEYWORDS[topic_key]
		for keyword_variant in keywords:
			if str(keyword_variant) in lowered:
				if not str(topic_key) in hits:
					hits.append(str(topic_key))
				break
	if hits.is_empty():
		hits.append("general")
	return hits


static func select_for_prompt(eligible_facts: Array, player_message: String, limit: int = DEFAULT_LIMIT) -> Array:
	if eligible_facts.is_empty():
		return []
	var topics := detect_topics(player_message)
	var is_general := topics.size() == 1 and topics[0] == "general"

	var scored: Array = []
	for fact_variant in eligible_facts:
		if typeof(fact_variant) != TYPE_DICTIONARY:
			continue
		var fact: Dictionary = (fact_variant as Dictionary).duplicate(true)
		var score := _score_fact(fact, topics, is_general)
		scored.append({"score": score, "fact": fact})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)

	var selected: Array = []
	var ops_count := 0
	var non_ops_count := 0
	var max_ops := 2 if is_general else 4
	var min_non_ops := 2 if is_general else 1

	# First pass: prefer topical / non-ops under caps.
	for entry_variant in scored:
		if selected.size() >= limit:
			break
		var entry: Dictionary = entry_variant
		var fact: Dictionary = entry.get("fact", {})
		var is_ops := _is_ops_fact(fact)
		if is_ops and ops_count >= max_ops:
			continue
		if is_general and is_ops and non_ops_count < min_non_ops:
			# Hold ops until we have some social/atmospheric variety.
			var remaining_non_ops := _count_remaining_non_ops(scored, selected)
			if remaining_non_ops > 0:
				continue
		selected.append(fact)
		if is_ops:
			ops_count += 1
		else:
			non_ops_count += 1

	# Fill remaining slots if caps left gaps.
	if selected.size() < limit:
		for entry_variant in scored:
			if selected.size() >= limit:
				break
			var fact: Dictionary = (entry_variant as Dictionary).get("fact", {})
			if _fact_already_selected(selected, fact):
				continue
			selected.append(fact)

	return selected


static func _score_fact(fact: Dictionary, topics: PackedStringArray, is_general: bool) -> float:
	var tags := _fact_topic_tags(fact)
	var fact_type := str(fact.get("factType", "")).to_lower()
	var summary := str(fact.get("summary", "")).to_lower()
	var score := 0.0

	if is_general:
		# Soft preference for social/atmospheric variety on open-ended chat.
		if fact_type in ["preference", "atmospheric", "staff", "seasonal", "fear", "rival_rumor"]:
			score += 2.5
		elif fact_type == "operational":
			score += 0.4
		else:
			score += 1.0
	else:
		for topic in topics:
			var t := str(topic)
			if t in tags:
				score += 3.0
			if t == fact_type or (t == "gossip" and fact_type == "atmospheric"):
				score += 2.0
			if t == "supply" and fact_type == "operational":
				score += 1.5
			# Keyword overlap in summary as a light boost.
			var keywords: Array = _TOPIC_KEYWORDS.get(t, [])
			for keyword_variant in keywords:
				if str(keyword_variant) in summary:
					score += 0.35
					break

	# Prefer easier disclosures slightly so chat can surface softer intel first.
	score += (5.0 - float(fact.get("sensitivity", 2))) * 0.15
	return score


static func _fact_topic_tags(fact: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var raw: Variant = fact.get("topicTags", [])
	if typeof(raw) == TYPE_ARRAY:
		for tag_variant in raw:
			var tag := str(tag_variant).strip_edges().to_lower()
			if not tag.is_empty() and not tag in out:
				out.append(tag)
	var fact_type := str(fact.get("factType", "")).to_lower()
	if not fact_type.is_empty() and not fact_type in out:
		out.append(fact_type)
	if fact_type == "operational" and not "supply" in out:
		out.append("supply")
	return out


static func _is_ops_fact(fact: Dictionary) -> bool:
	var fact_type := str(fact.get("factType", "")).to_lower()
	if fact_type == "operational":
		return true
	var tags := _fact_topic_tags(fact)
	return "supply" in tags or "delivery" in tags


static func _count_remaining_non_ops(scored: Array, selected: Array) -> int:
	var count := 0
	for entry_variant in scored:
		var fact: Dictionary = (entry_variant as Dictionary).get("fact", {})
		if _is_ops_fact(fact):
			continue
		if _fact_already_selected(selected, fact):
			continue
		count += 1
	return count


static func _fact_already_selected(selected: Array, fact: Dictionary) -> bool:
	var fact_id := str(fact.get("factId", ""))
	for selected_variant in selected:
		if typeof(selected_variant) != TYPE_DICTIONARY:
			continue
		if str((selected_variant as Dictionary).get("factId", "")) == fact_id:
			return true
	return false
