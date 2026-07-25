extends RefCounted

const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")

const CELL_SIZE_FP := 10 * 256


static func sweep(start_fp: Vector2i, end_fp: Vector2i, tick: int, context: Dictionary) -> Dictionary:
	var start_cell := _cell_for_position(start_fp)
	if not _in_bounds(start_cell, context):
		return _result("invalid_start_bounds", start_fp, start_cell, Vector2i.ZERO, [start_cell])
	if RoomOccupancy.is_solid(context, start_cell.x, start_cell.y):
		return _result("invalid_start_solid", start_fp, start_cell, Vector2i.ZERO, [start_cell])
	var visited: Array[Vector2i] = [start_cell]
	var current := start_cell
	var delta := end_fp - start_fp
	if delta == Vector2i.ZERO:
		return _result("clear", end_fp, current, Vector2i.ZERO, visited)
	var step_x := signi(delta.x)
	var step_y := signi(delta.y)
	var abs_dx := absi(delta.x)
	var abs_dy := absi(delta.y)
	var maximum_steps: int = context.width_cells + context.height_cells + 4
	for unused in maximum_steps:
		var x_cross := _next_x_crossing(start_fp, current, step_x, abs_dx)
		var y_cross := _next_y_crossing(start_fp, current, step_y, abs_dy)
		var x_available: bool = step_x != 0 and x_cross.numerator <= x_cross.denominator
		var y_available: bool = step_y != 0 and y_cross.numerator <= y_cross.denominator
		if not x_available and not y_available:
			return _result("clear", end_fp, _cell_for_position(end_fp), Vector2i.ZERO, visited)
		var cross_vertical := false
		if x_available and not y_available:
			cross_vertical = true
		elif x_available and y_available:
			var comparison: int = x_cross.numerator * y_cross.denominator - y_cross.numerator * x_cross.denominator
			if comparison < 0:
				cross_vertical = true
			elif comparison == 0:
				cross_vertical = tick % 2 == 0
		var previous := current
		var contact := Vector2i.ZERO
		var normal := Vector2i.ZERO
		if cross_vertical:
			current.x += step_x
			contact = _point_at_fraction(start_fp, delta, x_cross.numerator, x_cross.denominator)
			contact.x = x_cross.boundary_fp
			normal = Vector2i(-step_x, 0)
		else:
			current.y += step_y
			contact = _point_at_fraction(start_fp, delta, y_cross.numerator, y_cross.denominator)
			contact.y = y_cross.boundary_fp
			normal = Vector2i(0, -step_y)
		visited.append(current)
		if not _in_bounds(current, context):
			var bounds_result := _result("bounds", contact, previous, normal, visited)
			bounds_result.exit_cell = current
			return bounds_result
		if RoomOccupancy.is_solid(context, current.x, current.y):
			var collision := _result("collision", contact, previous, normal, visited)
			collision.solid_cell = current
			collision.impact_cell_id = previous.y * context.width_cells + previous.x
			return collision
	return {
		"kind": "error",
		"error": "traversal step budget exhausted",
		"position_fp": start_fp,
		"contact_cell": start_cell,
		"normal": Vector2i.ZERO,
		"visited_cells": visited,
	}


static func line_of_sight(start_fp: Vector2i, end_fp: Vector2i, tick: int, context: Dictionary) -> Dictionary:
	var start_cell := _cell_for_position(start_fp)
	var end_cell := _cell_for_position(end_fp)
	if not _in_bounds(start_cell, context) or not _in_bounds(end_cell, context):
		return {"visible": false, "error": "line-of-sight endpoint is outside bounds", "visited_cells": []}
	if RoomOccupancy.is_solid(context, start_cell.x, start_cell.y):
		return {"visible": false, "error": "line-of-sight start is solid", "visited_cells": [start_cell]}
	if RoomOccupancy.is_solid(context, end_cell.x, end_cell.y):
		return {"visible": false, "error": "line-of-sight end is solid", "visited_cells": [start_cell, end_cell]}
	var trace := sweep(start_fp, end_fp, tick, context)
	return {
		"visible": trace.kind == "clear",
		"error": "" if trace.kind == "clear" else "line of sight blocked",
		"visited_cells": trace.visited_cells,
		"trace": trace,
	}


static func _next_x_crossing(start_fp: Vector2i, cell: Vector2i, step: int, absolute_delta: int) -> Dictionary:
	if step == 0:
		return {"numerator": 1, "denominator": 0, "boundary_fp": 0}
	var boundary := (cell.x + 1) * CELL_SIZE_FP if step > 0 else cell.x * CELL_SIZE_FP
	var numerator := boundary - start_fp.x if step > 0 else start_fp.x - boundary
	return {"numerator": numerator, "denominator": absolute_delta, "boundary_fp": boundary}


static func _next_y_crossing(start_fp: Vector2i, cell: Vector2i, step: int, absolute_delta: int) -> Dictionary:
	if step == 0:
		return {"numerator": 1, "denominator": 0, "boundary_fp": 0}
	var boundary := (cell.y + 1) * CELL_SIZE_FP if step > 0 else cell.y * CELL_SIZE_FP
	var numerator := boundary - start_fp.y if step > 0 else start_fp.y - boundary
	return {"numerator": numerator, "denominator": absolute_delta, "boundary_fp": boundary}


static func _point_at_fraction(start: Vector2i, delta: Vector2i, numerator: int, denominator: int) -> Vector2i:
	return Vector2i(
		start.x + _divide_trunc(delta.x * numerator, denominator),
		start.y + _divide_trunc(delta.y * numerator, denominator)
	)


static func _cell_for_position(position_fp: Vector2i) -> Vector2i:
	return Vector2i(_floor_div(position_fp.x, CELL_SIZE_FP), _floor_div(position_fp.y, CELL_SIZE_FP))


static func _in_bounds(cell: Vector2i, context: Dictionary) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < context.width_cells and cell.y < context.height_cells


static func _result(kind: String, position: Vector2i, contact_cell: Vector2i, normal: Vector2i, visited: Array[Vector2i]) -> Dictionary:
	return {
		"kind": kind,
		"error": "",
		"position_fp": position,
		"contact_cell": contact_cell,
		"normal": normal,
		"visited_cells": visited,
	}


static func _floor_div(value: int, divisor: int) -> int:
	if value >= 0:
		return value / divisor
	return -((-value + divisor - 1) / divisor)


static func _divide_trunc(numerator: int, denominator: int) -> int:
	if numerator >= 0:
		return numerator / denominator
	return -((-numerator) / denominator)
