extends SceneTree

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")
const Deposition := preload("res://better_spewing/deposition/settled_deposition.gd")
const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const ReplayFixture := preload("res://better_spewing/tests/p2a_fixture_factory.gd")

const GRID_COUNT := 96 * 54
const CAPACITY := 16
const FP := 256
const EXPECTED_EMPTY_GRID_BYTES := 21699
const EXPECTED_EMPTY_GRID_SHA256 := "40696214b40eeb1f842b093bde87b008dafb8b95f25dd45f93873a80ccc12177"

var passed := 0
var failed := 0


func _init() -> void:
	_test_grid_contract()
	_test_candidate_ordering()
	_test_connectivity_solids_and_bounds()
	_test_exact_transfer_and_removal()
	_test_partial_saturation_retry()
	_test_blocked_conservation_and_diagnostics()
	_test_stable_packet_order()
	_test_replay_round_trip()
	_finish()


func _test_grid_contract() -> void:
	var state := Schema.default_state()
	_check(Deposition.initialize_grid(state).is_empty(), "settled grid initializes from canonical empty state")
	_check(state.settled_cells.size() == GRID_COUNT and state.cell_stable_counters.size() == GRID_COUNT and state.active_membership.size() == 648, "settled grid uses exact 96x54 row-major dimensions")
	_check(_sum(state.settled_cells) == 0 and _sum(state.cell_stable_counters) == 0 and _all_zero_bytes(state.active_membership), "new settled and deferred flow state initializes to integer zero")
	_check(state.active_queue.is_empty() and Serializer.serialize_state_checked(state).ok, "Package 2A initializes no active flow scheduling and remains canonical")
	var serialized := Serializer.serialize_state_checked(state)
	print("P2A_EMPTY_GRID bytes=%d sha256=%s" % [serialized.bytes.size(), Serializer.state_hash(state)])
	_check(serialized.bytes.size() == EXPECTED_EMPTY_GRID_BYTES, "initialized empty-grid canonical byte length fixture")
	_check(Serializer.state_hash(state) == EXPECTED_EMPTY_GRID_SHA256, "initialized empty-grid canonical SHA-256 fixture")
	var malformed := state.duplicate(true)
	malformed.settled_cells.pop_back()
	_check(not Serializer.serialize_state_checked(malformed).ok, "serializer rejects noncanonical settled grid length")
	var empty_mismatch := Schema.default_state()
	empty_mismatch.active_membership.resize(1)
	_check(not Serializer.serialize_state_checked(empty_mismatch).ok, "empty settled grid rejects stray future scheduling state")


func _test_candidate_ordering() -> void:
	var room := RoomOccupancy.build({
		"identifier": "p2a-order",
		"solids": [Rect2(0, 120, 960, 10)],
	})
	var state := _grid_state()
	var impact := _id(10, 10)
	var even := Deposition.derive_candidate_diagnostics(state, room, impact, 2)
	var odd := Deposition.derive_candidate_diagnostics(state, room, impact, 3)
	_check(even.ok and odd.ok, "candidate diagnostics derive without mutating authority")
	var expected_even := [impact, _id(10, 11), _id(9, 10), _id(11, 10), _id(10, 9)]
	var expected_odd := [impact, _id(10, 11), _id(11, 10), _id(9, 10), _id(10, 9)]
	_check(_first_ids(even.candidates, 5) == expected_even, "ordering is distance, supported down, even left, right, then up")
	_check(_first_ids(odd.candidates, 5) == expected_odd, "odd lateral parity orders right before left without changing other ranks")
	var support_room := RoomOccupancy.build({
		"identifier": "p2a-support-priority",
		"solids": [Rect2(90, 110, 10, 10)],
	})
	var support := Deposition.derive_candidate_diagnostics(state, support_room, impact, 0)
	_check(support.candidates[1].cell_id == _id(9, 10) and support.candidates[1].supported, "supported candidate precedes unsupported downward candidate at equal distance")
	var row_major_ok := true
	for index in range(1, even.candidates.size()):
		var previous: Dictionary = even.candidates[index - 1]
		var current: Dictionary = even.candidates[index]
		if previous.distance == current.distance \
				and previous.supported == current.supported \
				and previous.direction_rank == current.direction_rank \
				and previous.lateral_rank == current.lateral_rank:
			row_major_ok = row_major_ok and previous.cell_id < current.cell_id
	_check(row_major_ok, "row-major cell ID is the final deterministic candidate tie-break")


