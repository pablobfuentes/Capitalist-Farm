extends CanvasLayer

signal closed

const _Rival := preload("res://core/systems/rival_system.gd")
const _Diligence := preload("res://core/systems/diligence_system.gd")
const _V2 := preload("res://core/systems/negotiation_v2_engine.gd")
const _V2Display := preload("res://core/systems/negotiation_v2_display.gd")
const _Transcript := preload("res://core/systems/negotiation_transcript.gd")
const _Archetypes := preload("res://core/content/negotiation_archetypes.gd")
const _ChatBubble := preload("res://ui/components/negotiation_chat_bubble.gd")
const _CertModal := preload("res://ui/screens/acquisition_certificate_modal.gd")

const DESIGN_SIZE := Vector2(1523, 981)
const LAYOUT_PATH := "res://assets/ui/negotiation/layout.json"

const _COLOR_TITLE := Color(0.22, 0.12, 0.06, 1.0)
const _COLOR_ASK := Color(0.72, 0.14, 0.08, 1.0)
const _COLOR_BODY := Color(0.28, 0.18, 0.1, 1.0)
const _COLOR_NOTES := Color(0.24, 0.16, 0.1, 1.0)
const _COLOR_MUTED := Color(0.42, 0.34, 0.24, 1.0)
const _COLOR_GAUGE_UP := Color(0.18, 0.72, 0.38, 1.0)
const _COLOR_GAUGE_DOWN := Color(0.82, 0.22, 0.18, 1.0)
const _COLOR_DISCOUNT_UP := Color(0.12, 0.62, 0.32, 1.0)

const _GAUGE_POP_DURATION := 0.32
const _GAUGE_HOLD_DURATION := 0.45
const _GAUGE_MOVE_DURATION := 1.25
const _DISCOUNT_MIN_DELTA_PCT := 0.45
const _DISCOUNT_POP_DURATION := 0.28
const _DISCOUNT_FLOAT_DURATION := 1.35

const _PANEL_NODES: Dictionary = {
	"HeaderPanel": "header_panel",
	"PortraitSlot": "portrait_area",
	"GaugePanel": "gauge_panel",
	"NameBanner": "name_banner",
	"ChatBackground": "chat_background",
	"InputTray": "input_tray",
	"SendButton": "btn_send",
	"WalkButton": "btn_walk_away",
	"CloseDealButton": "btn_close_deal",
	"NotebookBg": "notebook",
	"NotebookDivider": "divider",
	"CrestBottom": "crest_bottom",
}

const _TEXT_NODES: Dictionary = {
	"HeaderText": "header_text",
	"SellerNameLabel": "name_banner",
	"NotesScroll": "notes_area",
	"DiligenceScroll": "diligence_area",
	"StatusLabel": "status_text",
}

const _DECORATIVE_NODES: Array[String] = [
	"FrameBg",
	"HeaderPanel",
	"HeaderText",
	"PortraitSlot",
	"GaugePanel",
	"NameBanner",
	"GaugePointer",
	"ChatBackground",
	"InputTray",
	"NotebookBg",
	"NotebookDivider",
	"CrestBottom",
]

const _INSET_NODES: Dictionary = {
	"ChatScroll": "chat_scroll",
	"InputField": "input_field",
}

var _opportunity_id: String = ""
var _busy: bool = false
var _layout: Dictionary = {}
var _backdrop_snapshot: ImageTexture
var _chat_follow_bottom := true
var _shown_gauge: float = -1.0
var _shown_discount_pct: float = -1.0
var _gauge_delta_label: Label
var _discount_delta_label: Label
var _feedback_tween: Tween
var _gauge_feedback_from: float = 0.0
var _gauge_feedback_to: float = 0.0
var _gauge_feedback_v2: Dictionary = {}
var _gauge_feedback_label: Label
var _turn_feedback_active := false
var _certificate_modal: CanvasLayer = null
var _close_ready_was := false
var _close_pulse_tween: Tween = null
var _notes_fingerprint := ""
var _prev_notes_text := ""
var _diligence_was_unlocked := false
var _momentum_arrow: Label = null
var _gauge_tick_bucket := -1


func _ready() -> void:
	layer = 128
	visible = false
	_load_layout()
	_style_labels()
	_configure_interaction()
	%CloseButton.pressed.connect(_on_walk)
	%SendButton.pressed.connect(_on_send_pressed)
	%WalkButton.pressed.connect(_on_walk)
	%CloseDealButton.pressed.connect(_on_close_deal)
	%CopyTranscriptButton.pressed.connect(_on_copy_transcript)
	%SaveLogButton.pressed.connect(_on_save_log)
	%MessageInput.text_submitted.connect(_on_text_submitted)
	%MessageInput.placeholder_text = "Type your offer here"
	%MessageInput.caret_blink = true
	var chat_bar: VScrollBar = %ChatScroll.get_v_scroll_bar()
	if chat_bar:
		chat_bar.value_changed.connect(_on_chat_scroll_changed)
	AiClient.health_updated.connect(_on_ai_health_updated)
	EventBus.negotiation_updated.connect(_on_negotiation_updated)
	get_tree().root.size_changed.connect(_on_viewport_resized)
	%CopyTranscriptButton.hide()
	%SaveLogButton.hide()
	%CloseButton.hide()
	FeedbackBus.wire_button(%SendButton)
	FeedbackBus.wire_button(%WalkButton)
	FeedbackBus.wire_button(%CloseDealButton)
	FeedbackBus.wire_scroll(%ChatScroll)
	FeedbackBus.wire_scroll(%NotesScroll)
	FeedbackBus.wire_scroll(%DiligenceScroll)
	_ensure_feedback_labels()
	_certificate_modal = preload("res://ui/screens/acquisition_certificate_modal.tscn").instantiate()
	add_child(_certificate_modal)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_walk()
		get_viewport().set_input_as_handled()


