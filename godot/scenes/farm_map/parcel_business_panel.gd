extends PanelContainer

signal closed

const _Ownership := preload("res://core/systems/parcel_ownership_system.gd")

@onready var _title_label: Label = %TitleLabel
@onready var _role_label: Label = %RoleLabel
@onready var _details_label: Label = %DetailsLabel
@onready var _ownership_label: Label = %StubLabel
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_button.pressed.connect(_on_close_pressed)


func show_parcel(entry: Dictionary, district: Dictionary) -> void:
	if typeof(entry) != TYPE_DICTIONARY or entry.is_empty():
		hide_panel()
		return
	_title_label.text = str(entry.get("label", "Parcel"))
	_role_label.text = _format_role(str(entry.get("role", "")))
	_details_label.text = _build_details(entry, district)
	_apply_ownership(entry, district)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_locked_district(district_name: String, requirement: int, net_worth: int, can_unlock: bool) -> void:
	_title_label.text = district_name
	_role_label.text = "District locked"
	var lines: PackedStringArray = []
	lines.append("Reach net worth %s to unlock." % MathUtil.fmt_money(requirement))
	lines.append("Your net worth: %s" % MathUtil.fmt_money(net_worth))
	if can_unlock:
		lines.append("Requirement met — unlocking will happen automatically on next refresh.")
	else:
		lines.append("Keep growing portfolio value to access this district.")
	_details_label.text = "\n".join(lines)
	_ownership_label.text = "Locked · progress by net worth"
	_ownership_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88, 1.0))
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func hide_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_close_pressed() -> void:
	hide_panel()
	closed.emit()


func _apply_ownership(entry: Dictionary, district: Dictionary) -> void:
	var state: RunState = Game.state
	var resolved: Dictionary = _Ownership.resolve(state, entry, district)
	var owner_state := str(resolved.get("state", _Ownership.OWNER_NPC))
	var headline := str(resolved.get("headline", _Ownership.ownership_label(owner_state)))
	var detail := str(resolved.get("detail", ""))
	var lines: PackedStringArray = []
	lines.append("%s · %s" % [_Ownership.ownership_label(owner_state), headline])
	if not detail.is_empty():
		lines.append(detail)
	_ownership_label.text = "\n".join(lines)
	_ownership_label.add_theme_color_override(
		"font_color",
		_ownership_color(owner_state)
	)


func _ownership_color(owner_state: String) -> Color:
	match owner_state:
		_Ownership.OWNER_PLAYER:
			return Color(0.62, 0.92, 0.68, 1.0)
		_Ownership.OWNER_OPPORTUNITY:
			return Color(0.98, 0.84, 0.42, 1.0)
		_Ownership.OWNER_CONTESTED:
			return Color(0.98, 0.62, 0.48, 1.0)
		_Ownership.OWNER_VACANT:
			return Color(0.78, 0.82, 0.88, 1.0)
		_Ownership.OWNER_CIVIC:
			return Color(0.72, 0.80, 0.98, 1.0)
		_:
			return Color(0.82, 0.78, 0.72, 1.0)


func _format_role(role: String) -> String:
	match role:
		"core":
			return "Core business · Level 1 pad"
		"specialization":
			return "Specialization duplicate"
		"competitive":
			return "Competitive / rival slot"
		"premium":
			return "Premium opportunity"
		"development":
			return "Vacant · development lot"
		"civic":
			return "Civic / landmark"
		"plaza":
			return "District plaza"
		_:
			return role.capitalize()


func _build_details(entry: Dictionary, district: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("District: %s" % str(district.get("name", "Unknown")))
	lines.append("Parcel: (%d, %d)" % [int(entry.get("parcel_x", 0)), int(entry.get("parcel_y", 0))])
	var template_id := str(entry.get("template_id", ""))
	if not template_id.is_empty():
		var tmpl := Content.get_template(template_id)
		if tmpl != null:
			lines.append("Template: %s" % tmpl.name)
			lines.append("Layer: %s" % tmpl.layer_label)
		else:
			lines.append("Template: %s" % template_id)
	else:
		lines.append("Template: —")
	return "\n".join(lines)