func _test_connectivity_solids_and_bounds() -> void:
	var barrier := RoomOccupancy.build({
		"identifier": "p2a-barrier",
		"solids": [Rect2(110, 60, 10, 90)],
	})
	var state := _grid_state()
	var impact := _id(10, 10)
	var derived := Deposition.derive_candidate_diagnostics(state, barrier, impact, 0)
	var ids := _candidate_ids(derived.candidates)
	_check(not ids.has(_id(11, 10)) and not ids.has(_id(12, 10)), "solid barrier and disconnected cells behind it are excluded")
	var all_non_solid := true
	for candidate in derived.candidates:
		all_non_solid = all_non_solid and not RoomOccupancy.is_solid(barrier, candidate.x, candidate.y)
	_check(all_non_solid, "candidate search never includes a solid cell")
	var deposition_state := _stationary_state(impact, 4)
	deposition_state.settled_cells[impact] = CAPACITY
	_reconcile_ledger(deposition_state)
	var deposited := Deposition.process_stationary_packets(deposition_state, barrier)
	var solid_cells_zero := true
	for y in range(6, 15):
		solid_cells_zero = solid_cells_zero and deposition_state.settled_cells[_id(11, y)] == 0
	_check(deposited.ok and deposited.packets[0].selected_cell_id != _id(11, 10) and solid_cells_zero, "actual deposition never writes into a solid barrier cell")
	var corner := Deposition.derive_candidate_diagnostics(state, _empty_room("p2a-corner"), 0, 0)
	var in_bounds := true
	for candidate in corner.candidates:
		in_bounds = in_bounds and candidate.x >= 0 and candidate.y >= 0 and candidate.x < 96 and candidate.y < 54
	_check(in_bounds and corner.candidates.size() == 15, "Manhattan radius-4 search clips deterministically at simulation bounds")


func _test_exact_transfer_and_removal() -> void:
	var room := _empty_room("p2a-full-transfer")
	var state := _stationary_state(_id(20, 20), 7)
	var packet_position := Vector2i(state.packets[0].position_x_fp, state.packets[0].position_y_fp)
	var result := Deposition.process_stationary_packets(state, room)
	_check(result.ok and result.packets[0].accepted_q == 7 and result.packets[0].status == "complete", "first available candidate accepts exact full packet amount")
	_check(state.packets.is_empty() and state.settled_cells[_id(20, 20)] == 7, "packet is removed only when its remainder reaches zero")
	_check(state.ledger.airborne == 0 and state.ledger.settled == 7 and _ledger_error(state) == 0, "full deposition transfers AIRBORNE to SETTLED exactly")
	_check(packet_position == Vector2i(20 * 10 * FP + 5 * FP, 20 * 10 * FP + 5 * FP), "full transfer fixture uses stable authoritative impact position")


