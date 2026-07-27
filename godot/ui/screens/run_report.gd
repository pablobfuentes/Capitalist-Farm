extends Control

@onready var title_label: Label = %TitleLabel
@onready var summary_label: Label = %SummaryLabel
@onready var stats_label: Label = %StatsLabel
@onready var extras_label: Label = %ExtrasLabel
@onready var graph: Control = %Graph


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	var s: RunState = Game.state
	if s == null:
		title_label.text = "No run data"
		return
	var go: Dictionary = s.game_over if typeof(s.game_over) == TYPE_DICTIONARY else {}
	var result: String = str(go.get("result", "end"))
	var reason: String = str(go.get("reason", ""))
	var title := "Target Reached" if result == "win" else ("Insolvency" if reason == "insolvency" else "Run Complete")
	title_label.text = "%s — %s" % [title, MathUtil.fmt_money(Game.net_worth())]
	summary_label.text = "Turn %d / %d · Reputation %d · Cash %s" % [
		mini(s.turn, s.max_turns),
		s.max_turns,
		s.reputation,
		MathUtil.fmt_money(s.cash),
	]
	var debt := 0
	for loan_variant in s.loans:
		if typeof(loan_variant) == TYPE_DICTIONARY:
			debt += int((loan_variant as Dictionary).get("principal", 0))
	stats_label.text = "Businesses %d · Real estate %d · Securities %d · Debt %s" % [
		s.portfolio.businesses.size(),
		s.portfolio.real_estate.size(),
		s.portfolio.securities.size(),
		MathUtil.fmt_money(debt),
	]
	var extras: Dictionary = RunStatsSystem.build_report_extras(s)
	var bits: PackedStringArray = []
	bits.append("Dominant strategy: %s" % str(extras.get("dominant", "")))
	var best_deal: Dictionary = extras.get("bestDeal", {})
	if not best_deal.is_empty():
		bits.append("Best deal: %s (quality %d, turn %d)" % [
			str(best_deal.get("name", "")),
			int(best_deal.get("quality", 0)),
			int(best_deal.get("turn", 0)),
		])
	var worst_shock: Dictionary = extras.get("worstShock", {})
	if not worst_shock.is_empty():
		bits.append("Worst shock: %s (turn %d)" % [str(worst_shock.get("label", "")), int(worst_shock.get("turn", 0))])
	if not s.strategic_edges.is_empty():
		var edge_names: PackedStringArray = []
		for edge_id in s.strategic_edges:
			var edge: Dictionary = ProgressionSystem.edge_by_id(str(edge_id))
			edge_names.append(str(edge.get("name", edge_id)))
		bits.append("Strategic edges: %s" % ", ".join(edge_names))
	extras_label.text = "\n".join(bits)
	graph.queue_redraw()


func _on_new_run_pressed() -> void:
	Game.start_new_run(GameMode.MODE_CAPITAL_FARM)
	Game.go_to_dashboard()


func _on_menu_pressed() -> void:
	Game.go_to_main_menu()


func _on_export_pressed() -> void:
	if Game.state == null:
		return
	var json_text: String = RunStatsSystem.export_json(Game.state)
	var path := "user://run_export_%d.json" % Time.get_unix_time_from_system()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_text)
		summary_label.text = "Exported to %s" % path


func _on_field_guide_pressed() -> void:
	var modal := preload("res://ui/screens/field_guide_modal.tscn").instantiate()
	add_child(modal)
	modal.open_guide()
