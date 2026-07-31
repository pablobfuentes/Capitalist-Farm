# Shared player-feedback juice: SFX, floats, shake/pulse/pop, button wiring.
extends Node

const SAMPLE_RATE := 22050
## Loud enough to notice under UI clicks; duck drops ~16 dB for a clear hush.
const AMBIENT_BASE_DB := -16.0
const AMBIENT_DUCK_DB := -32.0
const MUSIC_BASE_DB := -11.0
const MUSIC_DUCK_DB := -26.0
const OVERWORLD_MUSIC_PATH := "res://assets/audio/music/Stables_-_Zelda_BoTW.mp3"
const TOOLTIP_DELAY_SEC := 0.04

var _sfx_players: Array[AudioStreamPlayer] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _float_layer: CanvasLayer
var _player_index := 0
var _ambient_player: AudioStreamPlayer
var _ambient_mode := ""
var _ambient_ducked := false
var _ambient_fade: Tween
var _overworld_music: AudioStream


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_build_streams()
	_overworld_music = _load_overworld_music()
	for _i in 4:
		var sfx := AudioStreamPlayer.new()
		sfx.bus = "SFX"
		add_child(sfx)
		_sfx_players.append(sfx)
		var ui := AudioStreamPlayer.new()
		ui.bus = "UI"
		add_child(ui)
		_ui_players.append(ui)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "AmbientPlayer"
	_ambient_player.bus = "Ambient"
	_ambient_player.volume_db = AMBIENT_BASE_DB
	_ambient_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ambient_player)
	_float_layer = CanvasLayer.new()
	_float_layer.layer = 200
	_float_layer.name = "FeedbackFloatLayer"
	add_child(_float_layer)
	# Snappy tooltips (40ms) instead of the default half-second lag.
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", TOOLTIP_DELAY_SEC)


func play(sfx_id: String) -> void:
	if not _streams.has(sfx_id):
		return
	var bus_ui := sfx_id in ["click", "deny", "tick"]
	var pool: Array[AudioStreamPlayer] = _ui_players if bus_ui else _sfx_players
	if pool.is_empty():
		return
	_player_index = (_player_index + 1) % pool.size()
	var player: AudioStreamPlayer = pool[_player_index]
	player.stream = _streams[sfx_id]
	player.play()


func click() -> void:
	play("click")


func deny(control: Control = null) -> void:
	play("deny")
	if control != null:
		shake(control)


func success(control: Control = null) -> void:
	play("success")
	if control != null:
		pulse(control)


func celebrate_acquisition() -> void:
	play("fanfare")


func chime() -> void:
	play("chime")


func advance_whoosh() -> void:
	play("advance")


func stamp() -> void:
	play("stamp")


func whisper() -> void:
	play("whisper")


func door_chime() -> void:
	play("door")


func walk_away_sting() -> void:
	play("walk_away")


func warning_rattle() -> void:
	play("rattle")


func crest_burst(loud: bool = false) -> void:
	play("crest_loud" if loud else "crest")


func paper_whoosh() -> void:
	play("paper")


func shake(control: Control, strength: float = 7.0, duration: float = 0.28) -> void:
	if control == null or not is_instance_valid(control):
		return
	var origin := control.position
	var tween := create_tween()
	for i in 5:
		var amp := strength * (1.0 - float(i) / 5.0)
		tween.tween_property(control, "position", origin + Vector2(amp, 0), duration / 10.0)
		tween.tween_property(control, "position", origin - Vector2(amp * 0.7, 0), duration / 10.0)
	tween.tween_property(control, "position", origin, duration / 10.0)


