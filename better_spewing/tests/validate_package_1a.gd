extends SceneTree

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")

const EXPECTED_ZERO_STATE_BYTES := 315
const EXPECTED_ZERO_STATE_SHA256 := "48f35b356bbfb4dbe03ae558b5667cf69b5f849e189325d036f4539fde2175b6"
const EXPECTED_SCHEMA_FIELDS := 95
const EXPECTED_SCHEMA_SHA256 := "19bbd6fe7732ba4243a34389d57515b71dc5d1330708afc8bbac5900c9ab1ffa"
const EXPECTED_TUNING_BYTES := 144
const EXPECTED_TUNING_SHA256 := "f8a3c2e7a071b5b088da2bc1a32edeae7a7fe9dacd7e0d661457603a6f88bc65"
const EXPECTED_COMMAND_HEX := "04030201ff0101020b0a44332211feffffff"

var passed := 0
var failed := 0


func _init() -> void:
	_test_versions_and_tuning()
	_test_command_frame_contract()
	_test_ledger_and_stable_ids()
	_test_schema_audit()
	_test_zero_state_fixture()
	_test_rejections()
	print("P1A_SUITE passed=%d failed=%d result=%s" % [
		passed, failed, "PASS" if failed == 0 else "FAIL"
	])
	quit(0 if failed == 0 else 1)


func _test_versions_and_tuning() -> void:
	_check(Contracts.CONTRACT_VERSION == 1, "contract version is 1")
	_check(Contracts.SERIALIZATION_SCHEMA_VERSION == Schema.SCHEMA_VERSION, "schema versions agree")
	_check(Tuning.TUNING_VERSION == 1, "tuning version is 1")
	_check(Contracts.PacketLifecycle.size() == 3, "packet lifecycle states are declared")
	_check(Contracts.SettledCellLifecycle.size() == 3, "settled-cell lifecycle states are declared")
	_check(Contracts.SuctionLifecycle.size() == 3, "suction lifecycle states are declared")
	_check(Contracts.DrainLifecycle.size() == 2, "drain lifecycle states are declared")
	_check(Tuning.validate().is_empty(), "canonical tuning validates")
	var all_integer := true
	for field in Tuning.FIELD_ORDER:
		all_integer = all_integer and typeof(Tuning.VALUES[field]) == TYPE_INT
	_check(all_integer, "all tuning values are integers")
	_check(Tuning.canonical_bytes().size() == EXPECTED_TUNING_BYTES, "tuning fixed-width byte length")
	_check(Tuning.canonical_hash() == EXPECTED_TUNING_SHA256, "tuning canonical hash fixture")
	_check(Tuning.canonical_bytes().slice(0, 4).hex_encode() == "01002300", "tuning header is little-endian")
	_check(
		Tuning.VALUES.recoil_subpixel_numerator_per_s_per_q == 1536
		and Tuning.VALUES.recoil_subpixel_denominator == 5,
		"1.2px recoil is represented exactly as 1536/5 subpixels"
	)
	var float_tuning: Dictionary = Tuning.VALUES.duplicate(true)
	float_tuning.spew_rate_qps = 448.0
	_check("must be integer" in Tuning.validate(float_tuning), "floating-point tuning is rejected")
	var invalid_thresholds: Dictionary = Tuning.VALUES.duplicate(true)
	invalid_thresholds.swim_exit_permille = invalid_thresholds.swim_entry_permille
	_check("below entry" in Tuning.validate(invalid_thresholds), "invalid threshold ordering is rejected")
	var invalid_recoil: Dictionary = Tuning.VALUES.duplicate(true)
	invalid_recoil.recoil_subpixel_denominator = 0
	_check("denominator" in Tuning.validate(invalid_recoil), "zero recoil denominator is rejected")


func _test_command_frame_contract() -> void:
	_check(Contracts.COMMAND_FRAME_FIELD_ORDER == [
		"tick", "move_x", "move_y", "jump_pressed", "goo_action", "aim_angle",
		"asserted_mouth_x_fp", "asserted_mouth_y_fp"
	], "command frame field order is locked")
	var frame := Contracts.default_command_frame()
	frame.tick = 0x01020304
	frame.move_x = -1
	frame.move_y = 1
	frame.jump_pressed = true
	frame.goo_action = Contracts.GooAction.GULP
	frame.aim_angle = 0x0a0b
	frame.asserted_mouth_x_fp = 0x11223344
	frame.asserted_mouth_y_fp = -2
	var result := Serializer.serialize_command_frame_checked(frame)
	_check(result.ok, "valid command frame serializes")
	_check(result.bytes.size() == 18, "command frame fixed width is 18 bytes")
	_check(result.bytes.hex_encode() == EXPECTED_COMMAND_HEX, "command frame little-endian fixture")
	var bad_aim: Dictionary = frame.duplicate(true)
	bad_aim.aim_angle = 4096
	_check(not Serializer.serialize_command_frame_checked(bad_aim).ok, "out-of-range aim is rejected")
	var missing_field: Dictionary = frame.duplicate(true)
	missing_field.erase("asserted_mouth_y_fp")
	_check(not Serializer.serialize_command_frame_checked(missing_field).ok, "malformed command frame is rejected")


