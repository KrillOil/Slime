extends RefCounted

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const AimTable := preload("res://better_spewing/aim/aim_table.gd")
const MouthDerivation := preload("res://better_spewing/runner/mouth_derivation.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")
const GridTraversal := preload("res://better_spewing/collision/grid_traversal.gd")

const DIRECTION_SCALE := 1_000_000
const POSITION_DIVISOR := 60

var directions: Array[Vector2i]
var room_context: Dictionary = {}


func _init(direction_entries: Array[Vector2i] = []) -> void:
	if direction_entries.is_empty():
		var loaded := AimTable.load_checked()
		directions = loaded.entries if loaded.ok else []
	else:
		directions = direction_entries


func configure_room(state: Dictionary, context: Dictionary) -> String:
	var error := RoomOccupancy.bind_state(state, context)
	if error.is_empty():
		room_context = context.duplicate(true)
	return error


func step(state: Dictionary, frame: Dictionary) -> Dictionary:
	# A traversal/drain infrastructure failure rejects the authoritative tick.
	# Preserve the already-sampled command fields supplied by the runner, while
	# making all simulation-side ownership, ID, recoil, queue, and packet work atomic.
	var simulation_snapshot: Dictionary = state.duplicate(true)
	state.player.recoil_x_fp_per_s = 0
	state.player.recoil_y_fp_per_s = 0
	process_drain_returns(state)
	var emission := {"accepted_q": 0, "created": false, "merged": false, "rejected": false, "packet_id": 0}
	if frame.goo_action == Contracts.GooAction.SPEW:
		emission = accept_spew(state, frame)
	else:
		state.command_sampler.spew_rate_remainder = 0
	if frame.goo_action != Contracts.GooAction.GULP:
		state.command_sampler.gulp_rate_remainder = 0
	# Canonical Section 11 order: accepted emission precedes stable-ID travel.
	var integration := integrate_packets(state)
	if not integration.ok:
		state.clear()
		state.merge(simulation_snapshot, true)
		emission.ok = false
		emission.error = integration.error
		return emission
	emission.ok = true
	emission.error = ""
	return emission


func accept_spew(state: Dictionary, frame: Dictionary) -> Dictionary:
	var result := {"accepted_q": 0, "created": false, "merged": false, "rejected": false, "packet_id": 0}
	var old_rate_remainder: int = state.command_sampler.spew_rate_remainder
	var accumulated := old_rate_remainder + Tuning.VALUES.spew_rate_qps
	var requested := _divide_trunc(accumulated, Tuning.VALUES.authoritative_hz)
	var next_rate_remainder := accumulated % Tuning.VALUES.authoritative_hz
	# Section 8.4 rate progression belongs to the held input stream. It advances
	# before ownership/capacity checks even when the requested volume is rejected.
	state.command_sampler.spew_rate_remainder = next_rate_remainder
	requested = mini(requested, state.ledger.reserve)
	if requested <= 0:
		result.rejected = true
		return result

	var newest: Dictionary = {}
	var merge_capacity := 0
	if state.packets.size() >= Tuning.VALUES.maximum_airborne_packets:
		if state.packets.size() == Tuning.VALUES.maximum_airborne_packets:
			newest = state.packets[-1]
			if _newest_packet_is_compatible(state, newest, frame):
				merge_capacity = Tuning.VALUES.maximum_packet_volume_q - newest.volume_q
		if merge_capacity <= 0:
			result.rejected = true
			return result
		requested = mini(requested, merge_capacity)

	var creating: bool = state.packets.size() < Tuning.VALUES.maximum_airborne_packets
	if creating and (
		state.next_ids.packet < Contracts.FIRST_STABLE_ID
		or state.next_ids.packet > Contracts.MAX_STABLE_ID
	):
		result.rejected = true
		return result
	if requested <= 0:
		result.rejected = true
		return result

	# Transaction begins only after the exact accepted amount and ownership are known.
	state.ledger.reserve -= requested
	state.ledger.airborne += requested
	if creating:
		var packet_id: int = state.next_ids.packet
		var id_result := Contracts.consume_stable_id(packet_id)
		state.next_ids.packet = id_result.next_id
		var mouth := MouthDerivation.derive(state.player)
		var direction: Vector2i = directions[frame.aim_angle]
		var inherited_x := _divide_trunc(
			state.player.velocity_x_fp_per_s * Tuning.VALUES.player_velocity_inheritance_permille,
			Tuning.PERMILLE_SCALE
		)
		var inherited_y := _divide_trunc(
			state.player.velocity_y_fp_per_s * Tuning.VALUES.player_velocity_inheritance_permille,
			Tuning.PERMILLE_SCALE
		)
		var packet := {
			"id": packet_id,
			"emission_tick": state.tick,
			"aim_angle": frame.aim_angle,
			"impact_cell_id": Contracts.NO_IMPACT_CELL_ID,
			"impact_normal_x": 0,
			"impact_normal_y": 0,
			"position_x_fp": mouth.x,
			"position_y_fp": mouth.y,
			"velocity_x_fp_per_s": _divide_trunc(direction.x * Tuning.VALUES.packet_launch_speed_fp_per_s, DIRECTION_SCALE) + inherited_x,
			"velocity_y_fp_per_s": _divide_trunc(direction.y * Tuning.VALUES.packet_launch_speed_fp_per_s, DIRECTION_SCALE) + inherited_y,
			"volume_q": requested,
			# Remaining travel integrations, including the current authoritative
			# tick's Section 11.2 travel. Reaching zero transfers all volume to DRAIN.
			"lifetime_ticks": Tuning.VALUES.packet_lifetime_ticks,
			"lifecycle": Contracts.PacketLifecycle.AIRBORNE,
			"suction_reserved": false,
			"stationary_ticks": 0,
			"position_x_remainder": 0,
			"position_y_remainder": 0,
			"gravity_remainder": 0,
		}
		state.packets.append(packet)
		result.created = true
		result.packet_id = packet_id
	else:
		newest.volume_q += requested
		newest.emission_tick = state.tick
		newest.lifetime_ticks = Tuning.VALUES.packet_lifetime_ticks
		result.merged = true
		result.packet_id = newest.id
	result.accepted_q = requested
	var recoil := compute_recoil(state, requested, frame.aim_angle)
	state.player.recoil_x_fp_per_s = recoil.x
	state.player.recoil_y_fp_per_s = recoil.y
	return result


