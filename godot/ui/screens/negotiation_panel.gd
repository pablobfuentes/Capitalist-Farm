extends Window

signal closed

const _Archetypes := preload("res://core/content/negotiation_archetypes.gd")
const _Rival := preload("res://core/systems/rival_system.gd")
const _Diligence := preload("res://core/systems/diligence_system.gd")
const _V2 := preload("res://core/systems/negotiation_v2_engine.gd")
const _V2Display := preload("res://core/systems/negotiation_v2_display.gd")
const _Transcript := preload("res://core/systems/negotiation_transcript.gd")

var _opportunity_id: String = ""
var _busy: bool = false


func _ready() -> void:
	title = "Negotiate"
	unresizable = false
	close_requested.connect(_on_walk)
	%CloseButton.pressed.connect(_on_walk)
	%SendButton.pressed.connect(_on_send_pressed)
	%WalkButton.pressed.connect(_on_walk)
	%CloseDealButton.pressed.connect(_on_close_deal)
	%CopyTranscriptButton.pressed.connect(_on_copy_transcript)
	%SaveLogButton.pressed.connect(_on_save_log)
	%MessageInput.text_submitted.connect(_on_text_submitted)
	AiClient.health_updated.connect(_on_ai_health_updated)
	EventBus.negotiation_updated.connect(_on_negotiation_updated)
	get_tree().root.size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if visible:
		_fit_to_viewport()


func open_for_opportunity(opportunity_id: String) -> void:
	_opportunity_id = opportunity_id
	var result: Dictionary = Game.apply_command(GameCommand.start_negotiation(opportunity_id))
	if not bool(result.get("ok", false)):
		%StatusLabel.text = str(result.get("error", "Could not start negotiation"))
		return
	_open_session()


func open_active() -> void:
	if Game.state == null or Game.state.negotiation.is_empty():
		return
	_opportunity_id = str(Game.state.negotiation.get("opportunityId", ""))
	_open_session()


func _open_session() -> void:
	AiClient.begin_negotiation_session(Game.state)
	_fit_to_viewport()
	popup_centered()
	_refresh()
	_Transcript.save_to_user_file(Game.state.negotiation)


func _fit_to_viewport() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var margin := 32
	max_size = Vector2i(int(vp_size.x - margin), int(vp_size.y - margin))
	var target_w := clampi(int(vp_size.x * 0.82), min_size.x, max_size.x)
	var target_h := clampi(int(vp_size.y * 0.82), min_size.y, max_size.y)
	size = Vector2i(target_w, target_h)


func _refresh() -> void:
	var neg: Dictionary = Game.state.negotiation if Game.state else {}
	if neg.is_empty():
		return

	var ctx: Dictionary = neg.get("context", {})
	var cp: Dictionary = neg.get("counterparty", {})
	var arch: Dictionary = _Archetypes.get_archetype(str(cp.get("archetypeId", "")))
	var v2: Dictionary = neg.get("v2", {})
	var situation_label := str(v2.get("situationLabel", arch.get("flavor", "Seller"))) if not v2.is_empty() else str(arch.get("flavor", ""))

	%HeaderLabel.text = str(ctx.get("name", "Listing"))
	%MetaLabel.text = "Ask %s · %s · %s (%s) · Round %d/%d · Leverage: %s" % [
		MathUtil.fmt_money(int(ctx.get("price", 0))),
		situation_label,
		str(cp.get("speciesId", "—")).capitalize(),
		str(cp.get("role", "seller")),
		int(neg.get("round", 0)),
		int(neg.get("maxRounds", 6)),
		str(v2.get("leverageLabel", "Balanced")) if not v2.is_empty() else "Balanced",
	]
	_update_gauge_panel(neg)
	_update_progress_panel(neg)
	%EconomicHintLabel.text = str(neg.get("economicStatusHint", "No offer"))

	var is_contest := str(neg.get("kind", "")) == "rival_contest"
	title = "Three-Way Contest" if is_contest else "Negotiate"
	if is_contest:
		var rival_raw: Variant = neg.get("rival")
		var rival: Dictionary = rival_raw if rival_raw is Dictionary else {}
		var rname := _Rival.display_name(rival)
		var rival_offer: Dictionary = _Rival._offer_dict(neg, "rivalLastOffer")
		var rbid: int = int(rival_offer.get("totalPrice", 0))
		var player_offer: Dictionary = _Rival._offer_dict(neg, "playerLastOffer")
		var pbid: int = int(player_offer.get("totalPrice", 0))
		var lead := str(neg.get("leadingBidder", ""))
		var lead_text := ""
		if lead == "player":
			lead_text = " · You lead"
		elif lead == "rival":
			lead_text = " · %s leads" % rname
		var rival_line := "%s: conceded" % rname if bool(neg.get("rivalConceded", false)) else "%s bid: %s" % [rname, MathUtil.fmt_money(rbid)]
		%RivalBarLabel.text = "%s %s%s · Round %d/%d" % [
			rival_line,
			(" · Your bid: %s" % MathUtil.fmt_money(pbid)) if pbid > 0 else "",
			lead_text,
			int(neg.get("round", 0)),
			int(neg.get("maxRounds", 8)),
		]
		%CompareLabel.text = _Rival.package_comparison_text(neg)
		%RivalBarLabel.show()
		%CompareLabel.show()
	else:
		%RivalBarLabel.text = ""
		%CompareLabel.text = ""
		%RivalBarLabel.hide()
		%CompareLabel.hide()

	_update_intel_panel(neg)

	var ai_text := _update_ai_status(neg)
	%AiStatusLabel.visible = not ai_text.is_empty()

	%DataLabel.text = _Transcript.build_data_panel(neg)
	%MessagesEdit.text = _Transcript.build_messages(neg)
	%MessagesEdit.set_caret_line(maxi(0, %MessagesEdit.get_line_count() - 1))

	var last_decision: String = str(neg.get("lastDecision", ""))
	var utility: float = float(neg.get("lastUtility", 0.0))
	if _busy:
		%StatusLabel.text = "Waiting for AI reply…"
	elif bool(neg.get("readyToClose", false)):
		var pending: Dictionary = neg.get("pendingOffer", neg.get("playerLastOffer", {}))
		var close_total: int = int(pending.get("totalPrice", 0))
		if close_total > 0:
			%StatusLabel.text = "Ready to close at %s — click Close Deal." % MathUtil.fmt_money(close_total)
		else:
			%StatusLabel.text = "Both gates passed — click Close Deal to finalize."
	elif not v2.is_empty():
		var display: Dictionary = _V2.gauge_display(v2)
		%StatusLabel.text = "Last response: %s · %s" % [last_decision if last_decision != "" else "—", display.get("zoneHint", "")]
	elif last_decision != "":
		%StatusLabel.text = "Last response: %s (utility %.1f)" % [last_decision, utility]
	else:
		%StatusLabel.text = "Type your offer · Use Copy debug log / Save log to export full session data."

	var ready := bool(neg.get("readyToClose", false))
	%CloseDealButton.visible = ready
	%CloseDealButton.disabled = _busy or not ready
	_set_input_enabled(not _busy)
	_sync_scroll_content_widths()
	_scroll_messages_to_bottom()


