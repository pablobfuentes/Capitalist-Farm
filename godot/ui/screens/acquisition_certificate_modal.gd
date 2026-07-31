extends CanvasLayer

## Reward modal shown after buying or closing a negotiation acquisition.
## Deal text overlays come later — for now this presents the certificate art.

signal closed

const _CERT_PATH := "res://assets/ui/negotiation/certificate.png"

var _deal: Dictionary = {}
var _animating := false
var _can_dismiss := false
var _tween: Tween
var _card_rest_pos := Vector2.ZERO
var _banner_target: Control = null


func _ready() -> void:
	layer = 140
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	%CloseButton.pressed.connect(_on_close_pressed)
	%Backdrop.gui_input.connect(_on_backdrop_gui_input)
	%CertificateImage.gui_input.connect(_on_certificate_gui_input)
	# Keep the close control hoverable even while gated — disabled buttons eat the click path.
	%CloseButton.disabled = false
	FeedbackBus.wire_button(%CloseButton)
	_ensure_texture()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _animating or not _can_dismiss:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


## Call from buy/close handlers. Safe to await; emits [signal closed] after dismiss.
func present(deal: Dictionary = {}, banner_target: Control = null) -> void:
	_banner_target = banner_target
	# Avoid nested-CanvasLayer visibility quirks by living on the scene root.
	var root := get_tree().root
	if get_parent() != root:
		reparent(root)
	await open_with_deal(deal)
	if visible:
		await closed


func open_with_deal(deal: Dictionary = {}) -> void:
	_deal = deal.duplicate(true) if not deal.is_empty() else {}
	_ensure_texture()
	_kill_tween()
	_animating = true
	_can_dismiss = false
	%CloseButton.disabled = false
	show()
	layer = 140
	FeedbackBus.celebrate_acquisition()

	var backdrop: Control = %Backdrop
	var card: Control = %CertificateRoot
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_fit_certificate()
	_card_rest_pos = card.position
	card.pivot_offset = card.size * 0.5
	backdrop.modulate = Color(1, 1, 1, 0)
	card.modulate = Color(1, 1, 1, 0)
	card.scale = Vector2(0.70, 0.70)
	card.position = _card_rest_pos + Vector2(0, 42)

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(backdrop, "modulate:a", 1.0, 0.30).set_ease(Tween.EASE_OUT)
	_tween.tween_property(card, "modulate:a", 1.0, 0.24).set_ease(Tween.EASE_OUT)
	_tween.tween_property(card, "position", _card_rest_pos, 0.45)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(card, "scale", Vector2(1.05, 1.05), 0.38)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await _tween.finished
	if not is_inside_tree() or not visible:
		return

	_tween = create_tween()
	_tween.tween_property(card, "scale", Vector2.ONE, 0.14)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await _tween.finished
	if not is_inside_tree() or not visible:
		return
	FeedbackBus.stamp_punch(card)
	_play_mastery_juice(card)
	# Soft settle hold — dismiss only after the card lands.
	await get_tree().create_timer(0.35).timeout
	if not is_inside_tree() or not visible:
		return
	_can_dismiss = true
	_animating = false


func close_modal() -> void:
	if not visible or _animating or not _can_dismiss:
		return
	_animating = true
	_can_dismiss = false
	_kill_tween()

	var backdrop: Control = %Backdrop
	var card: Control = %CertificateRoot
	card.pivot_offset = card.size * 0.5

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(card, "scale", Vector2(0.88, 0.88), 0.20)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(card, "modulate:a", 0.0, 0.18).set_ease(Tween.EASE_IN)
	_tween.tween_property(card, "position", _card_rest_pos + Vector2(0, -24), 0.20)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(backdrop, "modulate:a", 0.0, 0.22).set_ease(Tween.EASE_IN)
	await _tween.finished
	hide()
	# Let the certificate leave the tree/input path before NW juice starts.
	await get_tree().process_frame

	# Only post-dismiss celebration: NW counts old → new, then slides to the banner.
	var nw_before := int(_deal.get("nwBefore", 0))
	var nw_after := int(_deal.get("nwAfter", 0))
	if nw_after != nw_before:
		await FeedbackBus.net_worth_cascade(nw_before, nw_after, _resolve_banner_target())

	_animating = false
	closed.emit()


