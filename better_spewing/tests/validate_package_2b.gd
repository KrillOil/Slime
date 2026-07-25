extends SceneTree

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")
const Deposition := preload("res://better_spewing/deposition/settled_deposition.gd")
const Flow := preload("res://better_spewing/flow/settled_flow.gd")
const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p2b_fixture_factory.gd")

const WIDTH := 96
const HEIGHT := 54
const COUNT := WIDTH * HEIGHT
const CAPACITY := 16

var passed := 0
var failed := 0


func _init() -> void:
	_test_live_canonical_scheduling_contract()
	_test_deposition_activation_fifo()
	_test_vertical_snapshot_and_claim()
	_test_lateral_snapshot_support_and_parity()
	_test_sleep_and_neighbor_wake()
	_test_basin_and_mirror()
	_test_active_budget()
	_test_lateral_budget()
	_test_pool_rise_only_by_deposition()
	_test_replay_resume()
	_finish()


func _test_live_canonical_scheduling_contract() -> void:
	var state := _state()
	state.settled_cells[_id(10, 10)] = 5
	state.ledger.initial = 5
	state.ledger.settled = 5
	Flow.activate_cells(state, [_id(10, 10)])
	_check(Serializer.serialize_state_checked(state).ok, "live queue, membership, counters, and settled ledger serialize canonically")
	var member_bad := state.duplicate(true)
	member_bad.active_membership[_id(10, 10) / 8] = 0
	_check(not Serializer.serialize_state_checked(member_bad).ok, "validator rejects queue and membership mismatch")
	var stray_bad := state.duplicate(true)
	stray_bad.active_membership[0] |= 1
	_check(not Serializer.serialize_state_checked(stray_bad).ok, "validator rejects membership bit absent from FIFO")
	var duplicate_bad := state.duplicate(true)
	duplicate_bad.active_queue.append(_id(10, 10))
	_check(not Serializer.serialize_state_checked(duplicate_bad).ok, "validator rejects duplicate FIFO IDs")
	var counter_bad := state.duplicate(true)
	counter_bad.cell_stable_counters[_id(10, 10)] = 12
	_check(not Serializer.serialize_state_checked(counter_bad).ok, "validator rejects sleeping counter inside active FIFO")
	var empty_counter_bad := state.duplicate(true)
	empty_counter_bad.settled_cells[_id(10, 10)] = 0
	empty_counter_bad.ledger.settled = 0
	empty_counter_bad.ledger.initial = 0
	empty_counter_bad.cell_stable_counters[_id(10, 10)] = 1
	_check(not Serializer.serialize_state_checked(empty_counter_bad).ok, "validator rejects nonzero stability on an empty cell")
	var sum_bad := state.duplicate(true)
	sum_bad.ledger.settled += 1
	sum_bad.ledger.initial += 1
	_check(not Serializer.serialize_state_checked(sum_bad).ok, "validator rejects settled-cell/category disagreement")


func _test_deposition_activation_fifo() -> void:
	var room := _empty_room("p2b-deposition-activation")
	var state := _state()
	state.settled_cells[_id(20, 20)] = 1
	state.ledger.initial = 1
	state.ledger.settled = 1
	Flow.activate_cells(state, [_id(20, 20)])
	var packet := Schema.default_packet()
	packet.id = 1
	packet.volume_q = 4
	packet.lifecycle = Contracts.PacketLifecycle.STATIONARY_DEPOSITION
	packet.impact_cell_id = _id(10, 10)
	packet.impact_normal_x = -1
	state.packets = [packet]
	state.ledger.airborne = 4
	state.ledger.initial += 4
	var result := Deposition.process_stationary_packets(state, room)
	var expected_new := [_id(10, 9), _id(9, 10), _id(10, 10), _id(11, 10), _id(10, 11)]
	expected_new.sort()
	_check(result.ok and state.active_queue[0] == _id(20, 20), "new activation preserves existing FIFO prefix")
	_check(state.active_queue.slice(1) == expected_new, "initial deposition appends destination and non-solid orthogonal neighbors in ascending ID order")
	var queue_before: Array = state.active_queue.duplicate()
	Flow.activate_cells(state, expected_new)
	_check(state.active_queue == queue_before, "activation deduplicates without disturbing FIFO")