func compute_recoil(state: Dictionary, accepted_q: int, aim_angle: int) -> Vector2i:
	if accepted_q <= 0:
		return Vector2i.ZERO
	var fraction_total: int = (
		accepted_q * Tuning.VALUES.recoil_subpixel_numerator_per_s_per_q
		+ state.remainders.recoil_fraction
	)
	var magnitude := _divide_trunc(fraction_total, Tuning.VALUES.recoil_subpixel_denominator)
	state.remainders.recoil_fraction = fraction_total % Tuning.VALUES.recoil_subpixel_denominator
	magnitude = mini(magnitude, Tuning.VALUES.recoil_tick_cap_fp_per_s)
	var direction: Vector2i = directions[aim_angle]
	var x_total: int = -direction.x * magnitude + state.remainders.player_recoil_x
	var y_total: int = -direction.y * magnitude + state.remainders.player_recoil_y
	var recoil_x := _divide_trunc(x_total, DIRECTION_SCALE)
	var recoil_y := _divide_trunc(y_total, DIRECTION_SCALE)
	state.remainders.player_recoil_x = x_total - recoil_x * DIRECTION_SCALE
	state.remainders.player_recoil_y = y_total - recoil_y * DIRECTION_SCALE
	return Vector2i(recoil_x, recoil_y)


func integrate_packets(state: Dictionary) -> Dictionary:
	var integration_snapshot: Dictionary = state.duplicate(true)
	var expiring_ids: Array[int] = []
	var bounds_ids: Array[int] = []
	for packet in state.packets:
		if packet.lifecycle != Contracts.PacketLifecycle.AIRBORNE:
			continue
		var gravity_total: int = packet.gravity_remainder + Tuning.VALUES.packet_gravity_fp_per_s2
		var gravity_step := _divide_trunc(gravity_total, POSITION_DIVISOR)
		var next_gravity_remainder := gravity_total - gravity_step * POSITION_DIVISOR
		var next_velocity_y: int = packet.velocity_y_fp_per_s + gravity_step
		var x_total: int = packet.position_x_remainder + packet.velocity_x_fp_per_s
		var y_total: int = packet.position_y_remainder + next_velocity_y
		var x_step := _divide_trunc(x_total, POSITION_DIVISOR)
		var y_step := _divide_trunc(y_total, POSITION_DIVISOR)
		var next_x_remainder := x_total - x_step * POSITION_DIVISOR
		var next_y_remainder := y_total - y_step * POSITION_DIVISOR
		var previous_position := Vector2i(packet.position_x_fp, packet.position_y_fp)
		var proposed_position := previous_position + Vector2i(x_step, y_step)
		var trace := {"kind": "clear", "position_fp": proposed_position}
		if not room_context.is_empty():
			trace = GridTraversal.sweep(previous_position, proposed_position, state.tick, room_context)
		if trace.kind.begins_with("invalid") or trace.kind == "error":
			return _integration_failure(state, integration_snapshot, "packet traversal failed: %s" % trace.kind)
		if trace.kind == "bounds":
			bounds_ids.append(packet.id)
			continue
		packet.gravity_remainder = next_gravity_remainder
		packet.lifetime_ticks = maxi(packet.lifetime_ticks - 1, 0)
		if trace.kind == "collision":
			# Collision consumes this tick's gravity phase but resets both position
			# division remainders at the exact near-side boundary contact.
			packet.position_x_fp = trace.position_fp.x
			packet.position_y_fp = trace.position_fp.y
			packet.velocity_x_fp_per_s = 0
			packet.velocity_y_fp_per_s = 0
			packet.position_x_remainder = 0
			packet.position_y_remainder = 0
			packet.lifecycle = Contracts.PacketLifecycle.STATIONARY_DEPOSITION
			packet.stationary_ticks = 1
			packet.impact_cell_id = trace.impact_cell_id
			packet.impact_normal_x = trace.normal.x
			packet.impact_normal_y = trace.normal.y
		else:
			packet.position_x_fp = proposed_position.x
			packet.position_y_fp = proposed_position.y
			packet.velocity_y_fp_per_s = next_velocity_y
			packet.position_x_remainder = next_x_remainder
			packet.position_y_remainder = next_y_remainder
			packet.impact_cell_id = Contracts.NO_IMPACT_CELL_ID
			packet.impact_normal_x = 0
			packet.impact_normal_y = 0
		if packet.lifetime_ticks == 0:
			expiring_ids.append(packet.id)
	for packet_id in bounds_ids:
		var result := drain_packet(state, packet_id)
		if not result.ok:
			return _integration_failure(state, integration_snapshot, "bounds drain rejected: %s" % result.error)
	for packet_id in expiring_ids:
		var result := drain_packet(state, packet_id)
		if not result.ok:
			return _integration_failure(state, integration_snapshot, "expiry drain rejected: %s" % result.error)
	return {"ok": true, "error": ""}