func pulse(control: Control, peak: float = 1.08, duration: float = 0.22) -> void:
	if control == null or not is_instance_valid(control):
		return
	_ensure_pivot(control)
	var tween := create_tween()
	tween.tween_property(control, "scale", Vector2(peak, peak), duration * 0.45)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(control, "scale", Vector2.ONE, duration * 0.55)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func pop_in(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	_ensure_pivot(control)
	control.scale = Vector2(0.88, 0.88)
	control.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(control, "modulate:a", 1.0, 0.14).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2(1.05, 1.05), 0.16)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.chain().tween_property(control, "scale", Vector2.ONE, 0.10)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func squash_button(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	_ensure_pivot(control)
	var tween := create_tween()
	tween.tween_property(control, "scale", Vector2(0.94, 0.94), 0.05)
	tween.tween_property(control, "scale", Vector2(1.03, 1.03), 0.07)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(control, "scale", Vector2.ONE, 0.08)


func wire_button(button: BaseButton) -> void:
	if button == null or button.has_meta("_feedback_wired"):
		return
	button.set_meta("_feedback_wired", true)
	button.pressed.connect(func() -> void:
		click()
		squash_button(button)
	)


func float_text(text: String, global_pos: Vector2, color: Color = Color(0.95, 0.92, 0.75, 1.0)) -> void:
	if _float_layer == null:
		return
	var label := Label.new()
	label.text = text
	label.z_index = 50
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	_float_layer.add_child(label)
	label.reset_size()
	label.global_position = global_pos - Vector2(label.size.x * 0.5, label.size.y * 0.5)
	label.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.12)
	tween.tween_property(label, "global_position:y", label.global_position.y - 36.0, 0.85)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tween.chain().tween_callback(label.queue_free)


## Count NW from old → new in screen center, then slide the label into the top banner.
func net_worth_cascade(from_nw: int, to_nw: int, banner: Control = null) -> void:
	if _float_layer == null:
		return
	if from_nw == to_nw:
		return
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 80
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(0.98, 0.90, 0.45, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.text = "NW %s" % MathUtil.fmt_money(from_nw)
	_float_layer.add_child(label)
	label.reset_size()
	var vp := get_viewport().get_visible_rect()
	var center := vp.get_center()
	label.pivot_offset = label.size * 0.5
	label.global_position = center - label.size * 0.5
	label.modulate.a = 0.0
	var intro := create_tween()
	intro.tween_property(label, "modulate:a", 1.0, 0.12)
	await intro.finished

	var steps := 10
	for i in steps:
		var t := float(i + 1) / float(steps)
		var val := int(round(lerpf(float(from_nw), float(to_nw), t)))
		label.text = "NW %s" % MathUtil.fmt_money(val)
		label.reset_size()
		label.pivot_offset = label.size * 0.5
		label.global_position = center - label.size * 0.5
		play("coin")
		await get_tree().create_timer(0.055).timeout
		if not is_instance_valid(label):
			return

	label.text = "NW %s" % MathUtil.fmt_money(to_nw)
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.global_position = center - label.size * 0.5
	play("success")
	await get_tree().create_timer(0.12).timeout
	if not is_instance_valid(label):
		return

	var target_center := Vector2(vp.size.x * 0.5, 56.0)
	if banner != null and is_instance_valid(banner):
		target_center = banner.get_global_rect().get_center()
	var target_pos := target_center - label.size * 0.5
	var slide := create_tween()
	slide.set_parallel(true)
	slide.tween_property(label, "global_position", target_pos, 0.38)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	slide.tween_property(label, "scale", Vector2(0.72, 0.72), 0.38)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await slide.finished
	if not is_instance_valid(label):
		return
	if banner != null and is_instance_valid(banner):
		pulse(banner, 1.06, 0.22)
	var fade := create_tween()
	fade.tween_interval(0.18)
	fade.tween_property(label, "modulate:a", 0.0, 0.2)
	fade.tween_callback(label.queue_free)
	await fade.finished


func float_text_near(control: Control, text: String, color: Color = Color(0.95, 0.92, 0.75, 1.0)) -> void:
	if control == null or not is_instance_valid(control):
		return
	var rect := control.get_global_rect()
	float_text(text, rect.get_center() + Vector2(0, -8), color)


func cash_delta(amount: int, near: Control = null) -> void:
	if amount == 0:
		return
	var text := "%s%s" % ["+" if amount > 0 else "-", MathUtil.fmt_money(absi(amount))]
	var color := Color(0.35, 0.85, 0.48, 1.0) if amount > 0 else Color(0.92, 0.38, 0.32, 1.0)
	if amount > 0:
		play("coin")
	else:
		play("whoosh")
	if near != null:
		float_text_near(near, text, color)
	else:
		var vp := get_viewport().get_visible_rect()
		float_text(text, Vector2(vp.size.x * 0.5, 72.0), color)


func ap_delta(amount: int, near: Control = null) -> void:
	if amount == 0:
		return
	var text := "%+d AP" % amount
	var color := Color(0.95, 0.82, 0.35, 1.0) if amount < 0 else Color(0.55, 0.85, 1.0, 1.0)
	if amount < 0:
		play("whoosh")
	pulse(near)
	if near != null:
		float_text_near(near, text, color)


func make_typing_indicator() -> Control:
	var wrap := HBoxContainer.new()
	wrap.name = "TypingIndicator"
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 6)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(12, 1)
	wrap.add_child(spacer)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.165, 0.29, 0.43, 0.92)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "Dots"
	label.text = "•••"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.96, 0.95, 0.92, 1.0))
	panel.add_child(label)
	wrap.add_child(panel)
	var expand := Control.new()
	expand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(expand)
	# Animate dots while alive.
	var tween := create_tween().set_loops()
	tween.tween_callback(func() -> void:
		if not is_instance_valid(label):
			return
		match label.text:
			"•":
				label.text = "••"
			"••":
				label.text = "•••"
			_:
				label.text = "•"
	)
	tween.tween_interval(0.28)
	wrap.set_meta("_typing_tween", tween)
	wrap.tree_exiting.connect(func() -> void:
		if tween.is_valid():
			tween.kill()
	)
	return wrap


