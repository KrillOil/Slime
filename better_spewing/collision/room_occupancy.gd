extends RefCounted

const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")

const ROOM_MAGIC := "GRD1"
const ROOM_VERSION := 1
const OCCUPANCY_MAGIC := "GOM1"
const OCCUPANCY_VERSION := 1
const HASH_BYTES := 32


static func build(room_definition: Dictionary) -> Dictionary:
	var validation := _validate_input(room_definition)
	if not validation.is_empty():
		return {"ok": false, "error": validation}
	var integer_rects: Array = []
	for authored: Rect2 in room_definition.solids:
		var x0 := floori(minf(authored.position.x, authored.end.x))
		var y0 := floori(minf(authored.position.y, authored.end.y))
		var x1 := ceili(maxf(authored.position.x, authored.end.x))
		var y1 := ceili(maxf(authored.position.y, authored.end.y))
		if x1 > x0 and y1 > y0:
			integer_rects.append({"left": x0, "top": y0, "right": x1, "bottom": y1})
	integer_rects.sort_custom(_rect_less)
	var room_bytes := _encode_room(room_definition.identifier, integer_rects)
	var room_hash := _sha256(room_bytes)
	var width: int = Tuning.VALUES.grid_width_cells
	var height: int = Tuning.VALUES.grid_height_cells
	var bitset := _derive_bitset(integer_rects)
	var occupancy_bytes := _encode_occupancy(room_hash, bitset)
	return {
		"ok": true,
		"error": "",
		"identifier": room_definition.identifier,
		"integer_rects": integer_rects,
		"cell_size_px": Tuning.VALUES.grid_cell_size_px,
		"width_cells": width,
		"height_cells": height,
		"width_px": width * Tuning.VALUES.grid_cell_size_px,
		"height_px": height * Tuning.VALUES.grid_cell_size_px,
		"bitset": bitset,
		"room_bytes": room_bytes,
		"room_hash": room_hash,
		"occupancy_bytes": occupancy_bytes,
		"occupancy_hash": _sha256(occupancy_bytes),
		"tuning_hash": Tuning.canonical_hash().hex_decode(),
	}


static func bind_state(state: Dictionary, context: Dictionary) -> String:
	var context_error := validate_context(context)
	if not context_error.is_empty():
		return context_error
	var expected := {
		"room_definition": context.room_hash,
		"tuning": context.tuning_hash,
		"occupancy": context.occupancy_hash,
	}
	var fields_to_bind: Array[String] = []
	for field in ["room_definition", "tuning", "occupancy"]:
		var current: PackedByteArray = state.immutable_hashes[field]
		if _is_zero_hash(current):
			fields_to_bind.append(field)
		elif current != expected[field]:
			return "immutable input mismatch: %s" % field
	for field in fields_to_bind:
		state.immutable_hashes[field] = expected[field].duplicate()
	return ""


static func validate_context(context: Dictionary) -> String:
	if not context.get("ok", false):
		return "room context is invalid"
	for field in [
		"room_bytes", "room_hash", "occupancy_bytes", "occupancy_hash", "tuning_hash",
		"bitset", "identifier", "cell_size_px", "width_cells", "height_cells", "width_px", "height_px",
	]:
		if not context.has(field):
			return "room context is missing %s" % field
	if context.cell_size_px != Tuning.VALUES.grid_cell_size_px \
			or context.width_cells != Tuning.VALUES.grid_width_cells \
			or context.height_cells != Tuning.VALUES.grid_height_cells \
			or context.width_px != Tuning.VALUES.grid_width_cells * Tuning.VALUES.grid_cell_size_px \
			or context.height_px != Tuning.VALUES.grid_height_cells * Tuning.VALUES.grid_cell_size_px:
		return "room context dimensions mismatch"
	var room_bytes: PackedByteArray = context.room_bytes
	var decoded := _decode_room(room_bytes)
	if not decoded.ok:
		return decoded.error
	if decoded.identifier != context.identifier:
		return "room definition identifier mismatch"
	if _sha256(room_bytes) != context.room_hash:
		return "room definition hash mismatch"
	if typeof(context.bitset) != TYPE_PACKED_BYTE_ARRAY:
		return "occupancy bitset must be PackedByteArray"
	var derived_bitset := _derive_bitset(decoded.rects)
	if derived_bitset != context.bitset:
		return "occupancy bitset contradicts encoded room geometry"
	var expected_occupancy := _encode_occupancy(context.room_hash, context.bitset)
	if context.occupancy_bytes != expected_occupancy:
		return "occupancy encoding mismatch"
	if _sha256(expected_occupancy) != context.occupancy_hash:
		return "occupancy hash mismatch"
	if context.occupancy_bytes.slice(0, 4).get_string_from_ascii() != OCCUPANCY_MAGIC \
			or _read_u16(context.occupancy_bytes, 4) != OCCUPANCY_VERSION:
		return "occupancy encoding version mismatch"
	if context.bitset.size() != (context.width_cells * context.height_cells + 7) / 8:
		return "occupancy bitset length mismatch"
	if context.tuning_hash != Tuning.canonical_hash().hex_decode():
		return "canonical tuning hash mismatch"
	return ""


