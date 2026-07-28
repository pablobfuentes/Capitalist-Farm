extends Window

@onready var diagram: Control = %Diagram
@onready var detail_label: Label = %DetailLabel


func _ready() -> void:
	visible = false
	title = "Supply Chain Diagram"
	size = Vector2i(920, 680)
	close_requested.connect(hide)
	%CloseButton.pressed.connect(hide)


func open_view() -> void:
	_refresh()
	popup_centered()


func _refresh() -> void:
	if Game.state == null:
		detail_label.text = "No active run."
		return
	diagram.queue_redraw()
	var lines: PackedStringArray = []
	if Game.state.is_capital_farm():
		var synergies: Array = SynergySystem.compute_synergies(Game.state)
		for syn_variant in synergies:
			if typeof(syn_variant) != TYPE_DICTIONARY:
				continue
			var syn: Dictionary = syn_variant
			var fulfill: float = float(syn.get("fulfillRatio", 1.0))
			var status := "OK" if fulfill >= 0.99 and not bool(syn.get("capacityStrained", false)) else "STRAINED/PARTIAL"
			lines.append("%s · fulfill %.0f%% · %s" % [str(syn.get("label", "")), fulfill * 100.0, status])
	detail_label.text = "\n".join(lines) if not lines.is_empty() else "Acquire linked businesses to see active connections."