func animate_modal_in(control: Control) -> void:
	if control == null:
		return
	_ensure_pivot(control)
	control.visible = true
	control.modulate.a = 0.0
	control.scale = Vector2(0.92, 0.92)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(control, "modulate:a", 1.0, 0.18)
	tween.tween_property(control, "scale", Vector2.ONE, 0.22)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func animate_modal_out(control: Control, then_hide: bool = true) -> void:
	if control == null:
		return
	_ensure_pivot(control)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(control, "modulate:a", 0.0, 0.14)
	tween.tween_property(control, "scale", Vector2(0.94, 0.94), 0.14)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	if then_hide:
		tween.chain().tween_callback(func() -> void:
			control.visible = false
			control.scale = Vector2.ONE
			control.modulate.a = 1.0
		)


## Awaitable slide+fade out for CanvasLayer panels (negotiation / community).
func slide_out_panel(root: Control) -> void:
	if root == null or not is_instance_valid(root):
		return
	_ensure_pivot(root)
	var origin := root.position
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(root, "modulate:a", 0.0, 0.22).set_ease(Tween.EASE_IN)
	tween.tween_property(root, "position", origin + Vector2(0, 28), 0.22)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await tween.finished
	if is_instance_valid(root):
		root.position = origin
		root.modulate.a = 1.0


func stamp_punch(control: Control = null) -> void:
	stamp()
	if control != null:
		pulse(control, 1.12, 0.28)


## Legacy helper — prefer net_worth_cascade for acquisition celebrations.
func coin_cascade(amount: int, near: Control = null, _ticks: int = 4) -> void:
	if amount == 0:
		return
	# Kept for callers that still pass a single delta; show one clear NW delta float.
	var text := "NW %s%s" % ["+" if amount > 0 else "-", MathUtil.fmt_money(absi(amount))]
	var color := Color(0.98, 0.90, 0.45, 1.0)
	if near != null and is_instance_valid(near):
		float_text_near(near, text, color)
	else:
		var vp := get_viewport().get_visible_rect()
		float_text(text, vp.get_center(), color)
	play("coin")


func vignette_pulse(color: Color = Color(0.85, 0.12, 0.1, 0.42), duration: float = 0.55) -> void:
	if _float_layer == null:
		return
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(color.r, color.g, color.b, 0.0)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.z_index = 40
	_float_layer.add_child(rect)
	var tween := create_tween()
	tween.tween_property(rect, "color:a", color.a, duration * 0.35).set_ease(Tween.EASE_OUT)
	tween.tween_property(rect, "color:a", 0.0, duration * 0.65).set_ease(Tween.EASE_IN)
	tween.tween_callback(rect.queue_free)


func show_chip(text: String, near: Control = null, duration: float = 2.2) -> void:
	if _float_layer == null or text.strip_edges().is_empty():
		return
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 60
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.16, 0.14, 0.92)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.border_color = Color(0.85, 0.78, 0.45, 0.75)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88, 1.0))
	panel.add_child(label)
	_float_layer.add_child(panel)
	panel.reset_size()
	var vp := get_viewport().get_visible_rect()
	var pos := Vector2(vp.size.x * 0.5 - panel.size.x * 0.5, 96.0)
	if near != null and is_instance_valid(near):
		var rect := near.get_global_rect()
		pos = Vector2(rect.get_center().x - panel.size.x * 0.5, rect.position.y - panel.size.y - 10.0)
	panel.global_position = pos
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.14)
	tween.tween_interval(duration)
	tween.tween_property(panel, "modulate:a", 0.0, 0.22)
	tween.tween_callback(panel.queue_free)


