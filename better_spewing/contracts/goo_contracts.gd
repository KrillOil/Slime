extends RefCounted

const CONTRACT_VERSION := 1
const SERIALIZATION_SCHEMA_VERSION := 2
const INVALID_STABLE_ID := 0
const FIRST_STABLE_ID := 1
const MAX_STABLE_ID := 0xffffffff

const LEDGER_CATEGORIES := [
	"reserve",
	"airborne",
	"settled",
	"suction",
	"recovery_queue",
	"drain",
]

const COMMAND_FRAME_FIELD_ORDER := [
	"tick",
	"move_x",
	"move_y",
	"jump_pressed",
	"goo_action",
	"aim_angle",
	"asserted_mouth_x_fp",
	"asserted_mouth_y_fp",
]

enum GooAction {
	NONE = 0,
	SPEW = 1,
	GULP = 2,
}

enum PacketLifecycle {
	AIRBORNE = 0,
	STATIONARY_DEPOSITION = 1,
	RESERVED_FOR_SUCTION = 2,
}

enum SettledCellLifecycle {
	EMPTY = 0,
	ACTIVE = 1,
	SLEEPING = 2,
}

enum SuctionLifecycle {
	RESERVED = 0,
	IN_TRANSIT = 1,
	RECOVERY_QUEUED = 2,
}

enum DrainLifecycle {
	DELAYED = 0,
	RETURN_READY = 1,
}

enum ImmersionState {
	DRY = 0,
	WADING = 1,
	SWIMMING = 2,
}

enum PlayerMovementState {
	GROUNDED = 0,
	AIRBORNE = 1,
	WADING = 2,
	SWIMMING = 3,
}

enum SuctionSourceType {
	PACKET = 0,
	SETTLED_CELL = 1,
}


static func default_command_frame() -> Dictionary:
	return {
		"tick": 0,
		"move_x": 0,
		"move_y": 0,
		"jump_pressed": false,
		"goo_action": GooAction.NONE,
		"aim_angle": 0,
		"asserted_mouth_x_fp": 0,
		"asserted_mouth_y_fp": 0,
	}


static func validate_command_frame(frame: Variant) -> String:
	if typeof(frame) != TYPE_DICTIONARY:
		return "command frame must be a Dictionary"
	for field in COMMAND_FRAME_FIELD_ORDER:
		if not frame.has(field):
			return "command frame missing field: %s" % field
	if frame.size() != COMMAND_FRAME_FIELD_ORDER.size():
		return "command frame contains undeclared fields"
	if not _is_int_in_range(frame.tick, 0, 0xffffffff):
		return "tick must be uint32"
	if not _is_int_in_range(frame.move_x, -1, 1):
		return "move_x must be -1, 0, or 1"
	if not _is_int_in_range(frame.move_y, -1, 1):
		return "move_y must be -1, 0, or 1"
	if typeof(frame.jump_pressed) != TYPE_BOOL:
		return "jump_pressed must be bool"
	if not _is_int_in_range(frame.goo_action, GooAction.NONE, GooAction.GULP):
		return "goo_action is out of range"
	if not _is_int_in_range(frame.aim_angle, 0, 4095):
		return "aim_angle must be a 12-bit unsigned value"
	if not _is_int_in_range(frame.asserted_mouth_x_fp, -0x80000000, 0x7fffffff):
		return "asserted_mouth_x_fp must be int32"
	if not _is_int_in_range(frame.asserted_mouth_y_fp, -0x80000000, 0x7fffffff):
		return "asserted_mouth_y_fp must be int32"
	return ""


static func validate_next_stable_id(next_id: Variant) -> String:
	if not _is_int_in_range(next_id, FIRST_STABLE_ID, MAX_STABLE_ID):
		return "next stable ID must be uint32 in the inclusive range 1..0xffffffff"
	return ""


static func consume_stable_id(next_id: int) -> Dictionary:
	var error := validate_next_stable_id(next_id)
	if not error.is_empty():
		return {"ok": false, "error": error}
	if next_id == MAX_STABLE_ID:
		return {
			"ok": true,
			"id": next_id,
			"next_id": INVALID_STABLE_ID,
			"exhausted": true,
		}
	return {
		"ok": true,
		"id": next_id,
		"next_id": next_id + 1,
		"exhausted": false,
	}


static func ledger_total(ledger: Dictionary) -> int:
	var total := 0
	for category in LEDGER_CATEGORIES:
		total += int(ledger.get(category, 0))
	return total


static func validate_ledger(ledger: Variant) -> String:
	if typeof(ledger) != TYPE_DICTIONARY:
		return "ledger must be a Dictionary"
	if not ledger.has("initial"):
		return "ledger missing initial"
	for category in LEDGER_CATEGORIES:
		if not ledger.has(category):
			return "ledger missing category: %s" % category
		if typeof(ledger[category]) != TYPE_INT or ledger[category] < 0:
			return "ledger category %s must be a non-negative integer" % category
	if typeof(ledger.initial) != TYPE_INT or ledger.initial < 0:
		return "ledger initial must be a non-negative integer"
	if ledger.size() != LEDGER_CATEGORIES.size() + 1:
		return "ledger contains undeclared categories"
	if ledger_total(ledger) != ledger.initial:
		return "ledger invariant mismatch"
	return ""


static func _is_int_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and value >= minimum and value <= maximum
