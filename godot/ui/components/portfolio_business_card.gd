extends PanelContainer

## Compact business row for the map portfolio sidebar.

signal pressed(business_id: String)

@onready var _name_label: Label = %NameLabel
@onready var _level_label: Label = %LevelLabel
@onready var _type_label: Label = %TypeLabel
@onready var _value_label: Label = %ValueLabel
@onready var _delta_label: Label = %DeltaLabel
@onready var _profit_label: Label = %ProfitLabel
@onready var _rev_label: Label = %RevLabel
@onready var _cost_label: Label = %CostLabel

var _business_id := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.10, 0.92)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(2)
	style.border_color = Color(0.32, 0.38, 0.30, 0.75)
	style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)


func apply(data: Dictionary) -> void:
	_business_id = str(data.get("id", ""))
	_name_label.text = str(data.get("name", "Business"))
	_level_label.text = "Lv %d" % int(data.get("level", 1))
	var type_bits: PackedStringArray = []
	var type_name := str(data.get("typeLabel", "")).strip_edges()
	var layer := str(data.get("layerLabel", "")).strip_edges()
	if not type_name.is_empty():
		type_bits.append(type_name)
	if not layer.is_empty() and layer != type_name:
		type_bits.append(layer)
	_type_label.text = " · ".join(type_bits) if not type_bits.is_empty() else "—"

	_value_label.text = MathUtil.fmt_money(int(data.get("currentValue", 0)))
	var pct: float = float(data.get("pctDelta", 0.0))
	if absf(pct) >= 0.5:
		var sign := "+" if pct >= 0 else ""
		_delta_label.text = "(%s%.0f%%)" % [sign, pct]
		_delta_label.add_theme_color_override(
			"font_color",
			Color(0.55, 0.82, 0.58, 1) if pct >= 0 else Color(0.86, 0.48, 0.42, 1),
		)
	else:
		_delta_label.text = ""
		_delta_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.62, 1))

	var profit: int = int(data.get("profitPerTurn", 0))
	_profit_label.text = "%s/qtr" % MathUtil.fmt_money(profit)
	_profit_label.add_theme_color_override(
		"font_color",
		Color(0.62, 0.84, 0.66, 1) if profit >= 0 else Color(0.88, 0.50, 0.44, 1),
	)
	_rev_label.text = "Rev %s" % MathUtil.fmt_money(int(data.get("revenuePerTurn", 0)))
	_cost_label.text = "Cost %s" % MathUtil.fmt_money(int(data.get("costPerTurn", 0)))


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not _business_id.is_empty():
			pressed.emit(_business_id)
			accept_event()