func _test_vertical_snapshot_and_claim() -> void:
	var room := _empty_room("p2b-vertical")
	var state := _state()
	var upper := _id(10, 10)
	var lower := _id(10, 11)
	state.settled_cells[upper] = 8
	state.settled_cells[lower] = 4
	_reconcile(state)
	Flow.activate_cells(state, [upper, lower])
	var result := Flow.step(state, room)
	_check(result.ok and state.settled_cells[upper] == 0 and state.settled_cells[lower] == 8 and state.settled_cells[_id(10, 12)] == 4, "Phase A uses tick-start snapshot and simultaneous deltas")
	_check(result.phase_a_moves[0].source == lower and result.phase_a_moves[1].source == upper, "vertical processing is descending y then ascending x")
	_check(result.phase_a_claimed == [_id(10, 11), _id(10, 12)], "vertical targets are explicitly and deterministically claimed")
	_check(_invariants(state), "vertical fall preserves capacity, SETTLED, and total ledger")
	var state_hash := Serializer.state_hash(state)
	result.phase_a_moves.clear()
	result.changed.clear()
	_check(Serializer.state_hash(state) == state_hash, "flow diagnostics are derived copies and cannot mutate authority")
	var cap_state := _state()
	var cap_source := _id(20, 10)
	var cap_target := _id(20, 11)
	cap_state.settled_cells[cap_source] = 16
	_reconcile(cap_state)
	Flow.activate_cells(cap_state, [cap_source])
	var cap_result := Flow.step(cap_state, room)
	_check(
		cap_result.ok
		and cap_state.settled_cells[cap_source] == 0
		and cap_state.settled_cells[cap_target] == 16
		and cap_result.phase_a_moves[0].amount_q == 16,
		"Phase A transfers the canonical 16q cap when source and free capacity permit"
	)


func _test_lateral_snapshot_support_and_parity() -> void:
	var floor_room := RoomOccupancy.build({
		"identifier": "p2b-lateral-floor",
		"solids": [Rect2(0, 210, 960, 10)],
	})
	var even := _state()
	even.tick = 0
	even.settled_cells[_id(10, 20)] = 16
	_reconcile(even)
	Flow.activate_cells(even, [_id(10, 20)])
	var even_result := Flow.step(even, floor_room)
	_check(even_result.ok and even.settled_cells[_id(10, 20)] == 12 and even.settled_cells[_id(11, 20)] == 4, "Phase B moves at most 4q from a fresh supported snapshot")
	var odd := _state()
	odd.tick = 1
	odd.settled_cells[_id(11, 20)] = 16
	_reconcile(odd)
	Flow.activate_cells(odd, [_id(11, 20)])
	var odd_result := Flow.step(odd, floor_room)
	_check(odd_result.ok and odd.settled_cells[_id(11, 20)] == 12 and odd.settled_cells[_id(12, 20)] == 4, "pair_start=tick%2 selects the odd non-overlapping pairing")
	var balanced := _state()
	balanced.settled_cells[_id(10, 20)] = 8
	balanced.settled_cells[_id(11, 20)] = 7
	_reconcile(balanced)
	Flow.activate_cells(balanced, [_id(10, 20)])
	Flow.step(balanced, floor_room)
	_check(balanced.settled_cells[_id(10, 20)] == 8 and balanced.settled_cells[_id(11, 20)] == 7, "one-quantum difference does not oscillate")


func _test_sleep_and_neighbor_wake() -> void:
	var room := RoomOccupancy.build({
		"identifier": "p2b-sleep",
		"solids": [
			Rect2(90, 200, 10, 20),
			Rect2(100, 210, 10, 10),
			Rect2(110, 200, 10, 20),
		],
	})
	var state := _state()
	var cell := _id(10, 20)
	state.settled_cells[cell] = 8
	_reconcile(state)
	Flow.activate_cells(state, [cell])
	var exact := true
	for processed_tick in 11:
		var result := Flow.step(state, room)
		exact = exact and result.ok \
			and state.cell_stable_counters[cell] == processed_tick + 1 \
			and state.active_queue.has(cell)
		state.tick += 1
	_check(exact, "unchanged nonempty cell remains scheduled through 11 processed stable ticks")
	var twelfth := Flow.step(state, room)
	_check(twelfth.ok and state.cell_stable_counters[cell] == 12 and not state.active_queue.has(cell), "cell sleeps exactly on its 12th unchanged processed tick")
	Flow.activate_cell_and_neighbors(state, room, _id(10, 19))
	_check(state.cell_stable_counters[cell] == 0 and state.active_queue.has(cell), "neighbor activation deterministically wakes and resets a sleeping cell")