func flash_color(control: Control, color: Color, duration: float = 0.35) -> void:
	if control == null or not is_instance_valid(control):
		return
	var original := control.modulate
	var tween := create_tween()
	tween.tween_property(control, "modulate", color, duration * 0.35).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate", original, duration * 0.65).set_ease(Tween.EASE_IN_OUT)


func highlight_text_control(control: Control, duration: float = 0.9) -> void:
	if control == null or not is_instance_valid(control):
		return
	var original := control.modulate
	control.modulate = Color(1.15, 1.05, 0.55, 1.0)
	pulse(control, 1.04, 0.2)
	var tween := create_tween()
	tween.tween_property(control, "modulate", original, duration).set_ease(Tween.EASE_IN_OUT)


func warmth_glow(control: Control, warmth: float = 1.0) -> void:
	if control == null or not is_instance_valid(control):
		return
	var peak := Color(1.0, 0.78 + 0.12 * clampf(warmth, 0.0, 1.0), 0.55, 1.0)
	flash_color(control, peak, 0.55)


func sparkle_burst(near: Control = null) -> void:
	play("sparkle")
	if near != null:
		pulse(near, 1.1, 0.25)
		float_text_near(near, "✦", Color(1.0, 0.55, 0.72, 1.0))


## Soft fade for anchored HUD panels (safe — does not touch position/offsets).
func panel_fade_in(control: Control = null) -> void:
	play("whoosh")
	if control == null or not is_instance_valid(control):
		return
	control.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(control, "modulate:a", 1.0, 0.16).set_ease(Tween.EASE_OUT)


## Soft horizontal swipe for free-positioned controls (titles, etc.).
## Do not use on anchor-preset HUD panels — use panel_fade_in instead.
func panel_swipe(control: Control = null, from_right: bool = true) -> void:
	play("whoosh")
	if control == null or not is_instance_valid(control):
		return
	# Anchored controls: position tweens fight layout and can clip the panel off-screen.
	if control.anchor_left != control.anchor_right or control.anchor_top != control.anchor_bottom:
		panel_fade_in(control)
		return
	_ensure_pivot(control)
	var origin := control.position
	var offset := Vector2(28.0 if from_right else -28.0, 0.0)
	control.position = origin + offset
	control.modulate.a = 0.55
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(control, "position", origin, 0.2)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(control, "modulate:a", 1.0, 0.16).set_ease(Tween.EASE_OUT)


## Awaitable slide+fade in for CanvasLayer panel roots.
func slide_in_panel(root: Control) -> void:
	if root == null or not is_instance_valid(root):
		return
	_ensure_pivot(root)
	var origin := root.position
	root.position = origin + Vector2(0, 22)
	root.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(root, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_property(root, "position", origin, 0.22)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tween.finished


func toast_error(text: String, duration: float = 2.4) -> void:
	_show_toast(text, false, duration)


func toast_success(text: String, duration: float = 2.2) -> void:
	_show_toast(text, true, duration)


func _show_toast(text: String, success: bool, duration: float) -> void:
	if _float_layer == null or text.strip_edges().is_empty():
		return
	play("toast_ping" if success else "toast_buzz")
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 90
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.22, 0.16, 0.94) if success else Color(0.28, 0.12, 0.12, 0.94)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.border_color = Color(0.55, 0.85, 0.62, 0.8) if success else Color(0.9, 0.45, 0.4, 0.8)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 1.0))
	panel.add_child(label)
	_float_layer.add_child(panel)
	panel.reset_size()
	var vp := get_viewport().get_visible_rect()
	var target := Vector2(vp.size.x * 0.5 - panel.size.x * 0.5, 28.0)
	panel.global_position = target + Vector2(0, -36)
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "global_position", target, 0.22)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate:a", 1.0, 0.16)
	tween.chain().tween_interval(duration)
	tween.chain().set_parallel(true)
	tween.tween_property(panel, "global_position", target + Vector2(0, -28), 0.2)\
		.set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(panel.queue_free)


