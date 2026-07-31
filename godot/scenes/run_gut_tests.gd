extends Node

## Run all GUT tests from res://.gutconfig.json without using the GUT bottom panel.
## Editor: open this scene and press F6 (Run Current Scene).

const _CONFIG := "res://.gutconfig.json"


func _ready() -> void:
	var gut_config: Variant = load("res://addons/gut/gut_config.gd").new()
	var loaded: int = gut_config.load_options(_CONFIG)
	if loaded < 0:
		push_error("RunGutTests: failed to load %s" % _CONFIG)
		get_tree().quit(1)
		return

	if Engine.is_editor_hint():
		gut_config.options.should_exit = false
		gut_config.options.should_exit_on_success = false

	var runner: Node = load("res://addons/gut/gui/GutRunner.tscn").instantiate()
	add_child(runner)
	runner.set_gut_config(gut_config)
	runner.run_tests(true)