func _test_ledger_and_stable_ids() -> void:
	_check(Contracts.LEDGER_CATEGORIES == [
		"reserve", "airborne", "settled", "suction", "recovery_queue", "drain"
	], "ledger category set is complete and ordered")
	var ledger := {
		"initial": 21,
		"reserve": 1,
		"airborne": 2,
		"settled": 3,
		"suction": 4,
		"recovery_queue": 5,
		"drain": 6,
	}
	_check(Contracts.validate_ledger(ledger).is_empty(), "complete ledger invariant validates")
	var float_ledger: Dictionary = ledger.duplicate(true)
	float_ledger.reserve = 1.0
	_check("non-negative integer" in Contracts.validate_ledger(float_ledger), "floating-point volume is rejected")
	var missing_category: Dictionary = ledger.duplicate(true)
	missing_category.erase("drain")
	_check("missing category" in Contracts.validate_ledger(missing_category), "missing ledger category is rejected")
	var bad_total: Dictionary = ledger.duplicate(true)
	bad_total.initial = 22
	_check("invariant mismatch" in Contracts.validate_ledger(bad_total), "ledger mismatch is rejected")
	_check(not Contracts.consume_stable_id(0).ok, "stable ID zero is invalid")
	var first_id := Contracts.consume_stable_id(1)
	_check(first_id.ok and first_id.id == 1 and first_id.next_id == 2 and not first_id.exhausted, "stable IDs are monotonic")
	var final_id := Contracts.consume_stable_id(Contracts.MAX_STABLE_ID)
	_check(final_id.ok and final_id.id == Contracts.MAX_STABLE_ID and final_id.exhausted, "stable ID exhaustion is explicit")


func _test_schema_audit() -> void:
	_check(Schema.FIELD_ORDER.size() == EXPECTED_SCHEMA_FIELDS, "schema field count fixture")
	_check(Schema.descriptor_hash() == EXPECTED_SCHEMA_SHA256, "schema descriptor hash fixture")
	_check(Schema.FIELD_ORDER[0] == "schema_version:u16", "schema starts with version")
	_check(Schema.FIELD_ORDER[1] == "tick:u32", "tick is second in canonical order")
	_check(Schema.FIELD_ORDER[-1] == "immutable_hashes.occupancy:bytes32", "occupancy hash closes canonical order")
	for item in Schema.SECTION_9_3_AUDIT:
		var item_ok := true
		for path in Schema.SECTION_9_3_AUDIT[item]:
			item_ok = item_ok and _schema_has_path(path)
		print("P1A_AUDIT item=%s paths=%s result=%s" % [
			item,
			",".join(PackedStringArray(Schema.SECTION_9_3_AUDIT[item])),
			"PASS" if item_ok else "FAIL",
		])
		_check(item_ok, "Section 9.3 mapping: %s" % item)


func _test_zero_state_fixture() -> void:
	var state := Schema.default_state()
	var first := Serializer.serialize_state_checked(state)
	var second := Serializer.serialize_state_checked(Schema.default_state())
	_check(first.ok and second.ok, "default states serialize")
	_check(first.bytes == second.bytes, "default serialization is byte-identical in process")
	_check(first.bytes.size() == EXPECTED_ZERO_STATE_BYTES, "zero-state byte length fixture")
	_check(Serializer.state_hash(state) == EXPECTED_ZERO_STATE_SHA256, "zero-state SHA-256 fixture")
	_check(first.bytes.slice(0, 6).hex_encode() == "010000000000", "state header is versioned little-endian")
	var wide_ledger := Schema.default_state()
	wide_ledger.ledger.initial = 0x0102030405060708
	wide_ledger.ledger.reserve = 0x0102030405060708
	var wide_result := Serializer.serialize_state_checked(wide_ledger)
	_check(wide_result.ok and wide_result.bytes.slice(6, 14).hex_encode() == "0807060504030201", "ledger i64 is little-endian")


func _test_rejections() -> void:
	var wrong_version := Schema.default_state()
	wrong_version.schema_version = 2
	var wrong_version_result := Serializer.serialize_state_checked(wrong_version)
	_check(not wrong_version_result.ok and "unsupported schema_version" in wrong_version_result.error, "unsupported schema version is rejected")
	var bad_tick := Schema.default_state()
	bad_tick.tick = -1
	_check(not Serializer.serialize_state_checked(bad_tick).ok, "negative uint32 state is rejected")
	var bad_hash := Schema.default_state()
	bad_hash.immutable_hashes.tuning.resize(31)
	_check(not Serializer.serialize_state_checked(bad_hash).ok, "malformed immutable hash is rejected")
	var bad_remainder := Schema.default_state()
	bad_remainder.command_sampler.spew_rate_remainder = 60
	_check(not Serializer.serialize_state_checked(bad_remainder).ok, "out-of-range rate remainder is rejected")
	var extra_root := Schema.default_state()
	extra_root.untracked_future_state = 1
	_check(not Serializer.serialize_state_checked(extra_root).ok, "undeclared future state is rejected")


func _schema_has_path(path: String) -> bool:
	for descriptor in Schema.FIELD_ORDER:
		var declared_path: String = descriptor.split(":", false, 1)[0]
		if declared_path == path or declared_path.begins_with(path + "."):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("P1A_CHECK_FAIL: %s" % label)
