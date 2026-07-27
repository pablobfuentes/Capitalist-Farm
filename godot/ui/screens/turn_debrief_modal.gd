extends Window

signal continued

const _Debrief := preload("res://core/systems/debrief_system.gd")

@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _rows_list: VBoxContainer = %RowsList
@onready var _highlights_label: Label = %HighlightsLabel
@onready var _supply_chain_label: Label = %SupplyChainLabel
@onready var _summary_label: Label = %SummaryLabel
@onready var _continue_button: Button = %ContinueButton

var _report: Dictionary = {}


func _ready() -> void:
	close_requested.connect(_on_continue)
	_continue_button.pressed.connect(_on_continue)


func open_with_report(report: Dictionary) -> void:
	_report = report if typeof(report) == TYPE_DICTIONARY else {}
	_refresh()
	popup_centered_ratio(0.72)


func _refresh() -> void:
	if _report.is_empty():
		return
	var turn_closed: int = int(_report.get("turnClosed", 0))
	_title_label.text = "Turn %d Debrief" % turn_closed
	_subtitle_label.text = "Start of turn %d → End of turn %d" % [turn_closed, turn_closed]
	_continue_button.text = "Continue → Turn %d" % (turn_closed + 1)

	for child in _rows_list.get_children():
		child.queue_free()

	_add_compare_row("Cash", int(_report.get("cashBefore", 0)), int(_report.get("cashAfter", 0)))
	_add_compare_row("Net worth", int(_report.get("nwBefore", 0)), int(_report.get("nwAfter", 0)))
	_add_compare_row("Debt outstanding", int(_report.get("debtBefore", 0)), int(_report.get("debtAfter", 0)), true)
	_add_compare_row("Revenue (qtr run-rate)", int(_report.get("revenueBefore", 0)), int(_report.get("revenueAfter", 0)))
	_add_compare_row("Costs + debt svc (qtr)", int(_report.get("costsDebtBefore", 0)), int(_report.get("costsDebtAfter", 0)), true)
	_add_compare_row("Profit run rate (qtr)", int(_report.get("profitRunBefore", 0)), int(_report.get("profitRunAfter", 0)))
	_add_profit_closed_row(int(_report.get("profitQuarterClosed", 0)))

	var highlights: Array = _report.get("highlights", [])
	if highlights.is_empty():
		_highlights_label.visible = false
		_highlights_label.text = ""
	else:
		_highlights_label.visible = true
		var bits: PackedStringArray = []
		for item in highlights:
			bits.append(str(item))
		_highlights_label.text = " · ".join(bits)

	var supply_line: String = str(_report.get("supplyChainLine", ""))
	if supply_line.is_empty():
		_supply_chain_label.visible = false
		_supply_chain_label.text = ""
	else:
		_supply_chain_label.visible = true
		_supply_chain_label.text = supply_line

	_summary_label.text = str(_report.get("summary", ""))


func _add_compare_row(label_text: String, before: int, after: int, invert: bool = false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var delta: int = after - before
	var delta_class: String = _Debrief.delta_class(delta, invert)

	var metric := Label.new()
	metric.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metric.text = label_text
	row.add_child(metric)

	var before_label := Label.new()
	before_label.custom_minimum_size.x = 88
	before_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	before_label.text = MathUtil.fmt_money(before)
	row.add_child(before_label)

	var after_label := Label.new()
	after_label.custom_minimum_size.x = 88
	after_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	after_label.text = MathUtil.fmt_money(after)
	row.add_child(after_label)

	var delta_label := Label.new()
	delta_label.custom_minimum_size.x = 88
	delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	delta_label.text = _Debrief.delta_text(delta)
	delta_label.add_theme_color_override("font_color", _color_for_class(delta_class))
	row.add_child(delta_label)

	_rows_list.add_child(row)


func _add_profit_closed_row(profit: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var delta_class: String = _Debrief.delta_class(profit)

	var metric := Label.new()
	metric.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metric.text = "Profit (quarter closed)"
	row.add_child(metric)

	var dash1 := Label.new()
	dash1.custom_minimum_size.x = 88
	dash1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dash1.text = "—"
	row.add_child(dash1)

	var after_label := Label.new()
	after_label.custom_minimum_size.x = 88
	after_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	after_label.text = MathUtil.fmt_money(profit)
	row.add_child(after_label)

	var delta_label := Label.new()
	delta_label.custom_minimum_size.x = 88
	delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	delta_label.text = _Debrief.delta_text(profit)
	delta_label.add_theme_color_override("font_color", _color_for_class(delta_class))
	row.add_child(delta_label)

	_rows_list.add_child(row)


func _color_for_class(delta_class: String) -> Color:
	match delta_class:
		"up":
			return Color(0.35, 0.62, 0.42)
		"down":
			return Color(0.72, 0.35, 0.30)
		_:
			return Color(0.55, 0.55, 0.50)


func _on_continue() -> void:
	hide()
	continued.emit()
