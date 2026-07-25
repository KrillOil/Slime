extends RefCounted

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const AimQuantizer := preload("res://better_spewing/aim/aim_quantizer.gd")

const MAGIC := "GRP1"
const VERSION := 1
const HEADER_BYTES := 264
const COMMAND_BYTES := 18
const HASH_BYTES := 32
const LEDGER_FIELDS := ["initial", "reserve", "airborne", "settled", "suction", "recovery_queue", "drain"]


static func encode(header: Dictionary, frames: Array) -> Dictionary:
	var error := validate_header(header)
	if not error.is_empty():
		return {"ok": false, "error": error, "bytes": PackedByteArray()}
	error = _validate_frames(frames)
	if not error.is_empty():
		return {"ok": false, "error": error, "bytes": PackedByteArray()}
	var bytes := PackedByteArray()
	bytes.append_array(MAGIC.to_ascii_buffer())
	_u16(bytes, VERSION)
	_u16(bytes, HEADER_BYTES)
	_fixed_string(bytes, header.project_commit_id, 40)
	_fixed_string(bytes, header.room_identifier, 32)
	bytes.append_array(header.room_definition_hash)
	bytes.append_array(header.tuning_hash)
	for field in LEDGER_FIELDS:
		_i64(bytes, header.initial_ledger[field])
	_i32(bytes, header.initial_player.position_x_fp)
	_i32(bytes, header.initial_player.position_y_fp)
	_i8(bytes, header.initial_player.facing)
	bytes.append_array(PackedByteArray([0, 0, 0]))
	_fixed_string(bytes, header.target_platform, 16)
	_fixed_string(bytes, header.engine_version, 32)
	_u32(bytes, frames.size())
	for frame in frames:
		var result := Serializer.serialize_command_frame_checked(frame)
		bytes.append_array(result.bytes)
	return {"ok": true, "error": "", "bytes": bytes}


static func decode(bytes: PackedByteArray, expected_header: Dictionary = {}) -> Dictionary:
	if bytes.size() < HEADER_BYTES:
		return _failure("replay is truncated")
	if bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return _failure("replay magic mismatch")
	if _read_u16(bytes, 4) != VERSION:
		return _failure("unsupported replay schema version")
	if _read_u16(bytes, 6) != HEADER_BYTES:
		return _failure("replay header byte length mismatch")
	for fixed_field in [[8, 40], [48, 32], [212, 16], [228, 32]]:
		if not _fixed_padding_is_canonical(bytes, fixed_field[0], fixed_field[1]):
			return _failure("replay fixed-string padding is not canonical")
	var header := {
		"project_commit_id": _read_fixed_string(bytes, 8, 40),
		"room_identifier": _read_fixed_string(bytes, 48, 32),
		"room_definition_hash": bytes.slice(80, 112),
		"tuning_hash": bytes.slice(112, 144),
		"initial_ledger": {},
		"initial_player": {
			"position_x_fp": _read_i32(bytes, 200),
			"position_y_fp": _read_i32(bytes, 204),
			"facing": _read_i8(bytes, 208),
		},
		"target_platform": _read_fixed_string(bytes, 212, 16),
		"engine_version": _read_fixed_string(bytes, 228, 32),
	}
	var offset := 144
	for field in LEDGER_FIELDS:
		header.initial_ledger[field] = _read_i64(bytes, offset)
		offset += 8
	if bytes[209] != 0 or bytes[210] != 0 or bytes[211] != 0:
		return _failure("replay reserved header bytes must be zero")
	var error := validate_header(header)
	if not error.is_empty():
		return _failure(error)
	error = _validate_expected_header(header, expected_header)
	if not error.is_empty():
		return _failure(error)
	var command_count := _read_u32(bytes, 260)
	var expected_length := HEADER_BYTES + command_count * COMMAND_BYTES
	if bytes.size() < expected_length:
		return _failure("replay command data is truncated")
	if bytes.size() > expected_length:
		return _failure("replay contains extra trailing data")
	var frames: Array = []
	for index in command_count:
		var command_offset := HEADER_BYTES + index * COMMAND_BYTES
		var frame := {
			"tick": _read_u32(bytes, command_offset),
			"move_x": _read_i8(bytes, command_offset + 4),
			"move_y": _read_i8(bytes, command_offset + 5),
			"jump_pressed": bytes[command_offset + 6] == 1,
			"goo_action": bytes[command_offset + 7],
			"aim_angle": _read_u16(bytes, command_offset + 8),
			"asserted_mouth_x_fp": _read_i32(bytes, command_offset + 10),
			"asserted_mouth_y_fp": _read_i32(bytes, command_offset + 14),
		}
		if bytes[command_offset + 6] > 1:
			return _failure("command boolean is not canonical")
		error = Contracts.validate_command_frame(frame)
		if not error.is_empty():
			return _failure("invalid command %d: %s" % [index, error])
		if index > 0 and frame.tick != frames[index - 1].tick + 1:
			return _failure("command ticks must be contiguous and increasing")
		frames.append(frame)
	return {"ok": true, "error": "", "header": header, "frames": frames}


