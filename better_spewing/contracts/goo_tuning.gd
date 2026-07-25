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
	"recoil_subpixels_per_s_per_q",
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
	"fall_transfer_q_per_tick": 16,
	"lateral_transfer_q_per_tick": 4,
	"maximum_active_cells_per_tick": 1536,
	"maximum_lateral_pairs_per_tick": 2048,
	"sleep_threshold_processed_ticks": 12,
	"deposition_search_radius_cells": 4,
	"suction_radius_px": 90,
	"maximum_suction_jobs": 128,
	"suction_travel_min_ticks": 4,
	"suction_travel_max_ticks": 18,
	"recoil_subpixels_per_s_per_q": 307,
	"recoil_tick_cap_fp_per_s": 16 * SUBPIXELS_PER_PIXEL,
	"maximum_upward_speed_fp_per_s": 800 * SUBPIXELS_PER_PIXEL,
	"wade_threshold_permille": 200,
	"swim_entry_permille": 550,
	"swim_exit_permille": 450,
	"spike_safe_depth_px": 12,
	"spike_unsafe_depth_px": 8,
	"drain_return_delay_ticks": 90,
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
	if values.authoritative_hz != 60:
		return "authoritative_hz is locked to 60"
	if values.grid_width_cells * values.grid_cell_size_px != 960:
		return "grid width must cover the 960px viewport"
	if values.grid_height_cells * values.grid_cell_size_px != 540:
		return "grid height must cover the 540px viewport"
	if values.hud_unit_q != values.cell_capacity_q:
		return "HUD unit and cell capacity must share the 16-quantum convention"
	if values.swim_exit_permille >= values.swim_entry_permille:
		return "swim exit threshold must be below entry threshold"
	if values.spike_unsafe_depth_px >= values.spike_safe_depth_px:
		return "spike unsafe depth must be below safe depth"
	if values.suction_travel_min_ticks > values.suction_travel_max_ticks:
		return "suction travel range is inverted"
	return ""


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
