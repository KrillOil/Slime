extends RefCounted

const TUNING_VERSION := 1
const SUBPIXELS_PER_PIXEL := 256
const PERMILLE_SCALE := 1000

const FIELD_ORDER := [
	"authoritative_hz",
	"grid_cell_size_px",
	"grid_width_cells",
	"grid_height_cells",
	"cell_capacity_q",
	"hud_unit_q",
	"reserve_capacity_q",
	"spew_rate_qps",
	"gulp_rate_qps",
	"packet_launch_speed_fp_per_s",
	"packet_gravity_fp_per_s2",
	"player_velocity_inheritance_permille",
	"packet_lifetime_ticks",
	"maximum_packet_volume_q",
	"maximum_airborne_packets",
	"fall_transfer_q_per_tick",
	"lateral_transfer_q_per_tick",
	"maximum_active_cells_per_tick",
	"maximum_lateral_pairs_per_tick",
	"sleep_threshold_processed_ticks",
	"deposition_search_radius_cells",
	"suction_radius_px",
	"maximum_suction_jobs",
	"suction_travel_min_ticks",
	"suction_travel_max_ticks",
	"recoil_subpixel_numerator_per_s_per_q",
	"recoil_subpixel_denominator",
	"recoil_tick_cap_fp_per_s",
	"maximum_upward_speed_fp_per_s",
	"wade_threshold_permille",
	"swim_entry_permille",
	"swim_exit_permille",
	"spike_safe_depth_px",
	"spike_unsafe_depth_px",
	"drain_return_delay_ticks",
]

const VALUES := {
	"authoritative_hz": 60,
	"grid_cell_size_px": 10,
	"grid_width_cells": 96,
	"grid_height_cells": 54,
	"cell_capacity_q": 16,
	"hud_unit_q": 16,
	"reserve_capacity_q": 1600,
	"spew_rate_qps": 448,
	"gulp_rate_qps": 672,
	"packet_launch_speed_fp_per_s": 720 * SUBPIXELS_PER_PIXEL,
	"packet_gravity_fp_per_s2": 1500 * SUBPIXELS_PER_PIXEL,
	"player_velocity_inheritance_permille": 500,
	"packet_lifetime_ticks": 90,
	"maximum_packet_volume_q": 16,
	"maximum_airborne_packets": 192,
	"fall_transfer_q_per_tick": 12,
	"lateral_transfer_q_per_tick": 4,
	"maximum_active_cells_per_tick": 1536,
	"maximum_lateral_pairs_per_tick": 2048,
	"sleep_threshold_processed_ticks": 12,
	"deposition_search_radius_cells": 4,
	"suction_radius_px": 90,
	"maximum_suction_jobs": 128,
	"suction_travel_min_ticks": 4,
	"suction_travel_max_ticks": 18,
	"recoil_subpixel_numerator_per_s_per_q": 1536,
	"recoil_subpixel_denominator": 5,
	"recoil_tick_cap_fp_per_s": 16 * SUBPIXELS_PER_PIXEL,
	"maximum_upward_speed_fp_per_s": 800 * SUBPIXELS_PER_PIXEL,
	"wade_threshold_permille": 200,
	"swim_entry_permille": 550,
	"swim_exit_permille": 450,
	"spike_safe_depth_px": 12,
	"spike_unsafe_depth_px": 8,
	"drain_return_delay_ticks": 90,
}

const LOCKED_VALUES := {
	"authoritative_hz": 60,
	"hud_unit_q": 16,
}

# Integer encodings of every permitted planning range in canonical Section 17.
# Pixel speeds use 256 subpixels per pixel and percentages use permille.
const RANGE_BOUNDS := {
	"grid_cell_size_px": [8, 16],
	"cell_capacity_q": [8, 32],
	"reserve_capacity_q": [1200, 2400],
	"spew_rate_qps": [320, 640],
	"gulp_rate_qps": [480, 960],
	"packet_launch_speed_fp_per_s": [480 * SUBPIXELS_PER_PIXEL, 900 * SUBPIXELS_PER_PIXEL],
	"packet_gravity_fp_per_s2": [900 * SUBPIXELS_PER_PIXEL, 2200 * SUBPIXELS_PER_PIXEL],
	"player_velocity_inheritance_permille": [0, 1000],
	"packet_lifetime_ticks": [60, 150],
	"maximum_packet_volume_q": [8, 32],
	"maximum_airborne_packets": [128, 256],
	"fall_transfer_q_per_tick": [8, 16],
	"lateral_transfer_q_per_tick": [2, 8],
	"maximum_active_cells_per_tick": [1024, 2048],
	"maximum_lateral_pairs_per_tick": [1024, 4096],
	"sleep_threshold_processed_ticks": [6, 30],
	"deposition_search_radius_cells": [2, 6],
	"suction_radius_px": [70, 120],
	"maximum_suction_jobs": [64, 192],
	"suction_travel_min_ticks": [4, 30],
	"suction_travel_max_ticks": [4, 30],
	"recoil_tick_cap_fp_per_s": [10 * SUBPIXELS_PER_PIXEL, 24 * SUBPIXELS_PER_PIXEL],
	"maximum_upward_speed_fp_per_s": [650 * SUBPIXELS_PER_PIXEL, 950 * SUBPIXELS_PER_PIXEL],
	"wade_threshold_permille": [150, 300],
	"swim_entry_permille": [500, 650],
	"swim_exit_permille": [350, 500],
	"spike_safe_depth_px": [8, 20],
	"spike_unsafe_depth_px": [4, 16],
	"drain_return_delay_ticks": [30, 180],
}