func _test_basin_and_mirror() -> void:
	var room := RoomOccupancy.build({
		"identifier": "p2b-basin",
		"solids": [
			Rect2(300, 0, 10, 410),
			Rect2(390, 0, 10, 410),
			Rect2(300, 400, 100, 10),
		],
	})
	var left := _state()
	left.settled_cells[_id(33, 34)] = 16
	left.settled_cells[_id(34, 34)] = 16
	_reconcile(left)
	Flow.activate_cells(left, [_id(33, 34), _id(34, 34)])
	var right := _state()
	right.settled_cells[_id(36, 34)] = 16
	right.settled_cells[_id(35, 34)] = 16
	_reconcile(right)
	Flow.activate_cells(right, [_id(36, 34), _id(35, 34)])
	var all_ok := true
	for tick in 48:
		left.tick = tick
		right.tick = tick
		all_ok = all_ok and Flow.step(left, room).ok and Flow.step(right, room).ok
		all_ok = all_ok and _invariants(left) and _invariants(right)
	var mirrored := true
	for y in HEIGHT:
		for x in range(31, 39):
			mirrored = mirrored and left.settled_cells[_id(x, y)] == right.settled_cells[_id(69 - x, y)]
	_check(all_ok and _nonzero(left.settled_cells) > 1, "unsupported goo falls into a basin and settles with invariants at every tick")
	_check(mirrored, "mirrored inputs produce mirrored final pools under identical alternating parity")


func _test_active_budget() -> void:
	var state := _state()
	var ids: Array = []
	for cell_id in 1600:
		ids.append(cell_id)
	Flow.activate_cells(state, ids)
	var result := Flow.step(state, _empty_room("p2b-active-budget"))
	_check(result.ok and result.selected.size() == 1536, "active-cell selection is capped at exactly 1,536 FIFO IDs")
	_check(state.active_queue == ids.slice(1536), "unprocessed active IDs retain their original FIFO order")
	_check(_membership_matches(state), "budget delay preserves exact deduplicated membership without volume loss")


func _test_lateral_budget() -> void:
	var state := _state()
	var related: Array = []
	for y in HEIGHT:
		for x in WIDTH:
			var cell := _id(x, y)
			related.append(cell)
			state.settled_cells[cell] = 16 if y % 2 == 1 else (16 if x % 2 == 0 else 0)
	_reconcile(state)
	var before_sum := _sum(state.settled_cells)
	var result := Flow.run_lateral_phase_for_validation(state, _empty_room("p2b-pair-budget"), related, 0)
	_check(result.pairs_scanned == 2048, "lateral work stops at exactly 2,048 related supported pairs in scan order")
	var delayed := {}
	for pair in result.processed_pairs:
		delayed[pair.left] = true
		delayed[pair.right] = true
	var tail: Array = []
	for cell_id in related:
		if not delayed.has(cell_id):
			tail.append(cell_id)
	var delayed_result := Flow.run_lateral_phase_for_validation(
		state, _empty_room("p2b-pair-budget"), tail, 0
	)
	_check(delayed_result.pairs_scanned > 0 and delayed_result.pairs_scanned < 2048, "unprocessed scan-order tail remains eligible and is deterministically delayed to later work")
	_check(_sum(state.settled_cells) == before_sum and _max(state.settled_cells) <= CAPACITY, "lateral budget exhaustion delays remaining pairs without loss or over-capacity")


func _test_pool_rise_only_by_deposition() -> void:
	var room := RoomOccupancy.build({
		"identifier": "p2b-pool-rise",
		"solids": [Rect2(0, 310, 960, 10)],
	})
	var state := _state()
	var base := _id(20, 30)
	state.settled_cells[base] = 16
	state.settled_cells[_id(19, 30)] = 16
	state.settled_cells[_id(21, 30)] = 16
	_reconcile(state)
	Flow.activate_cells(state, [base])
	for tick in 4:
		state.tick = tick
		Flow.step(state, room)
	_check(state.settled_cells[_id(20, 29)] == 0, "settled flow has no upward-pressure transfer")
	var packet := Schema.default_packet()
	packet.id = 1
	packet.volume_q = 5
	packet.lifecycle = Contracts.PacketLifecycle.STATIONARY_DEPOSITION
	packet.impact_cell_id = base
	packet.impact_normal_x = -1
	state.packets = [packet]
	state.ledger.airborne = 5
	state.ledger.initial += 5
	var deposited := Deposition.process_stationary_packets(state, room)
	_check(deposited.ok and state.settled_cells[_id(20, 29)] == 5, "pool rises only when new deposition selects available space above a full surface")


