extends SceneTree

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")
const GridTraversal := preload("res://better_spewing/collision/grid_traversal.gd")
const Simulation := preload("res://better_spewing/simulation/goo_simulation.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const ReplayFixture := preload("res://better_spewing/tests/p1d_fixture_factory.gd")

const FP := 256
const LOCKED_ROOM_SHA256 := "4ab4655b82ab6d74a8dbf81756c7345a60d31d50d58e4f37921cd238b5d24954"
const LOCKED_OCCUPANCY_SHA256 := "035e1954be68bf89aeec86fceea7f801d4510574941083140e5fad3ce74dcaf8"
const LOCKED_TUNING_SHA256 := "f8a3c2e7a071b5b088da2bc1a32edeae7a7fe9dacd7e0d661457603a6f88bc65"

var passed := 0
var failed := 0


func _init() -> void:
	_test_room_canonicalization_and_hashes()
	_test_immutable_binding_and_rejection()
	_test_swept_contacts()
	_test_corner_ties_and_los()
	_test_bounds()
	_test_simulation_collision_and_drain()
	_test_collision_replay()
	_test_visualization()
	_finish()


func _test_room_canonicalization_and_hashes() -> void:
	var room := RoomOccupancy.build({
		"identifier": "package-1d-mask-fixture",
		"solids": [
			Rect2(9.25, 9.75, 1.0, 1.0),
			Rect2(-4.5, -3.25, 6.0, 5.0),
			Rect2(955.5, 535.5, 20.0, 20.0),
			Rect2(1000.0, 600.0, 5.0, 5.0),
		],
	})
	_check(room.ok, "room definition canonicalizes valid authored Rect2 solids")
	_check(room.integer_rects == [
		{"left": -5, "top": -4, "right": 2, "bottom": 2},
		{"left": 9, "top": 9, "right": 11, "bottom": 11},
		{"left": 955, "top": 535, "right": 976, "bottom": 556},
		{"left": 1000, "top": 600, "right": 1005, "bottom": 605},
	], "Rect2 bounds use floor left/top, ceil right/bottom, and canonical order")
	_check(RoomOccupancy.is_solid(room, 0, 0), "negative partial rectangle clips outward into cell 0,0")
	_check(RoomOccupancy.is_solid(room, 1, 0) and RoomOccupancy.is_solid(room, 0, 1) and RoomOccupancy.is_solid(room, 1, 1), "sub-cell rectangle covers every outward-overlapped cell")
	_check(RoomOccupancy.is_solid(room, 95, 53), "partially outside bottom-right rectangle clips to final in-bounds cell")
	_check(not RoomOccupancy.is_solid(room, 94, 53), "clipped rectangle does not occupy unrelated neighbor cells")
	var outside_only := RoomOccupancy.build({"identifier": "outside-only", "solids": [Rect2(1000, 600, 5, 5)]})
	_check(_all_zero(outside_only.bitset), "fully outside rectangle marks no in-bounds occupancy bits")
	_check(room.bitset.size() == 648, "96x54 occupancy uses exact 648-byte bitset")
	_check(RoomOccupancy.bit_is_set(room.bitset, 0) and RoomOccupancy.bit_is_set(room.bitset, 1) and RoomOccupancy.bit_is_set(room.bitset, 96), "occupancy bit indices are row-major and least-significant-bit first")
	_check(not RoomOccupancy.bit_is_set(room.bitset, 2), "row-major bit fixture leaves the expected adjacent bit clear")
	_check(room.room_bytes.slice(0, 6).hex_encode() == "475244310100", "room definition encoding has locked ASCII magic and little-endian version")
	_check(room.occupancy_bytes.slice(0, 6).hex_encode() == "474f4d310100", "occupancy encoding has locked ASCII magic and little-endian version")
	var identity_a := _empty_context("identity-a")
	var identity_b := _empty_context("identity-b")
	_check(identity_a.bitset == identity_b.bitset and identity_a.room_hash != identity_b.room_hash and identity_a.occupancy_hash != identity_b.occupancy_hash, "occupancy hash includes separate room-definition identity even when mask bits match")
	print("P1D_ROOM bytes=%d sha256=%s occupancy_bytes=%d occupancy_sha256=%s tuning_sha256=%s" % [
		room.room_bytes.size(), room.room_hash.hex_encode(), room.occupancy_bytes.size(),
		room.occupancy_hash.hex_encode(), room.tuning_hash.hex_encode(),
	])
	_check(room.room_hash.hex_encode() == LOCKED_ROOM_SHA256, "room definition SHA-256 fixture")
	_check(room.occupancy_hash.hex_encode() == LOCKED_OCCUPANCY_SHA256, "occupancy SHA-256 fixture")
	_check(room.tuning_hash.hex_encode() == LOCKED_TUNING_SHA256, "canonical tuning SHA-256 fixture")


func _test_immutable_binding_and_rejection() -> void:
	var context := _empty_context("binding")
	var state := Schema.default_state()
	_check(RoomOccupancy.bind_state(state, context).is_empty(), "initialization binds exact room, occupancy, and tuning hashes")
	_check(state.immutable_hashes.room_definition == context.room_hash and state.immutable_hashes.occupancy == context.occupancy_hash and state.immutable_hashes.tuning == context.tuning_hash, "all three immutable hashes bind as exact 32-byte values")
	var mismatched := state.duplicate(true)
	for field in ["room_definition", "occupancy", "tuning"]:
		var field_mismatch := state.duplicate(true)
		field_mismatch.immutable_hashes[field][0] ^= 1
		_check(field in RoomOccupancy.bind_state(field_mismatch, context), "state initialization rejects %s hash mismatch" % field)
		if field == "occupancy":
			mismatched = field_mismatch
	var bad_version: Dictionary = context.duplicate(true)
	bad_version.room_bytes[4] = 2
	_check("version" in RoomOccupancy.validate_context(bad_version), "room definition encoding version mismatch is rejected")
	var bad_mask: Dictionary = context.duplicate(true)
	bad_mask.bitset[0] ^= 1
	_check("occupancy" in RoomOccupancy.validate_context(bad_mask), "occupancy bitset/encoding mismatch is rejected")
	var bad_hash: Dictionary = context.duplicate(true)
	bad_hash.occupancy_hash[0] ^= 1
	_check("occupancy hash" in RoomOccupancy.validate_context(bad_hash), "occupancy hash mismatch is rejected")
	var bad_tuning: Dictionary = context.duplicate(true)
	bad_tuning.tuning_hash[0] ^= 1
	_check("tuning" in RoomOccupancy.validate_context(bad_tuning), "canonical tuning hash mismatch is rejected")
	var runner := Runner.new(mismatched, context)
	var rejected := runner.step_frame(_frame(runner.state, Contracts.GooAction.NONE, 0))
	_check(not rejected.ok and "immutable input mismatch" in rejected.error, "runner rejects immutable-input mismatch before simulation")


func _test_swept_contacts() -> void:
	var wall := RoomOccupancy.build({"identifier": "four-way", "solids": [Rect2(50, 50, 10, 10)]})
	var cases := [
		[Vector2i(45, 55) * FP, Vector2i(65, 55) * FP, Vector2i(50, 55) * FP, Vector2i(4, 5), Vector2i(-1, 0)],
		[Vector2i(65, 55) * FP, Vector2i(45, 55) * FP, Vector2i(60, 55) * FP, Vector2i(6, 5), Vector2i(1, 0)],
		[Vector2i(55, 45) * FP, Vector2i(55, 65) * FP, Vector2i(55, 50) * FP, Vector2i(5, 4), Vector2i(0, -1)],
		[Vector2i(55, 65) * FP, Vector2i(55, 45) * FP, Vector2i(55, 60) * FP, Vector2i(5, 6), Vector2i(0, 1)],
	]
	for index in cases.size():
		var item: Array = cases[index]
		var hit := GridTraversal.sweep(item[0], item[1], 0, wall)
		_check(hit.kind == "collision" and hit.position_fp == item[2] and hit.contact_cell == item[3] and hit.normal == item[4], "near-side contact and normal are exact for direction %d" % index)
	var thin := RoomOccupancy.build({"identifier": "thin", "solids": [Rect2(500, 0, 1, 540)]})
	var maximum_tick_step: int = Tuning.RANGE_BOUNDS.packet_launch_speed_fp_per_s[1] / Tuning.VALUES.authoritative_hz
	var fast := GridTraversal.sweep(Vector2i(495, 250) * FP, Vector2i(495 * FP + maximum_tick_step, 250 * FP), 0, thin)
	_check(fast.kind == "collision" and fast.position_fp.x == 500 * FP, "maximum declared-speed sweep cannot tunnel through a one-pixel wall")
	var diagonal_wall := RoomOccupancy.build({"identifier": "long-diagonal", "solids": [Rect2(700, 400, 10, 10)]})
	var diagonal := GridTraversal.sweep(Vector2i(5, 5) * FP, Vector2i(905, 515) * FP, 0, diagonal_wall)
	_check(diagonal.visited_cells.size() > 80, "long diagonal deterministically visits every crossed cell")


func _test_corner_ties_and_los() -> void:
	var corner := RoomOccupancy.build({
		"identifier": "corner",
		"solids": [Rect2(20, 10, 10, 10), Rect2(10, 20, 10, 10)],
	})
	var start := Vector2i(15, 15) * FP
	var finish := Vector2i(35, 35) * FP
	var even := GridTraversal.sweep(start, finish, 2, corner)
	var odd := GridTraversal.sweep(start, finish, 3, corner)
	_check(even.kind == "collision" and even.visited_cells == [Vector2i(1, 1), Vector2i(2, 1)] and even.normal == Vector2i(-1, 0), "even-tick exact tie crosses vertical boundary first")
	_check(odd.kind == "collision" and odd.visited_cells == [Vector2i(1, 1), Vector2i(1, 2)] and odd.normal == Vector2i(0, -1), "odd-tick exact tie crosses horizontal boundary first")
	var empty := _empty_context("los-empty")
	var visible := GridTraversal.line_of_sight(Vector2i(5, 5) * FP, Vector2i(955, 535) * FP, 0, empty)
	_check(visible.visible and visible.visited_cells.size() > 2, "shared traversal reports unobstructed long line of sight")
	var blocked_context := RoomOccupancy.build({"identifier": "los-blocked", "solids": [Rect2(40, 0, 10, 540)]})
	var blocked := GridTraversal.line_of_sight(Vector2i(5, 15) * FP, Vector2i(95, 15) * FP, 0, blocked_context)
	_check(not blocked.visible and blocked.trace.kind == "collision", "first solid crossed blocks line of sight")
	var start_solid := GridTraversal.line_of_sight(Vector2i(45, 15) * FP, Vector2i(95, 15) * FP, 0, blocked_context)
	var end_solid := GridTraversal.line_of_sight(Vector2i(5, 15) * FP, Vector2i(45, 15) * FP, 0, blocked_context)
	_check(not start_solid.visible and "start is solid" in start_solid.error, "solid LOS start is invalid")
	_check(not end_solid.visible and "end is solid" in end_solid.error, "solid LOS end is invalid")
	var state := Schema.default_state()
	var before := Serializer.serialize_state_checked(state)
	GridTraversal.line_of_sight(Vector2i(5, 5) * FP, Vector2i(955, 535) * FP, 1, empty)
	var after := Serializer.serialize_state_checked(state)
	_check(before.ok and after.ok and before.bytes == after.bytes, "line-of-sight traversal cannot mutate authoritative state")


func _test_bounds() -> void:
	var empty := _empty_context("bounds")
	var cases := [
		[Vector2i(5, 100) * FP, Vector2i(-5, 100) * FP, Vector2i(1, 0)],
		[Vector2i(955, 100) * FP, Vector2i(965, 100) * FP, Vector2i(-1, 0)],
		[Vector2i(100, 5) * FP, Vector2i(100, -5) * FP, Vector2i(0, 1)],
		[Vector2i(100, 535) * FP, Vector2i(100, 545) * FP, Vector2i(0, -1)],
	]
	for index in cases.size():
		var item: Array = cases[index]
		var exit := GridTraversal.sweep(item[0], item[1], index, empty)
		_check(exit.kind == "bounds" and exit.normal == item[2], "swept bounds exit is deterministic on side %d" % index)
	var edge_solid := RoomOccupancy.build({"identifier": "solid-before-bound", "solids": [Rect2(950, 0, 10, 540)]})
	var precedence := GridTraversal.sweep(Vector2i(945, 100) * FP, Vector2i(970, 100) * FP, 0, edge_solid)
	_check(precedence.kind == "collision" and precedence.solid_cell == Vector2i(95, 10), "in-bounds solid collision precedes later bounds exit in traversal order")


func _test_simulation_collision_and_drain() -> void:
	var wall := RoomOccupancy.build({"identifier": "simulation-wall", "solids": [Rect2(50, 0, 10, 540)]})
	var state := _packet_state(Vector2i(45, 55) * FP, Vector2i(720, 0) * FP, 1)
	state.packets[0].gravity_remainder = 5
	var simulation := Simulation.new()
	_check(simulation.configure_room(state, wall).is_empty(), "isolated simulation accepts validated immutable room context")
	var result := simulation.integrate_packets(state)
	var packet: Dictionary = state.packets[0]
	_check(result.ok and packet.lifecycle == Contracts.PacketLifecycle.STATIONARY_DEPOSITION and packet.stationary_ticks == 1, "collision enters stationary deposition retry state")
	_check(packet.position_x_fp == 50 * FP and packet.velocity_x_fp_per_s == 0 and packet.velocity_y_fp_per_s == 0, "collision commits exact near-side contact and zero velocity")
	_check(packet.impact_cell_id == 5 * 96 + 4 and packet.impact_normal_x == -1 and packet.impact_normal_y == 0, "serialized impact cell and normal retain corner-sensitive contact authority")
	_check(packet.position_x_remainder == 0 and packet.position_y_remainder == 0 and packet.gravity_remainder == 5, "collision resets position remainders and preserves the computed gravity remainder")
	_check(state.ledger.airborne == 1 and state.ledger.settled == 0 and state.settled_cells.is_empty(), "impacted volume remains wholly AIRBORNE with no settled state")
	_check(Serializer.serialize_state_checked(state).ok, "stationary contact packet is canonical and hash-valid")
	var malformed_contact := state.duplicate(true)
	malformed_contact.packets[0].impact_normal_y = 1
	_check(not Serializer.serialize_state_checked(malformed_contact).ok, "diagonal serialized impact normal is rejected")
	var missing_contact := state.duplicate(true)
	missing_contact.packets[0].impact_cell_id = Contracts.NO_IMPACT_CELL_ID
	_check(not Serializer.serialize_state_checked(missing_contact).ok, "no-impact sentinel with nonzero normal is rejected")

	var clear_state := _packet_state(Vector2i(15, 15) * FP, Vector2i(61, 0), 1)
	var clear_sim := Simulation.new()
	clear_sim.configure_room(clear_state, _empty_context("clear-integration"))
	clear_sim.integrate_packets(clear_state)
	_check(clear_state.packets[0].position_x_fp == 15 * FP + 1 and clear_state.packets[0].position_x_remainder == 1, "no collision commits proposed fixed-point position and remainder")

	var bounds_state := _packet_state(Vector2i(955, 100) * FP, Vector2i(720, 0) * FP, 4)
	var bounds_sim := Simulation.new()
	bounds_sim.configure_room(bounds_state, _empty_context("bounds-drain"))
	var bounds_result := bounds_sim.integrate_packets(bounds_state)
	_check(bounds_result.ok and bounds_state.packets.is_empty() and bounds_state.ledger.airborne == 0 and bounds_state.ledger.drain == 4, "bounds exit transfers the full packet AIRBORNE-to-DRAIN atomically")
	_check(bounds_state.drain_queue.size() == 1 and bounds_state.drain_queue[0].return_tick == 90, "bounds drain uses existing stable FIFO delay contract")
	var side_specs := [
		[Vector2i(5, 100) * FP, Vector2i(-720, 0) * FP],
		[Vector2i(955, 100) * FP, Vector2i(720, 0) * FP],
		[Vector2i(100, 5) * FP, Vector2i(0, -720) * FP],
		[Vector2i(100, 535) * FP, Vector2i(0, 720) * FP],
	]
	for side in side_specs.size():
		var side_state := _packet_state(side_specs[side][0], side_specs[side][1], 3)
		var side_sim := Simulation.new()
		side_sim.configure_room(side_state, _empty_context("bounds-side-%d" % side))
		var side_result := side_sim.integrate_packets(side_state)
		_check(side_result.ok and side_state.packets.is_empty() and side_state.ledger.drain == 3, "simulation drains the full conserved packet on bounds side %d" % side)

	var exhausted := _packet_state(Vector2i(955, 100) * FP, Vector2i(720, 0) * FP, 4)
	exhausted.next_ids.drain_record = Contracts.INVALID_STABLE_ID
	var exhausted_sim := Simulation.new()
	exhausted_sim.configure_room(exhausted, _empty_context("bounds-exhausted"))
	var before := Serializer.serialize_state_checked(exhausted)
	var rejected := exhausted_sim.integrate_packets(exhausted)
	var after := Serializer.serialize_state_checked(exhausted)
	_check(not rejected.ok and "exhausted" in rejected.error, "bounds drain-ID exhaustion returns deterministic failure")
	_check(before.ok and after.ok and before.bytes == after.bytes and exhausted.ledger.airborne == 4, "bounds drain rejection preserves the source packet and conserved canonical state byte-for-byte")
	var runner_state := _packet_state(Vector2i(955, 100) * FP, Vector2i(720, 0) * FP, 4)
	runner_state.next_ids.drain_record = Contracts.INVALID_STABLE_ID
	var runner := Runner.new(runner_state, _empty_context("bounds-runner-exhausted"))
	var runner_packet_before: Dictionary = runner.state.packets[0].duplicate(true)
	var runner_ledger_before: Dictionary = runner.state.ledger.duplicate(true)
	var runner_next_ids_before: Dictionary = runner.state.next_ids.duplicate(true)
	var runner_rejected := runner.step_frame(_frame(runner.state, Contracts.GooAction.SPEW, 0))
	_check(not runner_rejected.ok and runner.state.tick == 0 and runner.state.packets[0] == runner_packet_before and runner.state.packets.size() == 1 and runner.state.ledger == runner_ledger_before and runner.state.next_ids == runner_next_ids_before, "runner-level bounds drain exhaustion rejects emission without packet, ledger, ID, or tick mutation")


func _test_visualization() -> void:
	var packed := load("res://better_spewing/visualization/isolated_packet_simulation.tscn")
	var instance: Node = packed.instantiate()
	instance._ready()
	var snapshots: Array = instance.authoritative_snapshots
	var stationary: bool = not snapshots.is_empty() and snapshots[-1][0].lifecycle == Contracts.PacketLifecycle.STATIONARY_DEPOSITION
	_check(stationary and snapshots[-1][0].impact_normal_x == -1, "isolated visualization advances a real packet from travel to stationary wall contact")
	var visualizer: Node = instance.get_node("PacketVisualizer")
	_check(visualizer.packet_snapshot == instance.runner.state.packets, "visualizer receives exact duplicated read-only authoritative contact snapshot")
	var hash_before := Serializer.state_hash(instance.runner.state)
	visualizer.packet_snapshot[0].position_x_fp += 1234
	_check(Serializer.state_hash(instance.runner.state) == hash_before, "render-side contact snapshot mutation cannot affect authority or hashes")
	instance.free()


func _test_collision_replay() -> void:
	var room := ReplayFixture.room_context()
	var bytes := ReplayFixture.replay_bytes()
	var decoded := ReplayCodec.decode(bytes, ReplayFixture.header())
	var reencoded := ReplayCodec.encode(decoded.header, decoded.frames) if decoded.ok else {"ok": false}
	_check(decoded.ok and reencoded.ok and reencoded.bytes == bytes, "collision/bounds replay has exact canonical byte round-trip")
	if not decoded.ok:
		return
	var state := ReplayCodec.state_from_header(decoded.header, room.occupancy_hash)
	var runner := Runner.new(state, room)
	var result := runner.run_ticks(ReplaySource.new(decoded.frames), decoded.frames.size())
	_check(result.ok and runner.checkpoint_hashes.size() == decoded.frames.size(), "collision/bounds replay produces one complete-state hash per ordered tick")
	var stationary := 0
	for packet in runner.state.packets:
		if packet.lifecycle == Contracts.PacketLifecycle.STATIONARY_DEPOSITION:
			stationary += 1
	_check(stationary == 1 and runner.state.ledger.drain > 0 and runner.state.ledger.airborne > 0, "nontrivial replay deterministically exercises collision and bounds drain without volume loss")


func _empty_context(identifier: String) -> Dictionary:
	return RoomOccupancy.build({"identifier": identifier, "solids": []})


func _packet_state(position: Vector2i, velocity: Vector2i, volume_q: int) -> Dictionary:
	var state := Schema.default_state()
	state.ledger.initial = volume_q
	state.ledger.airborne = volume_q
	var packet := Schema.default_packet()
	packet.position_x_fp = position.x
	packet.position_y_fp = position.y
	packet.velocity_x_fp_per_s = velocity.x
	packet.velocity_y_fp_per_s = velocity.y
	packet.volume_q = volume_q
	packet.lifetime_ticks = Tuning.VALUES.packet_lifetime_ticks
	state.packets = [packet]
	state.next_ids.packet = 2
	return state


func _frame(state: Dictionary, action: int, aim: int) -> Dictionary:
	return {
		"tick": state.tick,
		"move_x": 0,
		"move_y": 0,
		"jump_pressed": false,
		"goo_action": action,
		"aim_angle": aim,
		"asserted_mouth_x_fp": state.player.position_x_fp,
		"asserted_mouth_y_fp": state.player.position_y_fp + 3 * FP,
	}


func _all_zero(bytes: PackedByteArray) -> bool:
	for byte in bytes:
		if byte != 0:
			return false
	return true


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("P1D_CHECK_FAIL: %s" % label)


func _finish() -> void:
	print("P1D_SUITE passed=%d failed=%d result=%s" % [passed, failed, "PASS" if failed == 0 else "FAIL"])
	quit(0 if failed == 0 else 1)