static func validate(values: Variant = VALUES) -> String:
	if typeof(values) != TYPE_DICTIONARY:
		return "tuning must be a Dictionary"
	if values.size() != FIELD_ORDER.size():
		return "tuning field count mismatch"
	for field in FIELD_ORDER:
		if not values.has(field):
			return "tuning missing field: %s" % field
		if typeof(values[field]) != TYPE_INT:
			return "tuning field %s must be integer" % field
		if values[field] < 0 or values[field] > 0x7fffffff:
			return "tuning field %s must fit non-negative int32" % field
	for field in LOCKED_VALUES:
		var locked_error := validate_locked_field(field, values[field])
		if not locked_error.is_empty():
			return locked_error
	for field in RANGE_BOUNDS:
		var range_error := validate_field_range(field, values[field])
		if not range_error.is_empty():
			return range_error
	var recoil_error := validate_recoil_ratio(
		values.recoil_subpixel_numerator_per_s_per_q,
		values.recoil_subpixel_denominator
	)
	if not recoil_error.is_empty():
		return recoil_error
	var derived_dimensions := derived_grid_dimensions(values.grid_cell_size_px)
	if values.grid_width_cells != derived_dimensions.x:
		return "grid_width_cells must be derived from the 960px viewport"
	if values.grid_height_cells != derived_dimensions.y:
		return "grid_height_cells must be derived from the 540px viewport"
	if values.swim_exit_permille >= values.swim_entry_permille:
		return "swim exit threshold must be below entry threshold"
	if values.spike_unsafe_depth_px >= values.spike_safe_depth_px:
		return "spike unsafe depth must be below safe depth"
	if values.suction_travel_min_ticks > values.suction_travel_max_ticks:
		return "suction travel range is inverted"
	return ""


static func validate_locked_field(field: String, value: Variant) -> String:
	if not LOCKED_VALUES.has(field):
		return "unknown locked tuning field: %s" % field
	if typeof(value) != TYPE_INT or value != LOCKED_VALUES[field]:
		return "tuning field %s is locked to %d" % [field, LOCKED_VALUES[field]]
	return ""


static func validate_field_range(field: String, value: Variant) -> String:
	if not RANGE_BOUNDS.has(field):
		return "unknown ranged tuning field: %s" % field
	var bounds: Array = RANGE_BOUNDS[field]
	if typeof(value) != TYPE_INT or value < bounds[0] or value > bounds[1]:
		return "tuning field %s must be in integer range %d..%d" % [field, bounds[0], bounds[1]]
	return ""


static func validate_recoil_ratio(numerator: Variant, denominator: Variant) -> String:
	if typeof(numerator) != TYPE_INT or typeof(denominator) != TYPE_INT:
		return "recoil rational values must be integers"
	if numerator < 0 or numerator > 0x7fffffff:
		return "recoil rational numerator must fit non-negative int32"
	if denominator <= 0 or denominator > 0x7fffffff:
		return "recoil rational denominator must be positive int32"
	# Canonical permitted range is 0.8..1.6 px/s/q. In subpixels this is
	# exactly 1024/5..2048/5, compared by cross multiplication.
	if numerator * 5 < 1024 * denominator or numerator * 5 > 2048 * denominator:
		return "recoil rational must encode 0.8..1.6 px/s per quantum"
	return ""


static func derived_grid_dimensions(cell_size_px: int) -> Vector2i:
	if cell_size_px <= 0:
		return Vector2i.ZERO
	@warning_ignore("integer_division")
	var width := (960 + cell_size_px - 1) / cell_size_px
	@warning_ignore("integer_division")
	var height := (540 + cell_size_px - 1) / cell_size_px
	return Vector2i(width, height)


static func canonical_bytes(values: Dictionary = VALUES) -> PackedByteArray:
	if not validate(values).is_empty():
		return PackedByteArray()
	var bytes := PackedByteArray()
	_append_u16(bytes, TUNING_VERSION)
	_append_u16(bytes, FIELD_ORDER.size())
	for field in FIELD_ORDER:
		_append_i32(bytes, values[field])
	return bytes


static func canonical_hash(values: Dictionary = VALUES) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical_bytes(values))
	return context.finish().hex_encode()


static func descriptor() -> String:
	var lines := PackedStringArray([
		"tuning_version:u16",
		"field_count:u16",
	])
	for field in FIELD_ORDER:
		lines.append("%s:i32" % field)
	return "\n".join(lines)


static func _append_u16(bytes: PackedByteArray, value: int) -> void:
	bytes.append(value & 0xff)
	bytes.append((value >> 8) & 0xff)


static func _append_i32(bytes: PackedByteArray, value: int) -> void:
	for shift in [0, 8, 16, 24]:
		bytes.append((value >> shift) & 0xff)