func _sync_scroll_content_widths() -> void:
	var intel_w := maxi(%IntelScroll.size.x - 12, 200)
	%IntelLabel.custom_minimum_size.x = intel_w
	var data_w := maxi(%DataScroll.size.x - 12, 200)
	%DataLabel.custom_minimum_size.x = data_w


func _scroll_messages_to_bottom() -> void:
	await get_tree().process_frame
	%MessagesEdit.set_caret_line(maxi(0, %MessagesEdit.get_line_count() - 1))
	%MessagesEdit.scroll_vertical = int(%MessagesEdit.get_v_scroll_bar().max_value) if %MessagesEdit.get_v_scroll_bar() else 0


func _update_progress_panel(neg: Dictionary) -> void:
	var v2: Dictionary = neg.get("v2", {})
	if v2.is_empty():
		%ProgressPanel.hide()
		return
	var panel: Dictionary = _V2Display.format_progress_panel(
		v2,
		neg.get("counterparty", {}),
		bool(neg.get("readyToClose", false)),
		_get_v2_preview(neg),
	)
	if not bool(panel.get("visible", false)):
		%ProgressPanel.hide()
		return
	%ProgressPanel.show()
	%RapportLabel.text = str(panel.get("rapportLine", ""))
	%DiscountLabel.text = str(panel.get("discountLine", ""))
	var situation_line := str(panel.get("situationLine", ""))
	%SituationProgressLabel.text = situation_line
	%SituationProgressLabel.visible = not situation_line.is_empty()
	%CoachTipLabel.text = str(panel.get("coachLine", ""))


func _get_v2_preview(neg: Dictionary) -> Dictionary:
	var ctx: Dictionary = neg.get("context", {})
	var opp: Variant = ctx.get("opp")
	if opp is Dictionary:
		var preview: Variant = (opp as Dictionary).get("v2Preview")
		if preview is Dictionary:
			return preview as Dictionary
	return {}


func _update_gauge_panel(neg: Dictionary) -> void:
	var v2: Dictionary = neg.get("v2", {})
	if v2.is_empty():
		%GaugeRow.hide()
		return
	%GaugeRow.show()
	var display: Dictionary = _V2.gauge_display(v2)
	var gauge: int = int(display.get("gauge", 0))
	var arrow: String = str(display.get("arrow", "→"))
	%GaugeBar.value = gauge
	%GaugeLabel.text = "Deal Momentum: %s %s" % [str(display.get("zoneLabel", "Listening")), arrow]
	var zone_id: String = str(display.get("zoneId", ""))
	match zone_id:
		"collapsing":
			%GaugeBar.modulate = Color(0.85, 0.35, 0.35)
		"resistant":
			%GaugeBar.modulate = Color(0.9, 0.55, 0.35)
		"listening":
			%GaugeBar.modulate = Color(0.85, 0.8, 0.45)
		"close":
			%GaugeBar.modulate = Color(0.55, 0.75, 0.55)
		"ready":
			%GaugeBar.modulate = Color(0.4, 0.85, 0.5)
		_:
			%GaugeBar.modulate = Color.WHITE


