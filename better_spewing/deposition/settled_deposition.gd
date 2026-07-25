extends RefCounted

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")

const GRID_CELL_COUNT := 96 * 54
const MEMBERSHIP_BYTES := (GRID_CELL_COUNT + 7) / 8


static func initialize_grid(state: Dictionary) -> String:
	var all_empty: bool = (
		state.settled_cells.is_empty()
		and state.active_queue.is_empty()
		and state.active_membership.is_empty()
		and state.cell_stable_counters.is_empty()
	)
	if all_empty:
		state.settled_cells.resize(GRID_CELL_COUNT)
		state.settled_cells.fill(0)
		state.active_membership.resize(MEMBERSHIP_BYTES)
		state.active_membership.fill(0)
		state.cell_stable_counters.resize(GRID_CELL_COUNT)
		state.cell_stable_counters.fill(0)
		return ""
	if state.settled_cells.size() != GRID_CELL_COUNT:
		return "settled grid must contain exactly %d row-major cells" % GRID_CELL_COUNT
	if state.cell_stable_counters.size() != GRID_CELL_COUNT:
		return "settled stable counters must contain exactly %d cells" % GRID_CELL_COUNT
	if state.active_membership.size() != MEMBERSHIP_BYTES:
		return "settled active membership must contain exactly %d bytes" % MEMBERSHIP_BYTES
	return ""


static func process_stationary_packets(state: Dictionary, context: Dictionary) -> Dictionary:
	var state_before: Dictionary = state.duplicate(true)
	var diagnostics: Array = []
	var remove_ids: Array[int] = []
	for packet in state.packets:
		if packet.lifecycle != Contracts.PacketLifecycle.STATIONARY_DEPOSITION:
			continue
		var derived := derive_candidate_diagnostics(state, context, packet.impact_cell_id, state.tick)
		if not derived.ok:
			state.clear()
			state.merge(state_before, true)
			return {"ok": false, "error": derived.error, "packets": []}
		var selected_id := -1
		for candidate in derived.candidates:
			if state.settled_cells[candidate.cell_id] < Tuning.VALUES.cell_capacity_q:
				selected_id = candidate.cell_id
				break
		var accepted := 0
		if selected_id >= 0:
			var capacity: int = Tuning.VALUES.cell_capacity_q - state.settled_cells[selected_id]
			accepted = mini(packet.volume_q, capacity)
			state.settled_cells[selected_id] += accepted
			state.ledger.airborne -= accepted
			state.ledger.settled += accepted
			packet.volume_q -= accepted
		var status := "blocked"
		if accepted > 0 and packet.volume_q > 0:
			status = "partial"
		elif accepted > 0:
			status = "complete"
		if packet.volume_q == 0:
			remove_ids.append(packet.id)
		else:
			packet.stationary_ticks = mini(packet.stationary_ticks + 1, 0xffff)
		diagnostics.append({
			"packet_id": packet.id,
			"candidate_ids": _candidate_ids(derived.candidates),
			"selected_cell_id": selected_id,
			"accepted_q": accepted,
			"remaining_q": packet.volume_q,
			"status": status,
		})
	for packet_id in remove_ids:
		for index in state.packets.size():
			if state.packets[index].id == packet_id:
				state.packets.remove_at(index)
				break
	return {"ok": true, "error": "", "packets": diagnostics}


static func derive_candidate_diagnostics(
	state: Dictionary,
	context: Dictionary,
	impact_cell_id: int,
	tick: int
) -> Dictionary:
	if impact_cell_id < 0 or impact_cell_id >= GRID_CELL_COUNT:
		return {"ok": false, "error": "impact cell is outside canonical grid", "candidates": []}
	var impact := Vector2i(
		impact_cell_id % Tuning.VALUES.grid_width_cells,
		impact_cell_id / Tuning.VALUES.grid_width_cells
	)
	if RoomOccupancy.is_solid(context, impact.x, impact.y):
		return {"ok": false, "error": "impact cell cannot be solid", "candidates": []}
	var queue: Array[Vector2i] = [impact]
	var visited := {impact_cell_id: true}
	var eligible: Array = []
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var cell_id: int = cell.y * Tuning.VALUES.grid_width_cells + cell.x
		eligible.append(_candidate_record(state, context, impact, cell, cell_id, tick))
		for offset in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var neighbor: Vector2i = cell + offset
			if neighbor.x < 0 or neighbor.y < 0 \
					or neighbor.x >= Tuning.VALUES.grid_width_cells \
					or neighbor.y >= Tuning.VALUES.grid_height_cells:
				continue
			if absi(neighbor.x - impact.x) + absi(neighbor.y - impact.y) > Tuning.VALUES.deposition_search_radius_cells:
				continue
			var neighbor_id: int = neighbor.y * Tuning.VALUES.grid_width_cells + neighbor.x
			if visited.has(neighbor_id) or RoomOccupancy.is_solid(context, neighbor.x, neighbor.y):
				continue
			visited[neighbor_id] = true
			queue.append(neighbor)
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _candidate_less(a, b))
	return {"ok": true, "error": "", "candidates": eligible}


static func _candidate_record(
	state: Dictionary,
	context: Dictionary,
	impact: Vector2i,
	cell: Vector2i,
	cell_id: int,
	tick: int
) -> Dictionary:
	var delta := cell - impact
	var direction_rank := 1
	if delta.y > 0:
		direction_rank = 0
	elif delta.y < 0:
		direction_rank = 2
	var lateral_rank := 0
	if delta.y == 0 and delta.x != 0:
		var is_left := delta.x < 0
		lateral_rank = 0 if is_left == (tick % 2 == 0) else 1
	return {
		"cell_id": cell_id,
		"x": cell.x,
		"y": cell.y,
		"distance": absi(delta.x) + absi(delta.y),
		"supported": _is_supported(state, context, cell),
		"direction_rank": direction_rank,
		"lateral_rank": lateral_rank,
		"volume_q": state.settled_cells[cell_id],
		"capacity_q": Tuning.VALUES.cell_capacity_q - state.settled_cells[cell_id],
	}


static func _candidate_less(a: Dictionary, b: Dictionary) -> bool:
	if a.distance != b.distance:
		return a.distance < b.distance
	if a.supported != b.supported:
		return a.supported
	if a.direction_rank != b.direction_rank:
		return a.direction_rank < b.direction_rank
	if a.direction_rank == 1 and a.lateral_rank != b.lateral_rank:
		return a.lateral_rank < b.lateral_rank
	return a.cell_id < b.cell_id


static func _is_supported(state: Dictionary, context: Dictionary, cell: Vector2i) -> bool:
	var below_y := cell.y + 1
	if below_y >= Tuning.VALUES.grid_height_cells:
		return true
	if RoomOccupancy.is_solid(context, cell.x, below_y):
		return true
	var below_id := below_y * Tuning.VALUES.grid_width_cells + cell.x
	return state.settled_cells[below_id] >= Tuning.VALUES.cell_capacity_q


static func _candidate_ids(candidates: Array) -> Array[int]:
	var result: Array[int] = []
	for candidate in candidates:
		result.append(candidate.cell_id)
	return result