func _load_layout() -> void:
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if file == null:
		push_warning("NegotiationPanel: missing layout at %s" % LAYOUT_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_layout = parsed


func _ui_scale() -> float:
	var root: Control = %Root
	return clampf(root.size.y / DESIGN_SIZE.y, 0.72, 1.15)


func _apply_layouts() -> void:
	for node_name in _PANEL_NODES.keys():
		var node: Node = get_node_or_null("Overlay/Root/%s" % node_name)
		if node is Control:
			_place_panel(node as Control, str(_PANEL_NODES[node_name]))

	for node_name in _TEXT_NODES.keys():
		var node: Node = get_node_or_null("Overlay/Root/%s" % node_name)
		if node is Control:
			_place_text_area(node as Control, str(_TEXT_NODES[node_name]))

	for node_name in _INSET_NODES.keys():
		var node: Node = get_node_or_null("Overlay/Root/%s" % node_name)
		if node is Control:
			_place_text_area(node as Control, str(_INSET_NODES[node_name]))

	_apply_scaled_fonts()
	_layout_header_stack()
	_sync_notebook_scroll_widths()


func _configure_interaction() -> void:
	var root: Control = %Root
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	for node_name in _DECORATIVE_NODES:
		var node: Node = get_node_or_null("Overlay/Root/%s" % node_name)
		if node is Control:
			(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	%ChatScroll.mouse_filter = Control.MOUSE_FILTER_STOP
	%ChatScroll.z_index = 10
	for node_name in ["InputField", "SendButton", "WalkButton", "CloseDealButton"]:
		var node: Node = get_node_or_null("Overlay/Root/%s" % node_name)
		if node is Control:
			var ctrl := node as Control
			ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
			ctrl.z_index = 20
	%MessageInput.mouse_filter = Control.MOUSE_FILTER_STOP


func _sync_notebook_scroll_widths() -> void:
	var pad := int(4 * _ui_scale())
	if %NotesScroll.size.x > 0.0:
		%NotesLabel.custom_minimum_size.x = maxf(%NotesScroll.size.x - pad, 1.0)
	if %DiligenceScroll.size.x > 0.0:
		%DiligenceLabel.custom_minimum_size.x = maxf(%DiligenceScroll.size.x - pad, 1.0)


func _layout_header_stack() -> void:
	var bounds := _design_bounds("header_text")
	if bounds == Vector4.ZERO:
		return
	var inset := _inset_for("header_text")
	var design_w := (bounds.z - inset.z) - (bounds.x + inset.x)
	if design_w <= 0.0:
		return
	var root: Control = %Root
	var px_w := design_w * (root.size.x / DESIGN_SIZE.x)
	%HeaderStack.custom_minimum_size = Vector2(px_w, 0.0)
	%HeaderLabel.custom_minimum_size = Vector2(px_w, 0.0)
	%AskLabel.custom_minimum_size = Vector2(px_w, 0.0)
	%DiscountLabel.custom_minimum_size = Vector2(px_w, 0.0)


func _design_bounds(layout_key: String) -> Vector4:
	var entry: Dictionary = _layout.get(layout_key, {})
	var rect: Array = entry.get("rect", [0, 0, 0, 0])
	if rect.size() < 4:
		return Vector4.ZERO
	return Vector4(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))


func _inset_for(layout_key: String) -> Vector4:
	var entry: Dictionary = _layout.get(layout_key, {})
	var inset: Array = entry.get("inset", [0, 0, 0, 0])
	if inset.size() < 4:
		return Vector4.ZERO
	return Vector4(float(inset[0]), float(inset[1]), float(inset[2]), float(inset[3]))


func _place_panel(node: Control, layout_key: String) -> void:
	var bounds := _design_bounds(layout_key)
	if bounds == Vector4.ZERO:
		return
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.anchor_left = bounds.x / DESIGN_SIZE.x
	node.anchor_top = bounds.y / DESIGN_SIZE.y
	node.anchor_right = bounds.z / DESIGN_SIZE.x
	node.anchor_bottom = bounds.w / DESIGN_SIZE.y
	node.offset_left = 0.0
	node.offset_top = 0.0
	node.offset_right = 0.0
	node.offset_bottom = 0.0
	if node is TextureRect:
		var tex := node as TextureRect
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
	elif node is TextureButton:
		var btn := node as TextureButton
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_SCALE


func _place_text_area(node: Control, layout_key: String) -> void:
	var bounds := _design_bounds(layout_key)
	if bounds == Vector4.ZERO:
		return
	var inset := _inset_for(layout_key)
	var left := bounds.x + inset.x
	var top := bounds.y + inset.y
	var right := bounds.z - inset.z
	var bottom := bounds.w - inset.w
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.anchor_left = left / DESIGN_SIZE.x
	node.anchor_top = top / DESIGN_SIZE.y
	node.anchor_right = right / DESIGN_SIZE.x
	node.anchor_bottom = bottom / DESIGN_SIZE.y
	node.offset_left = 0.0
	node.offset_top = 0.0
	node.offset_right = 0.0
	node.offset_bottom = 0.0


func _apply_scaled_fonts() -> void:
	var s := _ui_scale()
	%HeaderLabel.add_theme_font_size_override("font_size", int(20 * s))
	%AskLabel.add_theme_font_size_override("font_size", int(24 * s))
	%DiscountLabel.add_theme_font_size_override("font_size", int(13 * s))
	%SellerNameLabel.add_theme_font_size_override("font_size", int(18 * s))
	%NotesLabel.add_theme_font_size_override("font_size", int(12 * s))
	%DiligenceLabel.add_theme_font_size_override("font_size", int(12 * s))
	%StatusLabel.add_theme_font_size_override("font_size", int(11 * s))
	%PortraitPlaceholder.add_theme_font_size_override("font_size", int(14 * s))
	%MessageInput.add_theme_font_size_override("font_size", int(15 * s))
	%HeaderStack.add_theme_constant_override("separation", int(3 * s))
	_style_feedback_labels()


func _style_labels() -> void:
	%HeaderLabel.add_theme_color_override("font_color", _COLOR_TITLE)
	%AskLabel.add_theme_color_override("font_color", _COLOR_ASK)
	%DiscountLabel.add_theme_color_override("font_color", _COLOR_BODY)
	%SellerNameLabel.add_theme_color_override("font_color", Color(0.98, 0.95, 0.9, 1.0))
	%NotesLabel.add_theme_color_override("font_color", _COLOR_NOTES)
	%DiligenceLabel.add_theme_color_override("font_color", _COLOR_NOTES)
	%StatusLabel.add_theme_color_override("font_color", _COLOR_MUTED)
	%PortraitPlaceholder.add_theme_color_override("font_color", _COLOR_MUTED)
	%HeaderLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%HeaderLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%AskLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%DiscountLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%HeaderStack.alignment = BoxContainer.ALIGNMENT_CENTER
	%NotesLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%DiligenceLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%StatusLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%StatusLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%SellerNameLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%SellerNameLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_scaled_fonts()


func _on_viewport_resized() -> void:
	if visible:
		_fit_to_viewport()


func open_for_opportunity(opportunity_id: String) -> void:
	_opportunity_id = opportunity_id
	var result: Dictionary = Game.apply_command(GameCommand.start_negotiation(opportunity_id))
	if not bool(result.get("ok", false)):
		%StatusLabel.text = str(result.get("error", "Could not start negotiation"))
		return
	_open_session()


func open_active() -> void:
	if Game.state == null or Game.state.negotiation.is_empty():
		return
	_opportunity_id = str(Game.state.negotiation.get("opportunityId", ""))
	_open_session()


func _open_session() -> void:
	AiClient.begin_negotiation_session(Game.state)
	_chat_follow_bottom = true
	_shown_gauge = -1.0
	_shown_discount_pct = -1.0
	_close_ready_was = false
	_busy = false
	_notes_fingerprint = ""
	_prev_notes_text = ""
	_diligence_was_unlocked = false
	_stop_feedback_tween()
	_update_close_deal_pulse(false)
	_fit_to_viewport()
	await _capture_backdrop()
	show()
	FeedbackBus.set_ambient("negotiation")
	await FeedbackBus.slide_in_panel(%Root)
	_refresh()
	_set_input_enabled(not _busy)
	call_deferred("_focus_message_input")
	_Transcript.save_to_user_file(Game.state.negotiation)


func _focus_message_input() -> void:
	if not visible or _busy or not %MessageInput.editable:
		return
	%MessageInput.grab_focus()
	%MessageInput.caret_column = %MessageInput.text.length()


func _capture_backdrop() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var vp_tex: ViewportTexture = get_viewport().get_texture()
	if vp_tex == null:
		return
	var img: Image = vp_tex.get_image()
	if img == null or img.is_empty():
		return
	_backdrop_snapshot = ImageTexture.create_from_image(img)
	%BackdropImage.texture = _backdrop_snapshot
	var mat: Material = %BackdropImage.material
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("snap_texture", _backdrop_snapshot)


func _fit_to_viewport() -> void:
	var overlay: Control = $Overlay
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE)
	overlay.size = vp_size

	var pad := 48.0
	var avail := Vector2(
		maxi(vp_size.x - pad * 2.0, 640.0),
		maxi(vp_size.y - pad * 2.0, 460.0),
	)
	var aspect := DESIGN_SIZE.x / DESIGN_SIZE.y
	var target_w := avail.x
	var target_h := target_w / aspect
	if target_h > avail.y:
		target_h = avail.y
		target_w = target_h * aspect

	var root: Control = %Root
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.offset_left = -target_w * 0.5
	root.offset_top = -target_h * 0.5
	root.offset_right = target_w * 0.5
	root.offset_bottom = target_h * 0.5
	root.custom_minimum_size = Vector2(target_w, target_h)
	_apply_layouts()


