extends RefCounted

const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")

static func activate_cells(state: Dictionary, cell_ids: Array) -> void:
	var additions: Array[int] = []
	var pending := {}
	for value in cell_ids:
		var cell_id: int = value
		if cell_id < 0 or cell_id >= _cell_count():
			continue
		if _membership_get(state.active_membership, cell_id) or pending.has(cell_id):
			continue
		pending[cell_id] = true
		additions.append(cell_id)
	additions.sort()
	for cell_id in additions:
		state.active_queue.append(cell_id)
		_membership_set(state.active_membership, cell_id, true)


static func activate_cell_and_neighbors(
	state: Dictionary,
	context: Dictionary,
	cell_id: int,
	include_empty_self: bool = true
) -> void:
	var ids: Array = []
	if include_empty_self or state.settled_cells[cell_id] > 0:
		ids.append(cell_id)
	for neighbor_id in _orthogonal_neighbors(cell_id):
		if not _is_solid_id(context, neighbor_id):
			ids.append(neighbor_id)
	for active_id in ids:
		state.cell_stable_counters[active_id] = 0
	activate_cells(state, ids)


static func step(state: Dictionary, context: Dictionary) -> Dictionary:
	var state_before := state.duplicate(true)
	var validation_error := _validate_runtime_inputs(state, context)
	if not validation_error.is_empty():
		return {"ok": false, "error": validation_error}

	var tick_start: Array = state.settled_cells.duplicate()
	var selected: Array[int] = []
	var selected_set := {}
	var selection_count := mini(
		state.active_queue.size(),
		Tuning.VALUES.maximum_active_cells_per_tick
	)
	for unused in selection_count:
		var cell_id: int = state.active_queue.pop_front()
		_membership_set(state.active_membership, cell_id, false)
		selected.append(cell_id)
		selected_set[cell_id] = true

	var phase_a := _phase_a(state, context, selected, tick_start)
	var phase_b := _phase_b(
		state,
		context,
		selected_set,
		phase_a.changed,
		state.tick
	)
	var changed_final: Array[int] = []
	for cell_id in _cell_count():
		if state.settled_cells[cell_id] != tick_start[cell_id]:
			changed_final.append(cell_id)
			state.cell_stable_counters[cell_id] = 0

	var wake_ids: Array = []
	for cell_id in changed_final:
		for neighbor_id in _orthogonal_neighbors(cell_id):
			if not _is_solid_id(context, neighbor_id):
				wake_ids.append(neighbor_id)
				state.cell_stable_counters[neighbor_id] = 0

	var sleeping: Array[int] = []
	for cell_id in selected:
		if state.settled_cells[cell_id] == 0:
			state.cell_stable_counters[cell_id] = 0
			continue
		if state.settled_cells[cell_id] != tick_start[cell_id]:
			continue
		state.cell_stable_counters[cell_id] = mini(
			state.cell_stable_counters[cell_id] + 1,
			Tuning.VALUES.sleep_threshold_processed_ticks
		)
		if state.cell_stable_counters[cell_id] \
				>= Tuning.VALUES.sleep_threshold_processed_ticks:
			sleeping.append(cell_id)

	var reschedule: Array = []
	for cell_id in changed_final:
		if state.settled_cells[cell_id] > 0:
			reschedule.append(cell_id)
	for cell_id in selected:
		if state.settled_cells[cell_id] > 0 \
				and state.cell_stable_counters[cell_id] \
				< Tuning.VALUES.sleep_threshold_processed_ticks:
			reschedule.append(cell_id)
	reschedule.append_array(wake_ids)
	activate_cells(state, reschedule)

	var settled_sum := _sum_cells(state.settled_cells)
	if settled_sum != state.ledger.settled:
		state.clear()
		state.merge(state_before, true)
		return {
			"ok": false,
			"error": "settled flow category mismatch: cells=%d ledger=%d" % [
				settled_sum, state.ledger.settled
			],
		}
	return {
		"ok": true,
		"error": "",
		"selected": selected,
		"phase_a_moves": phase_a.moves,
		"phase_a_claimed": phase_a.claimed,
		"phase_b_pairs_scanned": phase_b.pairs_scanned,
		"phase_b_pairs_processed": phase_b.processed_pairs,
		"phase_b_moves": phase_b.moves,
		"changed": changed_final,
		"sleeping": sleeping,
		"queued_after": state.active_queue.size(),
		"settled_sum_q": settled_sum,
	}


static func run_lateral_phase_for_validation(
	state: Dictionary,
	context: Dictionary,
	related_ids: Array,
	tick: int
) -> Dictionary:
	# Isolated validation entrypoint for the independently bounded Phase B work
	# budget. Production ticks derive this set only from selection and Phase A.
	var related := {}
	for cell_id in related_ids:
		related[cell_id] = true
	return _phase_b(state, context, related, {}, tick)


static func _phase_a(
	state: Dictionary,
	context: Dictionary,
	selected: Array[int],
	snapshot: Array
) -> Dictionary:
	var ordered := selected.duplicate()
	var width := _width()
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var ay := a / width
		var by := b / width
		return ay > by if ay != by else (a % width) < (b % width)
	)
	var delta: Array = []
	delta.resize(_cell_count())
	delta.fill(0)
	var claimed := {}
	var changed := {}
	var moves: Array = []
	for cell_id in ordered:
		var volume: int = snapshot[cell_id]
		if volume == 0:
			continue
		var y: int = cell_id / width
		if y + 1 >= _height():
			continue
		var below: int = cell_id + width
		if _is_solid_id(context, below) or claimed.has(below):
			continue
		var free: int = Tuning.VALUES.cell_capacity_q - snapshot[below]
		var amount := mini(
			volume,
			mini(free, Tuning.VALUES.fall_transfer_q_per_tick)
		)
		if amount <= 0:
			continue
		delta[cell_id] -= amount
		delta[below] += amount
		claimed[below] = true
		changed[cell_id] = true
		changed[below] = true
		moves.append({"source": cell_id, "target": below, "amount_q": amount})
	for cell_id in _cell_count():
		if delta[cell_id] != 0:
			state.settled_cells[cell_id] += delta[cell_id]
	return {
		"changed": changed,
		"moves": moves,
		"claimed": _sorted_keys(claimed),
	}


