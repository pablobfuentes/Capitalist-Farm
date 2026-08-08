# HTTP client for local AI negotiation proxy (optional — game playable offline).
extends Node

signal health_updated(available: bool, model: String)
signal negotiate_finished(result: Dictionary, error: String)
signal community_chat_finished(result: Dictionary, error: String)

const DEFAULT_PROXY_URL := "http://127.0.0.1:8787"
const NEGOTIATE_PATH := "/negotiate"
const COMMUNITY_CHAT_PATH := "/community-chat"
const HEALTH_PATH := "/health"
const OFFLINE_NOTE := "AI offline — using basic replies. Start with: npm start, then open http://127.0.0.1:8787/"
const COMMUNITY_CHAT_DISABLED_NOTE := "Community chat is not enabled for this build."
const NEGOTIATE_TIMEOUT_SEC := 60.0
const COMMUNITY_CHAT_TIMEOUT_SEC := 60.0
const HEALTH_TIMEOUT_SEC := 10.0

const _COMMUNITY_SCHEMA_HINT := """Reply with ONLY a raw JSON object (no markdown fences, no extra text) matching exactly:
{"dialogue":"1-3 sentence in-character reply","tone":"neutral|warm|irritated|guarded|amused|hostile","social_action":"none|small_talk|compliment|apology|gift_offer|request|promise|disclosure|refusal","fact_disclosures":[],"gift":null,"promise_proposal":null,"interaction_classification":{"sincerity":"low|medium|high","respectfulness":"low|medium|high","manipulation_signal":"none|mild|strong","repetition":"new|repeated|excessive"},"new_fact_proposals":[]}"""

const _Prompt := preload("res://core/systems/ai_negotiation_prompt.gd")

var proxy_base_url: String = DEFAULT_PROXY_URL
var ai_available: bool = false
var ai_model: String = ""


func _ready() -> void:
	check_health()


func check_health(on_complete: Callable = Callable()) -> void:
	var url := proxy_base_url.trim_suffix("/") + HEALTH_PATH
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = HEALTH_TIMEOUT_SEC
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		ai_available = false
		ai_model = ""
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 0:
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY and bool(parsed.get("ok", false)):
				ai_available = true
				ai_model = str(parsed.get("model", ""))
		if on_complete.is_valid():
			on_complete.call(ai_available, ai_model)
		health_updated.emit(ai_available, ai_model)
		req.queue_free()
	)
	var err := req.request(url)
	if err != OK:
		if on_complete.is_valid():
			on_complete.call(false, "")
		health_updated.emit(false, "")
		req.queue_free()


func begin_negotiation_session(state: RunState) -> void:
	if state == null or state.negotiation.is_empty():
		return
	state.negotiation["aiStatus"] = "checking"
	state.negotiation["aiModel"] = ""
	check_health(func(available: bool, model: String) -> void:
		if state == null or state.negotiation.is_empty():
			return
		if available:
			state.negotiation["aiStatus"] = "online"
			state.negotiation["aiModel"] = model
			state.negotiation["aiOfflineNoted"] = false
		else:
			_note_offline(state)
	)


