extends RefCounted

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")
const SettledFlow := preload("res://better_spewing/flow/settled_flow.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")

const PACKET_COUNT := 192
const SLEEPING_COUNT := 100
const DRAIN_Q := 16
const FP := 256


static func room_context(identifier: String) -> Dictionary:
	var cell_size: int = Tuning.VALUES.grid_cell_size_px
	return RoomOccupancy.build({
		"identifier": identifier,
		"solids": [
			Rect2(5 * cell_size, 5 * cell_size, 11 * cell_size, cell_size),
			Rect2(5 * cell_size, 15 * cell_size, 11 * cell_size, cell_size),
			Rect2(5 * cell_size, 6 * cell_size, cell_size, 9 * cell_size),
			Rect2(15 * cell_size, 6 * cell_size, cell_size, 9 * cell_size),
		],
	})


static func build_stress_runner() -> Dictionary:
	var room := room_context("package-2c-stress")
	var state := _base_state()
	var runner := Runner.new(state, room)
	var active_ids: Array = []
	for y in _height():
		for x in _width():
			var cell_id := _id(x, y)
			if RoomOccupancy.is_solid(room, x, y):
				continue
			if x % 2 == 1 or (y >= 12 and y % 2 == 0):
				runner.state.settled_cells[cell_id] = Tuning.VALUES.cell_capacity_q
			if (
				y >= 12
				and y % 2 == 0
				and x % 2 == 0
				and not _inside_packet_enclosure(x, y)
			):
				active_ids.append(cell_id)

	var impact := _id(10, 10)
	for y in range(6, 15):
		for x in range(6, 15):
			if absi(x - 10) + absi(y - 10) <= 4:
				runner.state.settled_cells[_id(x, y)] = Tuning.VALUES.cell_capacity_q

	var active_seen := {}
	for cell_id in active_ids:
		active_seen[cell_id] = true
	for y in range(9, _height()):
		for x in _width():
			if active_ids.size() >= Tuning.VALUES.maximum_active_cells_per_tick:
				break
			var cell_id := _id(x, y)
			if (
				not active_seen.has(cell_id)
				and not RoomOccupancy.is_solid(room, x, y)
				and not _inside_packet_enclosure(x, y)
			):
				active_ids.append(cell_id)
				active_seen[cell_id] = true
		if active_ids.size() >= Tuning.VALUES.maximum_active_cells_per_tick:
			break
	SettledFlow.activate_cells(runner.state, active_ids)

	var sleeping := 0
	for cell_id in 8 * _width():
		if sleeping >= SLEEPING_COUNT:
			break
		if runner.state.settled_cells[cell_id] > 0 and not active_seen.has(cell_id):
			runner.state.cell_stable_counters[cell_id] = Tuning.VALUES.sleep_threshold_processed_ticks
			sleeping += 1

	var cell_size_fp := Tuning.VALUES.grid_cell_size_px * FP
	for packet_index in PACKET_COUNT:
		var packet := Schema.default_packet()
		packet.id = packet_index + 1
		packet.impact_cell_id = impact
		packet.impact_normal_x = -1
		packet.position_x_fp = 10 * cell_size_fp + cell_size_fp / 2
		packet.position_y_fp = 10 * cell_size_fp + cell_size_fp / 2
		packet.volume_q = 1
		packet.lifetime_ticks = Tuning.VALUES.packet_lifetime_ticks
		packet.lifecycle = Contracts.PacketLifecycle.STATIONARY_DEPOSITION
		packet.stationary_ticks = 1
		runner.state.packets.append(packet)
	runner.state.next_ids.packet = PACKET_COUNT + 1
	runner.state.drain_queue = [{
		"id": 1,
		"amount_q": DRAIN_Q,
		"return_tick": 0,
		"lifecycle": Contracts.DrainLifecycle.DELAYED,
	}]
	runner.state.next_ids.drain_record = 2
	runner.state.ledger.settled = _sum(runner.state.settled_cells)
	runner.state.ledger.airborne = PACKET_COUNT
	runner.state.ledger.drain = DRAIN_Q
	runner.state.ledger.initial = Contracts.ledger_total(runner.state.ledger)
	return {
		"runner": runner,
		"room": room,
		"template": runner.state.duplicate(true),
	}


static func build_normal_runner() -> Dictionary:
	var room := room_context("package-2c-normal")
	var runner := Runner.new(_base_state(), room)
	for record in [
		{"id": _id(46, 18), "q": 16},
		{"id": _id(47, 18), "q": 16},
		{"id": _id(48, 18), "q": 16},
	]:
		runner.state.settled_cells[record.id] = record.q
		runner.state.ledger.reserve -= record.q
		runner.state.ledger.settled += record.q
		SettledFlow.activate_cell_and_neighbors(runner.state, room, record.id)
	return {"runner": runner, "room": room}


static func no_action_frame(state: Dictionary) -> Dictionary:
	return {
		"tick": state.tick,
		"move_x": 0,
		"move_y": 0,
		"jump_pressed": false,
		"goo_action": Contracts.GooAction.NONE,
		"aim_angle": 0,
		"asserted_mouth_x_fp": state.player.position_x_fp,
		"asserted_mouth_y_fp": state.player.position_y_fp + 3 * FP,
	}


static func stress_lane_report(step_result: Dictionary, state: Dictionary) -> Dictionary:
	var flow: Dictionary = step_result.simulation.flow
	return {
		"packet_count": state.packets.size(),
		"airborne_q": state.ledger.airborne,
		"selected_cells": flow.selected.size(),
		"lateral_pairs": flow.phase_b_pairs_scanned,
		"drain_q": state.ledger.drain,
		"reserve_q": state.ledger.reserve,
		"sleeping_cells": _sleeping_cells(state),
		"active_after": state.active_queue.size(),
		"settled_q": state.ledger.settled,
		"category_error": _sum(state.settled_cells) - state.ledger.settled,
		"ledger_error": state.ledger.initial - Contracts.ledger_total(state.ledger),
		"canonical": Serializer.serialize_state_checked(state).ok,
	}


static func stress_lanes_reached(report: Dictionary) -> bool:
	return (
		report.packet_count == PACKET_COUNT
		and report.airborne_q == PACKET_COUNT
		and report.selected_cells == Tuning.VALUES.maximum_active_cells_per_tick
		and report.lateral_pairs == Tuning.VALUES.maximum_lateral_pairs_per_tick
		and report.drain_q == DRAIN_Q
		and report.reserve_q == Tuning.VALUES.reserve_capacity_q
		and report.sleeping_cells >= SLEEPING_COUNT
		and report.category_error == 0
		and report.ledger_error == 0
		and report.canonical
	)


static func _base_state() -> Dictionary:
	var state := Schema.default_state()
	state.ledger.reserve = Tuning.VALUES.reserve_capacity_q
	state.ledger.initial = Tuning.VALUES.reserve_capacity_q
	return state


static func _sleeping_cells(state: Dictionary) -> int:
	var count := 0
	for counter in state.cell_stable_counters:
		if counter >= Tuning.VALUES.sleep_threshold_processed_ticks:
			count += 1
	return count


static func _sum(values: Array) -> int:
	var total := 0
	for value in values:
		total += value
	return total


static func _id(x: int, y: int) -> int:
	return y * _width() + x


static func _width() -> int:
	return Tuning.VALUES.grid_width_cells


static func _height() -> int:
	return Tuning.VALUES.grid_height_cells


static func _inside_packet_enclosure(x: int, y: int) -> bool:
	return x >= 5 and x <= 15 and y >= 5 and y <= 15
