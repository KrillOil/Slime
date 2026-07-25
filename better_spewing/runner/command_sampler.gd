extends RefCounted

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const AimQuantizer := preload("res://better_spewing/aim/aim_quantizer.gd")
const MouthDerivation := preload("res://better_spewing/runner/mouth_derivation.gd")

var entries: Array[Vector2i]


func _init(direction_entries: Array[Vector2i]) -> void:
	entries = direction_entries


func sample_snapshot(tick: int, snapshot: Dictionary, state: Dictionary) -> Dictionary:
	var player_state: Dictionary = state.player
	var mouth := MouthDerivation.derive(player_state)
	var aim := AimQuantizer.resolve(
		int(snapshot.cursor_x_fp),
		int(snapshot.cursor_y_fp),
		mouth,
		int(state.command_sampler.last_valid_aim),
		int(player_state.facing),
		entries
	)
	var action := Contracts.GooAction.NONE
	if bool(snapshot.spew_pressed):
		action = Contracts.GooAction.SPEW
	elif bool(snapshot.gulp_pressed):
		action = Contracts.GooAction.GULP
	return {
		"tick": tick,
		"move_x": clampi(int(snapshot.move_x), -1, 1),
		"move_y": clampi(int(snapshot.move_y), -1, 1),
		"jump_pressed": bool(snapshot.jump_pressed),
		"goo_action": action,
		"aim_angle": aim,
		"asserted_mouth_x_fp": mouth.x,
		"asserted_mouth_y_fp": mouth.y,
	}