func _refresh(animate_turn: bool = false) -> void:
	var neg: Dictionary = Game.state.negotiation if Game.state else {}
	if neg.is_empty():
		return

	var ctx: Dictionary = neg.get("context", {})
	var v2: Dictionary = neg.get("v2", {})
	var cp: Dictionary = neg.get("counterparty", {})

	var listing_name := str(ctx.get("name", "")).strip_edges()
	if listing_name.is_empty():
		var opp: Dictionary = ctx.get("opp", {}) if typeof(ctx.get("opp")) == TYPE_DICTIONARY else {}
		listing_name = str(opp.get("name", "")).strip_edges()
	if listing_name.is_empty():
		listing_name = "Listing"
	%HeaderLabel.text = listing_name
	call_deferred("_layout_header_stack")
	_update_seller_name(cp)
	_update_context_summary(neg)
	_update_rival_ui(neg)
	_update_notebook(neg)
	await _update_chat(neg)

	var gauge_delta := 0
	var gauge_from := 0.0
	var gauge_to := 0.0
	var discount_delta_pct := 0.0
	var base_discount_pct := -1.0
	if not v2.is_empty():
		gauge_delta = int(v2.get("gaugeDelta", 0))
		gauge_to = clampf(float(v2.get("gauge", 0)), 0.0, 100.0)
		gauge_from = clampf(float(v2.get("previousGauge", gauge_to)), 0.0, 100.0)
		if _shown_gauge >= 0.0:
			gauge_from = _shown_gauge
		var new_discount_pct := float(v2.get("unlockedDiscount", 0.0)) * 100.0
		base_discount_pct = _shown_discount_pct if _shown_discount_pct >= 0.0 else new_discount_pct
		discount_delta_pct = new_discount_pct - base_discount_pct

	var play_gauge := animate_turn and gauge_delta != 0 and not v2.is_empty()
	var play_discount := animate_turn and discount_delta_pct >= _DISCOUNT_MIN_DELTA_PCT and not v2.is_empty()

	if play_discount and _shown_discount_pct >= 0.0:
		_update_price_labels(ctx, v2, base_discount_pct)
	else:
		_update_price_labels(ctx, v2)

	if play_gauge:
		_turn_feedback_active = true
		_set_gauge_pointer(gauge_from, v2)
		await _play_gauge_feedback(gauge_from, gauge_to, gauge_delta, v2)
		_turn_feedback_active = false
	elif not v2.is_empty():
		_update_gauge(neg)
	else:
		%GaugePointer.hide()

	if play_discount:
		_turn_feedback_active = true
		await _play_discount_feedback(discount_delta_pct, ctx, v2)
		_turn_feedback_active = false
		_update_price_labels(ctx, v2)

	if not v2.is_empty():
		_shown_gauge = gauge_to
		_shown_discount_pct = float(v2.get("unlockedDiscount", 0.0)) * 100.0

	var ai_text := _update_ai_status(neg)
	%AiStatusLabel.visible = not ai_text.is_empty()

	var last_decision: String = str(neg.get("lastDecision", ""))
	if _busy:
		%StatusLabel.text = "Waiting for reply…"
	elif bool(neg.get("readyToClose", false)):
		var pending: Dictionary = neg.get("pendingOffer", neg.get("playerLastOffer", {}))
		var close_total: int = int(pending.get("totalPrice", 0))
		if close_total > 0:
			%StatusLabel.text = "Ready to close at %s" % MathUtil.fmt_money(close_total)
		else:
			%StatusLabel.text = "Both gates passed — click Close Deal."
	elif not v2.is_empty():
		var display: Dictionary = _V2.gauge_display(v2)
		%StatusLabel.text = "%s · %s" % [
			last_decision if last_decision != "" else "—",
			display.get("zoneHint", ""),
		]
	elif last_decision != "":
		%StatusLabel.text = "Last response: %s" % last_decision
	else:
		%StatusLabel.text = ""

	var ready := bool(neg.get("readyToClose", false))
	%CloseDealButton.visible = true
	%CloseDealButton.disabled = _busy or not ready
	_apply_close_deal_affordability(neg, ready)
	_update_close_deal_pulse(ready and not _busy)
	_update_momentum_arrow(v2, animate_turn)
	_set_input_enabled(not _busy)
	if _busy:
		_show_typing_indicator()
	else:
		_clear_typing_indicator()


