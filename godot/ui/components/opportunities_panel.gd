extends VBoxContainer

signal buy_business(opportunity_id: String)
signal buy_real_estate(opportunity_id: String)
signal buy_security(opportunity_id: String)
signal take_loan(opportunity_id: String)
signal level_up(opportunity_id: String)
signal negotiate(opportunity_id: String)
signal investigate(opportunity_id: String)
signal urgent_negotiate(problem_id: String)


func refresh(state: RunState) -> void:
	for child in get_children():
		child.queue_free()

	_populate_urgent_problems(state)

	if state.opportunities.is_empty() and state.urgent_problems.is_empty():
		var empty := Label.new()
		empty.text = "No listings this turn."
		add_child(empty)
		return

	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		_add_opportunity_row(state, opp_variant as Dictionary)


func _populate_urgent_problems(state: RunState) -> void:
	if state.urgent_problems.is_empty():
		return
	var heading := Label.new()
	heading.text = "⚠ Urgent relationship issues"
	heading.add_theme_color_override("font_color", Color(0.9, 0.65, 0.45))
	add_child(heading)
	for prob_variant in state.urgent_problems:
		if typeof(prob_variant) != TYPE_DICTIONARY:
			continue
		var prob: Dictionary = prob_variant
		var row_data: Dictionary = RunView.urgent_problem_row(state, prob)
		var detail_lines := RunView.urgent_problem_detail_lines(prob)
		var summary := "\n".join(detail_lines) if not detail_lines.is_empty() else str(row_data.get("summary", ""))
		var row := _make_row(summary)
		var problem_id := str(row_data.get("id", ""))
		var negotiate_btn := Button.new()
		negotiate_btn.text = "Negotiate terms (1 AP)"
		negotiate_btn.disabled = not bool(row_data.get("canNegotiate", false))
		negotiate_btn.pressed.connect(func() -> void: urgent_negotiate.emit(problem_id))
		row.add_child(negotiate_btn)
		add_child(row)


func _add_opportunity_row(state: RunState, opp: Dictionary) -> void:
	var row_data: Dictionary = RunView.opportunity_row(state, opp)
	var kind: String = str(row_data.get("kind", ""))
	var opp_id := str(row_data.get("id", ""))
	match kind:
		"loan_opp":
			_add_simple_action_row(row_data, "Accept (1 AP)", func() -> void: take_loan.emit(opp_id), "canAccept")
		"security_opp":
			_add_simple_action_row(
				row_data,
				str(row_data.get("buyLabel", "Buy 10 shares (1 AP)")),
				func() -> void: buy_security.emit(opp_id),
				"canBuy",
			)
		"realestate_opp":
			_add_simple_action_row(
				row_data,
				str(row_data.get("buyLabel", "Buy Now (1 AP)")),
				func() -> void: buy_real_estate.emit(opp_id),
				"canBuy",
			)
		"levelup_opp":
			_add_level_up_row(row_data)
		_:
			_add_business_opp_row(row_data)


func _add_simple_action_row(row_data: Dictionary, label: String, on_pressed: Callable, flag_key: String) -> void:
	var row := _make_row(str(row_data.get("summary", "")))
	var btn := Button.new()
	btn.text = label
	btn.disabled = not bool(row_data.get(flag_key, false))
	btn.pressed.connect(on_pressed)
	row.add_child(btn)
	add_child(row)


func _add_business_opp_row(row_data: Dictionary) -> void:
	var row := _make_row(str(row_data.get("summary", "")))
	var opp_id := str(row_data.get("id", ""))

	var buy := Button.new()
	buy.text = str(row_data.get("buyLabel", "Buy Now (1 AP)"))
	buy.disabled = not bool(row_data.get("canBuy", false))
	buy.pressed.connect(func() -> void: buy_business.emit(opp_id))
	row.add_child(buy)

	var investigate_btn := Button.new()
	investigate_btn.text = "Investigate (1 AP)"
	investigate_btn.disabled = not bool(row_data.get("canInvestigate", false))
	investigate_btn.pressed.connect(func() -> void: investigate.emit(opp_id))
	row.add_child(investigate_btn)

	var negotiate_btn := Button.new()
	negotiate_btn.text = str(row_data.get("negotiateLabel", "Negotiate (1 AP)"))
	negotiate_btn.disabled = not bool(row_data.get("canNegotiate", false))
	negotiate_btn.pressed.connect(func() -> void: negotiate.emit(opp_id))
	row.add_child(negotiate_btn)
	add_child(row)


func _add_level_up_row(row_data: Dictionary) -> void:
	var row := _make_row(str(row_data.get("summary", "")))
	var opp_id: String = str(row_data.get("id", ""))
	if bool(row_data.get("requiresNegotiation", false)):
		var negotiate_btn := Button.new()
		negotiate_btn.text = "Negotiate (1 AP)"
		negotiate_btn.disabled = not bool(row_data.get("canNegotiate", false))
		negotiate_btn.pressed.connect(func() -> void: negotiate.emit(opp_id))
		row.add_child(negotiate_btn)
	else:
		var invest := Button.new()
		var price: int = int(row_data.get("price", 0))
		invest.text = "1AP + %s" % MathUtil.fmt_money(price) if price > 0 else "1AP"
		invest.disabled = not bool(row_data.get("canInvest", false))
		invest.pressed.connect(func() -> void: level_up.emit(opp_id))
		row.add_child(invest)
	add_child(row)


func _make_row(summary: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = summary
	row.add_child(info)
	return row
