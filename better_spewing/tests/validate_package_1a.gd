extends SceneTree

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")

const EXPECTED_ZERO_STATE_BYTES := 315
const EXPECTED_ZERO_STATE_SHA256 := "25e1fd9e42241badddddf27570c114b79349aac91b20f693bcd0af8a535c2086"
const EXPECTED_SCHEMA_FIELDS := 100
const EXPECTED_SCHEMA_SHA256 := "2724e5e3baf6ae0ef571a94eb289dc34eedf6797b5d03d42182a8fecd96d6f4c"
const EXPECTED_TUNING_BYTES := 144
const EXPECTED_TUNING_SHA256 := "d8c1a98010b611489e68f6733f121648c92dc2a151cf35ae6ad99b9d62356a7f"
const EXPECTED_COMMAND_HEX := "04030201ff0101020b0a44332211feffffff"

var passed := 0
var failed := 0


func _init() -> void:
	_test_versions_and_tuning()
	_test_all_tuning_boundaries()
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
	print("P1A_TUNING bytes=%d sha256=%s" % [Tuning.canonical_bytes().size(), Tuning.canonical_hash()])
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
	invalid_thresholds.swim_entry_permille = 500
	invalid_thresholds.swim_exit_permille = 500
	_check("below entry" in Tuning.validate(invalid_thresholds), "invalid threshold ordering is rejected")
	var invalid_recoil: Dictionary = Tuning.VALUES.duplicate(true)
	invalid_recoil.recoil_subpixel_denominator = 0
	_check("denominator" in Tuning.validate(invalid_recoil), "zero recoil denominator is rejected")