func _update_price_labels(ctx: Dictionary, v2: Dictionary, discount_pct_override: float = -1.0) -> void:
	var ask: int = int(ctx.get("price", 0))
	%AskLabel.text = "Ask %s" % MathUtil.fmt_money(ask)
	if v2.is_empty():
		%DiscountLabel.text = ""
		return
	var discount_pct: float = discount_pct_override if discount_pct_override >= 0.0 else float(v2.get("unlockedDiscount", 0.0)) * 100.0
	var acceptable: int = int(v2.get("acceptableValue", ask))
	if discount_pct_override >= 0.0:
		acceptable = maxi(int(v2.get("hardFloor", 0)), int(round(float(ask) * (1.0 - discount_pct / 100.0))))
	if discount_pct <= 0.05:
		%DiscountLabel.text = "No discount unlocked yet"
	else:
		var savings: int = maxi(0, ask - acceptable)
		%DiscountLabel.text = "Unlocked %.0f%% — %s" % [discount_pct, MathUtil.fmt_money(savings)]


func _update_seller_name(cp: Dictionary) -> void:
	var name := str(cp.get("npcName", "")).strip_edges()
	if name.is_empty():
		var arch: Dictionary = _Archetypes.get_archetype(str(cp.get("archetypeId", "")))
		name = str(arch.get("name", "Seller"))
	%SellerNameLabel.text = name


func _update_gauge(neg: Dictionary) -> void:
	var v2: Dictionary = neg.get("v2", {})
	if v2.is_empty():
		%GaugePointer.hide()
		return
	%GaugePointer.show()
	var gauge: float = clampf(float(_V2.gauge_display(v2).get("gauge", 0)), 0.0, 100.0)
	_set_gauge_pointer(gauge, v2)


func _gauge_track_anchors() -> Vector4:
	var track: Dictionary = _layout.get("gauge_track", {"rect": [60, 780, 450, 820]})
	var track_rect: Array = track["rect"]
	return Vector4(
		float(track_rect[0]) / DESIGN_SIZE.x,
		float(track_rect[1]) / DESIGN_SIZE.y,
		float(track_rect[2]) / DESIGN_SIZE.x,
		float(track_rect[3]) / DESIGN_SIZE.y,
	)


func _set_gauge_pointer(gauge: float, v2: Dictionary = {}) -> void:
	var track := _gauge_track_anchors()
	var pointer: Control = %GaugePointer
	var t: float = clampf(gauge, 0.0, 100.0) / 100.0
	pointer.show()
	pointer.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pointer.anchor_left = lerpf(track.x, track.z, t)
	pointer.anchor_right = pointer.anchor_left
	pointer.anchor_top = track.y
	pointer.anchor_bottom = track.w
	pointer.offset_left = -13.0 * _ui_scale()
	pointer.offset_right = 13.0 * _ui_scale()
	pointer.offset_top = -6.0 * _ui_scale()
	pointer.offset_bottom = 38.0 * _ui_scale()
	if not v2.is_empty():
		var display: Dictionary = _V2.gauge_display(v2)
		pointer.tooltip_text = "%s — %s" % [display.get("zoneLabel", ""), display.get("zoneHint", "")]


func _position_gauge_floater(gauge: float) -> void:
	var track := _gauge_track_anchors()
	var label := _gauge_delta_label
	var t: float = clampf(gauge, 0.0, 100.0) / 100.0
	var anchor_x := lerpf(track.x, track.z, t)
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.anchor_left = anchor_x
	label.anchor_right = anchor_x
	label.anchor_top = track.y
	label.anchor_bottom = track.y
	var half_w := 44.0 * _ui_scale()
	label.offset_left = -half_w
	label.offset_right = half_w
	label.offset_top = -42.0 * _ui_scale()
	label.offset_bottom = -10.0 * _ui_scale()


func _ensure_feedback_labels() -> void:
	var root: Control = %Root
	if _gauge_delta_label == null:
		_gauge_delta_label = Label.new()
		_gauge_delta_label.name = "GaugeDeltaFloater"
		_gauge_delta_label.z_index = 6
		_gauge_delta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gauge_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_gauge_delta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		root.add_child(_gauge_delta_label)
	if _discount_delta_label == null:
		_discount_delta_label = Label.new()
		_discount_delta_label.name = "DiscountDeltaFloater"
		_discount_delta_label.z_index = 6
		_discount_delta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_discount_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(_discount_delta_label)
	_style_feedback_labels()


func _style_feedback_labels() -> void:
	var s := _ui_scale()
	if _gauge_delta_label:
		_gauge_delta_label.add_theme_font_size_override("font_size", int(28 * s))
		_gauge_delta_label.add_theme_constant_override("outline_size", int(3 * s))
		_gauge_delta_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
	if _discount_delta_label:
		_discount_delta_label.add_theme_font_size_override("font_size", int(16 * s))
		_discount_delta_label.add_theme_constant_override("outline_size", int(2 * s))
		_discount_delta_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.8))