func _integration_failure(state: Dictionary, snapshot: Dictionary, error: String) -> Dictionary:
	state.clear()
	state.merge(snapshot, true)
	return {"ok": false, "error": error}


func drain_packet(state: Dictionary, packet_id: int) -> Dictionary:
	var packet_index := -1
	for index in state.packets.size():
		if state.packets[index].id == packet_id:
			packet_index = index
			break
	if packet_index < 0:
		return {"ok": false, "error": "packet ID not found", "amount_q": 0}
	if state.next_ids.drain_record < Contracts.FIRST_STABLE_ID:
		return {"ok": false, "error": "drain stable IDs exhausted", "amount_q": 0}
	var packet: Dictionary = state.packets[packet_index]
	var amount: int = packet.volume_q
	var record_id: int = state.next_ids.drain_record
	var id_result := Contracts.consume_stable_id(record_id)
	state.next_ids.drain_record = id_result.next_id
	state.packets.remove_at(packet_index)
	state.ledger.airborne -= amount
	state.ledger.drain += amount
	state.drain_queue.append({
		"id": record_id,
		"amount_q": amount,
		"return_tick": state.tick + Tuning.VALUES.drain_return_delay_ticks,
		"lifecycle": Contracts.DrainLifecycle.DELAYED,
	})
	return {"ok": true, "error": "", "amount_q": amount, "record_id": record_id}


func process_drain_returns(state: Dictionary) -> int:
	var returned := 0
	while not state.drain_queue.is_empty():
		var record: Dictionary = state.drain_queue[0]
		if state.tick < record.return_tick:
			break
		record.lifecycle = Contracts.DrainLifecycle.RETURN_READY
		var free_capacity: int = Tuning.VALUES.reserve_capacity_q - state.ledger.reserve
		if free_capacity <= 0:
			break
		var amount := mini(record.amount_q, free_capacity)
		record.amount_q -= amount
		state.ledger.drain -= amount
		state.ledger.reserve += amount
		returned += amount
		if record.amount_q == 0:
			state.drain_queue.pop_front()
		else:
			break
	return returned


func _newest_packet_is_compatible(state: Dictionary, packet: Dictionary, frame: Dictionary) -> bool:
	if state.tick == 0 or packet.emission_tick != state.tick - 1:
		return false
	if packet.aim_angle != frame.aim_angle:
		return false
	var mouth := MouthDerivation.derive(state.player)
	var cell_span_fp := Tuning.VALUES.grid_cell_size_px * Tuning.SUBPIXELS_PER_PIXEL
	if abs(packet.position_x_fp - mouth.x) > cell_span_fp:
		return false
	if abs(packet.position_y_fp - mouth.y) > cell_span_fp:
		return false
	if packet.lifecycle != Contracts.PacketLifecycle.AIRBORNE:
		return false
	if packet.suction_reserved or packet.stationary_ticks != 0:
		return false
	return packet.volume_q < Tuning.VALUES.maximum_packet_volume_q


static func _divide_trunc(numerator: int, denominator: int) -> int:
	if numerator >= 0:
		return numerator / denominator
	return -((-numerator) / denominator)