static func _phase_b(
	state: Dictionary,
	context: Dictionary,
	selected: Dictionary,
	changed_a: Dictionary,
	tick: int
) -> Dictionary:
	var width := _width()
	var height := _height()
	var snapshot: Array = state.settled_cells.duplicate()
	var delta: Array = []
	delta.resize(_cell_count())
	delta.fill(0)
	var pair_start := tick % 2
	var scanned := 0
	var processed_pairs: Array = []
	var moves: Array = []
	for y_offset in height:
		var y := height - 1 - y_offset
		var x := pair_start
		while x < width - 1:
			var left := y * width + x
			var right := left + 1
			x += 2
			if _is_solid_id(context, left) or _is_solid_id(context, right):
				continue
			if not selected.has(left) and not selected.has(right) \
					and not changed_a.has(left) and not changed_a.has(right):
				continue
			if not _is_supported(snapshot, context, left) \
					and not _is_supported(snapshot, context, right):
				continue
			if scanned >= Tuning.VALUES.maximum_lateral_pairs_per_tick:
				break
			scanned += 1
			processed_pairs.append({"left": left, "right": right})
			var difference: int = snapshot[left] - snapshot[right]
			if absi(difference) <= 1:
				continue
			var amount := mini(
				absi(difference) / 2,
				Tuning.VALUES.lateral_transfer_q_per_tick
			)
			if difference > 1:
				delta[left] -= amount
				delta[right] += amount
				moves.append({"source": left, "target": right, "amount_q": amount})
			else:
				delta[right] -= amount
				delta[left] += amount
				moves.append({"source": right, "target": left, "amount_q": amount})
		if scanned >= Tuning.VALUES.maximum_lateral_pairs_per_tick:
			break
	for cell_id in _cell_count():
		if delta[cell_id] != 0:
			state.settled_cells[cell_id] += delta[cell_id]
	return {
		"pairs_scanned": scanned,
		"processed_pairs": processed_pairs,
		"moves": moves,
	}


static func _is_supported(snapshot: Array, context: Dictionary, cell_id: int) -> bool:
	var width := _width()
	var y := cell_id / width
	if y + 1 >= _height():
		return true
	var below := cell_id + width
	return _is_solid_id(context, below) \
		or snapshot[below] >= Tuning.VALUES.cell_capacity_q


static func _orthogonal_neighbors(cell_id: int) -> Array[int]:
	var width := _width()
	var height := _height()
	var x := cell_id % width
	var y := cell_id / width
	var result: Array[int] = []
	if y > 0:
		result.append(cell_id - width)
	if x > 0:
		result.append(cell_id - 1)
	if x + 1 < width:
		result.append(cell_id + 1)
	if y + 1 < height:
		result.append(cell_id + width)
	return result


static func _is_solid_id(context: Dictionary, cell_id: int) -> bool:
	return RoomOccupancy.is_solid(
		context,
		cell_id % _width(),
		cell_id / _width()
	)


static func _membership_get(bytes: PackedByteArray, cell_id: int) -> bool:
	return (bytes[cell_id / 8] & (1 << (cell_id % 8))) != 0


static func _membership_set(bytes: PackedByteArray, cell_id: int, value: bool) -> void:
	var byte_index := cell_id / 8
	var mask := 1 << (cell_id % 8)
	if value:
		bytes[byte_index] |= mask
	else:
		bytes[byte_index] &= ~mask


static func _validate_runtime_inputs(state: Dictionary, context: Dictionary) -> String:
	var cell_count := _cell_count()
	if state.settled_cells.size() != cell_count \
			or state.cell_stable_counters.size() != cell_count \
			or state.active_membership.size() != (cell_count + 7) / 8:
		return "settled flow requires initialized canonical grid state"
	if context.is_empty():
		return "settled flow requires immutable room occupancy"
	var queued := {}
	for cell_id in state.active_queue:
		if cell_id < 0 or cell_id >= cell_count or queued.has(cell_id):
			return "settled flow active FIFO is malformed"
		if _is_solid_id(context, cell_id):
			return "solid cell cannot enter settled flow scheduling"
		queued[cell_id] = true
	for cell_id in cell_count:
		var member := _membership_get(state.active_membership, cell_id)
		if member != queued.has(cell_id):
			return "settled flow membership does not mirror FIFO"
		if _is_solid_id(context, cell_id) and (
			state.settled_cells[cell_id] != 0
			or state.cell_stable_counters[cell_id] != 0
		):
			return "solid cell cannot carry settled authority"
	return ""


static func _sum_cells(cells: Array) -> int:
	var total := 0
	for volume in cells:
		total += volume
	return total


static func _width() -> int:
	return Tuning.VALUES.grid_width_cells


static func _height() -> int:
	return Tuning.VALUES.grid_height_cells


static func _cell_count() -> int:
	return _width() * _height()


static func _sorted_keys(values: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(value)
	result.sort()
	return result
