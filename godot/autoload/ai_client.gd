# HTTP client for local AI negotiation proxy (optional — game playable offline).
extends Node

signal health_updated(available: bool, model: String)
signal negotiate_finished(result: Dictionary, error: String)

const DEFAULT_PROXY_URL := "http://127.0.0.1:8787"
const NEGOTIATE_PATH := "/negotiate"
const HEALTH_PATH := "/health"
const OFFLINE_NOTE := "AI offline — using basic replies. Start with: npm start, then open http://127.0.0.1:8787/"
const NEGOTIATE_TIMEOUT_SEC := 60.0
const HEALTH_TIMEOUT_SEC := 10.0

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
		"dialogue": str(raw.get("dialogue", "")),
		"intent": str(raw.get("intent", "question")),
	}
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