func _test_replay_resume() -> void:
	var room := Fixture.room_context()
	var bytes := Fixture.replay_bytes()
	var decoded := ReplayCodec.decode(bytes, Fixture.header())
	var encoded := ReplayCodec.encode(decoded.header, decoded.frames) if decoded.ok else {"ok": false}
	_check(decoded.ok and encoded.ok and encoded.bytes == bytes, "Package 2B replay round-trips exact canonical command bytes")
	if not decoded.ok:
		return
	var state := ReplayCodec.state_from_header(decoded.header, room.occupancy_hash)
	var runner := Runner.new(state, room)
	Fixture.seed_state(runner.state, room)
	var source := ReplaySource.new(decoded.frames)
	var first_hashes: Array[String] = []
	var invariant_ok := true
	var checkpoint_state: Dictionary
	for index in decoded.frames.size():
		var result := runner.step_from_source(source)
		invariant_ok = invariant_ok and result.ok and _invariants(runner.state)
		first_hashes.append(result.hash)
		if index == 11:
			checkpoint_state = runner.state.duplicate(true)
	var resumed := Runner.new(checkpoint_state, room)
	var resumed_source := ReplaySource.new(decoded.frames.slice(12))
	var resumed_hashes: Array[String] = []
	for unused in range(12, decoded.frames.size()):
		var result := resumed.step_from_source(resumed_source)
		invariant_ok = invariant_ok and result.ok and _invariants(resumed.state)
		resumed_hashes.append(result.hash)
	_check(invariant_ok and resumed_hashes == first_hashes.slice(12), "serialized queue, membership, counters, and parity resume with identical hashes")
	_check(Serializer.state_hash(resumed.state) == Serializer.state_hash(runner.state), "nontrivial flow replay reaches an identical final complete-state hash")


func _state() -> Dictionary:
	var state := Schema.default_state()
	Deposition.initialize_grid(state)
	return state


func _empty_room(identifier: String) -> Dictionary:
	return RoomOccupancy.build({"identifier": identifier, "solids": []})


func _reconcile(state: Dictionary) -> void:
	state.ledger.reserve = 0
	state.ledger.airborne = 0
	for packet in state.packets:
		state.ledger.airborne += packet.volume_q
	state.ledger.settled = _sum(state.settled_cells)
	state.ledger.initial = (
		state.ledger.reserve + state.ledger.airborne + state.ledger.settled
		+ state.ledger.suction + state.ledger.recovery_queue + state.ledger.drain
	)


func _invariants(state: Dictionary) -> bool:
	return _sum(state.settled_cells) == state.ledger.settled \
		and _ledger_error(state) == 0 \
		and _max(state.settled_cells) <= CAPACITY \
		and _membership_matches(state) \
		and Serializer.serialize_state_checked(state).ok


func _membership_matches(state: Dictionary) -> bool:
	var queued := {}
	for cell_id in state.active_queue:
		if queued.has(cell_id):
			return false
		queued[cell_id] = true
	for cell_id in COUNT:
		var member: bool = (
			state.active_membership[cell_id / 8] & (1 << (cell_id % 8))
		) != 0
		if member != queued.has(cell_id):
			return false
	return true


func _id(x: int, y: int) -> int:
	return y * WIDTH + x


func _sum(values: Array) -> int:
	var total := 0
	for value in values:
		total += value
	return total


func _max(values: Array) -> int:
	var result := 0
	for value in values:
		result = maxi(result, value)
	return result


func _nonzero(values: Array) -> int:
	var result := 0
	for value in values:
		if value > 0:
			result += 1
	return result


func _ledger_error(state: Dictionary) -> int:
	return state.ledger.initial - (
		state.ledger.reserve + state.ledger.airborne + state.ledger.settled
		+ state.ledger.suction + state.ledger.recovery_queue + state.ledger.drain
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("P2B_CHECK_FAIL: %s" % label)


func _finish() -> void:
	print("P2B_SUITE passed=%d failed=%d result=%s" % [
		passed, failed, "PASS" if failed == 0 else "FAIL"
	])
	quit(0 if failed == 0 else 1)
