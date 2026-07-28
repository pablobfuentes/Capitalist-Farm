extends PanelContainer

signal expanded_toggled(expanded: bool)

@onready var _debrief_toggle: Button = %DebriefToggle
@onready var _debrief_body: VBoxContainer = %DebriefBody
@onready var _debrief_label: Label = %DebriefLabel
@onready var _debrief_summary: Label = %DebriefSummary


func _ready() -> void:
	_debrief_toggle.pressed.connect(_on_debrief_toggle_pressed)


func refresh(state: RunState) -> void:
	if state == null:
		return
	if state.last_advance_report.is_empty():
		show_empty_prompt()
		return

	var card: Dictionary = RunView.debrief_card(state)
	if card.is_empty():
		show_empty_prompt()
		return

	_debrief_toggle.visible = true
	_debrief_toggle.text = str(card.get("toggleText", ""))
	_debrief_body.visible = bool(card.get("expanded", false))
	_debrief_label.text = str(card.get("detailLine", ""))
	var summary: String = str(card.get("summary", ""))
	_debrief_summary.text = summary
	_debrief_summary.visible = not summary.is_empty()


func show_empty_prompt() -> void:
	_debrief_toggle.visible = false
	_debrief_body.visible = true
	_debrief_label.text = "Acquire your first business, then advance the turn."
	_debrief_summary.text = ""


func set_feedback(message: String) -> void:
	_debrief_label.text = message


func _on_debrief_toggle_pressed() -> void:
	var state: RunState = Game.state
	if state == null:
		return
	state.debrief_expanded = not state.debrief_expanded
	refresh(state)
	expanded_toggled.emit(state.debrief_expanded)
