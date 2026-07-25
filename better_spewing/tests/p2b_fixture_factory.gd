extends RefCounted

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")
const SettledFlow := preload("res://better_spewing/flow/settled_flow.gd")

const PLAYER_X_FP := 480 * 256
const PLAYER_Y_FP := 100 * 256
const MOUTH_Y_FP := PLAYER_Y_FP + 3 * 256


static func room_context() -> Dictionary:
	return RoomOccupancy.build({
		"identifier": "package-2b-flow-replay",
		"solids": [
			Rect2(390, 0, 10, 310),
			Rect2(560, 0, 10, 310),
			Rect2(390, 300, 180, 10),
		],
	})


static func header() -> Dictionary:
	var room := room_context()
	return {
		"project_commit_id": "9b1e87b02472307246659a1c4748f2f0a6289203",
		"room_identifier": "package-2b-flow-replay",
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
	var result: Array = []
	for tick in 32:
		result.append({
			"tick": tick,
			"move_x": 0,
			"move_y": 0,
			"jump_pressed": false,
			"goo_action": Contracts.GooAction.NONE,
			"aim_angle": 0,
			"asserted_mouth_x_fp": PLAYER_X_FP,
			"asserted_mouth_y_fp": MOUTH_Y_FP,
		})
	return result


static func replay_bytes() -> PackedByteArray:
	var encoded := ReplayCodec.encode(header(), frames())
	return encoded.bytes if encoded.ok else PackedByteArray()


static func seed_state(state: Dictionary, context: Dictionary) -> void:
	var seeded := [
		{"id": _id(46, 18), "q": 16},
		{"id": _id(47, 18), "q": 16},
		{"id": _id(48, 18), "q": 16},
	]
	for record in seeded:
		state.settled_cells[record.id] = record.q
		state.ledger.reserve -= record.q
		state.ledger.settled += record.q
		SettledFlow.activate_cell_and_neighbors(state, context, record.id)


static func _id(x: int, y: int) -> int:
	return y * 96 + x
