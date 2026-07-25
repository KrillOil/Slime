extends RefCounted

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")
const SettledFlow := preload("res://better_spewing/flow/settled_flow.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")

const WIDTH := 96
const HEIGHT := 54
const CELL_COUNT := WIDTH * HEIGHT
const PACKET_COUNT := 192
const ACTIVE_COUNT := 1536
const SLEEPING_COUNT := 100
const DRAIN_Q := 16
const FP := 256


static func room_context(identifier: String) -> Dictionary:
	return RoomOccupancy.build({"identifier": identifier, "solids": []})


static func build_stress_runner() -> Dictionary:
	var room := room_context("package-2c-stress")
	var state := _base_state()
	var runner := Runner.new(state, room)
	var active_ids: Array = []
	for y in HEIGHT:
		for x in WIDTH:
			var cell_id := _id(x, y)
			if x % 2 == 1:
				runner.state.settled_cells[cell_id] = 16
			elif y >= 12 and y % 2 == 0:
				runner.state.settled_cells[cell_id] = 16
				active_ids.append(cell_id)

	var impact := _id(10, 10)
	for y in range(6, 15):
		for x in range(6, 15):
			if absi(x - 10) + absi(y - 10) <= 4:
				runner.state.settled_cells[_id(x, y)] = 16

	var active_seen := {}
	for cell_id in active_ids:
		active_seen[cell_id] = true
	for y in range(9, HEIGHT):
		for x in WIDTH:
			if active_ids.size() >= ACTIVE_COUNT:
				break
			var cell_id := _id(x, y)
			if not active_seen.has(cell_id):
				active_ids.append(cell_id)
				active_seen[cell_id] = true
		if active_ids.size() >= ACTIVE_COUNT:
			break
	SettledFlow.activate_cells(runner.state, active_ids)

	var sleeping := 0
	for cell_id in 8 * WIDTH:
		if sleeping >= SLEEPING_COUNT:
			break
		if runner.state.settled_cells[cell_id] > 0 and not active_seen.has(cell_id):
			runner.state.cell_stable_counters[cell_id] = 12
			sleeping += 1

	for packet_index in PACKET_COUNT:
		var packet := Schema.default_packet()
		packet.id = packet_index + 1
		packet.impact_cell_id = impact
		packet.impact_normal_x = -1
		packet.position_x_fp = 105 * FP
		packet.position_y_fp = 105 * FP
		packet.volume_q = 1
		packet.lifetime_ticks = 90
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
		and report.selected_cells == ACTIVE_COUNT
		and report.lateral_pairs == 2048
		and report.drain_q == DRAIN_Q
		and report.reserve_q == 1600
		and report.sleeping_cells >= SLEEPING_COUNT
		and report.category_error == 0
		and report.ledger_error == 0
		and report.canonical
	)


static func _base_state() -> Dictionary:
	var state := Schema.default_state()
	state.ledger.reserve = 1600
	state.ledger.initial = 1600
	return state


static func _sleeping_cells(state: Dictionary) -> int:
	var count := 0
	for counter in state.cell_stable_counters:
		if counter >= 12:
			count += 1
	return count


static func _sum(values: Array) -> int:
	var total := 0
	for value in values:
		total += value
	return total


static func _id(x: int, y: int) -> int:
	return y * WIDTH + x
