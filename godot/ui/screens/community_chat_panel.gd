extends CanvasLayer

signal closed

const _ChatBubble := preload("res://ui/components/negotiation_chat_bubble.gd")

const DESIGN_SIZE := Vector2(1523, 981)
const LAYOUT_PATH := "res://assets/ui/negotiation/layout.json"

const _COLOR_TITLE := Color(0.22, 0.12, 0.06, 1.0)
const _COLOR_BODY := Color(0.28, 0.18, 0.1, 1.0)
const _COLOR_NOTES := Color(0.24, 0.16, 0.1, 1.0)
const _COLOR_MUTED := Color(0.42, 0.34, 0.24, 1.0)

const _PANEL_NODES: Dictionary = {
	"HeaderPanel": "header_panel",
	"PortraitSlot": "portrait_area",
	"NameBanner": "name_banner",
	"ChatBackground": "chat_background",
	"InputTray": "input_tray",
	"SendButton": "btn_send",
	"WalkButton": "btn_walk_away",
	"NotebookBg": "notebook",
	"NotebookDivider": "divider",
	"CrestBottom": "crest_bottom",
}

const _TEXT_NODES: Dictionary = {
	"HeaderText": "header_text",
	"NpcNameLabel": "name_banner",
	"NotesScroll": "notes_area",
	"DiligenceScroll": "diligence_area",
	"StatusLabel": "status_text",
}

const _INSET_NODES: Dictionary = {
	"ChatScroll": "chat_scroll",
	"InputField": "input_field",
}

const _DECORATIVE_NODES: Array[String] = [
	"FrameBg",
	"HeaderPanel",
	"HeaderText",
	"PortraitSlot",
	"NameBanner",
	"ChatBackground",
	"InputTray",
	"NotebookBg",
	"NotebookDivider",
	"CrestBottom",
]

var _npc_id: String = ""
var _community_business_id: String = ""
var _busy: bool = false
var _layout: Dictionary = {}
var _backdrop_snapshot: ImageTexture
var _chat_follow_bottom := true
var _updating_chat := false
var _status_override: String = ""
var _refresh_token: int = 0
var _rendered_messages_fingerprint: String = ""
var _last_chat_column_width: float = -1.0


func _ready() -> void:
	layer = 128
	visible = false
	_load_layout()
	_style_labels()
	_configure_interaction()
	%SendButton.pressed.connect(_on_send_pressed)
	%WalkButton.pressed.connect(_on_walk)
	%MessageInput.text_submitted.connect(_on_text_submitted)
	%MessageInput.placeholder_text = "Say something…"
	%MessageInput.focus_mode = Control.FOCUS_ALL
	%MessageInput.caret_blink = true
	var chat_bar: VScrollBar = %ChatScroll.get_v_scroll_bar()
	if chat_bar:
		chat_bar.value_changed.connect(_on_chat_scroll_changed)
	AiClient.health_updated.connect(_on_ai_health_updated)
	get_tree().root.size_changed.connect(_on_viewport_resized)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_walk()
		get_viewport().set_input_as_handled()


func open_for_community_business(community_business_id: String, parcel_id: String, district_id: String) -> void:
	if Game.state == null:
		return
	var business: Dictionary = CommunityGenerator.get_business(Game.state, community_business_id)
	if business.is_empty():
		_status_override = "Unknown business"
		return
	var npc_id := str(business.get("ownerNpcId", ""))
	var result: Dictionary = CommunityChatRuntime.start_session(
		Game.state,
		npc_id,
		community_business_id,
		parcel_id,
		district_id,
	)
	if not bool(result.get("ok", false)):
		_status_override = str(result.get("error", "Could not start chat"))
		return
	_npc_id = npc_id
	_community_business_id = community_business_id
	_status_override = ""
	_chat_follow_bottom = true
	_rendered_messages_fingerprint = ""
	_last_chat_column_width = -1.0
	_fit_to_viewport()
	await _capture_backdrop()
	show()
	await _ensure_ai_ready()
	await _refresh()
	call_deferred("_focus_message_input")


func _ensure_ai_ready() -> void:
	var done := false
	AiClient.check_health(func(_available: bool, _model: String) -> void:
		done = true
	)
	while not done:
		await get_tree().process_frame


func _on_walk() -> void:
	if _busy:
		return
	if not _npc_id.is_empty() and Game.state != null:
		CommunityChatRuntime.end_session(Game.state, _npc_id)
	_npc_id = ""
	_community_business_id = ""
	_status_override = ""
	_rendered_messages_fingerprint = ""
	_last_chat_column_width = -1.0
	_updating_chat = false
	hide()
	closed.emit()


func _on_send_pressed() -> void:
	_send_message(%MessageInput.text)