func _test_all_tuning_boundaries() -> void:
	var covered_fields := {}
	for field in Tuning.LOCKED_VALUES:
		covered_fields[field] = true
		var locked_value: int = Tuning.LOCKED_VALUES[field]
		_check(Tuning.validate_locked_field(field, locked_value).is_empty(), "%s locked value accepts exact boundary" % field)
		var below: Dictionary = Tuning.VALUES.duplicate(true)
		below[field] = locked_value - 1
		_check(not Tuning.validate(below).is_empty(), "%s rejects below locked value" % field)
		var above: Dictionary = Tuning.VALUES.duplicate(true)
		above[field] = locked_value + 1
		_check(not Tuning.validate(above).is_empty(), "%s rejects above locked value" % field)

	for field in Tuning.RANGE_BOUNDS:
		covered_fields[field] = true
		var bounds: Array = Tuning.RANGE_BOUNDS[field]
		var minimum: int = bounds[0]
		var maximum: int = bounds[1]
		_check(Tuning.validate_field_range(field, minimum).is_empty(), "%s accepts permitted minimum" % field)
		_check(Tuning.validate_field_range(field, maximum).is_empty(), "%s accepts permitted maximum" % field)
		_check(not Tuning.validate_field_range(field, minimum - 1).is_empty(), "%s helper rejects below minimum" % field)
		_check(not Tuning.validate_field_range(field, maximum + 1).is_empty(), "%s helper rejects above maximum" % field)
		var below: Dictionary = Tuning.VALUES.duplicate(true)
		below[field] = minimum - 1
		_check(not Tuning.validate(below).is_empty(), "%s full validation rejects below minimum" % field)
		var above: Dictionary = Tuning.VALUES.duplicate(true)
		above[field] = maximum + 1
		_check(not Tuning.validate(above).is_empty(), "%s full validation rejects above maximum" % field)

	covered_fields.grid_width_cells = true
	covered_fields.grid_height_cells = true
	for cell_size in [8, 16]:
		var derived: Dictionary = Tuning.VALUES.duplicate(true)
		derived.grid_cell_size_px = cell_size
		var dimensions := Tuning.derived_grid_dimensions(cell_size)
		derived.grid_width_cells = dimensions.x
		derived.grid_height_cells = dimensions.y
		_check(Tuning.validate(derived).is_empty(), "derived grid dimensions validate at cell-size boundary %d" % cell_size)
	var bad_width: Dictionary = Tuning.VALUES.duplicate(true)
	bad_width.grid_width_cells += 1
	_check("grid_width_cells" in Tuning.validate(bad_width), "non-derived grid width is rejected")
	var bad_height: Dictionary = Tuning.VALUES.duplicate(true)
	bad_height.grid_height_cells += 1
	_check("grid_height_cells" in Tuning.validate(bad_height), "non-derived grid height is rejected")

	covered_fields.recoil_subpixel_numerator_per_s_per_q = true
	covered_fields.recoil_subpixel_denominator = true
	_check(Tuning.validate_recoil_ratio(1024, 5).is_empty(), "recoil accepts exact 0.8 minimum")
	_check(Tuning.validate_recoil_ratio(2048, 5).is_empty(), "recoil accepts exact 1.6 maximum")
	_check(not Tuning.validate_recoil_ratio(1023, 5).is_empty(), "recoil rejects below 0.8")
	_check(not Tuning.validate_recoil_ratio(2049, 5).is_empty(), "recoil rejects above 1.6")
	var low_recoil: Dictionary = Tuning.VALUES.duplicate(true)
	low_recoil.recoil_subpixel_numerator_per_s_per_q = 1023
	_check(not Tuning.validate(low_recoil).is_empty(), "full validation rejects low rational recoil")
	var high_recoil: Dictionary = Tuning.VALUES.duplicate(true)
	high_recoil.recoil_subpixel_numerator_per_s_per_q = 2049
	_check(not Tuning.validate(high_recoil).is_empty(), "full validation rejects high rational recoil")

	_check(covered_fields.size() == Tuning.FIELD_ORDER.size(), "validation coverage count matches every tuning field")
	for field in Tuning.FIELD_ORDER:
		_check(covered_fields.has(field), "validation coverage includes %s" % field)

	var inverted_suction: Dictionary = Tuning.VALUES.duplicate(true)
	inverted_suction.suction_travel_min_ticks = 20
	inverted_suction.suction_travel_max_ticks = 10
	_check("inverted" in Tuning.validate(inverted_suction), "suction travel ordering is enforced")
	var equal_swim: Dictionary = Tuning.VALUES.duplicate(true)
	equal_swim.swim_entry_permille = 500
	equal_swim.swim_exit_permille = 500
	_check("below entry" in Tuning.validate(equal_swim), "swim threshold ordering is enforced")
	var equal_spikes: Dictionary = Tuning.VALUES.duplicate(true)
	equal_spikes.spike_unsafe_depth_px = equal_spikes.spike_safe_depth_px
	_check("below safe" in Tuning.validate(equal_spikes), "spike depth ordering is enforced")
	var unauthorized_hud: Dictionary = Tuning.VALUES.duplicate(true)
	unauthorized_hud.hud_unit_q = 20
	unauthorized_hud.cell_capacity_q = 20
	_check("locked to 16" in Tuning.validate(unauthorized_hud), "HUD remains locked even when cell capacity matches")
	var unauthorized_spew: Dictionary = Tuning.VALUES.duplicate(true)
	unauthorized_spew.spew_rate_qps = 1
	_check(not Tuning.validate(unauthorized_spew).is_empty(), "spew rate 1 is rejected")
	var unauthorized_lifetime: Dictionary = Tuning.VALUES.duplicate(true)
	unauthorized_lifetime.packet_lifetime_ticks = 1
	_check(not Tuning.validate(unauthorized_lifetime).is_empty(), "packet lifetime 1 is rejected")


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
	var packet_default := Schema.default_packet()
	_check(packet_default.has("emission_tick") and packet_default.has("aim_angle") and packet_default.has("impact_cell_id") and packet_default.size() == 18, "packet default declares every schema-v3 future field")
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
	_check(first.bytes.slice(0, 6).hex_encode() == "030000000000", "state header is versioned little-endian")
	var wide_ledger := Schema.default_state()
	wide_ledger.ledger.initial = 0x0102030405060708
	wide_ledger.ledger.reserve = 0x0102030405060708
	var wide_result := Serializer.serialize_state_checked(wide_ledger)
	_check(wide_result.ok and wide_result.bytes.slice(6, 14).hex_encode() == "0807060504030201", "ledger i64 is little-endian")


func _test_rejections() -> void:
	var wrong_version := Schema.default_state()
	wrong_version.schema_version = 2
	var wrong_version_result := Serializer.serialize_state_checked(wrong_version)
	_check(not wrong_version_result.ok and "unsupported schema_version" in wrong_version_result.error, "old schema version is rejected")
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
