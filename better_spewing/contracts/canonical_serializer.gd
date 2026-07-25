extends RefCounted

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")

const ROOT_FIELDS := [
	"schema_version",
	"tick",
	"ledger",
	"packets",
	"settled_cells",
	"active_queue",
	"active_membership",
	"cell_stable_counters",
	"suction_jobs",
	"drain_queue",
	"recovery_queue",
	"hazards",
	"next_ids",
	"remainders",
	"player",
	"command_sampler",
	"immutable_hashes",
]


static func serialize_command_frame_checked(frame: Variant) -> Dictionary:
	var error := Contracts.validate_command_frame(frame)
	if not error.is_empty():
		return {"ok": false, "error": error, "bytes": PackedByteArray()}
	var bytes := PackedByteArray()
	_append_u32(bytes, frame.tick)
	_append_i8(bytes, frame.move_x)
	_append_i8(bytes, frame.move_y)
	_append_bool(bytes, frame.jump_pressed)
	_append_u8(bytes, frame.goo_action)
	_append_u16(bytes, frame.aim_angle)
	_append_i32(bytes, frame.asserted_mouth_x_fp)
	_append_i32(bytes, frame.asserted_mouth_y_fp)
	return {"ok": true, "error": "", "bytes": bytes}


static func serialize_state_checked(state: Variant) -> Dictionary:
	var error := validate_state(state)
	if not error.is_empty():
		return {"ok": false, "error": error, "bytes": PackedByteArray()}
	var bytes := PackedByteArray()
	_append_u16(bytes, state.schema_version)
	_append_u32(bytes, state.tick)
	for field in ["initial", "reserve", "airborne", "settled", "suction", "recovery_queue", "drain"]:
		_append_i64(bytes, state.ledger[field])

	_append_u32(bytes, state.packets.size())
	for packet in state.packets:
		_append_u32(bytes, packet.id)
		_append_u32(bytes, packet.emission_tick)
		_append_u16(bytes, packet.aim_angle)
		_append_u32(bytes, packet.impact_cell_id)
		_append_i8(bytes, packet.impact_normal_x)
		_append_i8(bytes, packet.impact_normal_y)
		_append_i32(bytes, packet.position_x_fp)
		_append_i32(bytes, packet.position_y_fp)
		_append_i32(bytes, packet.velocity_x_fp_per_s)
		_append_i32(bytes, packet.velocity_y_fp_per_s)
		_append_u16(bytes, packet.volume_q)
		_append_u16(bytes, packet.lifetime_ticks)
		_append_u8(bytes, packet.lifecycle)
		_append_bool(bytes, packet.suction_reserved)
		_append_u16(bytes, packet.stationary_ticks)
		_append_i32(bytes, packet.position_x_remainder)
		_append_i32(bytes, packet.position_y_remainder)
		_append_i32(bytes, packet.gravity_remainder)

	_append_u16_array(bytes, state.settled_cells)
	_append_u32_array(bytes, state.active_queue)
	_append_byte_array(bytes, state.active_membership)
	_append_u16_array(bytes, state.cell_stable_counters)

	_append_u32(bytes, state.suction_jobs.size())
	for job in state.suction_jobs:
		_append_u32(bytes, job.id)
		_append_u8(bytes, job.source_type)
		_append_u32(bytes, job.source_id)
		_append_u32(bytes, job.source_cell_id)
		_append_i32(bytes, job.source_x_fp)
		_append_i32(bytes, job.source_y_fp)
		_append_u16(bytes, job.amount_q)
		_append_u32(bytes, job.start_tick)
		_append_u32(bytes, job.arrival_tick)
		_append_u8(bytes, job.lifecycle)

	_append_u32(bytes, state.drain_queue.size())
	for record in state.drain_queue:
		_append_u32(bytes, record.id)
		_append_u16(bytes, record.amount_q)
		_append_u32(bytes, record.return_tick)
		_append_u8(bytes, record.lifecycle)

	_append_u32(bytes, state.recovery_queue.size())
	for record in state.recovery_queue:
		_append_u32(bytes, record.id)
		_append_u16(bytes, record.amount_q)
		_append_u32(bytes, record.arrival_tick)

	_append_u32(bytes, state.hazards.size())
	for hazard in state.hazards:
		_append_u32(bytes, hazard.id)
		_append_bool(bytes, hazard.safe)
		_append_u32_array(bytes, hazard.column_depth_numerators)

	for field in ["packet", "suction_job", "drain_record", "recovery_record"]:
		_append_u32(bytes, state.next_ids[field])
	for field in ["spew_rate", "gulp_rate", "drain_return", "player_gravity", "player_position_x", "player_position_y", "player_recoil_x", "player_recoil_y", "recoil_fraction"]:
		_append_i32(bytes, state.remainders[field])

	_append_i32(bytes, state.player.position_x_fp)
	_append_i32(bytes, state.player.position_y_fp)
	_append_i32(bytes, state.player.velocity_x_fp_per_s)
	_append_i32(bytes, state.player.velocity_y_fp_per_s)
	_append_bool(bytes, state.player.grounded)
	_append_u8(bytes, state.player.movement_state)
	_append_u8(bytes, state.player.immersion_state)
	_append_u32(bytes, state.player.submerged_numerator)
	_append_u16_array(bytes, state.player.immersion_samples)
	_append_u8(bytes, state.player.swim_entry_counter)
	_append_u8(bytes, state.player.swim_exit_counter)
	_append_i32(bytes, state.player.recoil_x_fp_per_s)
	_append_i32(bytes, state.player.recoil_y_fp_per_s)
	_append_u16(bytes, state.player.last_valid_aim)
	_append_i8(bytes, state.player.facing)
	_append_u8(bytes, state.player.current_goo_action)
	_append_bool(bytes, state.player.action_released)

	_append_u32(bytes, state.command_sampler.last_tick)
	_append_i8(bytes, state.command_sampler.last_move_x)
	_append_i8(bytes, state.command_sampler.last_move_y)
	_append_bool(bytes, state.command_sampler.jump_was_down)
	_append_bool(bytes, state.command_sampler.spew_was_down)
	_append_bool(bytes, state.command_sampler.gulp_was_down)
	_append_u8(bytes, state.command_sampler.resolved_action)
	_append_u16(bytes, state.command_sampler.last_valid_aim)
	_append_i8(bytes, state.command_sampler.facing)
	_append_u16(bytes, state.command_sampler.spew_rate_remainder)
	_append_u16(bytes, state.command_sampler.gulp_rate_remainder)

	bytes.append_array(state.immutable_hashes.room_definition)
	bytes.append_array(state.immutable_hashes.tuning)
	bytes.append_array(state.immutable_hashes.occupancy)
	return {"ok": true, "error": "", "bytes": bytes}