func _on_text_submitted(text: String) -> void:
	_send_message(text)


func _send_message(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or _busy or _npc_id.is_empty() or Game.state == null:
		return
	_busy = true
	_status_override = ""
	_chat_follow_bottom = true
	_set_input_enabled(false)
	%StatusLabel.text = "Waiting for reply…"
	%MessageInput.text = ""
	CommunityChatRuntime.send_player_message(Game.state, _npc_id, trimmed, _on_chat_result)


func _on_chat_result(result: Dictionary) -> void:
	_busy = false
	if bool(result.get("fallback", false)):
		_status_override = "%s (fallback reply)" % str(result.get("error", "AI issue"))
	elif not bool(result.get("ok", false)):
		_status_override = str(result.get("error", "Send failed"))
	else:
		_status_override = ""
	await _refresh()
	if bool(result.get("dismissed", false)):
		await get_tree().create_timer(1.4).timeout
		_on_walk()
		return
	call_deferred("_focus_message_input")


func _refresh(rebuild_chat: bool = true) -> void:
	if Game.state == null or _npc_id.is_empty():
		return
	_refresh_token += 1
	var token := _refresh_token
	var session: Dictionary = CommunityChatRuntime.get_active_session(Game.state, _npc_id)
	var business: Dictionary = CommunityGenerator.get_business(Game.state, _community_business_id)
	var npc: Dictionary = CommunityGenerator.get_npc(Game.state, _npc_id)
	%HeaderLabel.text = str(business.get("displayName", "Neighbor visit"))
	_update_chat_subheader()
	call_deferred("_layout_header_stack")
	%NpcNameLabel.text = str(npc.get("displayName", "Neighbor"))
	var remaining := _messages_remaining(session)
	%DiligenceLabel.text = "%d message%s left this visit" % [remaining, "" if remaining == 1 else "s"]
	_update_notebook()
	_update_portrait_ai_status()
	if rebuild_chat:
		await _update_chat(session)
	if token != _refresh_token:
		return
	if not _status_override.is_empty():
		%StatusLabel.text = _status_override
	elif _busy:
		%StatusLabel.text = "Waiting for reply…"
	elif str(session.get("status", "")) == "dismissed":
		%StatusLabel.text = "Visit ended."
	else:
		%StatusLabel.text = ""
	_set_input_enabled(_can_accept_input(session, remaining))


func _update_notebook() -> void:
	var lines: PackedStringArray = []
	for entry_variant in CommunityState.notebook_entries_for(Game.state, "chat"):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("sourceNpcId", "")) != _npc_id:
			continue
		var summary := str(entry.get("displaySummary", "")).strip_edges()
		if summary.is_empty():
			continue
		lines.append("• %s" % summary)
	if lines.is_empty():
		%NotesLabel.text = "Community intel discovered here will appear in your negotiation notebook."
	else:
		%NotesLabel.text = "Notebook intel from this neighbor:\n%s" % "\n".join(lines)
	call_deferred("_sync_notebook_scroll_widths")


func _sync_notebook_scroll_widths() -> void:
	var pad := int(4 * _ui_scale())
	if %NotesScroll.size.x > 0.0:
		%NotesLabel.custom_minimum_size.x = maxf(%NotesScroll.size.x - pad, 1.0)
	if %DiligenceScroll.size.x > 0.0:
		%DiligenceLabel.custom_minimum_size.x = maxf(%DiligenceScroll.size.x - pad, 1.0)


func _update_chat(session: Dictionary) -> void:
	var follow_bottom := _chat_follow_bottom
	var fingerprint := _messages_fingerprint(session)
	var scroll_w := _chat_column_width()
	var width_changed := absf(scroll_w - _last_chat_column_width) > 2.0
	if fingerprint == _rendered_messages_fingerprint and not width_changed:
		if follow_bottom:
			call_deferred("_scroll_chat_to_bottom")
		return

	_updating_chat = true
	var box: VBoxContainer = %ChatMessages
	for child in box.get_children():
		child.queue_free()

	await get_tree().process_frame
	scroll_w = _chat_column_width()
	_last_chat_column_width = scroll_w
	box.custom_minimum_size = Vector2.ZERO
	box.custom_minimum_size.x = scroll_w
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_theme_constant_override("separation", int(6 * _ui_scale()))
	var bubble_scale := _ui_scale()
	for msg_variant in session.get("messages", []):
		if typeof(msg_variant) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = msg_variant
		var text := str(msg.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		var role := str(msg.get("role", msg.get("speaker", ""))).to_lower()
		var kind: int = _ChatBubble.kind_from_role(role)
		box.add_child(_ChatBubble.create(text, kind, scroll_w, bubble_scale))
	# Bottom pad so the last line clears the chat clip / status band.
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(1.0, 18.0 * bubble_scale)
	bottom_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bottom_pad)

	await get_tree().process_frame
	for child in box.get_children():
		if child is Control:
			_ChatBubble.sync_min_height(child as Control)

	_rendered_messages_fingerprint = fingerprint
	_updating_chat = false
	if follow_bottom:
		call_deferred("_scroll_chat_to_bottom")


