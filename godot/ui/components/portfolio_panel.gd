extends VBoxContainer

signal improve_business(business_id: String)
signal improve_real_estate(asset_id: String)
signal sell_asset(asset_kind: String, asset_id: String)
signal sell_security(ticker: String)
signal payoff_loan(loan_id: String)


func refresh(state: RunState) -> void:
	for child in get_children():
		child.queue_free()

	var has_businesses := not state.portfolio.businesses.is_empty()
	var has_loans := not state.loans.is_empty()
	var has_securities := not state.portfolio.securities.is_empty()
	var has_re := not state.portfolio.real_estate.is_empty()

	if not has_businesses and not has_loans and not has_securities and not has_re:
		var empty := Label.new()
		empty.text = "No businesses yet."
		add_child(empty)
		return

	if has_businesses:
		for biz: BusinessInstance in state.portfolio.businesses:
			_add_business_row(state, biz)

	for raw_variant in state.portfolio.real_estate:
		if typeof(raw_variant) == TYPE_DICTIONARY:
			_add_real_estate_row(state, raw_variant as Dictionary)

	for raw_variant in state.portfolio.securities:
		if typeof(raw_variant) == TYPE_DICTIONARY:
			_add_security_row(raw_variant as Dictionary)

	if has_loans:
		if has_businesses:
			var heading := Label.new()
			heading.text = "Loans"
			add_child(heading)
		for loan_variant in state.loans:
			if typeof(loan_variant) == TYPE_DICTIONARY:
				_add_loan_row(state, loan_variant as Dictionary)


func _add_business_row(state: RunState, biz: BusinessInstance) -> void:
	var row_data: Dictionary = RunView.business_row(state, biz)
	var row := _make_row(row_data.get("summary", ""))
	var business_id := str(row_data.get("id", ""))

	if bool(row_data.get("canImprove", false)):
		var improve := Button.new()
		improve.text = str(row_data.get("improveLabel", "Improve (1 AP)"))
		improve.disabled = not bool(row_data.get("canSell", false))
		improve.pressed.connect(func() -> void: improve_business.emit(business_id))
		row.add_child(improve)

	var sell := Button.new()
	sell.text = str(row_data.get("sellLabel", "Sell (1 AP)"))
	sell.disabled = not bool(row_data.get("canSell", false))
	sell.pressed.connect(func() -> void: sell_asset.emit("business", business_id))
	row.add_child(sell)
	add_child(row)


func _add_real_estate_row(state: RunState, asset: Dictionary) -> void:
	var row_data: Dictionary = RunView.real_estate_row(state, asset)
	var row := _make_row(row_data.get("summary", ""))
	var asset_id := str(row_data.get("id", ""))

	if bool(row_data.get("canImprove", false)):
		var improve_re := Button.new()
		improve_re.text = "Improve (1 AP)"
		improve_re.disabled = not bool(row_data.get("canSell", false))
		improve_re.pressed.connect(func() -> void: improve_real_estate.emit(asset_id))
		row.add_child(improve_re)

	var sell_re := Button.new()
	sell_re.text = str(row_data.get("sellLabel", "Sell (1 AP)"))
	sell_re.disabled = not bool(row_data.get("canSell", false))
	sell_re.pressed.connect(func() -> void: sell_asset.emit("realestate", asset_id))
	row.add_child(sell_re)
	add_child(row)


func _add_security_row(holding: Dictionary) -> void:
	var row_data: Dictionary = RunView.security_row(null, holding)
	var row := _make_row(row_data.get("summary", ""))
	var ticker := str(row_data.get("ticker", ""))
	var sell := Button.new()
	sell.text = "Sell"
	sell.pressed.connect(func() -> void: sell_security.emit(ticker))
	row.add_child(sell)
	add_child(row)


func _add_loan_row(state: RunState, loan: Dictionary) -> void:
	var row_data: Dictionary = RunView.loan_row(state, loan)
	var row := _make_row(row_data.get("summary", ""))
	var loan_id := str(row_data.get("id", ""))
	var payoff := Button.new()
	payoff.text = "Pay Off Early"
	payoff.disabled = not bool(row_data.get("canPayoff", false))
	payoff.pressed.connect(func() -> void: payoff_loan.emit(loan_id))
	row.add_child(payoff)
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