static func state_hash(state: Variant) -> String:
	var result := serialize_state_checked(state)
	if not result.ok:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(result.bytes)
	return context.finish().hex_encode()


static func validate_state(state: Variant) -> String:
	if typeof(state) != TYPE_DICTIONARY:
		return "state must be a Dictionary"
	var root_error := _validate_exact_fields(state, ROOT_FIELDS, "state")
	if not root_error.is_empty():
		return root_error
	if not _is_uint(state.schema_version, 16) or state.schema_version != Schema.SCHEMA_VERSION:
		return "unsupported schema_version"
	if not _is_uint(state.tick, 32):
		return "tick must be uint32"
	var ledger_error := Contracts.validate_ledger(state.ledger)
	if not ledger_error.is_empty():
		return ledger_error
	var packet_error := _validate_packets(state.packets)
	if not packet_error.is_empty():
		return packet_error
	var cells_error := _validate_cells(state)
	if not cells_error.is_empty():
		return cells_error
	var suction_error := _validate_suction_jobs(state.suction_jobs)
	if not suction_error.is_empty():
		return suction_error
	var drain_error := _validate_drain_queue(state.drain_queue)
	if not drain_error.is_empty():
		return drain_error
	var recovery_error := _validate_recovery_queue(state.recovery_queue)
	if not recovery_error.is_empty():
		return recovery_error
	var hazard_error := _validate_hazards(state.hazards)
	if not hazard_error.is_empty():
		return hazard_error
	var next_id_error := _validate_next_ids(state.next_ids)
	if not next_id_error.is_empty():
		return next_id_error
	var remainder_error := _validate_remainders(state.remainders)
	if not remainder_error.is_empty():
		return remainder_error
	var player_error := _validate_player(state.player)
	if not player_error.is_empty():
		return player_error
	var sampler_error := _validate_command_sampler(state.command_sampler)
	if not sampler_error.is_empty():
		return sampler_error
	return _validate_hashes(state.immutable_hashes)