func request_negotiation(state: RunState, player_message: String, callback: Callable) -> void:
	if state == null or state.negotiation.is_empty():
		callback.call({}, "No active negotiation")
		return

	var prompt := _Prompt.build_prompt(state, state.negotiation, player_message)
	var url := proxy_base_url.trim_suffix("/") + NEGOTIATE_PATH
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = NEGOTIATE_TIMEOUT_SEC
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var err := ""
		var parsed: Dictionary = {}
		if result != HTTPRequest.RESULT_SUCCESS:
			err = "Network error (%d)" % result
		elif code != 200:
			var fail_body: Variant = JSON.parse_string(body.get_string_from_utf8()) if body.size() > 0 else {}
			if typeof(fail_body) == TYPE_DICTIONARY:
				err = str(fail_body.get("error", "AI proxy %d" % code))
			else:
				err = "AI proxy %d" % code
		else:
			var raw: Variant = JSON.parse_string(body.get_string_from_utf8()) if body.size() > 0 else {}
			if typeof(raw) != TYPE_DICTIONARY:
				err = "Empty AI reply"
			else:
				parsed = _normalize_ai_response(raw)
				if str(parsed.get("dialogue", "")).is_empty() and str(parsed.get("intent", "")).is_empty():
					err = "Empty AI reply"
				else:
					ai_available = true
					state.negotiation["aiStatus"] = "online"
					state.negotiation["aiOfflineNoted"] = false
		if not err.is_empty():
			_note_offline(state)
		negotiate_finished.emit(parsed, err)
		if callback.is_valid():
			callback.call(parsed, err)
		req.queue_free()
	)
	var headers := ["Content-Type: application/json"]
	req.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify({"prompt": prompt}))


func request_community_chat(request: Dictionary, callback: Callable) -> void:
	var payload := {
		"prompt": str(request.get("prompt", "")),
		"systemPrompt": str(request.get("systemPrompt", "")),
		"userPrompt": str(request.get("userPrompt", "")),
		"responseSchema": str(request.get("responseSchema", "community_chat_v1")),
	}
	var url := proxy_base_url.trim_suffix("/") + COMMUNITY_CHAT_PATH
	_post_json(url, COMMUNITY_CHAT_TIMEOUT_SEC, payload, func(code: int, parsed: Dictionary, err: String) -> void:
		if _should_fallback_community_to_negotiate(code, err):
			_request_community_via_negotiate(request, callback)
			return
		if err.is_empty():
			if str(parsed.get("dialogue", "")).strip_edges().is_empty():
				err = "Empty AI reply"
			else:
				ai_available = true
		community_chat_finished.emit(parsed, err)
		if callback.is_valid():
			callback.call(parsed, err)
	)


func _should_fallback_community_to_negotiate(code: int, err: String) -> bool:
	if code == 404:
		return true
	var lowered := err.to_lower()
	return lowered.contains("not found") or lowered.contains("404")


func _request_community_via_negotiate(request: Dictionary, callback: Callable) -> void:
	var base_prompt := str(request.get("prompt", "")).strip_edges()
	if base_prompt.is_empty():
		base_prompt = ("%s\n\n%s" % [
			str(request.get("systemPrompt", "")),
			str(request.get("userPrompt", "")),
		]).strip_edges()
	var full_prompt := "%s\n\n%s" % [base_prompt, _COMMUNITY_SCHEMA_HINT]
	var url := proxy_base_url.trim_suffix("/") + NEGOTIATE_PATH
	_post_json(url, NEGOTIATE_TIMEOUT_SEC, {"prompt": full_prompt}, func(code: int, raw: Dictionary, err: String) -> void:
		var parsed: Dictionary = {}
		if err.is_empty():
			parsed = _normalize_community_chat_response(raw)
			if str(parsed.get("dialogue", "")).strip_edges().is_empty():
				err = "Empty AI reply"
			else:
				ai_available = true
		if code == 404:
			err = "Proxy missing /community-chat — restart npm start from repo root"
		community_chat_finished.emit(parsed, err)
		if callback.is_valid():
			callback.call(parsed, err)
	)


func _post_json(
	url: String,
	timeout_sec: float,
	payload: Dictionary,
	on_complete: Callable,
) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = timeout_sec
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var err := ""
		var parsed: Dictionary = {}
		if result != HTTPRequest.RESULT_SUCCESS:
			err = "Network error (%d)" % result
		elif code != 200:
			var fail_body: Variant = JSON.parse_string(body.get_string_from_utf8()) if body.size() > 0 else {}
			if typeof(fail_body) == TYPE_DICTIONARY:
				err = str(fail_body.get("error", "AI proxy %d" % code))
			else:
				err = "AI proxy %d" % code
		else:
			var raw: Variant = JSON.parse_string(body.get_string_from_utf8()) if body.size() > 0 else {}
			if typeof(raw) != TYPE_DICTIONARY:
				err = "Empty AI reply"
			else:
				parsed = raw
		if on_complete.is_valid():
			on_complete.call(code, parsed, err)
		req.queue_free()
	)
	var headers := ["Content-Type: application/json"]
	req.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))