static func state_from_header(header: Dictionary, occupancy_hash: PackedByteArray) -> Dictionary:
	var state := Schema.default_state()
	state.ledger = header.initial_ledger.duplicate(true)
	state.player.position_x_fp = header.initial_player.position_x_fp
	state.player.position_y_fp = header.initial_player.position_y_fp
	state.player.facing = header.initial_player.facing
	state.player.last_valid_aim = AimQuantizer.initial_aim_for_facing(header.initial_player.facing)
	state.command_sampler.facing = header.initial_player.facing
	state.command_sampler.last_valid_aim = state.player.last_valid_aim
	state.immutable_hashes.room_definition = header.room_definition_hash.duplicate()
	state.immutable_hashes.tuning = header.tuning_hash.duplicate()
	state.immutable_hashes.occupancy = occupancy_hash.duplicate()
	return state


static func validate_header(header: Variant) -> String:
	if typeof(header) != TYPE_DICTIONARY:
		return "replay header must be a Dictionary"
	var fields := ["project_commit_id", "room_identifier", "room_definition_hash", "tuning_hash", "initial_ledger", "initial_player", "target_platform", "engine_version"]
	if header.size() != fields.size():
		return "replay header field count mismatch"
	for field in fields:
		if not header.has(field):
			return "replay header missing field: %s" % field
	if not _valid_commit_id(header.project_commit_id):
		return "project_commit_id must be 40 lowercase hexadecimal characters"
	for pair in [["room_identifier", 32], ["target_platform", 16], ["engine_version", 32]]:
		if not _valid_fixed_string(header[pair[0]], pair[1]):
			return "%s is not a canonical fixed ASCII string" % pair[0]
	for field in ["room_definition_hash", "tuning_hash"]:
		if typeof(header[field]) != TYPE_PACKED_BYTE_ARRAY or header[field].size() != HASH_BYTES:
			return "%s must contain exactly 32 bytes" % field
	var ledger_error := Contracts.validate_ledger(header.initial_ledger)
	if not ledger_error.is_empty():
		return ledger_error
	if typeof(header.initial_player) != TYPE_DICTIONARY or header.initial_player.size() != 3:
		return "initial_player field count mismatch"
	for field in ["position_x_fp", "position_y_fp", "facing"]:
		if not header.initial_player.has(field):
			return "initial_player missing field: %s" % field
	for field in ["position_x_fp", "position_y_fp"]:
		var value: Variant = header.initial_player[field]
		if typeof(value) != TYPE_INT or value < -0x80000000 or value > 0x7fffffff:
			return "initial_player %s must be int32" % field
	if typeof(header.initial_player.facing) != TYPE_INT or abs(header.initial_player.facing) != 1:
		return "initial_player facing must be -1 or 1"
	return ""


static func _validate_frames(frames: Variant) -> String:
	if typeof(frames) != TYPE_ARRAY:
		return "frames must be an Array"
	for index in frames.size():
		var error := Contracts.validate_command_frame(frames[index])
		if not error.is_empty():
			return "invalid command %d: %s" % [index, error]
		if index > 0 and frames[index].tick != frames[index - 1].tick + 1:
			return "command ticks must be contiguous and increasing"
	return ""


static func _validate_expected_header(actual: Dictionary, expected: Dictionary) -> String:
	for field in expected:
		if not actual.has(field):
			return "unknown expected replay header field: %s" % field
		if actual[field] != expected[field]:
			return "replay header mismatch: %s" % field
	return ""


static func _valid_commit_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 40:
		return false
	for index in value.length():
		if not "0123456789abcdef".contains(value[index]):
			return false
	return true


static func _valid_fixed_string(value: Variant, width: int) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > width:
		return false
	if value.to_utf8_buffer().size() != value.length():
		return false
	for index in value.length():
		if value.unicode_at(index) == 0:
			return false
	return true


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "header": {}, "frames": []}


static func _fixed_string(bytes: PackedByteArray, text: String, width: int) -> void:
	var encoded := text.to_ascii_buffer()
	bytes.append_array(encoded)
	for unused in width - encoded.size():
		bytes.append(0)


static func _read_fixed_string(bytes: PackedByteArray, offset: int, width: int) -> String:
	var value := ""
	for index in width:
		var byte := bytes[offset + index]
		if byte == 0:
			break
		value += String.chr(byte)
	return value


static func _fixed_padding_is_canonical(bytes: PackedByteArray, offset: int, width: int) -> bool:
	var found_zero := false
	for index in width:
		var byte := bytes[offset + index]
		if found_zero and byte != 0:
			return false
		found_zero = found_zero or byte == 0
	return true


static func _u16(bytes: PackedByteArray, value: int) -> void:
	bytes.append(value & 0xff)
	bytes.append((value >> 8) & 0xff)


static func _u32(bytes: PackedByteArray, value: int) -> void:
	for shift in [0, 8, 16, 24]:
		bytes.append((value >> shift) & 0xff)


static func _i8(bytes: PackedByteArray, value: int) -> void:
	bytes.append(value & 0xff)


static func _i32(bytes: PackedByteArray, value: int) -> void:
	_u32(bytes, value)


static func _i64(bytes: PackedByteArray, value: int) -> void:
	for shift in [0, 8, 16, 24, 32, 40, 48, 56]:
		bytes.append((value >> shift) & 0xff)


static func _read_u16(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] | (bytes[offset + 1] << 8)


static func _read_u32(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)


static func _read_i8(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] - 256 if bytes[offset] >= 128 else bytes[offset]


static func _read_i32(bytes: PackedByteArray, offset: int) -> int:
	var value := _read_u32(bytes, offset)
	return value - 0x100000000 if value >= 0x80000000 else value


static func _read_i64(bytes: PackedByteArray, offset: int) -> int:
	var value := 0
	for index in 8:
		value |= bytes[offset + index] << (index * 8)
	return value
