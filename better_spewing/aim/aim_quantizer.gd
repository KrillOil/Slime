extends RefCounted

const AimTable := preload("res://better_spewing/aim/aim_table.gd")
const MIN_CURSOR_DISTANCE_FP := 8 * 256


static func wrap_index(index: int) -> int:
	return posmod(index, AimTable.ENTRY_COUNT)


static func quantize_vector(delta_x: int, delta_y: int, entries: Array[Vector2i]) -> int:
	if delta_x == 0 and delta_y == 0:
		return 0
	var best_index := 0
	var best_dot := -0x7fffffffffffffff
	for index in entries.size():
		var direction := entries[index]
		var dot := delta_x * direction.x + delta_y * direction.y
		if dot > best_dot:
			best_dot = dot
			best_index = index
	return best_index


static func resolve(
	cursor_x_fp: int,
	cursor_y_fp: int,
	mouth: Vector2i,
	has_last_valid_aim: bool,
	last_valid_aim: int,
	facing: int,
	entries: Array[Vector2i]
) -> int:
	var delta_x := cursor_x_fp - mouth.x
	var delta_y := cursor_y_fp - mouth.y
	var distance_squared := delta_x * delta_x + delta_y * delta_y
	if distance_squared < MIN_CURSOR_DISTANCE_FP * MIN_CURSOR_DISTANCE_FP:
		if has_last_valid_aim:
			return wrap_index(last_valid_aim)
		return 0 if facing >= 0 else 2048
	return quantize_vector(delta_x, delta_y, entries)
