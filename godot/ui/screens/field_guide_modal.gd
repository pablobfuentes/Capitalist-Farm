extends Window

var _page: int = 0


func _ready() -> void:
	title = "Negotiation Field Guide"
	size = Vector2i(560, 420)
	close_requested.connect(hide)
	%PrevButton.pressed.connect(_on_prev)
	%NextButton.pressed.connect(_on_next)
	%CloseButton.pressed.connect(hide)


func open_guide(page: int = 0) -> void:
	_page = clampi(page, 0, FieldGuide.PAGES.size() - 1)
	_refresh()
	popup_centered()


func _refresh() -> void:
	var page: Dictionary = FieldGuide.PAGES[_page]
	%TitleLabel.text = str(page.get("title", ""))
	%SubtitleLabel.text = str(page.get("subtitle", ""))
	%BodyLabel.text = str(page.get("body", ""))
	%PageLabel.text = "Page %d / %d" % [_page + 1, FieldGuide.PAGES.size()]
	%PrevButton.disabled = _page <= 0
	%NextButton.disabled = _page >= FieldGuide.PAGES.size() - 1


func _on_prev() -> void:
	_page = maxi(0, _page - 1)
	_refresh()


func _on_next() -> void:
	_page = mini(FieldGuide.PAGES.size() - 1, _page + 1)
	_refresh()