func _test_partial_saturation_retry() -> void:
	var room := RoomOccupancy.build({
		"identifier": "p2a-partial",
		"solids": [Rect2(0, 120, 960, 10)],
	})
	var impact := _id(10, 10)
	var state := _stationary_state(impact, 7)
	state.settled_cells[impact] = 14
	_reconcile_ledger(state)
	var before_packet: Dictionary = state.packets[0].duplicate(true)
	var first := Deposition.process_stationary_packets(state, room)
	_check(first.ok and first.packets[0].accepted_q == 2 and first.packets[0].remaining_q == 5 and first.packets[0].status == "partial", "partial saturation accepts exact remaining cell capacity")
	_check(state.settled_cells[impact] == CAPACITY and state.packets.size() == 1 and state.packets[0].id == before_packet.id and state.packets[0].volume_q == 5, "partial remainder retains same stable packet and fills cell exactly")
	_check(state.packets[0].position_x_fp == before_packet.position_x_fp and state.packets[0].position_y_fp == before_packet.position_y_fp and state.packets[0].velocity_x_fp_per_s == 0 and state.packets[0].velocity_y_fp_per_s == 0, "partial retry has no position or velocity drift")
	_check(_ledger_error(state) == 0 and _max(state.settled_cells) <= CAPACITY, "partial tick conserves ledger and never exceeds capacity")
	state.tick += 1
	var second := Deposition.process_stationary_packets(state, room)
	_check(second.ok and second.packets[0].accepted_q == 5 and second.packets[0].selected_cell_id == _id(10, 11), "next authoritative tick retries deterministic ordering at next supported cell")
	_check(state.packets.is_empty() and state.settled_cells[_id(10, 11)] == 5 and _ledger_error(state) == 0, "retry removes packet only after exact remaining transfer without loss")


func _test_blocked_conservation_and_diagnostics() -> void:
	var room := _empty_room("p2a-blocked")
	var impact := _id(30, 20)
	var state := _stationary_state(impact, 9)
	var candidates := Deposition.derive_candidate_diagnostics(state, room, impact, 0)
	for candidate in candidates.candidates:
		state.settled_cells[candidate.cell_id] = CAPACITY
	_reconcile_ledger(state)
	var before_packet: Dictionary = state.packets[0].duplicate(true)
	var result := Deposition.process_stationary_packets(state, room)
	_check(result.ok and result.packets[0].status == "blocked" and result.packets[0].accepted_q == 0, "fully saturated connected search reports deterministic blocked deposition")
	_check(state.packets[0].id == before_packet.id and state.packets[0].volume_q == before_packet.volume_q and state.packets[0].position_x_fp == before_packet.position_x_fp and state.packets[0].position_y_fp == before_packet.position_y_fp, "blocked packet remains stationary, same-ID, and fully conserved")
	_check(_ledger_error(state) == 0 and Serializer.serialize_state_checked(state).ok, "blocked deposition remains byte-valid with zero ledger error")
	var hash_before := Serializer.state_hash(state)
	result.packets[0].candidate_ids.clear()
	result.packets[0].accepted_q = 99
	_check(Serializer.state_hash(state) == hash_before, "derived diagnostics are read-only copies and cannot mutate authoritative state")
	_check(state.active_queue.is_empty() and _sum(state.cell_stable_counters) == 0 and _all_zero_bytes(state.active_membership), "Package 2A deposition does not begin active flow scheduling")


func _test_stable_packet_order() -> void:
	var room := _empty_room("p2a-stable-packets")
	var impact := _id(40, 20)
	var state := _grid_state()
	state.packets = [_packet(1, impact, 12), _packet(2, impact, 8)]
	_reconcile_ledger(state)
	var result := Deposition.process_stationary_packets(state, room)
	_check(result.ok and result.packets[0].packet_id == 1 and result.packets[0].accepted_q == 12 and result.packets[1].packet_id == 2 and result.packets[1].accepted_q == 4, "stationary packets deposit in stable-ID order against the same capacity")
	_check(state.packets.size() == 1 and state.packets[0].id == 2 and state.packets[0].volume_q == 4 and state.settled_cells[impact] == CAPACITY, "later packet retains same ID and exact remainder after earlier stable-ID ownership")
	_check(_ledger_error(state) == 0, "multi-packet ordered deposition conserves every intermediate category")


