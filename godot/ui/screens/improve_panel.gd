extends Window

signal closed
signal level_up(opportunity_id: String)
signal negotiate(opportunity_id: String)

var _business_id: String = ""
var _pending_level_up_opp_id: String = ""


func open_for_business(business_id: String) -> void:
	_business_id = business_id
	_refresh()
	popup_centered_ratio(0.55)


func _ready() -> void:
	visible = false
	title = "Improve Business"
	close_requested.connect(_on_close)
	%CloseButton.pressed.connect(_on_close)
	%LevelUpInvestButton.pressed.connect(_on_level_up_invest_pressed)
	%LevelUpNegotiateButton.pressed.connect(_on_level_up_negotiate_pressed)


func _on_close() -> void:
	%GhostPreviewLabel.text = ""
	hide()
	closed.emit()


func _refresh() -> void:
	var biz := UpgradeSystem.find_business(Game.state, _business_id)
	if biz == null:
		return
	%BusinessName.text = biz.name
	var tmpl := Content.get_template(biz.template_id)
	var current_value: int = PortfolioSystem.business_market_value(Game.state, biz)
	var growth := RunView.business_value_growth_line(biz, current_value)
	var val_part := "Val %s" % MathUtil.fmt_money(current_value)
	if not growth.is_empty():
		val_part += " (%s)" % growth
	%MetaLabel.text = "%s · %s · AP %s · Cap ×%.2f · Dem ×%.2f · Opex ×%.2f" % [
		val_part,
		tmpl.layer_label if tmpl else biz.layer,
		UpgradeSystem.autopilot_display(biz),
		float(biz.upgrade_stats.get("capacityMult", 1.0)),
		float(biz.upgrade_stats.get("demandMult", 1.0)),
		float(biz.upgrade_stats.get("opexMult", 1.0)),
	]
	%LevelProgressLabel.text = LevelUpSystem.progress_label(biz)
	_refresh_level_up_section(biz)
	%GhostPreviewLabel.text = ""

	for child in %TracksList.get_children():
		child.queue_free()

	for track_id: String in ["hire", "marketing", "automation", "care", "manager"]:
		_add_track_row(biz, track_id)


func _add_track_row(biz: BusinessInstance, track_id: String) -> void:
	var track: Dictionary = UpgradeSystem.TRACKS.get(track_id, {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var tier: int = 1 if track_id == "manager" and bool(biz.upgrades.get("manager", false)) else int(biz.upgrades.get(track_id, 0))
	var max_tier: int = int(track.get("max_tier", 1))
	var pips := UpgradeSystem.render_tier_pips(tier if track_id != "manager" else (1 if bool(biz.upgrades.get("manager", false)) else 0), max_tier)

	var preview: Dictionary = UpgradeSystem.compute_upgrade_preview(Game.state, biz.id, track_id)
	var preview_line := ""
	var effect_line := UpgradeSystem.format_track_effect_line(preview, track_id)
	if not effect_line.is_empty():
		preview_line = " · %s" % effect_line
	elif bool(preview.get("canApply", false)):
		var delta: int = int(preview.get("profitDelta", 0))
		preview_line = " · +%s/qtr" % MathUtil.fmt_money(delta)
	elif preview.has("reason"):
		preview_line = " · %s" % str(preview.get("reason", ""))

	info.text = "%s  %s%s" % [str(track.get("name", track_id)), pips, preview_line]
	row.add_child(info)

	var apply_btn := Button.new()
	var cost: int = int(preview.get("cost", 0))
	apply_btn.text = "1AP + %s" % MathUtil.fmt_money(cost)
	apply_btn.disabled = (
		not bool(preview.get("canApply", false))
		or Game.state.cash < cost
		or Game.state.action_points < 1
	)
	apply_btn.pressed.connect(_on_apply_pressed.bind(track_id))
	if track_id in ["hire", "marketing"] and bool(preview.get("canApply", false)):
		apply_btn.mouse_entered.connect(_on_track_hover.bind(preview, track_id))
		apply_btn.mouse_exited.connect(_on_track_hover_clear)
	row.add_child(apply_btn)

	%TracksList.add_child(row)


func _refresh_level_up_section(biz: BusinessInstance) -> void:
	var view: Dictionary = LevelUpSystem.improve_panel_view(Game.state, biz)
	if not bool(view.get("visible", false)) or not bool(view.get("ready", false)):
		%LevelUpSection.hide()
		_pending_level_up_opp_id = ""
		return
	%LevelUpSection.show()
	%LevelUpTitle.text = "Level %d ready — %s" % [
		int(view.get("targetLevel", biz.level + 1)),
		str(view.get("title", "Level up")),
	]
	%LevelUpBlurb.text = str(view.get("blurb", ""))
	%LevelUpReward.text = str(view.get("rewardLine", ""))
	%LevelUpActions.show()
	_pending_level_up_opp_id = str(view.get("opportunityId", ""))
	var price: int = int(view.get("price", 0))
	if bool(view.get("requiresNegotiation", false)):
		%LevelUpInvestButton.hide()
		%LevelUpNegotiateButton.show()
		%LevelUpNegotiateButton.text = "Negotiate · 1AP"
		%LevelUpNegotiateButton.disabled = not bool(view.get("canNegotiate", false))
	else:
		%LevelUpNegotiateButton.hide()
		%LevelUpInvestButton.show()
		%LevelUpInvestButton.text = "1AP + %s" % MathUtil.fmt_money(price)
		%LevelUpInvestButton.disabled = not bool(view.get("canInvest", false))


func _on_level_up_invest_pressed() -> void:
	if _pending_level_up_opp_id.is_empty():
		return
	var result: Dictionary = Game.apply_command(GameCommand.do_level_up(_pending_level_up_opp_id))
	if bool(result.get("ok", false)):
		_refresh()
		level_up.emit(_pending_level_up_opp_id)
	else:
		%LevelUpReward.text = "Failed: %s" % str(result.get("error", "unknown"))


func _on_level_up_negotiate_pressed() -> void:
	if _pending_level_up_opp_id.is_empty():
		return
	negotiate.emit(_pending_level_up_opp_id)


func _on_track_hover(preview: Dictionary, track_id: String) -> void:
	var line := UpgradeSystem.format_track_effect_line(preview, track_id)
	if line.is_empty():
		%GhostPreviewLabel.text = ""
	else:
		%GhostPreviewLabel.text = "Preview: %s" % line


func _on_track_hover_clear() -> void:
	%GhostPreviewLabel.text = ""


func _on_apply_pressed(track_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.apply_upgrade(_business_id, track_id))
	if bool(result.get("ok", false)):
		_refresh()
	else:
		%MetaLabel.text = "Failed: %s" % str(result.get("error", "unknown"))