static func _decode_room(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 22 or bytes.slice(0, 4).get_string_from_ascii() != ROOM_MAGIC:
		return {"ok": false, "error": "room definition encoding magic mismatch"}
	if _read_u16(bytes, 4) != ROOM_VERSION:
		return {"ok": false, "error": "room definition encoding version mismatch"}
	if _read_u16(bytes, 6) != Tuning.VALUES.grid_cell_size_px \
			or _read_u16(bytes, 8) != Tuning.VALUES.grid_width_cells \
			or _read_u16(bytes, 10) != Tuning.VALUES.grid_height_cells \
			or _read_u16(bytes, 12) != Tuning.VALUES.grid_width_cells * Tuning.VALUES.grid_cell_size_px \
			or _read_u16(bytes, 14) != Tuning.VALUES.grid_height_cells * Tuning.VALUES.grid_cell_size_px:
		return {"ok": false, "error": "room definition encoding dimensions mismatch"}
	var identifier_length := _read_u16(bytes, 16)
	var rectangle_count_offset := 18 + identifier_length
	if identifier_length < 1 or rectangle_count_offset + 4 > bytes.size():
		return {"ok": false, "error": "room definition encoding identifier length mismatch"}
	var identifier_bytes := bytes.slice(18, rectangle_count_offset)
	var identifier := identifier_bytes.get_string_from_ascii()
	if identifier.is_empty() or identifier.to_ascii_buffer() != identifier_bytes:
		return {"ok": false, "error": "room definition identifier is not canonical ASCII"}
	var rectangle_count := _read_u32(bytes, rectangle_count_offset)
	if rectangle_count < 0:
		return {"ok": false, "error": "room definition rectangle count is invalid"}
	var expected_length := rectangle_count_offset + 4 + rectangle_count * 16
	if bytes.size() != expected_length:
		return {"ok": false, "error": "room definition encoding has truncated or trailing rectangle data"}
	var rects: Array = []
	var offset := rectangle_count_offset + 4
	for index in rectangle_count:
		var rect := {
			"left": _read_i32(bytes, offset),
			"top": _read_i32(bytes, offset + 4),
			"right": _read_i32(bytes, offset + 8),
			"bottom": _read_i32(bytes, offset + 12),
		}
		offset += 16
		if rect.right <= rect.left or rect.bottom <= rect.top:
			return {"ok": false, "error": "room definition rectangle %d is structurally invalid" % index}
		if not rects.is_empty() and _rect_less(rect, rects[-1]):
			return {"ok": false, "error": "room definition rectangles are not in canonical order"}
		rects.append(rect)
	return {"ok": true, "error": "", "identifier": identifier, "rects": rects}


static func _derive_bitset(rects: Array) -> PackedByteArray:
	var width: int = Tuning.VALUES.grid_width_cells
	var height: int = Tuning.VALUES.grid_height_cells
	var bitset := PackedByteArray()
	bitset.resize((width * height + 7) / 8)
	bitset.fill(0)
	for rect in rects:
		var min_x := _floor_div(rect.left, Tuning.VALUES.grid_cell_size_px)
		var min_y := _floor_div(rect.top, Tuning.VALUES.grid_cell_size_px)
		var max_x := _ceil_div(rect.right, Tuning.VALUES.grid_cell_size_px) - 1
		var max_y := _ceil_div(rect.bottom, Tuning.VALUES.grid_cell_size_px) - 1
		min_x = maxi(min_x, 0)
		min_y = maxi(min_y, 0)
		max_x = mini(max_x, width - 1)
		max_y = mini(max_y, height - 1)
		if min_x > max_x or min_y > max_y:
			continue
		for y in range(min_y, max_y + 1):
			for x in range(min_x, max_x + 1):
				_set_bit(bitset, y * width + x)
	return bitset


static func is_solid(context: Dictionary, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= context.width_cells or y >= context.height_cells:
		return false
	return bit_is_set(context.bitset, y * context.width_cells + x)


static func bit_is_set(bitset: PackedByteArray, cell_id: int) -> bool:
	if cell_id < 0 or cell_id >= bitset.size() * 8:
		return false
	return (bitset[cell_id / 8] & (1 << (cell_id % 8))) != 0


static func _validate_input(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY or value.size() != 2:
		return "room definition must contain exactly identifier and solids"
	if not value.has("identifier") or not value.has("solids"):
		return "room definition is missing identifier or solids"
	if typeof(value.identifier) != TYPE_STRING or value.identifier.is_empty():
		return "room identifier must be a non-empty String"
	var identifier_bytes: PackedByteArray = value.identifier.to_utf8_buffer()
	if identifier_bytes.size() != value.identifier.length() or identifier_bytes.size() > 0xffff:
		return "room identifier must be canonical ASCII within uint16 length"
	if typeof(value.solids) != TYPE_ARRAY:
		return "room solids must be an Array"
	for solid in value.solids:
		if typeof(solid) != TYPE_RECT2:
			return "every authored solid must be Rect2"
	return ""


static func _encode_room(identifier: String, rects: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.append_array(ROOM_MAGIC.to_ascii_buffer())
	_u16(bytes, ROOM_VERSION)
	_u16(bytes, Tuning.VALUES.grid_cell_size_px)
	_u16(bytes, Tuning.VALUES.grid_width_cells)
	_u16(bytes, Tuning.VALUES.grid_height_cells)
	_u16(bytes, Tuning.VALUES.grid_width_cells * Tuning.VALUES.grid_cell_size_px)
	_u16(bytes, Tuning.VALUES.grid_height_cells * Tuning.VALUES.grid_cell_size_px)
	var identifier_bytes := identifier.to_ascii_buffer()
	_u16(bytes, identifier_bytes.size())
	bytes.append_array(identifier_bytes)
	_u32(bytes, rects.size())
	for rect in rects:
		_i32(bytes, rect.left)
		_i32(bytes, rect.top)
		_i32(bytes, rect.right)
		_i32(bytes, rect.bottom)
	return bytes


static func _encode_occupancy(room_hash: PackedByteArray, bitset: PackedByteArray) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.append_array(OCCUPANCY_MAGIC.to_ascii_buffer())
	_u16(bytes, OCCUPANCY_VERSION)
	_u16(bytes, Tuning.VALUES.grid_cell_size_px)
	_u16(bytes, Tuning.VALUES.grid_width_cells)
	_u16(bytes, Tuning.VALUES.grid_height_cells)
	bytes.append_array(room_hash)
	_u32(bytes, bitset.size())
	bytes.append_array(bitset)
	return bytes


static func _rect_less(a: Dictionary, b: Dictionary) -> bool:
	for field in ["left", "top", "right", "bottom"]:
		if a[field] != b[field]:
			return a[field] < b[field]
	return false


static func _set_bit(bitset: PackedByteArray, cell_id: int) -> void:
	var byte_index := cell_id / 8
	bitset[byte_index] = bitset[byte_index] | (1 << (cell_id % 8))


static func _is_zero_hash(bytes: PackedByteArray) -> bool:
	if bytes.size() != HASH_BYTES:
		return false
	for byte in bytes:
		if byte != 0:
			return false
	return true


static func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()


static func _floor_div(value: int, divisor: int) -> int:
	if value >= 0:
		return value / divisor
	return -((-value + divisor - 1) / divisor)


static func _ceil_div(value: int, divisor: int) -> int:
	return -_floor_div(-value, divisor)


static func _u16(bytes: PackedByteArray, value: int) -> void:
	bytes.append(value & 0xff)
	bytes.append((value >> 8) & 0xff)


static func _u32(bytes: PackedByteArray, value: int) -> void:
	for shift in [0, 8, 16, 24]:
		bytes.append((value >> shift) & 0xff)


static func _i32(bytes: PackedByteArray, value: int) -> void:
	_u32(bytes, value)


static func _read_u16(bytes: PackedByteArray, offset: int) -> int:
	if offset < 0 or offset + 2 > bytes.size():
		return -1
	return bytes[offset] | (bytes[offset + 1] << 8)


static func _read_u32(bytes: PackedByteArray, offset: int) -> int:
	if offset < 0 or offset + 4 > bytes.size():
		return -1
	return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)


static func _read_i32(bytes: PackedByteArray, offset: int) -> int:
	var value := _read_u32(bytes, offset)
	return value - 0x100000000 if value > 0x7fffffff else value