func _stop_feedback_tween() -> void:
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = null
	if _gauge_delta_label:
		_gauge_delta_label.visible = false
	if _discount_delta_label:
		_discount_delta_label.visible = false
	%DiscountLabel.scale = Vector2.ONE
	%DiscountLabel.modulate = Color.WHITE
	%GaugePointer.scale = Vector2.ONE


func _play_gauge_feedback(from_gauge: float, to_gauge: float, delta: int, v2: Dictionary) -> void:
	_stop_feedback_tween()
	_style_feedback_labels()
	_gauge_feedback_from = from_gauge
	_gauge_feedback_to = to_gauge
	_gauge_feedback_v2 = v2
	var label := _gauge_delta_label
	_gauge_feedback_label = label
	var sign := "+" if delta > 0 else ""
	label.text = "%s%d" % [sign, delta]
	label.modulate = _COLOR_GAUGE_UP if delta > 0 else _COLOR_GAUGE_DOWN
	label.modulate.a = 0.0
	label.scale = Vector2(0.45, 0.45)
	label.reset_size()
	_set_gauge_pointer(from_gauge, v2)
	_position_gauge_floater(from_gauge)
	label.visible = true
	label.pivot_offset = label.size * 0.5
	_gauge_tick_bucket = -1
	FeedbackBus.play("tick")
	FeedbackBus.flash_color(%GaugePointer, label.modulate, 0.4)
	FeedbackBus.species_react(%PortraitSlot, delta > 0)

	_feedback_tween = create_tween()
	_feedback_tween.tween_property(label, "scale", Vector2(1.15, 1.15), _GAUGE_POP_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_feedback_tween.parallel().tween_property(label, "modulate:a", 1.0, _GAUGE_POP_DURATION * 0.6)
	_feedback_tween.tween_interval(_GAUGE_HOLD_DURATION)
	_feedback_tween.tween_callback(func() -> void:
		_set_gauge_pointer(from_gauge, v2)
		%GaugePointer.scale = Vector2(1.12, 1.12)
	)
	_feedback_tween.tween_method(_gauge_move_tick, 0.0, 1.0, _GAUGE_MOVE_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_feedback_tween.tween_callback(func() -> void:
		_set_gauge_pointer(to_gauge, v2)
		%GaugePointer.scale = Vector2.ONE
	)
	await _feedback_tween.finished
	label.visible = false


func _gauge_move_tick(progress: float) -> void:
	var gauge := lerpf(_gauge_feedback_from, _gauge_feedback_to, progress)
	_set_gauge_pointer(gauge, _gauge_feedback_v2)
	_position_gauge_floater(gauge)
	var pointer: Control = %GaugePointer
	var pulse := 1.0 + sin(progress * PI) * 0.14
	pointer.scale = Vector2(pulse, pulse)
	if _gauge_feedback_label and progress > 0.4:
		_gauge_feedback_label.modulate.a = lerpf(1.0, 0.0, (progress - 0.4) / 0.6)
	var bucket := int(progress * 6.0)
	if bucket != _gauge_tick_bucket and bucket > 0:
		_gauge_tick_bucket = bucket
		FeedbackBus.play("tick")


func _play_discount_feedback(delta_pct: float, ctx: Dictionary, v2: Dictionary) -> void:
	var ask: int = int(ctx.get("price", 0))
	var acceptable: int = int(v2.get("acceptableValue", ask))
	var savings_delta: int = maxi(0, int(round(float(ask) * delta_pct / 100.0)))
	var label := _discount_delta_label
	_style_feedback_labels()
	label.text = "+%.0f%% unlocked" % delta_pct if savings_delta <= 0 else "+%.0f%% · %s" % [delta_pct, MathUtil.fmt_money(savings_delta)]
	label.modulate = _COLOR_DISCOUNT_UP
	label.modulate.a = 0.0
	label.scale = Vector2(0.55, 0.55)
	label.visible = true
	label.reset_size()

	var dl := %DiscountLabel
	dl.pivot_offset = dl.size * 0.5

	await get_tree().process_frame
	var anchor: Vector2 = dl.get_global_rect().get_center()
	label.global_position = anchor + Vector2(-label.size.x * 0.5, -28.0 * _ui_scale())

	_feedback_tween = create_tween()
	_feedback_tween.set_parallel(true)
	_feedback_tween.tween_property(label, "scale", Vector2(1.1, 1.1), _DISCOUNT_POP_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_feedback_tween.tween_property(label, "modulate:a", 1.0, _DISCOUNT_POP_DURATION * 0.7)
	_feedback_tween.tween_property(label, "global_position:y", label.global_position.y - 28.0 * _ui_scale(), _DISCOUNT_FLOAT_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_feedback_tween.tween_property(label, "modulate:a", 0.0, 0.45).set_delay(_DISCOUNT_FLOAT_DURATION * 0.55)
	_feedback_tween.parallel().tween_property(dl, "scale", Vector2(1.08, 1.08), 0.22).set_delay(0.12)
	_feedback_tween.parallel().tween_property(dl, "modulate", Color(1.15, 1.1, 0.95), 0.22).set_delay(0.12)
	await _feedback_tween.finished
	label.visible = false
	dl.scale = Vector2.ONE
	dl.modulate = Color.WHITE
	_update_price_labels(ctx, v2)


func _update_chat(neg: Dictionary) -> void:
	var follow_bottom := _chat_follow_bottom
	var box: VBoxContainer = %ChatMessages
	for child in box.get_children():
		child.queue_free()

	await get_tree().process_frame
	var scroll_w := maxf(%ChatScroll.size.x, 220.0)
	var bar: VScrollBar = %ChatScroll.get_v_scroll_bar()
	if bar != null:
		scroll_w = maxf(scroll_w - maxf(bar.size.x, bar.get_combined_minimum_size().x) - 4.0, 220.0)
	box.custom_minimum_size.x = scroll_w
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_theme_constant_override("separation", int(6 * _ui_scale()))
	var bubble_scale := _ui_scale()
	var last_bubble: Control = null
	for msg_variant in neg.get("messages", []):
		if typeof(msg_variant) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = msg_variant
		var text := str(msg.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		var role := str(msg.get("role", msg.get("speaker", ""))).to_lower()
		var kind: int = _ChatBubble.kind_from_role(role)
		var bubble: Control = _ChatBubble.create(text, kind, scroll_w, bubble_scale)
		box.add_child(bubble)
		last_bubble = bubble
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(1.0, 18.0 * bubble_scale)
	bottom_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bottom_pad)

	await get_tree().process_frame
	for child in box.get_children():
		if child is Control:
			_ChatBubble.sync_min_height(child as Control)
	if last_bubble != null:
		FeedbackBus.pop_in(last_bubble)
	if _busy:
		_show_typing_indicator()

	if follow_bottom:
		call_deferred("_scroll_chat_to_bottom")


func _scroll_chat_to_bottom() -> void:
	var scroll: ScrollContainer = %ChatScroll
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	if bar:
		scroll.scroll_vertical = int(bar.max_value)
	_chat_follow_bottom = true


func _chat_is_at_bottom(threshold: float = 16.0) -> bool:
	var bar: VScrollBar = %ChatScroll.get_v_scroll_bar()
	if bar == null:
		return true
	return bar.max_value <= 0.0 or bar.value >= bar.max_value - threshold


func _on_chat_scroll_changed() -> void:
	_chat_follow_bottom = _chat_is_at_bottom()


func _format_notes(neg: Dictionary) -> String:
	var cp: Dictionary = neg.get("counterparty", {})
	var v2: Dictionary = neg.get("v2", {})
	var species_id := str(v2.get("speciesId", cp.get("speciesId", "")))
	var species_label := species_id.capitalize() if not species_id.is_empty() else "—"

	var likes := "—"
	var avoid := "—"
	var offer := "—"
	match species_id:
		"pig":
			likes = "Deal structure, earn-outs, upside participation"
			avoid = "Pure price haggling without structure"
		"donkey":
			likes = "Evidence, warranties, verified numbers"
			avoid = "Pressure without proof"
		"hen":
			likes = "Cash timing, certainty, fast close"
			avoid = "Vague financing without dates"
		"horse":
			likes = "Employee retention, continuity, legacy"
			avoid = "Dismissive treatment of staff"
		"goat":
			likes = "Complete packages with concrete terms"
			avoid = "Price-only offers"
		"sheep":
			likes = "Reputation, fair dealing, references"
			avoid = "Transactional lowballing"
		_:
			likes = "Serious terms aligned to their situation"

	if not v2.is_empty():
		offer = _V2Display.format_progress_panel(
			v2,
			cp,
			bool(neg.get("readyToClose", false)),
			_get_v2_preview(neg),
		).get("coachLine", "Lead with species-aligned terms, then price.")

	var notes := "Species: %s\nLikes: %s\nAvoid: %s\nOffer: %s" % [species_label, likes, avoid, offer]
	if Game.state != null:
		var snapshot: String = CommunityNegotiationBridge.format_modifier_snapshot(Game.state, v2, cp)
		if not snapshot.is_empty():
			notes = "%s\n\n%s" % [notes, snapshot]
	return notes


func _format_diligence(neg: Dictionary) -> String:
	if not bool(neg.get("intelUnlocked", false)):
		return "Investigate this listing (1 AP) before negotiating to reveal seller leverage, floor, and unlock phrases."

	var cp: Dictionary = neg.get("counterparty", {})
	var asking: int = int(neg.get("context", {}).get("price", 0))
	var ctx: Dictionary = neg.get("context", {})
	var opp: Dictionary = ctx.get("opp", {}) if typeof(ctx.get("opp")) == TYPE_DICTIONARY else {}
	var rng := SeededRng.new(Game.state.run_seed + asking + Game.state.turn) if Game.state else SeededRng.new(asking)

	var lines: PackedStringArray = []
	var seller_name := str(cp.get("npcName", "")).strip_edges()
	if seller_name.is_empty():
		seller_name = _update_seller_name_text(cp)
	lines.append(seller_name)

	var v2: Dictionary = neg.get("v2", {})
	var situation := str(v2.get("situationLabel", "")).strip_edges()
	if not situation.is_empty():
		lines.append(situation)

	var preview_raw: Variant = opp.get("v2Preview")
	if preview_raw is Dictionary and not (preview_raw as Dictionary).is_empty():
		var keywords: Array = (preview_raw as Dictionary).get("keywords", [])
		if not keywords.is_empty():
			lines.append("Phrases to unlock leverage:")
			for kw in keywords:
				lines.append("• \"%s\"" % str(kw))

	var diligence_text := _Diligence.seller_diligence_block_text(asking, cp, rng)
	for line in diligence_text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty() or trimmed == "SELLER DILIGENCE":
			continue
		lines.append(trimmed.replace("Hidden leverage: ", "Hidden leverage — "))

	return "\n".join(lines)


func _update_seller_name_text(cp: Dictionary) -> String:
	var name := str(cp.get("npcName", "")).strip_edges()
	if name.is_empty():
		var arch: Dictionary = _Archetypes.get_archetype(str(cp.get("archetypeId", "")))
		name = str(arch.get("name", "Seller"))
	return name


func _update_notebook(neg: Dictionary) -> void:
	var notes_text := _format_notes(neg)
	var diligence_text := _format_diligence(neg)
	if Game.state != null and CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_NOTEBOOK_INTEL, Game.state):
		diligence_text = CommunityNotebookService.format_diligence_with_notebook(Game.state, diligence_text, neg)
	var notes_fp := "%s||%s" % [notes_text, diligence_text]
	var notes_grew := not _prev_notes_text.is_empty() and notes_text != _prev_notes_text and notes_text.length() >= _prev_notes_text.length()
	%NotesLabel.text = notes_text
	%DiligenceLabel.text = diligence_text
	var unlocked := bool(neg.get("intelUnlocked", false))
	%DiligenceLabel.modulate = Color.WHITE if unlocked else Color(0.72, 0.68, 0.62, 1.0)
	if unlocked and not _diligence_was_unlocked:
		FeedbackBus.stamp_punch(%DiligenceLabel)
		FeedbackBus.highlight_text_control(%DiligenceLabel, 1.1)
	elif notes_grew and notes_fp != _notes_fingerprint:
		FeedbackBus.paper_whoosh()
		FeedbackBus.play("success")
		FeedbackBus.highlight_text_control(%NotesLabel, 0.9)
	_diligence_was_unlocked = unlocked
	_notes_fingerprint = notes_fp
	_prev_notes_text = notes_text
	call_deferred("_sync_notebook_scroll_widths")


func _update_rival_ui(neg: Dictionary) -> void:
	var is_contest := str(neg.get("kind", "")) == "rival_contest"
	if not is_contest:
		%RivalBarLabel.hide()
		%CompareLabel.hide()
		return
	var rival_raw: Variant = neg.get("rival")
	var rival: Dictionary = rival_raw if rival_raw is Dictionary else {}
	var rname := _Rival.display_name(rival)
	var rival_offer: Dictionary = _Rival._offer_dict(neg, "rivalLastOffer")
	var rbid: int = int(rival_offer.get("totalPrice", 0))
	var player_offer: Dictionary = _Rival._offer_dict(neg, "playerLastOffer")
	var pbid: int = int(player_offer.get("totalPrice", 0))
	var lead := str(neg.get("leadingBidder", ""))
	var lead_text := ""
	if lead == "player":
		lead_text = " · You lead"
	elif lead == "rival":
		lead_text = " · %s leads" % rname
	var rival_line := "%s conceded" % rname if bool(neg.get("rivalConceded", false)) else "%s bid: %s" % [rname, MathUtil.fmt_money(rbid)]
	%RivalBarLabel.text = "%s%s · Your bid: %s%s" % [
		rival_line,
		(" · Round %d/%d" % [int(neg.get("round", 0)), int(neg.get("maxRounds", 8))]),
		MathUtil.fmt_money(pbid) if pbid > 0 else "—",
		lead_text,
	]
	%CompareLabel.text = _Rival.package_comparison_text(neg)
	%RivalBarLabel.show()
	%CompareLabel.show()


func _update_context_summary(neg: Dictionary) -> void:
	var v2: Dictionary = neg.get("v2", {})
	var summary: Dictionary = _V2Display.format_context_summary(
		v2,
		neg.get("counterparty", {}),
		str(neg.get("economicStatusHint", "")),
	)
	%ContextSummaryLabel.hide()
	%ContextSummaryLabel.text = str(summary.get("summaryLine", ""))

	var coach := ""
	if not v2.is_empty():
		var panel: Dictionary = _V2Display.format_progress_panel(
			v2,
			neg.get("counterparty", {}),
			bool(neg.get("readyToClose", false)),
			_get_v2_preview(neg),
		)
		coach = str(panel.get("coachLine", ""))
	%CoachTipLabel.hide()
	%CoachTipLabel.text = coach


func _get_v2_preview(neg: Dictionary) -> Dictionary:
	var ctx: Dictionary = neg.get("context", {})
	var opp: Variant = ctx.get("opp")
	if opp is Dictionary:
		var preview: Variant = (opp as Dictionary).get("v2Preview")
		if preview is Dictionary:
			return preview as Dictionary
	return {}


func _update_ai_status(neg: Dictionary) -> String:
	var st: Dictionary = AiClient.status_label(neg)
	var status_text: String = str(st.get("text", ""))
	if str(neg.get("aiStatus", "")) == "offline":
		status_text += "\nRun: npm start · Ollama · http://127.0.0.1:8787/health"
	%AiStatusLabel.text = status_text
	%AiStatusLabel.visible = not status_text.is_empty()
	return status_text


func _on_ai_health_updated(_available: bool, _model: String) -> void:
	if _opportunity_id.is_empty() or Game.state == null or Game.state.negotiation.is_empty():
		return
	_refresh()


func _on_negotiation_updated(_state: RunState = null) -> void:
	if _opportunity_id.is_empty() or _turn_feedback_active:
		return
	_refresh()


func _set_input_enabled(enabled: bool) -> void:
	%SendButton.disabled = not enabled
	%MessageInput.editable = enabled
	%WalkButton.disabled = not enabled
	var ready := Game.state != null and bool(Game.state.negotiation.get("readyToClose", false))
	%CloseDealButton.disabled = not enabled or not ready
	_update_close_deal_pulse(ready and enabled)


func _update_close_deal_pulse(ready: bool) -> void:
	var btn: Control = %CloseDealButton
	if _close_pulse_tween != null and _close_pulse_tween.is_valid():
		_close_pulse_tween.kill()
	_close_pulse_tween = null
	if btn == null:
		return
	if btn.size != Vector2.ZERO:
		btn.pivot_offset = btn.size * 0.5
	if not ready:
		btn.scale = Vector2.ONE
		_close_ready_was = false
		return
	if not _close_ready_was:
		FeedbackBus.chime()
		_close_ready_was = true
	_close_pulse_tween = create_tween().set_loops()
	_close_pulse_tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.55)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_close_pulse_tween.tween_property(btn, "scale", Vector2.ONE, 0.55)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _show_typing_indicator() -> void:
	_clear_typing_indicator()
	FeedbackBus.duck_ambient(true)
	var box: VBoxContainer = %ChatMessages
	if box == null:
		return
	var indicator := FeedbackBus.make_typing_indicator()
	# Insert before bottom pad when present.
	var insert_at := box.get_child_count()
	if insert_at > 0:
		var last: Node = box.get_child(insert_at - 1)
		if last is Control and (last as Control).custom_minimum_size.y > 0.0 and last.get_child_count() == 0:
			insert_at = maxi(0, insert_at - 1)
	box.add_child(indicator)
	box.move_child(indicator, insert_at)
	FeedbackBus.pop_in(indicator)
	call_deferred("_scroll_chat_to_bottom")


func _clear_typing_indicator() -> void:
	FeedbackBus.duck_ambient(false)
	var box: VBoxContainer = %ChatMessages
	if box == null:
		return
	var existing := box.get_node_or_null("TypingIndicator")
	if existing != null:
		existing.queue_free()


func _on_close_deal() -> void:
	if _busy:
		return
	var nw_before := FinanceSystem.net_worth(Game.state) if Game.state != null else 0
	var result: Dictionary = Game.apply_command(GameCommand.close_negotiation_deal())
	if not bool(result.get("ok", false)):
		FeedbackBus.deny(%CloseDealButton)
		var err := str(result.get("error", "Could not close deal"))
		%StatusLabel.text = err
		FeedbackBus.toast_error(err)
		_refresh()
		return
	_update_close_deal_pulse(false)
	if bool(result.get("closed", false)) and _result_is_acquisition(result):
		%StatusLabel.text = "Deal closed!"
		FeedbackBus.toast_success("Deal closed")
		await _present_acquisition_certificate(result, nw_before)
		FeedbackBus.set_ambient("map")
		hide()
		closed.emit()
	else:
		_refresh()


func _on_send_pressed() -> void:
	_send_message(%MessageInput.text)


func _on_text_submitted(text: String) -> void:
	_send_message(text)


func _send_message(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or _busy:
		return

	_busy = true
	_set_input_enabled(false)
	%StatusLabel.text = "Waiting for reply…"
	%MessageInput.text = ""
	FeedbackBus.paper_whoosh()
	_show_typing_indicator()

	Game.send_negotiation_message_async(trimmed, _on_negotiation_result)


func _on_negotiation_result(result: Dictionary) -> void:
	_busy = false
	_clear_typing_indicator()

	if not bool(result.get("ok", false)):
		FeedbackBus.deny(%SendButton)
		var err := str(result.get("error", "Send failed"))
		%StatusLabel.text = err
		FeedbackBus.toast_error(err)
		_refresh(false)
		return

	if bool(result.get("ready_to_close", false)):
		_refresh(true)
		call_deferred("_focus_message_input")
		return

	if bool(result.get("closed", false)):
		_refresh(true)
		if _result_is_acquisition(result):
			%StatusLabel.text = "Deal closed!"
			FeedbackBus.toast_success("Deal closed")
			# NW-before is unknown on async path; cascade uses current as both (no-op) unless stored.
			await _present_acquisition_certificate(result, -1)
			FeedbackBus.set_ambient("map")
			hide()
			closed.emit()
			return
		var decision := str(result.get("decision", ""))
		if decision == "rival_win":
			%StatusLabel.text = str(result.get("reply", "Rowe wins the contest."))
			FeedbackBus.deny(%Root)
			FeedbackBus.toast_error("Outbid")
			FeedbackBus.vignette_pulse(Color(0.85, 0.12, 0.1, 0.45), 0.7)
			await get_tree().create_timer(2.0).timeout
			await FeedbackBus.slide_out_panel(%Root)
			FeedbackBus.set_ambient("map")
			hide()
			closed.emit()
			return
		%StatusLabel.text = str(result.get("reply", "Negotiation ended."))
		_refresh(false)
		return

	_refresh(true)
	call_deferred("_focus_message_input")


func _result_is_acquisition(result: Dictionary) -> bool:
	return _CertModal.is_acquisition_result(result)


func _present_acquisition_certificate(result: Dictionary, nw_before: int = -1) -> void:
	if _certificate_modal == null:
		_certificate_modal = preload("res://ui/screens/acquisition_certificate_modal.tscn").instantiate()
		add_child(_certificate_modal)
	var before_nw := nw_before
	var after_nw := FinanceSystem.net_worth(Game.state) if Game.state != null else 0
	if before_nw < 0:
		# Best-effort: estimate prior NW from after + cash paid - asset mark is unavailable here.
		before_nw = after_nw
	var deal: Dictionary = _CertModal.deal_from_command_result(result, before_nw, after_nw)
	var banner: Control = get_tree().root.find_child("RunStats", true, false) as Control
	await _certificate_modal.present(deal, banner)


func _apply_close_deal_affordability(neg: Dictionary, ready: bool) -> void:
	var btn: Control = %CloseDealButton
	if not ready:
		btn.modulate = Color(1, 1, 1, 0.55)
		return
	var pending: Dictionary = neg.get("pendingOffer", neg.get("playerLastOffer", {}))
	var need: int = int(pending.get("cashAtClosing", pending.get("totalPrice", 0)))
	var cash := Game.state.cash if Game.state != null else 0
	var tint := FeedbackBus.affordability_color(cash, need)
	btn.modulate = Color(tint.r, tint.g, tint.b, 1.0)


func _update_momentum_arrow(v2: Dictionary, animate_turn: bool) -> void:
	if _momentum_arrow == null:
		_momentum_arrow = Label.new()
		_momentum_arrow.name = "MomentumArrow"
		_momentum_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_momentum_arrow.z_index = 7
		_momentum_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%Root.add_child(_momentum_arrow)
	if v2.is_empty():
		_momentum_arrow.visible = false
		return
	var delta := int(v2.get("gaugeDelta", 0))
	if not animate_turn or delta == 0:
		_momentum_arrow.visible = false
		return
	_momentum_arrow.visible = true
	_momentum_arrow.text = "▲" if delta > 0 else "▼"
	_momentum_arrow.modulate = _COLOR_GAUGE_UP if delta > 0 else _COLOR_GAUGE_DOWN
	_momentum_arrow.add_theme_font_size_override("font_size", int(22 * _ui_scale()))
	var pointer: Control = %GaugePointer
	_momentum_arrow.global_position = pointer.get_global_rect().position + Vector2(18 * _ui_scale(), -8 * _ui_scale())
	FeedbackBus.pulse(_momentum_arrow, 1.2, 0.3)
	get_tree().create_timer(1.1).timeout.connect(func() -> void:
		if is_instance_valid(_momentum_arrow):
			_momentum_arrow.visible = false
	)


func _on_walk() -> void:
	if _busy:
		return
	_Transcript.save_to_user_file(Game.state.negotiation if Game.state else {})
	Game.apply_command(GameCommand.end_negotiation(true))
	_update_close_deal_pulse(false)
	_clear_typing_indicator()
	FeedbackBus.walk_away_sting()
	await FeedbackBus.slide_out_panel(%Root)
	FeedbackBus.set_ambient("map")
	hide()
	closed.emit()


func _on_copy_transcript() -> void:
	var neg: Dictionary = Game.state.negotiation if Game.state else {}
	var text := _Transcript.build_transcript(neg)
	if text.is_empty():
		%StatusLabel.text = "Nothing to copy yet."
		return
	DisplayServer.clipboard_set(text)
	%StatusLabel.text = "Debug log copied."


func _on_save_log() -> void:
	var neg: Dictionary = Game.state.negotiation if Game.state else {}
	var path := _Transcript.save_to_user_file(neg)
	if path.is_empty():
		%StatusLabel.text = "Could not save log file."
		return
	DisplayServer.clipboard_set(path)
	%StatusLabel.text = "Log saved: %s" % path
