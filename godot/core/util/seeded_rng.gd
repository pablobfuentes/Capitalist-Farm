class_name SeededRng
extends RefCounted

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	set_rng_seed(seed_value)


func set_rng_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func randf_range(min_v: float, max_v: float) -> float:
	return _rng.randf_range(min_v, max_v)


func randf() -> float:
	return _rng.randf()


func randi_range(min_v: int, max_v: int) -> int:
	return _rng.randi_range(min_v, max_v)


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi() % arr.size()]
