extends PanelContainer

signal prev_pressed
signal next_pressed
signal pause_toggled(paused: bool)
signal controls_hover_changed(hovered: bool)

@onready var _label: Label = %PathLabel
@onready var _prev: Button = %PrevButton
@onready var _pause: Button = %PauseButton
@onready var _next: Button = %NextButton

var _paused := false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_prev.pressed.connect(func() -> void: prev_pressed.emit())
	_next.pressed.connect(func() -> void: next_pressed.emit())
	_pause.pressed.connect(_on_pause_pressed)
	FeedbackBus.wire_button(_prev)
	FeedbackBus.wire_button(_pause)
	FeedbackBus.wire_button(_next)
	mouse_entered.connect(func() -> void: controls_hover_changed.emit(true))
	mouse_exited.connect(func() -> void: controls_hover_changed.emit(false))


func set_path_info(index: int, total: int, paused: bool = false) -> void:
	_paused = paused
	if total <= 1:
		visible = false
		return
	visible = true
	var safe_index := clampi(index, 0, maxi(total - 1, 0))
	_label.text = "Path %d of %d" % [safe_index + 1, total]
	_pause.text = "Resume" if _paused else "Pause"
	_prev.disabled = total <= 1
	_next.disabled = total <= 1


func hide_controls() -> void:
	visible = false
	_paused = false


func _on_pause_pressed() -> void:
	_paused = not _paused
	_pause.text = "Resume" if _paused else "Pause"
	pause_toggled.emit(_paused)