func _messages_fingerprint(session: Dictionary) -> String:
	var parts: PackedStringArray = []
	for msg_variant in session.get("messages", []):
		if typeof(msg_variant) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = msg_variant
		var text := str(msg.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		var role := str(msg.get("role", msg.get("speaker", ""))).to_lower()
		parts.append("%s|%s" % [role, text])
	return "%d::%s" % [parts.size(), "|".join(parts)]


func _chat_column_width() -> float:
	# Match the ScrollContainer content width (exclude scrollbar + small safety inset)
	# so bubble wrap height is never computed for a wider column than the real one.
	var live_w: float = %ChatScroll.size.x
	var bar: VScrollBar = %ChatScroll.get_v_scroll_bar()
	if bar != null:
		live_w -= maxf(bar.size.x, bar.get_combined_minimum_size().x)
	live_w -= 4.0 * _ui_scale()
	var layout_w: float = _chat_layout_width()
	if live_w > 1.0 and layout_w > 1.0:
		return maxf(minf(live_w, layout_w), 220.0)
	if live_w > 1.0:
		return maxf(live_w, 220.0)
	return maxf(layout_w, 220.0)


func _chat_layout_width() -> float:
	var bounds := _design_bounds("chat_scroll")
	if bounds == Vector4.ZERO:
		return 0.0
	var inset := _inset_for("chat_scroll")
	var design_w := (bounds.z - inset.z) - (bounds.x + inset.x)
	if design_w <= 0.0:
		return 0.0
	return design_w * (%Root.size.x / DESIGN_SIZE.x)


func _scroll_chat_to_bottom() -> void:
	_scroll_chat_to_bottom_async()


func _scroll_chat_to_bottom_async() -> void:
	var scroll: ScrollContainer = %ChatScroll
	for _attempt in range(3):
		var bar: VScrollBar = scroll.get_v_scroll_bar()
		if bar != null and bar.max_value > 0.0:
			scroll.scroll_vertical = int(bar.max_value)
			_chat_follow_bottom = true
			return
		await get_tree().process_frame
	var box: VBoxContainer = %ChatMessages
	var children := box.get_children()
	if not children.is_empty() and children[children.size() - 1] is Control:
		scroll.ensure_control_visible(children[children.size() - 1] as Control)
	_chat_follow_bottom = true


func _chat_is_at_bottom(threshold: float = 16.0) -> bool:
	var bar: VScrollBar = %ChatScroll.get_v_scroll_bar()
	if bar == null:
		return true
	return bar.max_value <= 0.0 or bar.value >= bar.max_value - threshold


func _on_chat_scroll_changed(_value: float = 0.0) -> void:
	if _updating_chat:
		return
	_chat_follow_bottom = _chat_is_at_bottom()


func _messages_remaining(session: Dictionary) -> int:
	return maxi(
		0,
		int(session.get("maxPlayerMessages", CommunityConfig.chat_max_player_messages()))
		- int(session.get("playerMessagesSent", 0)),
	)


func _can_accept_input(session: Dictionary, remaining: int) -> bool:
	if _busy or remaining <= 0:
		return false
	var status := str(session.get("status", "active"))
	return status != "dismissed" and status != "closed"


func _update_chat_subheader() -> void:
	if AiClient.ai_available:
		var model := AiClient.ai_model.strip_edges()
		if model.is_empty():
			%SubheaderLabel.text = "Community chat · AI online"
		else:
			%SubheaderLabel.text = "Community chat · %s" % model
		%SubheaderLabel.add_theme_color_override("font_color", Color(0.18, 0.52, 0.28, 1.0))
	else:
		%SubheaderLabel.text = "Community chat · AI offline"
		%SubheaderLabel.add_theme_color_override("font_color", Color(0.72, 0.24, 0.18, 1.0))


func _update_portrait_ai_status() -> void:
	%PortraitPlaceholder.text = "Character portrait"
	%PortraitPlaceholder.add_theme_color_override("font_color", _COLOR_MUTED)


func _ai_status_text() -> String:
	if not AiClient.ai_available:
		return CommunityConfig.offline_block_message()
	var model := AiClient.ai_model
	return "AI online%s" % (" · %s" % model if not model.is_empty() else "")


func _on_ai_health_updated(_available: bool, _model: String) -> void:
	if visible and not _busy:
		# Status/model only — do not rebuild the message list.
		_refresh(false)


func _set_input_enabled(enabled: bool) -> void:
	%MessageInput.editable = enabled
	%SendButton.disabled = not enabled
	%WalkButton.disabled = false
	if enabled:
		call_deferred("_focus_message_input")


func _focus_message_input() -> void:
	if not visible or _busy or not %MessageInput.editable:
		return
	%MessageInput.grab_focus()
	%MessageInput.caret_column = %MessageInput.text.length()


func _load_layout() -> void:
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if file == null:
		push_warning("CommunityChatPanel: missing layout at %s" % LAYOUT_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_layout = parsed


func _ui_scale() -> float:
	return clampf(%Root.size.y / DESIGN_SIZE.y, 0.72, 1.15)


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


func _layout_header_stack() -> void:
	var bounds := _design_bounds("header_text")
	if bounds == Vector4.ZERO:
		return
	var inset := _inset_for("header_text")
	var design_w: float = (bounds.z - inset.z) - (bounds.x + inset.x)
	if design_w <= 0.0:
		return
	var root: Control = %Root
	var px_w: float = design_w * (root.size.x / DESIGN_SIZE.x)
	%HeaderStack.custom_minimum_size = Vector2(px_w, 0.0)
	%HeaderLabel.custom_minimum_size = Vector2(px_w, 0.0)
	%SubheaderLabel.custom_minimum_size = Vector2(px_w, 0.0)


func _apply_scaled_fonts() -> void:
	var s := _ui_scale()
	%HeaderLabel.add_theme_font_size_override("font_size", int(20 * s))
	%SubheaderLabel.add_theme_font_size_override("font_size", int(14 * s))
	%NpcNameLabel.add_theme_font_size_override("font_size", int(18 * s))
	%NotesLabel.add_theme_font_size_override("font_size", int(12 * s))
	%DiligenceLabel.add_theme_font_size_override("font_size", int(12 * s))
	%StatusLabel.add_theme_font_size_override("font_size", int(11 * s))
	%PortraitPlaceholder.add_theme_font_size_override("font_size", int(14 * s))
	%MessageInput.add_theme_font_size_override("font_size", int(15 * s))
	%HeaderStack.add_theme_constant_override("separation", int(3 * s))


func _style_labels() -> void:
	%HeaderLabel.add_theme_color_override("font_color", _COLOR_TITLE)
	%SubheaderLabel.add_theme_color_override("font_color", _COLOR_BODY)
	%NpcNameLabel.add_theme_color_override("font_color", Color(0.98, 0.95, 0.9, 1.0))
	%NotesLabel.add_theme_color_override("font_color", _COLOR_NOTES)
	%DiligenceLabel.add_theme_color_override("font_color", _COLOR_NOTES)
	%StatusLabel.add_theme_color_override("font_color", _COLOR_MUTED)
	%PortraitPlaceholder.add_theme_color_override("font_color", _COLOR_MUTED)
	%PortraitPlaceholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%PortraitPlaceholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%AiStatusLabel.visible = false
	%HeaderLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%SubheaderLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%HeaderLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%SubheaderLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%HeaderStack.alignment = BoxContainer.ALIGNMENT_CENTER
	%NotesLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%DiligenceLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%StatusLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%StatusLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%NpcNameLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%NpcNameLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_scaled_fonts()


func _configure_interaction() -> void:
	var root: Control = %Root
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	for node_name in _DECORATIVE_NODES:
		var node: Node = get_node_or_null("Overlay/Root/%s" % node_name)
		if node is Control:
			(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	%ChatScroll.mouse_filter = Control.MOUSE_FILTER_STOP
	%ChatScroll.z_index = 10
	for node_name in ["StatusLabel", "AiStatusLabel"]:
		var label: Node = get_node_or_null("Overlay/Root/%s" % node_name)
		if label is Control:
			(label as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for node_name in ["InputField", "SendButton", "WalkButton"]:
		var node: Node = get_node_or_null("Overlay/Root/%s" % node_name)
		if node is Control:
			var ctrl := node as Control
			ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
			ctrl.z_index = 20
	%MessageInput.mouse_filter = Control.MOUSE_FILTER_STOP


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


func _on_viewport_resized() -> void:
	if not visible:
		return
	_fit_to_viewport()
	# Rebuild bubbles only when the chat column width actually changed.
	if Game.state == null or _npc_id.is_empty():
		return
	var scroll_w := _chat_column_width()
	if absf(scroll_w - _last_chat_column_width) <= 2.0:
		return
	var session: Dictionary = CommunityChatRuntime.get_active_session(Game.state, _npc_id)
	call_deferred("_update_chat", session)
