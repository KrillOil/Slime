extends RefCounted

const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")

const PLAYER_X_FP := 100 * 256
const PLAYER_Y_FP := 200 * 256
const MOUTH_Y_FP := PLAYER_Y_FP + 3 * 256


static func header() -> Dictionary:
	return {
		"project_commit_id": "f3bc2ba24e1db6c488b72bf17c6fcbb0653a34b4",
		"room_identifier": "package-1b-isolated-room",
		"room_definition_hash": "package-1b-room".sha256_buffer(),
		"tuning_hash": Tuning.canonical_hash().hex_decode(),
		"initial_ledger": {
			"initial": 1600,
			"reserve": 1600,
			"airborne": 0,
			"settled": 0,
			"suction": 0,
			"recovery_queue": 0,
			"drain": 0,
		},
		"initial_player": {
			"position_x_fp": PLAYER_X_FP,
			"position_y_fp": PLAYER_Y_FP,
			"facing": 1,
		},
		"target_platform": "isolated-test",
		"engine_version": "Godot 4.6.3",
	}


static func occupancy_hash() -> PackedByteArray:
	return "package-1b-occupancy".sha256_buffer()


static func frames() -> Array:
	var specifications := [
		[-1, 0, false, 0, 0],
		[1, 1, true, 1, 512],
		[0, -1, false, 1, 1024],
		[-1, 0, false, 2, 2048],
		[0, 0, false, 0, 3072],
		[1, -1, true, 0, 4095],
	]
	var result: Array = []
	for tick in specifications.size():
		var item: Array = specifications[tick]
		result.append({
			"tick": tick,
			"move_x": item[0],
			"move_y": item[1],
			"jump_pressed": item[2],
			"goo_action": item[3],
			"aim_angle": item[4],
			"asserted_mouth_x_fp": PLAYER_X_FP,
			"asserted_mouth_y_fp": MOUTH_Y_FP,
		})
	return result


static func replay_bytes() -> PackedByteArray:
	var encoded := ReplayCodec.encode(header(), frames())
	return encoded.bytes if encoded.ok else PackedByteArray()
