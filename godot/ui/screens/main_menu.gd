extends Control

@onready var load_button: Button = %LoadButton

var _community_log_modal: Window = null


func _ready() -> void:
	load_button.disabled = not Game.has_save_file()
	_community_log_modal = preload("res://ui/screens/community_debug_log_modal.tscn").instantiate()
	add_child(_community_log_modal)


func _on_capital_farm_pressed() -> void:
	Game.start_new_run(GameMode.MODE_CAPITAL_FARM)
	Game.go_to_dashboard()


func _on_new_2d_run_pressed() -> void:
	Game.start_new_run(GameMode.MODE_2D_RUN)
	Game.go_to_iso_farm_map()


func _on_load_pressed() -> void:
	if Game.load_from_file():
		Game.go_to_active_run()


func _on_smoke_test_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/smoke_test.tscn")


func _on_community_log_pressed() -> void:
	if _community_log_modal != null:
		_community_log_modal.open_log()