func species_react(control: Control, positive: bool) -> void:
	if control == null or not is_instance_valid(control):
		return
	play("tick" if positive else "deny")
	_ensure_pivot(control)
	var peak := Vector2(1.14, 1.14) if positive else Vector2(0.92, 0.92)
	var tint := Color(0.75, 1.05, 0.8, 1.0) if positive else Color(1.05, 0.7, 0.68, 1.0)
	var original := control.modulate
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(control, "scale", peak, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(control, "modulate", tint, 0.12)
	tween.chain().tween_property(control, "scale", Vector2.ONE, 0.18)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(control, "modulate", original, 0.22)


func first_of_type_badge(label_text: String = "New type!", near: Control = null) -> void:
	play("badge")
	show_chip(label_text, near, 2.4)
	if near != null:
		pulse(near, 1.12, 0.28)


func combo_sting(deal_count: int, near: Control = null) -> void:
	if deal_count < 2:
		return
	play("combo")
	var text := "Deal combo ×%d" % deal_count
	show_chip(text, near, 2.0)
	if near != null:
		pulse(near, 1.1, 0.28)


func trusted_seal(near: Control = null) -> void:
	play("trusted")
	toast_success("Trusted", 2.0)
	show_chip("Trusted", near, 2.2)
	if near != null:
		warmth_glow(near, 1.0)
		pulse(near, 1.12, 0.3)


func profit_streak_tick(streak: int, near: Control = null) -> void:
	if streak <= 0:
		return
	play("streak")
	var text := "Profit streak ×%d" % streak
	show_chip(text, near, 2.0)
	if near != null:
		pulse(near, 1.06, 0.22)


## Map / negotiation ambient bed. Pass "" to stop.
## Modes: "map" (overworld music loop), "negotiation" / "room" (quiet interior bed).
func set_ambient(mode: String) -> void:
	var next := mode.strip_edges()
	if next == "room":
		next = "negotiation"
	if _ambient_player == null:
		return
	if next == _ambient_mode and _ambient_player.playing and not _ambient_ducked:
		return
	_kill_ambient_fade()
	_ambient_mode = next
	_ambient_ducked = false
	if next.is_empty():
		_ambient_fade = create_tween()
		_ambient_fade.tween_property(_ambient_player, "volume_db", -80.0, 0.3)
		_ambient_fade.tween_callback(func() -> void:
			if is_instance_valid(_ambient_player):
				_ambient_player.stop()
				_ambient_player.volume_db = AMBIENT_BASE_DB
		)
		return
	var stream: AudioStream = _stream_for_ambient_mode(next)
	if stream == null:
		return
	var target_db := _base_db_for_ambient_mode(next)
	# Restart so map music ↔ room bed switches cleanly.
	_ambient_player.stop()
	_ambient_player.stream = stream
	_ambient_player.volume_db = -48.0
	_ambient_player.play()
	_ambient_fade = create_tween()
	_ambient_fade.tween_property(_ambient_player, "volume_db", target_db, 0.7)\
		.set_ease(Tween.EASE_OUT)


## Soften music/ambient while AI typing / thinking.
func duck_ambient(on: bool) -> void:
	if _ambient_player == null:
		return
	if on == _ambient_ducked:
		return
	if on and not _ambient_player.playing and not _ambient_mode.is_empty():
		var stream: AudioStream = _stream_for_ambient_mode(_ambient_mode)
		if stream != null:
			_ambient_player.stream = stream
			_ambient_player.play()
	if not _ambient_player.playing:
		return
	_ambient_ducked = on
	_kill_ambient_fade()
	var base_db := _base_db_for_ambient_mode(_ambient_mode)
	var duck_db := MUSIC_DUCK_DB if _ambient_mode == "map" else AMBIENT_DUCK_DB
	var target := duck_db if on else base_db
	_ambient_fade = create_tween()
	_ambient_fade.tween_property(_ambient_player, "volume_db", target, 0.28)\
		.set_ease(Tween.EASE_IN_OUT)


func _kill_ambient_fade() -> void:
	if _ambient_fade != null and is_instance_valid(_ambient_fade):
		_ambient_fade.kill()
	_ambient_fade = null


func _load_overworld_music() -> AudioStream:
	if not ResourceLoader.exists(OVERWORLD_MUSIC_PATH):
		push_warning("FeedbackBus: overworld music missing at %s" % OVERWORLD_MUSIC_PATH)
		return null
	var stream: AudioStream = load(OVERWORLD_MUSIC_PATH) as AudioStream
	if stream == null:
		push_warning("FeedbackBus: failed to load overworld music")
		return null
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = 0
	return stream


func _stream_for_ambient_mode(mode: String) -> AudioStream:
	if mode == "map":
		if _overworld_music != null:
			return _overworld_music
		return _streams.get("ambient_map", null) as AudioStream
	return _streams.get("ambient_room", null) as AudioStream


func _base_db_for_ambient_mode(mode: String) -> float:
	if mode == "map" and _overworld_music != null:
		return MUSIC_BASE_DB
	return AMBIENT_BASE_DB


func wire_scroll(scroll: ScrollContainer) -> void:
	if scroll == null or not is_instance_valid(scroll) or scroll.has_meta("_feedback_scroll"):
		return
	scroll.set_meta("_feedback_scroll", true)
	for bar in [scroll.get_v_scroll_bar(), scroll.get_h_scroll_bar()]:
		if bar == null:
			continue
		bar.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				play("tick")
				_scrollbar_grab_feel(bar)
		)


