extends Window

signal closed

const _Bank := preload("res://core/systems/bank_system.gd")
const _Security := preload("res://core/systems/security_system.gd")

@onready var _loan_label: Label = %LoanLabel
@onready var _loan_button: Button = %LoanButton
@onready var _securities_list: VBoxContainer = %SecuritiesList
@onready var _status_label: Label = %StatusLabel
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	title = "Capital Farm Bank"
	unresizable = false
	close_requested.connect(_on_close)
	_close_button.pressed.connect(_on_close)
	_loan_button.pressed.connect(_on_take_loan_pressed)


func open_bank() -> void:
	_refresh()
	popup_centered_ratio(0.72)


func _refresh() -> void:
	if Game.state == null:
		return
	var loan_row: Dictionary = _Bank.loan_offer_row(Game.state)
	if loan_row.is_empty():
		_loan_label.text = "No credit line available this turn."
		_loan_button.disabled = true
		_loan_button.text = "Draw line of credit (1 AP)"
	else:
		_loan_label.text = str(loan_row.get("summary", ""))
		var can_take := bool(loan_row.get("canTake", false))
		_loan_button.disabled = not can_take
		if bool(loan_row.get("alreadyDrawn", false)):
			_loan_button.text = "Line of credit drawn"
		else:
			_loan_button.text = "Draw line of credit (1 AP)"

	for child in _securities_list.get_children():
		child.queue_free()

	for row_variant in _Bank.security_catalog(Game.state):
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		_securities_list.add_child(_make_security_row(row))

	_status_label.text = "Cash %s · AP %d" % [
		MathUtil.fmt_money(Game.state.cash),
		Game.state.action_points,
	]


func _make_security_row(row: Dictionary) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = str(row.get("summary", ""))
	container.add_child(info)

	var ticker := str(row.get("ticker", ""))
	var price_per_share: int = int(row.get("pricePerShare", 0))

	var qty_box := SpinBox.new()
	qty_box.min_value = _Security.MIN_SHARE_LOT
	qty_box.max_value = 1000
	qty_box.step = _Security.MIN_SHARE_LOT
	qty_box.value = _Security.MIN_SHARE_LOT
	qty_box.custom_minimum_size.x = 88
	qty_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.add_child(qty_box)

	var buy_btn := Button.new()
	container.add_child(buy_btn)

	var sync_buy := func() -> void:
		if Game.state == null:
			return
		var qty := int(qty_box.value)
		var cost := qty * price_per_share
		buy_btn.text = "Buy %d · %s (1 AP)" % [qty, MathUtil.fmt_money(cost)]
		buy_btn.disabled = not _Bank.can_afford_shares(Game.state, price_per_share, qty)

	qty_box.value_changed.connect(func(_value: float) -> void: sync_buy.call())
	buy_btn.pressed.connect(func() -> void: _on_buy_security_pressed(ticker, int(qty_box.value)))
	sync_buy.call()
	return container


func _on_take_loan_pressed() -> void:
	var result: Dictionary = Game.apply_command(GameCommand.take_bank_loan())
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("error", "Loan failed"))
		return
	_status_label.text = "Line of credit drawn."
	_refresh()


func _on_buy_security_pressed(ticker: String, quantity: int) -> void:
	var result: Dictionary = Game.apply_command(
		GameCommand.buy_security_ticker(ticker, quantity)
	)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("error", "Purchase failed"))
		return
	_status_label.text = "Bought %d shares of %s." % [
		int(result.get("shares", quantity)),
		ticker,
	]
	_refresh()


func _on_close() -> void:
	hide()
	closed.emit()