func _update_intel_panel(neg: Dictionary) -> void:
	var intel_text := _Diligence.format_intel_panel(neg, Game.state)
	%IntelLabel.text = intel_text
	var unlocked := bool(neg.get("intelUnlocked", false))
	if unlocked:
		%IntelLabel.add_theme_color_override("font_color", Color(0.78, 0.92, 0.82))
	else:
		%IntelLabel.add_theme_color_override("font_color", Color(0.72, 0.68, 0.58))
	%IntelScroll.visible = not intel_text.is_empty()


func _update_ai_status(neg: Dictionary) -> String:
	var st: Dictionary = AiClient.status_label(neg)
	var status_text: String = str(st.get("text", ""))
	if str(neg.get("aiStatus", "")) == "offline":
		status_text += "\nRun: npm start  ·  Ollama running  ·  http://127.0.0.1:8787/health"
	%AiStatusLabel.text = status_text
	if bool(st.get("online", false)):
		%AiStatusLabel.add_theme_color_override("font_color", Color(0.35, 0.6, 0.35))
	elif str(neg.get("aiStatus", "")) == "checking":
		%AiStatusLabel.add_theme_color_override("font_color", Color(0.5, 0.55, 0.45))
	else:
		%AiStatusLabel.add_theme_color_override("font_color", Color(0.65, 0.45, 0.35))
	return status_text


func _on_ai_health_updated(_available: bool, _model: String) -> void:
	if _opportunity_id.is_empty() or Game.state == null or Game.state.negotiation.is_empty():
		return
	_refresh()


func _on_negotiation_updated(_state: RunState = null) -> void:
	if _opportunity_id.is_empty():
		return
	_refresh()


func _set_input_enabled(enabled: bool) -> void:
	%SendButton.disabled = not enabled
	%MessageInput.editable = enabled
	%WalkButton.disabled = not enabled
	var ready := Game.state != null and bool(Game.state.negotiation.get("readyToClose", false))
	%CloseDealButton.disabled = not enabled or not ready


func _on_close_deal() -> void:
	if _busy:
		return
	var result: Dictionary = Game.apply_command(GameCommand.close_negotiation_deal())
	if not bool(result.get("ok", false)):
		%StatusLabel.text = str(result.get("error", "Could not close deal"))
		_refresh()
		return
	if bool(result.get("closed", false)) and result.has("business"):
		%StatusLabel.text = "Deal closed!"
		_refresh()
		await get_tree().create_timer(1.2).timeout
		hide()
		closed.emit()
	else:
		_refresh()


func _on_send_pressed() -> void:
	_send_message(%MessageInput.text)


func _on_text_submitted(text: String) -> void:
	_send_message(text)


func _send_message(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or _busy:
		return

	_busy = true
	_set_input_enabled(false)
	%StatusLabel.text = "Waiting for AI reply…" if AiClient.ai_available else "Sending…"
	%MessageInput.text = ""

	Game.send_negotiation_message_async(trimmed, _on_negotiation_result)


func _on_negotiation_result(result: Dictionary) -> void:
	_busy = false

	if not bool(result.get("ok", false)):
		%StatusLabel.text = str(result.get("error", "Send failed"))
		_refresh()
		return

	if bool(result.get("ready_to_close", false)):
		_refresh()
		%MessageInput.grab_focus()
		return

	if bool(result.get("closed", false)):
		_refresh()
		if result.has("business"):
			%StatusLabel.text = "Deal closed!"
			await get_tree().create_timer(1.2).timeout
			hide()
			closed.emit()
			return
		var decision := str(result.get("decision", ""))
		if decision == "rival_win":
			%StatusLabel.text = str(result.get("reply", "Rowe wins the contest."))
			await get_tree().create_timer(2.0).timeout
			hide()
			closed.emit()
			return
		%StatusLabel.text = str(result.get("reply", "Negotiation ended."))
		_refresh()
		return

	_refresh()
	%MessageInput.grab_focus()


func _on_walk() -> void:
	if _busy:
		return
	_Transcript.save_to_user_file(Game.state.negotiation if Game.state else {})
	Game.apply_command(GameCommand.end_negotiation(true))
	hide()
	closed.emit()


func _on_copy_transcript() -> void:
	var neg: Dictionary = Game.state.negotiation if Game.state else {}
	var text := _Transcript.build_transcript(neg)
	if text.is_empty():
		%StatusLabel.text = "Nothing to copy yet."
		return
	DisplayServer.clipboard_set(text)
	%StatusLabel.text = "Debug log copied to clipboard (%d chars)." % text.length()


func _on_save_log() -> void:
	var neg: Dictionary = Game.state.negotiation if Game.state else {}
	var path := _Transcript.save_to_user_file(neg)
	if path.is_empty():
		%StatusLabel.text = "Could not save log file."
		return
	DisplayServer.clipboard_set(path)
	%StatusLabel.text = "Log saved (path also copied): %s" % path