static func _validate_packets(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "packets must be an Array"
	var previous_id := 0
	var fields := ["id", "emission_tick", "aim_angle", "impact_cell_id", "impact_normal_x", "impact_normal_y", "position_x_fp", "position_y_fp", "velocity_x_fp_per_s", "velocity_y_fp_per_s", "volume_q", "lifetime_ticks", "lifecycle", "suction_reserved", "stationary_ticks", "position_x_remainder", "position_y_remainder", "gravity_remainder"]
	for packet in value:
		var field_error := _validate_exact_fields(packet, fields, "packet")
		if not field_error.is_empty():
			return field_error
		if not _is_uint(packet.id, 32) or packet.id == 0 or packet.id <= previous_id:
			return "packets must have strictly increasing nonzero stable IDs"
		previous_id = packet.id
		if not _is_uint(packet.emission_tick, 32):
			return "packet emission_tick must be uint32"
		if not _is_uint(packet.aim_angle, 16) or packet.aim_angle > 4095:
			return "packet aim_angle must be 12-bit"
		if not _is_uint(packet.impact_cell_id, 32):
			return "packet impact_cell_id must be uint32"
		for field in ["impact_normal_x", "impact_normal_y"]:
			if not _is_int_range(packet[field], -1, 1):
				return "packet %s must be -1, 0, or 1" % field
		var normal_axis_count: int = absi(packet.impact_normal_x) + absi(packet.impact_normal_y)
		if packet.impact_cell_id == Contracts.NO_IMPACT_CELL_ID:
			if normal_axis_count != 0:
				return "no-impact packet must have zero contact normal"
		else:
			if packet.impact_cell_id >= Tuning.VALUES.grid_width_cells * Tuning.VALUES.grid_height_cells:
				return "packet impact_cell_id is outside canonical grid"
			if normal_axis_count != 1:
				return "impact packet must have one axis-aligned contact normal"
		for field in ["position_x_fp", "position_y_fp", "velocity_x_fp_per_s", "velocity_y_fp_per_s", "position_x_remainder", "position_y_remainder", "gravity_remainder"]:
			if not _is_int32(packet[field]):
				return "packet %s must be int32" % field
		for field in ["volume_q", "lifetime_ticks", "stationary_ticks"]:
			if not _is_uint(packet[field], 16):
				return "packet %s must be uint16" % field
		if packet.volume_q == 0 or packet.volume_q > Tuning.VALUES.maximum_packet_volume_q:
			return "packet volume_q is outside tuning bounds"
		if not _is_uint(packet.lifecycle, 8) or packet.lifecycle > Contracts.PacketLifecycle.RESERVED_FOR_SUCTION:
			return "packet lifecycle is out of range"
		if typeof(packet.suction_reserved) != TYPE_BOOL:
			return "packet suction_reserved must be bool"
	return ""


static func _validate_cells(state: Dictionary) -> String:
	if typeof(state.settled_cells) != TYPE_ARRAY:
		return "settled_cells must be an Array"
	if typeof(state.active_queue) != TYPE_ARRAY:
		return "active_queue must be an Array"
	if typeof(state.active_membership) != TYPE_PACKED_BYTE_ARRAY:
		return "active_membership must be PackedByteArray"
	if typeof(state.cell_stable_counters) != TYPE_ARRAY:
		return "cell_stable_counters must be an Array"
	var grid_cell_count: int = Tuning.VALUES.grid_width_cells * Tuning.VALUES.grid_height_cells
	var membership_bytes: int = (grid_cell_count + 7) / 8
	if state.settled_cells.is_empty():
		if not state.cell_stable_counters.is_empty() or not state.active_membership.is_empty() or not state.active_queue.is_empty():
			return "empty settled grid requires empty scheduling state"
	elif state.settled_cells.size() != grid_cell_count \
			or state.cell_stable_counters.size() != grid_cell_count \
			or state.active_membership.size() != membership_bytes:
		return "initialized settled grid dimensions mismatch"
	for volume in state.settled_cells:
		if not _is_uint(volume, 16) or volume > Tuning.VALUES.cell_capacity_q:
			return "settled cell volume is out of range"
	for counter in state.cell_stable_counters:
		if not _is_uint(counter, 16):
			return "cell stable counter must be uint16"
	var seen := {}
	for cell_id in state.active_queue:
		if not _is_uint(cell_id, 32) or cell_id >= state.settled_cells.size():
			return "active queue cell ID is out of range"
		if seen.has(cell_id):
			return "active queue contains a duplicate cell ID"
		seen[cell_id] = true
	return ""


static func _validate_suction_jobs(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "suction_jobs must be an Array"
	var previous_id := 0
	var fields := ["id", "source_type", "source_id", "source_cell_id", "source_x_fp", "source_y_fp", "amount_q", "start_tick", "arrival_tick", "lifecycle"]
	for job in value:
		var error := _validate_exact_fields(job, fields, "suction job")
		if not error.is_empty():
			return error
		if not _is_uint(job.id, 32) or job.id == 0 or job.id <= previous_id:
			return "suction jobs must have strictly increasing nonzero IDs"
		previous_id = job.id
		if not _is_uint(job.source_type, 8) or job.source_type > Contracts.SuctionSourceType.SETTLED_CELL:
			return "suction source_type is out of range"
		for field in ["source_id", "source_cell_id", "start_tick", "arrival_tick"]:
			if not _is_uint(job[field], 32):
				return "suction job %s must be uint32" % field
		for field in ["source_x_fp", "source_y_fp"]:
			if not _is_int32(job[field]):
				return "suction job %s must be int32" % field
		if not _is_uint(job.amount_q, 16) or job.amount_q == 0:
			return "suction amount_q must be nonzero uint16"
		if not _is_uint(job.lifecycle, 8) or job.lifecycle > Contracts.SuctionLifecycle.RECOVERY_QUEUED:
			return "suction lifecycle is out of range"
	return ""


static func _validate_drain_queue(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "drain_queue must be an Array"
	var seen := {}
	var fields := ["id", "amount_q", "return_tick", "lifecycle"]
	for record in value:
		var error := _validate_exact_fields(record, fields, "drain record")
		if not error.is_empty():
			return error
		if not _is_uint(record.id, 32) or record.id == 0 or seen.has(record.id):
			return "drain record ID must be unique nonzero uint32"
		seen[record.id] = true
		if not _is_uint(record.amount_q, 16) or record.amount_q == 0:
			return "drain amount_q must be nonzero uint16"
		if not _is_uint(record.return_tick, 32):
			return "drain return_tick must be uint32"
		if not _is_uint(record.lifecycle, 8) or record.lifecycle > Contracts.DrainLifecycle.RETURN_READY:
			return "drain lifecycle is out of range"
	return ""


static func _validate_recovery_queue(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "recovery_queue must be an Array"
	var seen := {}
	var fields := ["id", "amount_q", "arrival_tick"]
	for record in value:
		var error := _validate_exact_fields(record, fields, "recovery record")
		if not error.is_empty():
			return error
		if not _is_uint(record.id, 32) or record.id == 0 or seen.has(record.id):
			return "recovery record ID must be unique nonzero uint32"
		seen[record.id] = true
		if not _is_uint(record.amount_q, 16) or record.amount_q == 0:
			return "recovery amount_q must be nonzero uint16"
		if not _is_uint(record.arrival_tick, 32):
			return "recovery arrival_tick must be uint32"
	return ""


static func _validate_hazards(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "hazards must be an Array"
	var previous_id := 0
	var fields := ["id", "safe", "column_depth_numerators"]
	for hazard in value:
		var error := _validate_exact_fields(hazard, fields, "hazard state")
		if not error.is_empty():
			return error
		if not _is_uint(hazard.id, 32) or hazard.id == 0 or hazard.id <= previous_id:
			return "hazards must have strictly increasing nonzero IDs"
		previous_id = hazard.id
		if typeof(hazard.safe) != TYPE_BOOL:
			return "hazard safe must be bool"
		if typeof(hazard.column_depth_numerators) != TYPE_ARRAY:
			return "hazard column depths must be an Array"
		for depth in hazard.column_depth_numerators:
			if not _is_uint(depth, 32):
				return "hazard column depth numerator must be uint32"
	return ""


static func _validate_next_ids(value: Variant) -> String:
	var fields := ["packet", "suction_job", "drain_record", "recovery_record"]
	var error := _validate_exact_fields(value, fields, "next_ids")
	if not error.is_empty():
		return error
	for field in fields:
		var id_error := Contracts.validate_next_stable_id(value[field])
		if not id_error.is_empty():
			return "%s: %s" % [field, id_error]
	return ""


static func _validate_remainders(value: Variant) -> String:
	var fields := ["spew_rate", "gulp_rate", "drain_return", "player_gravity", "player_position_x", "player_position_y", "player_recoil_x", "player_recoil_y", "recoil_fraction"]
	var error := _validate_exact_fields(value, fields, "remainders")
	if not error.is_empty():
		return error
	for field in fields:
		if not _is_int32(value[field]):
			return "remainder %s must be int32" % field
	return ""


static func _validate_player(value: Variant) -> String:
	var fields := ["position_x_fp", "position_y_fp", "velocity_x_fp_per_s", "velocity_y_fp_per_s", "grounded", "movement_state", "immersion_state", "submerged_numerator", "immersion_samples", "swim_entry_counter", "swim_exit_counter", "recoil_x_fp_per_s", "recoil_y_fp_per_s", "last_valid_aim", "facing", "current_goo_action", "action_released"]
	var error := _validate_exact_fields(value, fields, "player")
	if not error.is_empty():
		return error
	for field in ["position_x_fp", "position_y_fp", "velocity_x_fp_per_s", "velocity_y_fp_per_s", "recoil_x_fp_per_s", "recoil_y_fp_per_s"]:
		if not _is_int32(value[field]):
			return "player %s must be int32" % field
	for field in ["grounded", "action_released"]:
		if typeof(value[field]) != TYPE_BOOL:
			return "player %s must be bool" % field
	if not _is_uint(value.movement_state, 8) or value.movement_state > Contracts.PlayerMovementState.SWIMMING:
		return "player movement_state is out of range"
	if not _is_uint(value.immersion_state, 8) or value.immersion_state > Contracts.ImmersionState.SWIMMING:
		return "player immersion_state is out of range"
	if not _is_uint(value.submerged_numerator, 32):
		return "player submerged_numerator must be uint32"
	if typeof(value.immersion_samples) != TYPE_ARRAY or value.immersion_samples.size() != 5:
		return "player immersion_samples must contain five entries"
	for sample in value.immersion_samples:
		if not _is_uint(sample, 16):
			return "player immersion sample must be uint16"
	for field in ["swim_entry_counter", "swim_exit_counter"]:
		if not _is_uint(value[field], 8):
			return "player %s must be uint8" % field
	if not _is_uint(value.last_valid_aim, 16) or value.last_valid_aim > 4095:
		return "player last_valid_aim must be 12-bit"
	if not _is_int_range(value.facing, -1, 1) or value.facing == 0:
		return "player facing must be -1 or 1"
	if not _is_uint(value.current_goo_action, 8) or value.current_goo_action > Contracts.GooAction.GULP:
		return "player current_goo_action is out of range"
	return ""


static func _validate_command_sampler(value: Variant) -> String:
	var fields := ["last_tick", "last_move_x", "last_move_y", "jump_was_down", "spew_was_down", "gulp_was_down", "resolved_action", "last_valid_aim", "facing", "spew_rate_remainder", "gulp_rate_remainder"]
	var error := _validate_exact_fields(value, fields, "command_sampler")
	if not error.is_empty():
		return error
	if not _is_uint(value.last_tick, 32):
		return "command sampler last_tick must be uint32"
	for field in ["last_move_x", "last_move_y"]:
		if not _is_int_range(value[field], -1, 1):
			return "command sampler %s must be -1, 0, or 1" % field
	for field in ["jump_was_down", "spew_was_down", "gulp_was_down"]:
		if typeof(value[field]) != TYPE_BOOL:
			return "command sampler %s must be bool" % field
	if not _is_uint(value.resolved_action, 8) or value.resolved_action > Contracts.GooAction.GULP:
		return "command sampler resolved_action is out of range"
	if not _is_uint(value.last_valid_aim, 16) or value.last_valid_aim > 4095:
		return "command sampler last_valid_aim must be 12-bit"
	if not _is_int_range(value.facing, -1, 1) or value.facing == 0:
		return "command sampler facing must be -1 or 1"
	for field in ["spew_rate_remainder", "gulp_rate_remainder"]:
		if not _is_uint(value[field], 16) or value[field] >= Tuning.VALUES.authoritative_hz:
			return "command sampler %s must be an integer rate remainder below 60" % field
	return ""


static func _validate_hashes(value: Variant) -> String:
	var fields := ["room_definition", "tuning", "occupancy"]
	var error := _validate_exact_fields(value, fields, "immutable_hashes")
	if not error.is_empty():
		return error
	for field in fields:
		if typeof(value[field]) != TYPE_PACKED_BYTE_ARRAY or value[field].size() != Schema.HASH_BYTE_COUNT:
			return "immutable hash %s must contain exactly 32 bytes" % field
	return ""


static func _validate_exact_fields(value: Variant, fields: Array, label: String) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "%s must be a Dictionary" % label
	if value.size() != fields.size():
		return "%s field count mismatch" % label
	for field in fields:
		if not value.has(field):
			return "%s missing field: %s" % [label, field]
	return ""


static func _is_uint(value: Variant, bits: int) -> bool:
	if typeof(value) != TYPE_INT or value < 0:
		return false
	var maximum := 0xffffffff if bits == 32 else (1 << bits) - 1
	return value <= maximum


static func _is_int32(value: Variant) -> bool:
	return _is_int_range(value, -0x80000000, 0x7fffffff)


static func _is_int_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and value >= minimum and value <= maximum


static func _append_bool(bytes: PackedByteArray, value: bool) -> void:
	_append_u8(bytes, 1 if value else 0)


static func _append_u8(bytes: PackedByteArray, value: int) -> void:
	bytes.append(value & 0xff)


static func _append_i8(bytes: PackedByteArray, value: int) -> void:
	bytes.append(value & 0xff)


static func _append_u16(bytes: PackedByteArray, value: int) -> void:
	for shift in [0, 8]:
		bytes.append((value >> shift) & 0xff)


static func _append_u32(bytes: PackedByteArray, value: int) -> void:
	for shift in [0, 8, 16, 24]:
		bytes.append((value >> shift) & 0xff)


static func _append_i32(bytes: PackedByteArray, value: int) -> void:
	_append_u32(bytes, value)


static func _append_i64(bytes: PackedByteArray, value: int) -> void:
	for shift in [0, 8, 16, 24, 32, 40, 48, 56]:
		bytes.append((value >> shift) & 0xff)


static func _append_u16_array(bytes: PackedByteArray, values: Array) -> void:
	_append_u32(bytes, values.size())
	for value in values:
		_append_u16(bytes, value)


static func _append_u32_array(bytes: PackedByteArray, values: Array) -> void:
	_append_u32(bytes, values.size())
	for value in values:
		_append_u32(bytes, value)


static func _append_byte_array(bytes: PackedByteArray, values: PackedByteArray) -> void:
	_append_u32(bytes, values.size())
	bytes.append_array(values)
