extends RefCounted

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")

const PLAYER_X_FP := 25 * 256
const PLAYER_Y_FP := 100 * 256
const MOUTH_Y_FP := PLAYER_Y_FP + 3 * 256


static func room_context() -> Dictionary:
	return RoomOccupancy.build({
		"identifier": "package-1d-replay",
		"solids": [Rect2(60, 0, 10, 540)],
	})


static func header() -> Dictionary:
	var room := room_context()
	return {
		"project_commit_id": "4e9e5dc46abdd88e16bb4637124455ae86e2083f",
		"room_identifier": "package-1d-replay",
		"room_definition_hash": room.room_hash,
		"tuning_hash": room.tuning_hash,
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


static func frames() -> Array:
	var actions := [
		[Contracts.GooAction.SPEW, 0],
		[Contracts.GooAction.NONE, 0],
		[Contracts.GooAction.SPEW, 2048],
		[Contracts.GooAction.NONE, 2048],
		[Contracts.GooAction.NONE, 2048],
		[Contracts.GooAction.NONE, 2048],
	]
	var result: Array = []
	for tick in actions.size():
		result.append({
			"tick": tick,
			"move_x": 0,
			"move_y": 0,
			"jump_pressed": false,
			"goo_action": actions[tick][0],
			"aim_angle": actions[tick][1],
			"asserted_mouth_x_fp": PLAYER_X_FP,
			"asserted_mouth_y_fp": MOUTH_Y_FP,
		})
	return result


static func replay_bytes() -> PackedByteArray:
	var encoded := ReplayCodec.encode(header(), frames())
	return encoded.bytes if encoded.ok else PackedByteArray()