func _scrollbar_grab_feel(bar: ScrollBar) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	_ensure_pivot(bar)
	var tween := create_tween()
	tween.tween_property(bar, "scale", Vector2(1.04, 1.04), 0.06)
	tween.tween_property(bar, "scale", Vector2.ONE, 0.14)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func affordability_color(cash: int, need: int) -> Color:
	if need <= 0:
		return Color(0.45, 0.85, 0.55, 1.0)
	if cash >= need:
		return Color(0.35, 0.82, 0.48, 1.0)
	if cash >= int(round(float(need) * 0.7)):
		return Color(0.92, 0.72, 0.28, 1.0)
	return Color(0.9, 0.35, 0.3, 1.0)


func _ensure_pivot(control: Control) -> void:
	if control.size == Vector2.ZERO:
		control.reset_size()
	control.pivot_offset = control.size * 0.5


func _ensure_buses() -> void:
	_ensure_bus("SFX", "Master")
	_ensure_bus("UI", "Master")
	_ensure_bus("Ambient", "Master")
	var ambient_idx := AudioServer.get_bus_index("Ambient")
	if ambient_idx != -1:
		# Slightly hotter than SFX so the bed stays present under clicks.
		AudioServer.set_bus_volume_db(ambient_idx, 2.0)


func _ensure_bus(bus_name: String, parent_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, parent_name)


