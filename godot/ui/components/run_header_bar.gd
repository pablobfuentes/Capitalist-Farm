extends HBoxContainer

@onready var _turn_label: Label = %TurnLabel
@onready var _cash_label: Label = %CashLabel
@onready var _nw_label: Label = %NetWorthLabel
@onready var _debt_label: Label = %DebtLabel
@onready var _ap_label: Label = %ActionPointsLabel
@onready var _reputation_label: Label = %ReputationLabel


func refresh(state: RunState) -> void:
	if state == null:
		return
	var stats: Dictionary = RunView.header_stats(state)
	_turn_label.text = "Turn %d / %d" % [int(stats.get("turn", 0)), int(stats.get("maxTurns", 0))]
	_cash_label.text = "Cash: %s" % MathUtil.fmt_money(int(stats.get("cash", 0)))
	_nw_label.text = "Net worth: %s" % MathUtil.fmt_money(int(stats.get("netWorth", 0)))
	_debt_label.text = "Debt: %s" % MathUtil.fmt_money(int(stats.get("debt", 0)))
	_ap_label.text = "AP: %d / %d" % [int(stats.get("actionPoints", 0)), int(stats.get("maxActionPoints", 0))]
	_reputation_label.text = "Rep: %d" % int(stats.get("reputation", 0))
