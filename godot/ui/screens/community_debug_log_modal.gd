extends Window

@onready var _body: TextEdit = %BodyText
@onready var _path_label: Label = %PathLabel
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	visible = false
	title = "Community Map Log"
	size = Vector2i(920, 640)
	close_requested.connect(hide)
	%CloseButton.pressed.connect(hide)
	%RefreshButton.pressed.connect(_refresh)
	if _body != null:
		_body.syntax_highlighter = null


func open_log() -> void:
	_refresh()
	popup_centered()


func _refresh() -> void:
	var text := ""
	var path := CommunityDebugLogService.latest_path()
	if Game.state != null:
		var live: Dictionary = CommunityDebugLogService.write_from_state(Game.state)
		if bool(live.get("ok", false)):
			path = str(live.get("path", path))
			text = CommunityDebugLogService.read_latest()
			_status_label.text = "Refreshed from active run (seed %d, turn %d)." % [
				Game.state.run_seed,
				Game.state.turn,
			]
		elif bool(live.get("skipped", false)):
			text = CommunityDebugLogService.read_latest()
			_status_label.text = "Active run has community generation off — showing last saved log."
		else:
			text = CommunityDebugLogService.read_latest()
			_status_label.text = str(live.get("error", "Could not build log from active run."))
	else:
		text = CommunityDebugLogService.read_latest()
		if text.is_empty():
			_status_label.text = "No log yet. Start a new Capital Farm / 2D run with community_generation enabled."
		else:
			_status_label.text = "Showing last saved community map log."

	if text.is_empty():
		text = "No community map log found.\n\nStart a new run with community_generation enabled in community_config.json, then open this viewer again."
		_path_label.text = "Expected: %s\n(%s)" % [path, CommunityDebugLogService.latest_filesystem_path()]
	else:
		_path_label.text = "File: %s\n(%s)" % [path, CommunityDebugLogService.latest_filesystem_path()]

	if _body != null:
		_body.text = text
		_body.set_caret_line(0)
