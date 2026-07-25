extends RefCounted

const AimData := preload("res://better_spewing/aim/generated_aim_table.gd")
const MAGIC := "GAT1"
const VERSION := 1
const ENTRY_COUNT := 4096
const SCALE := 1_000_000
const HEADER_BYTES := 12
const ENTRY_BYTES := 8
const BYTE_LENGTH := HEADER_BYTES + ENTRY_COUNT * ENTRY_BYTES
const SHA256 := "cd57fcdb178d685bf3ba4b07d37244fda27a8ebe802b7faa43d17b690e0e444b"


static func load_checked() -> Dictionary:
	var bytes: PackedByteArray = AimData.canonical_bytes()
	if bytes.size() != BYTE_LENGTH:
		return {"ok": false, "error": "aim table byte length mismatch", "entries": []}
	if _sha256(bytes) != SHA256:
		return {"ok": false, "error": "aim table checksum mismatch", "entries": []}
	if bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return {"ok": false, "error": "aim table magic mismatch", "entries": []}
	if _u16(bytes, 4) != VERSION or _u16(bytes, 6) != ENTRY_COUNT or _u32(bytes, 8) != SCALE:
		return {"ok": false, "error": "aim table header mismatch", "entries": []}
	var entries: Array[Vector2i] = []
	entries.resize(ENTRY_COUNT)
	for index in ENTRY_COUNT:
		var offset := HEADER_BYTES + index * ENTRY_BYTES
		entries[index] = Vector2i(_i32(bytes, offset), _i32(bytes, offset + 4))
	return {"ok": true, "error": "", "entries": entries}


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _u16(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] | (bytes[offset + 1] << 8)


static func _u32(bytes: PackedByteArray, offset: int) -> int:
	return (
		bytes[offset]
		| (bytes[offset + 1] << 8)
		| (bytes[offset + 2] << 16)
		| (bytes[offset + 3] << 24)
	)


static func _i32(bytes: PackedByteArray, offset: int) -> int:
	var value := _u32(bytes, offset)
	return value - 0x100000000 if value >= 0x80000000 else value