static func deal_from_command_result(result: Dictionary, nw_before: int = -1, nw_after: int = -1) -> Dictionary:
	var offer: Dictionary = {}
	if typeof(result.get("offer")) == TYPE_DICTIONARY:
		offer = (result.get("offer") as Dictionary).duplicate(true)
	var business_name := ""
	var asset_type := "business"
	var template_id := ""
	if result.get("business") is BusinessInstance:
		var biz: BusinessInstance = result.get("business")
		business_name = biz.name
		template_id = biz.template_id
		asset_type = "business"
	elif typeof(result.get("realEstate")) == TYPE_DICTIONARY:
		var re: Dictionary = result.get("realEstate")
		business_name = str(re.get("name", "Property"))
		template_id = str(re.get("templateId", ""))
		asset_type = "realestate"
	elif not str(result.get("name", "")).is_empty():
		business_name = str(result.get("name", ""))
	var deal := {
		"assetType": asset_type,
		"name": business_name,
		"templateId": template_id,
		"totalPrice": int(result.get("price", offer.get("totalPrice", 0))),
		"cashAtClosing": int(offer.get("cashAtClosing", result.get("price", 0))),
		"sellerNote": int(offer.get("sellerNote", offer.get("noteAmount", 0))),
		"earnOut": int(offer.get("earnOut", 0)),
		"finance": result.get("finance", {}),
		"offer": offer,
	}
	if nw_before >= 0:
		deal["nwBefore"] = nw_before
	if nw_after >= 0:
		deal["nwAfter"] = nw_after
	elif Game.state != null:
		deal["nwAfter"] = FinanceSystem.net_worth(Game.state)
	return deal


static func is_acquisition_result(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return false
	return result.get("business") is BusinessInstance or typeof(result.get("realEstate")) == TYPE_DICTIONARY


func _play_mastery_juice(near: Control = null) -> void:
	if Game.state == null:
		return
	var template_id := str(_deal.get("templateId", ""))
	var name := str(_deal.get("name", ""))
	var mastery: Dictionary = RunStatsSystem.note_acquisition(
		Game.state,
		template_id,
		name,
		0,
		0,
		str(_deal.get("assetType", "acquisition")),
	)
	if bool(mastery.get("firstOfType", false)):
		var label := "New type: %s" % (name if not name.is_empty() else template_id)
		FeedbackBus.first_of_type_badge(label, near)
	var combo := int(mastery.get("combo", 0))
	if combo >= 2:
		FeedbackBus.combo_sting(combo, near)


func _resolve_banner_target() -> Control:
	if _banner_target != null and is_instance_valid(_banner_target):
		return _banner_target
	var run_stats := get_tree().root.find_child("RunStats", true, false)
	if run_stats is Control:
		return run_stats as Control
	var top_bar := get_tree().root.find_child("TopBar", true, false)
	if top_bar is Control:
		return top_bar as Control
	return null


func _on_close_pressed() -> void:
	close_modal()


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if _animating or not _can_dismiss:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close_modal()


func _on_certificate_gui_input(event: InputEvent) -> void:
	# Whole certificate art is dismissible (X is decorative).
	_on_backdrop_gui_input(event)


func _ensure_texture() -> void:
	var tex: TextureRect = %CertificateImage
	if tex.texture != null:
		return
	if not ResourceLoader.exists(_CERT_PATH):
		push_warning("AcquisitionCertificateModal: missing texture at %s" % _CERT_PATH)
		return
	var loaded: Resource = ResourceLoader.load(_CERT_PATH, "Texture2D", ResourceLoader.CACHE_MODE_REUSE)
	if loaded is Texture2D:
		tex.texture = loaded as Texture2D
	else:
		push_warning("AcquisitionCertificateModal: failed to load Texture2D from %s" % _CERT_PATH)


func _fit_certificate() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var card: Control = %CertificateRoot
	var tex: TextureRect = %CertificateImage
	var native := Vector2(1448, 1086)
	if tex.texture != null:
		native = tex.texture.get_size()
	var max_w := vp.x * 0.72
	var max_h := vp.y * 0.88
	var scale_factor := minf(max_w / maxf(native.x, 1.0), max_h / maxf(native.y, 1.0))
	scale_factor = clampf(scale_factor, 0.35, 1.15)
	var target := native * scale_factor
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.custom_minimum_size = target
	card.size = target
	card.position = (vp - target) * 0.5
	_card_rest_pos = card.position
	# Large top-right hit target over the decorative X.
	var close_btn: Button = %CloseButton
	var btn_size := Vector2(maxi(64.0, target.x * 0.12), maxi(64.0, target.x * 0.12))
	close_btn.custom_minimum_size = btn_size
	close_btn.size = btn_size
	close_btn.position = Vector2(target.x - btn_size.x * 1.05, btn_size.y * 0.08)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	# Image must receive clicks so the whole certificate dismisses.
	tex.mouse_filter = Control.MOUSE_FILTER_STOP
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
