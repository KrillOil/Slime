class_name GooGrid
extends Node2D

const CELL_SIZE := 20.0
const GRID_WIDTH := 48
const GRID_HEIGHT := 27
const CELL_CAPACITY := 5.0
const GULP_RADIUS := 86.0

var wetness: Array[float] = []


func _init() -> void:
	wetness.resize(GRID_WIDTH * GRID_HEIGHT)
	wetness.fill(0.0)


func _ready() -> void:
	add_to_group("goo_grid")


func spew(origin: Vector2, aim_direction: Vector2, requested_amount: float) -> float:
	var direction := aim_direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var perpendicular := Vector2(-direction.y, direction.x)
	var targets: Array[Vector2] = [
		origin + direction * 28.0,
		origin + direction * 46.0,
		origin + direction * 62.0,
		origin + direction * 46.0 + perpendicular * 14.0,
		origin + direction * 46.0 - perpendicular * 14.0,
	]
	var remaining := requested_amount
	var deposited := 0.0
	for target in targets:
		if remaining <= 0.0:
			break
		var cell := world_to_cell(target)
		if not is_cell_valid(cell):
			continue
		var index := cell_index(cell)
		var room := (1.0 - wetness[index]) * CELL_CAPACITY
		var portion := minf(remaining, minf(requested_amount / float(targets.size()), room))
		wetness[index] += portion / CELL_CAPACITY
		remaining -= portion
		deposited += portion
	if deposited > 0.0:
		queue_redraw()
	return deposited


func gulp(origin: Vector2, requested_amount: float) -> float:
	var remaining := requested_amount
	var recovered := 0.0
	var center := world_to_cell(origin)
	var radius_cells := ceili(GULP_RADIUS / CELL_SIZE)
	for y in range(center.y - radius_cells, center.y + radius_cells + 1):
		for x in range(center.x - radius_cells, center.x + radius_cells + 1):
			if remaining <= 0.0:
				break
			var cell := Vector2i(x, y)
			if not is_cell_valid(cell):
				continue
			var cell_center := cell_to_world(cell)
			if cell_center.distance_to(origin) > GULP_RADIUS:
				continue
			var index := cell_index(cell)
			var available := wetness[index] * CELL_CAPACITY
			var removed := minf(available, remaining)
			wetness[index] -= removed / CELL_CAPACITY
			remaining -= removed
			recovered += removed
	if recovered > 0.0:
		queue_redraw()
	return recovered


func sample_wetness(origin: Vector2, radius: float) -> float:
	var total := 0.0
	var samples := 0
	var center := world_to_cell(origin)
	var radius_cells := ceili(radius / CELL_SIZE)
	for y in range(center.y - radius_cells, center.y + radius_cells + 1):
		for x in range(center.x - radius_cells, center.x + radius_cells + 1):
			var cell := Vector2i(x, y)
			if not is_cell_valid(cell):
				continue
			if cell_to_world(cell).distance_to(origin) <= radius:
				total += wetness[cell_index(cell)]
				samples += 1
	return total / float(maxi(samples, 1))


func clear_all() -> void:
	wetness.fill(0.0)
	queue_redraw()


func world_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL_SIZE + Vector2.ONE * CELL_SIZE * 0.5


func is_cell_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_WIDTH and cell.y >= 0 and cell.y < GRID_HEIGHT


func cell_index(cell: Vector2i) -> int:
	return cell.y * GRID_WIDTH + cell.x


func total_stored_goo() -> float:
	var total := 0.0
	for value in wetness:
		total += value * CELL_CAPACITY
	return total


func _draw() -> void:
	for y in GRID_HEIGHT:
		for x in GRID_WIDTH:
			var value := wetness[y * GRID_WIDTH + x]
			if value <= 0.005:
				continue
			var rect := Rect2(Vector2(x, y) * CELL_SIZE + Vector2.ONE, Vector2.ONE * (CELL_SIZE - 2.0))
			var color := Color(0.18, 0.82, 0.72, 0.22 + value * 0.68)
			draw_rect(rect, color, true)
			if value > 0.65:
				draw_circle(rect.position + Vector2(6, 5), 2.0, Color(0.72, 1.0, 0.92, 0.45))