func _test_replay_round_trip() -> void:
	var room := ReplayFixture.room_context()
	var bytes := ReplayFixture.replay_bytes()
	var decoded := ReplayCodec.decode(bytes, ReplayFixture.header())
	var reencoded := ReplayCodec.encode(decoded.header, decoded.frames) if decoded.ok else {"ok": false}
	_check(decoded.ok and reencoded.ok and reencoded.bytes == bytes, "Package 2A replay has exact canonical byte round-trip")
	if not decoded.ok:
		return
	var state := ReplayCodec.state_from_header(decoded.header, room.occupancy_hash)
	var runner := Runner.new(state, room)
	var source := ReplaySource.new(decoded.frames)
	var flow_ok := false
	var invariant_ok := true
	for unused in decoded.frames.size():
		var step := runner.step_from_source(source)
		invariant_ok = invariant_ok and step.ok and _ledger_error(runner.state) == 0 and _max(runner.state.settled_cells) <= CAPACITY
		flow_ok = flow_ok or not runner.state.active_queue.is_empty()
	_check(invariant_ok and flow_ok, "nontrivial replay conserves every tick and hands deposition to canonical active flow")
	_check(runner.state.packets.is_empty() and runner.state.ledger.settled == 21 and _nonzero_count(runner.state.settled_cells) == 4, "replay completes 21q without duplication while deterministic flow redistributes cells")


func _grid_state() -> Dictionary:
	var state := Schema.default_state()
	Deposition.initialize_grid(state)
	return state


func _stationary_state(impact_cell_id: int, volume_q: int) -> Dictionary:
	var state := _grid_state()
	state.packets = [_packet(1, impact_cell_id, volume_q)]
	_reconcile_ledger(state)
	return state


func _packet(id: int, impact_cell_id: int, volume_q: int) -> Dictionary:
	var packet := Schema.default_packet()
	packet.id = id
	packet.impact_cell_id = impact_cell_id
	packet.impact_normal_x = -1
	packet.lifecycle = Contracts.PacketLifecycle.STATIONARY_DEPOSITION
	packet.stationary_ticks = 1
	packet.volume_q = volume_q
	var x: int = impact_cell_id % 96
	var y: int = impact_cell_id / 96
	packet.position_x_fp = x * 10 * FP + 5 * FP
	packet.position_y_fp = y * 10 * FP + 5 * FP
	packet.lifetime_ticks = Tuning.VALUES.packet_lifetime_ticks
	return packet


func _reconcile_ledger(state: Dictionary) -> void:
	state.ledger.reserve = 0
	state.ledger.airborne = 0
	for packet in state.packets:
		state.ledger.airborne += packet.volume_q
	state.ledger.settled = _sum(state.settled_cells)
	state.ledger.initial = Contracts.ledger_total(state.ledger)


func _empty_room(identifier: String) -> Dictionary:
	return RoomOccupancy.build({"identifier": identifier, "solids": []})


func _id(x: int, y: int) -> int:
	return y * 96 + x


func _candidate_ids(candidates: Array) -> Array[int]:
	var result: Array[int] = []
	for candidate in candidates:
		result.append(candidate.cell_id)
	return result


func _first_ids(candidates: Array, count: int) -> Array[int]:
	return _candidate_ids(candidates.slice(0, count))


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


func _nonzero_count(values: Array) -> int:
	var result := 0
	for value in values:
		if value != 0:
			result += 1
	return result


func _all_zero_bytes(values: PackedByteArray) -> bool:
	for value in values:
		if value != 0:
			return false
	return true


func _ledger_error(state: Dictionary) -> int:
	return state.ledger.initial - Contracts.ledger_total(state.ledger)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("P2A_CHECK_FAIL: %s" % label)


func _finish() -> void:
	print("P2A_SUITE passed=%d failed=%d result=%s" % [passed, failed, "PASS" if failed == 0 else "FAIL"])
	quit(0 if failed == 0 else 1)