func _normalize_community_chat_response(raw: Dictionary) -> Dictionary:
	var classification: Variant = raw.get("interaction_classification")
	if typeof(classification) != TYPE_DICTIONARY:
		classification = {
			"sincerity": "medium",
			"respectfulness": "medium",
			"manipulation_signal": "none",
			"repetition": "new",
		}
	return {
		"dialogue": str(raw.get("dialogue", "")),
		"tone": str(raw.get("tone", "neutral")),
		"social_action": str(raw.get("social_action", "none")),
		"fact_disclosures": raw.get("fact_disclosures", []) if typeof(raw.get("fact_disclosures")) == TYPE_ARRAY else [],
		"gift": raw.get("gift", null),
		"promise_proposal": raw.get("promise_proposal", null),
		"interaction_classification": classification,
		"new_fact_proposals": raw.get("new_fact_proposals", []) if typeof(raw.get("new_fact_proposals")) == TYPE_ARRAY else [],
	}


func can_start_community_chat(state: RunState = null) -> bool:
	return bool(community_chat_gate(state).get("allowed", false))


func community_chat_gate(state: RunState = null) -> Dictionary:
	CommunityConfig.load_config()
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_CHAT, state):
		return {"allowed": false, "message": COMMUNITY_CHAT_DISABLED_NOTE, "reason": "feature_disabled"}
	if CommunityConfig.community_chat_requires_ai() and not ai_available:
		return {
			"allowed": false,
			"message": CommunityConfig.offline_block_message(),
			"reason": "ai_offline",
		}
	return {"allowed": true, "message": "", "reason": "ok"}


func status_label(negotiation: Dictionary) -> Dictionary:
	var st := str(negotiation.get("aiStatus", ""))
	if st == "online":
		var model := str(negotiation.get("aiModel", ai_model))
		var suffix := " · %s" % model if not model.is_empty() else ""
		return {"text": "AI online%s" % suffix, "online": true}
	if st == "checking":
		return {"text": "AI connecting…", "online": false}
	return {"text": "AI offline — basic replies", "online": false}


func _note_offline(state: RunState) -> void:
	if state == null or state.negotiation.is_empty():
		return
	state.negotiation["aiStatus"] = "offline"
	if bool(state.negotiation.get("aiOfflineNoted", false)):
		return
	state.negotiation["aiOfflineNoted"] = true
	var msgs: Array = state.negotiation.get("messages", [])
	msgs.append({"role": "system", "speaker": "System", "text": OFFLINE_NOTE})
	state.negotiation["messages"] = msgs


func _normalize_ai_response(raw: Dictionary) -> Dictionary:
	var out := {
		"dialogue": MathUtil.str_or_empty(raw.get("dialogue", "")),
		"intent": MathUtil.str_or_empty(raw.get("intent", "question")),
	}
	if out["intent"].is_empty():
		out["intent"] = "question"
	if typeof(raw.get("offer")) == TYPE_DICTIONARY:
		var offer: Dictionary = {}
		var raw_offer: Dictionary = raw["offer"]
		for key in ["totalPrice", "cashAtClosing", "closingSpeed", "priceAdjustment", "concessionSize"]:
			if raw_offer.has(key) and raw_offer[key] != null:
				offer[key] = raw_offer[key]
		if typeof(raw_offer.get("termsOffered")) == TYPE_ARRAY:
			var terms: Array = []
			for t in raw_offer["termsOffered"]:
				if t != null:
					terms.append(t)
			offer["termsOffered"] = terms
		out["offer"] = offer
	return out
