extends Control

@onready var _header_bar = %TopBar
@onready var _debrief_card = %DebriefCard
@onready var portfolio_list = %PortfolioList
@onready var opportunities_list = %OpportunitiesList
@onready var supply_chain_list = %SupplyChainList
@onready var advance_button: Button = %AdvanceButton

var _improve_panel: Window = null
var _negotiation_panel: Window = null
var _shortage_modal: Window = null
var _edge_modal: Window = null
var _supply_chain_view: Window = null
var _field_guide: Window = null
var _turn_debrief_modal: Window = null
var _re_improve_panel: Window = null


func _ready() -> void:
	if not Game.has_active_run():
		Game.go_to_main_menu()
		return

	_improve_panel = preload("res://ui/screens/improve_panel.tscn").instantiate()
	add_child(_improve_panel)
	_improve_panel.closed.connect(_refresh)
	_improve_panel.level_up.connect(func(_id: String) -> void: _refresh())
	_improve_panel.negotiate.connect(_on_negotiate_pressed)

	_negotiation_panel = preload("res://ui/screens/negotiation_panel.tscn").instantiate()
	add_child(_negotiation_panel)
	_negotiation_panel.closed.connect(_refresh)

	_shortage_modal = preload("res://ui/screens/supply_shortage_modal.tscn").instantiate()
	add_child(_shortage_modal)
	_shortage_modal.confirmed.connect(_on_shortage_confirmed)
	_shortage_modal.cancelled.connect(_on_shortage_cancelled)

	_supply_chain_view = preload("res://ui/screens/supply_chain_view.tscn").instantiate()
	add_child(_supply_chain_view)
	_field_guide = preload("res://ui/screens/field_guide_modal.tscn").instantiate()
	add_child(_field_guide)

	_turn_debrief_modal = preload("res://ui/screens/turn_debrief_modal.tscn").instantiate()
	add_child(_turn_debrief_modal)
	_turn_debrief_modal.continued.connect(_on_turn_debrief_continued)

	_re_improve_panel = preload("res://ui/screens/real_estate_improve_panel.tscn").instantiate()
	add_child(_re_improve_panel)
	_re_improve_panel.closed.connect(_refresh)

	_edge_modal = preload("res://ui/components/edge_choice_modal.gd").new()
	add_child(_edge_modal)
	_edge_modal.edge_chosen.connect(_on_edge_chosen)
	_edge_modal.skipped.connect(_on_edge_skipped)

	_connect_panel_signals()

	EventBus.turn_advanced.connect(_on_state_changed)
	EventBus.command_applied.connect(_on_state_changed)
	EventBus.asset_acquired.connect(_on_state_changed)
	EventBus.edge_choices_pending.connect(_on_edge_choices_pending)
	_refresh()


func _connect_panel_signals() -> void:
	portfolio_list.improve_business.connect(_on_improve_pressed)
	portfolio_list.improve_real_estate.connect(_on_improve_re_pressed)
	portfolio_list.sell_asset.connect(_on_sell_pressed)
	portfolio_list.sell_security.connect(_on_sell_security_pressed)
	portfolio_list.payoff_loan.connect(_on_payoff_loan_pressed)

	opportunities_list.buy_business.connect(_on_buy_pressed)
	opportunities_list.buy_real_estate.connect(_on_buy_re_pressed)
	opportunities_list.buy_security.connect(_on_buy_security_pressed)
	opportunities_list.take_loan.connect(_on_take_loan_pressed)
	opportunities_list.level_up.connect(_on_level_up_pressed)
	opportunities_list.negotiate.connect(_on_negotiate_pressed)
	opportunities_list.investigate.connect(_on_investigate_pressed)
	opportunities_list.urgent_negotiate.connect(_on_urgent_negotiate_pressed)


func _on_state_changed(_a = null, _b = null) -> void:
	_refresh()


func _on_edge_choices_pending(_state: RunState, _choices: Array) -> void:
	_maybe_show_edge_choices(Game.state)


func _refresh() -> void:
	var s: RunState = Game.state
	if s == null:
		return

	_header_bar.refresh(s)

	if s.game_over != null:
		Game.go_to_run_report()
		return

	_debrief_card.refresh(s)
	portfolio_list.refresh(s)
	opportunities_list.refresh(s)
	supply_chain_list.refresh(s)
	_maybe_show_edge_choices(s)
	_maybe_show_turn_debrief(s)
	advance_button.disabled = s.game_over != null


func _feedback(message: String) -> void:
	_debrief_card.set_feedback(message)


func _maybe_show_turn_debrief(s: RunState) -> void:
	if s.pending_turn_debrief.is_empty() or s.game_over != null:
		return
	if _turn_debrief_modal.visible:
		return
	_turn_debrief_modal.open_with_report(s.pending_turn_debrief)


func _on_turn_debrief_continued() -> void:
	Game.apply_command(GameCommand.dismiss_turn_debrief())
	_refresh()


func _on_level_up_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.do_level_up(opportunity_id))
	if not bool(result.get("ok", false)):
		_feedback("Level-up failed: %s" % str(result.get("error", "unknown")))
	else:
		_feedback("Level-up completed.")


func _on_urgent_negotiate_pressed(problem_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.start_urgent_negotiation(problem_id))
	if not bool(result.get("ok", false)):
		_feedback("Urgent negotiation failed: %s" % str(result.get("error", "unknown")))
	else:
		_negotiation_panel.open_active()


