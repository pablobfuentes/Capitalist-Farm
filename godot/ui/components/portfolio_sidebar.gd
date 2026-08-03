extends PanelContainer

## Collapsible left column: NW/Cash/Debt graph + compact business cards (map HUD).

signal expanded_toggled(expanded: bool)
signal business_selected(business_id: String)

const _CARD_SCENE := preload("res://ui/components/portfolio_business_card.tscn")
const _GRAPH_SCRIPT := preload("res://ui/components/progress_graph.gd")

const EXPANDED_WIDTH := 272.0
const COLLAPSED_WIDTH := 30.0
const GRAPH_HEIGHT := 128.0

@onready var _toggle: Button = %ToggleButton
@onready var _title: Label = %TitleLabel
@onready var _expanded_body: Control = %ExpandedBody
@onready var _graph_host: Control = %GraphHost
@onready var _card_list: VBoxContainer = %CardList
@onready var _empty_label: Label = %EmptyLabel
@onready var _scroll: ScrollContainer = %CardScroll

var _expanded := true
var _graph: Control = null


func _ready() -> void:
	_apply_panel_style()
	_graph = Control.new()
	_graph.name = "ProgressGraph"
	_graph.set_script(_GRAPH_SCRIPT)
	_graph.custom_minimum_size = Vector2(0, GRAPH_HEIGHT)
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_graph.max_visible_turns = 10
	_graph_host.add_child(_graph)
	_graph_host.resized.connect(func() -> void:
		if _graph != null:
			_graph.queue_redraw()
	)
	_toggle.pressed.connect(_on_toggle_pressed)
	FeedbackBus.wire_button(_toggle)
	FeedbackBus.wire_scroll(_scroll)
	EventBus.turn_advanced.connect(_on_refresh)
	EventBus.command_applied.connect(_on_refresh)
	EventBus.run_started.connect(_on_refresh)
	EventBus.run_loaded.connect(_on_refresh)
	EventBus.asset_acquired.connect(_on_refresh)
	resized.connect(_on_refresh)
	_apply_collapsed_state(false)
	call_deferred("refresh")


func refresh() -> void:
	if Game.state == null:
		return
	if _graph != null and _graph.has_method("set_history"):
		_graph.call("set_history", Game.state.turn_history)
		_graph.queue_redraw()
	_rebuild_cards()
	_update_mouse_filter()


func set_expanded(expanded: bool) -> void:
	_expanded = expanded
	_apply_collapsed_state(true)


func expanded_width() -> float:
	return EXPANDED_WIDTH if _expanded else COLLAPSED_WIDTH


func is_expanded() -> bool:
	return _expanded


func _apply_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.13, 0.11, 0.94)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(2)
	style.border_color = Color(0.40, 0.46, 0.36, 0.85)
	style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)


func _rebuild_cards() -> void:
	for child in _card_list.get_children():
		child.queue_free()
	if Game.state == null:
		_empty_label.visible = true
		_scroll.visible = false
		return
	var businesses: Array = Game.state.portfolio.businesses
	if businesses.is_empty():
		_empty_label.visible = true
		_scroll.visible = false
		return
	_empty_label.visible = false
	if UpgradeSystem.is_active(Game.state):
		UpgradeSystem.ensure_portfolio_upgrades(Game.state)
	for biz_variant in businesses:
		if not (biz_variant is BusinessInstance):
			continue
		var card: PanelContainer = _CARD_SCENE.instantiate()
		_card_list.add_child(card)
		card.apply(RunView.portfolio_card_data(Game.state, biz_variant))
		if card.has_signal("pressed"):
			card.pressed.connect(_on_card_pressed)
	_scroll.visible = true


func _apply_collapsed_state(animate: bool) -> void:
	_expanded_body.visible = _expanded
	_title.visible = _expanded
	_toggle.text = "◀" if _expanded else "▶"
	_toggle.tooltip_text = "Collapse portfolio" if _expanded else "Expand portfolio"
	custom_minimum_size.x = expanded_width()
	_update_mouse_filter()
	if animate:
		FeedbackBus.pop_in(_expanded_body if _expanded else _toggle)


func _update_mouse_filter() -> void:
	var block := _expanded
	mouse_filter = Control.MOUSE_FILTER_STOP if block else Control.MOUSE_FILTER_IGNORE
	_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	if _expanded_body != null:
		_expanded_body.mouse_filter = Control.MOUSE_FILTER_STOP if block else Control.MOUSE_FILTER_IGNORE
	if _scroll != null:
		_scroll.mouse_filter = Control.MOUSE_FILTER_STOP if block else Control.MOUSE_FILTER_IGNORE
	if _graph_host != null:
		_graph_host.mouse_filter = Control.MOUSE_FILTER_STOP if block else Control.MOUSE_FILTER_IGNORE
	if _graph != null:
		_graph.mouse_filter = Control.MOUSE_FILTER_STOP if block else Control.MOUSE_FILTER_IGNORE


func _on_toggle_pressed() -> void:
	_expanded = not _expanded
	_apply_collapsed_state(true)
	expanded_toggled.emit(_expanded)


func _on_card_pressed(business_id: String) -> void:
	if not business_id.is_empty():
		business_selected.emit(business_id)


func _on_refresh(_a = null, _b = null) -> void:
	refresh()