func _build_streams() -> void:
	_streams["click"] = _tone_blip([880.0], 0.045, 0.22)
	_streams["deny"] = _tone_blip([180.0, 140.0], 0.09, 0.28)
	_streams["success"] = _tone_blip([523.25, 659.25], 0.08, 0.24)
	_streams["coin"] = _tone_blip([987.77, 1318.5], 0.07, 0.22)
	_streams["stamp"] = _noise_thud(0.08, 0.35)
	_streams["whoosh"] = _noise_whoosh(0.12, 0.18)
	_streams["chime"] = _tone_blip([784.0, 1046.5], 0.12, 0.2)
	_streams["advance"] = _tone_blip([392.0, 523.25, 659.25], 0.1, 0.2)
	_streams["fanfare"] = _tone_blip([523.25, 659.25, 783.99, 1046.5], 0.16, 0.26)
	_streams["tick"] = _tone_blip([1240.0], 0.03, 0.14)
	_streams["whisper"] = _noise_whoosh(0.16, 0.12)
	_streams["door"] = _tone_blip([392.0, 523.25], 0.11, 0.18)
	_streams["walk_away"] = _tone_blip([330.0, 247.0, 196.0], 0.1, 0.2)
	_streams["rattle"] = _noise_thud(0.12, 0.28)
	_streams["crest"] = _tone_blip([523.25, 659.25, 783.99], 0.12, 0.24)
	_streams["crest_loud"] = _tone_blip([392.0, 523.25, 659.25, 880.0], 0.14, 0.28)
	_streams["paper"] = _noise_whoosh(0.09, 0.14)
	_streams["sparkle"] = _tone_blip([1174.7, 1568.0], 0.08, 0.2)
	_streams["calc"] = _tone_blip([980.0], 0.035, 0.16)
	_streams["toast_buzz"] = _tone_blip([220.0, 160.0], 0.08, 0.22)
	_streams["toast_ping"] = _tone_blip([880.0, 1320.0], 0.07, 0.2)
	_streams["badge"] = _tone_blip([659.25, 880.0, 1174.7], 0.1, 0.22)
	_streams["combo"] = _tone_blip([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.12, 0.24)
	_streams["trusted"] = _tone_blip([392.0, 523.25, 659.25], 0.14, 0.22)
	_streams["streak"] = _tone_blip([784.0, 988.0], 0.09, 0.2)
	_streams["ambient_map"] = _ambient_bed(true)
	_streams["ambient_room"] = _ambient_bed(false)


func _tone_blip(freqs: Array, note_len: float, volume: float) -> AudioStreamWAV:
	var total := note_len * float(freqs.size())
	var sample_count := maxi(1, int(SAMPLE_RATE * total))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(SAMPLE_RATE)
		var note_i := mini(freqs.size() - 1, int(t / note_len))
		var local_t := t - float(note_i) * note_len
		var env := clampf(1.0 - local_t / note_len, 0.0, 1.0)
		env *= env
		var freq := float(freqs[note_i])
		var sample := int(sin(local_t * freq * TAU) * 32767.0 * volume * env)
		data.encode_s16(i * 2, sample)
	return _wav_from_data(data)


func _noise_thud(duration: float, volume: float) -> AudioStreamWAV:
	var sample_count := maxi(1, int(SAMPLE_RATE * duration))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in sample_count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := clampf(1.0 - t / duration, 0.0, 1.0)
		env *= env
		var n := rng.randf_range(-1.0, 1.0)
		var boom := sin(t * 70.0 * TAU) * 0.7
		var sample := int((boom + n * 0.35) * 32767.0 * volume * env)
		data.encode_s16(i * 2, sample)
	return _wav_from_data(data)


func _noise_whoosh(duration: float, volume: float) -> AudioStreamWAV:
	var sample_count := maxi(1, int(SAMPLE_RATE * duration))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in sample_count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := sin((t / duration) * PI)
		var n := rng.randf_range(-1.0, 1.0)
		var sample := int(n * 32767.0 * volume * env * 0.55)
		data.encode_s16(i * 2, sample)
	return _wav_from_data(data)


func _ambient_bed(outdoor: bool) -> AudioStreamWAV:
	# Mid-range content so laptop speakers can hear it (old beds were ~110 Hz + -34 dB ≈ silent).
	var duration := 3.2
	var sample_count := maxi(1, int(SAMPLE_RATE * duration))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91 if outdoor else 113
	var lp := 0.0
	for i in sample_count:
		var t := float(i) / float(SAMPLE_RATE)
		var sig := 0.0
		if outdoor:
			# Rural: breeze + soft open fifth + occasional chirp.
			var noise := rng.randf_range(-1.0, 1.0)
			lp = lerpf(lp, noise, 0.04)
			sig += lp * 0.28
			sig += sin(t * 262.0 * TAU) * 0.10
			sig += sin(t * 392.0 * TAU) * 0.07
			sig += sin(t * 0.55 * TAU) * 0.05
			# Chirps near 0.7s and 2.1s in the loop.
			for chirp_at_variant in [0.7, 2.1]:
				var chirp_at: float = float(chirp_at_variant)
				var ct: float = t - chirp_at
				if ct >= 0.0 and ct < 0.12:
					var env: float = sin((ct / 0.12) * PI)
					var freq: float = lerpf(1400.0, 1900.0, ct / 0.12)
					sig += sin(ct * freq * TAU) * 0.16 * env
		else:
			# Quiet interior: warmer pad, less hiss, soft room pulse.
			var noise := rng.randf_range(-1.0, 1.0)
			lp = lerpf(lp, noise, 0.02)
			sig += lp * 0.10
			sig += sin(t * 196.0 * TAU) * 0.14
			sig += sin(t * 294.0 * TAU) * 0.09
			sig += sin(t * 0.35 * TAU) * 0.06
			# Soft wooden tick every ~1.05s.
			var tick_phase := fposmod(t, 1.05)
			if tick_phase < 0.03:
				var tenv := 1.0 - tick_phase / 0.03
				sig += rng.randf_range(-1.0, 1.0) * 0.12 * tenv * tenv
		var edge := 1.0
		var fade := 0.12
		if t < fade:
			edge = t / fade
		elif t > duration - fade:
			edge = (duration - t) / fade
		var sample := int(clampf(sig, -1.0, 1.0) * 32767.0 * 0.72 * edge)
		data.encode_s16(i * 2, sample)
	var stream := _wav_from_data(data)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


func _wav_from_data(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