func _maybe_show_edge_choices(s: RunState) -> void:
	if s == null or s.edge_choices_pending.is_empty() or s.game_over != null:
		if _edge_modal.visible:
			_edge_modal.close_modal()
		return
	if _edge_modal.visible:
		return
	_edge_modal.open_with_choices(s.edge_choices_pending)


func _on_edge_chosen(edge_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.choose_edge(edge_id))
	if bool(result.get("ok", false)):
		_feedback("Strategic edge acquired.")
	_refresh()


func _on_edge_skipped() -> void:
	Game.apply_command(GameCommand.skip_edge())
	_refresh()


func _on_buy_re_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.acquire_real_estate(opportunity_id))
	if not bool(result.get("ok", false)):
		_feedback("Purchase failed: %s" % str(result.get("error", "unknown")))


func _on_sell_pressed(asset_kind: String, asset_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.sell_asset(asset_kind, asset_id))
	if not bool(result.get("ok", false)):
		_feedback("Sell failed: %s" % str(result.get("error", "unknown")))
	else:
		_feedback("Sold for %s." % MathUtil.fmt_money(int(result.get("proceeds", 0))))


func _on_buy_security_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.buy_security(opportunity_id, 10))
	if not bool(result.get("ok", false)):
		_feedback("Security purchase failed: %s" % str(result.get("error", "unknown")))
	else:
		_feedback("Bought %d shares of %s." % [int(result.get("shares", 0)), str(result.get("ticker", ""))])


func _on_sell_security_pressed(ticker: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.sell_security(ticker))
	if not bool(result.get("ok", false)):
		_feedback("Sell failed: %s" % str(result.get("error", "unknown")))
	else:
		_feedback("Sold for %s." % MathUtil.fmt_money(int(result.get("proceeds", 0))))


func _on_supply_chain_pressed() -> void:
	_supply_chain_view.open_view()


func _on_field_guide_pressed() -> void:
	_field_guide.open_guide()


func _on_take_loan_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.take_loan(opportunity_id))
	if not bool(result.get("ok", false)):
		_feedback("Loan failed: %s" % str(result.get("error", "unknown")))
	else:
		_feedback("Line of credit accepted — cash increased, debt service starts next quarter.")


func _on_payoff_loan_pressed(loan_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.payoff_loan(loan_id))
	if not bool(result.get("ok", false)):
		_feedback("Payoff failed: %s" % str(result.get("error", "unknown")))
	else:
		_feedback("Loan paid off early.")


func _on_improve_pressed(business_id: String) -> void:
	_improve_panel.open_for_business(business_id)


func _on_improve_re_pressed(asset_id: String) -> void:
	_re_improve_panel.open_for_asset(asset_id)


func _on_buy_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.acquire_business(opportunity_id))
	if not bool(result.get("ok", false)):
		_feedback("Purchase failed: %s" % str(result.get("error", "unknown")))


func _on_negotiate_pressed(opportunity_id: String) -> void:
	_negotiation_panel.open_for_opportunity(opportunity_id)


func _on_investigate_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.investigate(opportunity_id))
	if not bool(result.get("ok", false)):
		_feedback("Investigate failed: %s" % str(result.get("error", "unknown")))
	else:
		var opp: Variant = result.get("opportunity")
		if opp is Dictionary and (opp as Dictionary).has("v2Preview"):
			var preview: Dictionary = (opp as Dictionary)["v2Preview"]
			var kw: Array = preview.get("keywords", [])
			var kw_hint := ""
			if kw.size() > 0:
				kw_hint = " Try: \"%s\"." % str(kw[0])
			_feedback("Diligence complete — %.1f%% opening discount, floor %s, target ~%s.%s" % [
				float(preview.get("openingDiscountPct", 0.0)) * 100.0,
				MathUtil.fmt_money(int(preview.get("hardFloor", 0))),
				MathUtil.fmt_money(int(preview.get("openingAcceptable", 0))),
				kw_hint,
			])
		else:
			_feedback("Diligence complete — negotiation intel unlocked.")


func _on_advance_pressed() -> void:
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	if bool(result.get("requires_supply_policy", false)):
		_feedback(str(result.get("error", "Set allocation policy first.")))
		_shortage_modal.open_with_shortages(result.get("shortages", []))
		return
	if not bool(result.get("ok", false)):
		_feedback("Turn failed: %s" % str(result.get("error", "unknown")))
	elif Game.state != null and Game.state.game_over != null:
		Game.go_to_run_report()


func _on_shortage_confirmed() -> void:
	_refresh()
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	if bool(result.get("requires_supply_policy", false)):
		_feedback(str(result.get("error", "Set allocation policy first.")))
		_shortage_modal.open_with_shortages(result.get("shortages", []))
	elif not bool(result.get("ok", false)):
		_feedback("Turn failed: %s" % str(result.get("error", "unknown")))
	elif Game.state != null and Game.state.game_over != null:
		Game.go_to_run_report()
	else:
		_feedback("Turn advanced.")


func _on_shortage_cancelled() -> void:
	_feedback("Advance cancelled — resolve supply allocation first.")


func _on_save_pressed() -> void:
	if Game.save_to_file():
		_feedback("Game saved.")
	else:
		_feedback("Save failed.")


func _on_menu_pressed() -> void:
	Game.go_to_main_menu()
