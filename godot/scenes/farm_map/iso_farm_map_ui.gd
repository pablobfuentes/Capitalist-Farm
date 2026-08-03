extends Control

## HUD passes clicks through except interactive widgets (TopBar, parcel panel when open).

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in get_children():
		if child is Control:
			var ctrl := child as Control
			if ctrl.name == "Hint" or ctrl.name == "ParcelBusinessPanel":
				ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			elif ctrl.name == "PortfolioSidebar":
				# Sidebar manages its own filter when collapsed vs expanded.
				pass
			else:
				# TopBar, AdvanceButton, and other chrome stay clickable.
				ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
